//! The built-in player: Media Foundation's MFPlay on a thread of its own.
// from: audioplayer.pas
//
// MFPlay posts its work to the thread that created the player, so that thread pumps messages
// while it waits for commands from the window's commands.

use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use windows::core::{HSTRING, PCWSTR};
use windows::Win32::Media::MediaFoundation::{
    IMFPMediaItem, IMFPMediaPlayer, IMFPMediaPlayerCallback, MFPCreateMediaPlayer, MFP_CREATION_OPTIONS, MFP_MEDIAPLAYER_STATE_PAUSED,
    MFP_MEDIAPLAYER_STATE_PLAYING, MFP_POSITIONTYPE_100NS,
};
use windows::Win32::System::Com::StructuredStorage::PROPVARIANT;
use windows::Win32::System::Com::{CoInitializeEx, COINIT_APARTMENTTHREADED};
use windows::Win32::System::Variant::{VT_I8, VT_UI8};
use windows::Win32::UI::WindowsAndMessaging::{DispatchMessageW, PeekMessageW, TranslateMessage, MSG, PM_REMOVE};

const PLAYER_MISSING: &str = "Windows Media Foundation findes ikke på denne computer";
/// rsKanIkkeAfspilles; %s is the HRESULT in hex
const CANNOT_PLAY: &str = "filen kan ikke afspilles af Windows (codec mangler?) – fejl %s";

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum PlayerState {
    Stopped,
    Playing,
    Paused,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct PlayerStatus {
    pub state: PlayerState,
    pub position: f64,
    pub duration: f64,
    pub file: String,
}

enum Cmd {
    Play(String, f32, Sender<Result<(), String>>),
    Pause,
    Resume,
    Stop(Sender<()>),
    Seek(f64),
    Volume(f32),
    Status(Sender<PlayerStatus>),
}

pub struct Player {
    tx: Sender<Cmd>,
}

fn pump() {
    let mut msg = MSG::default();
    unsafe {
        while PeekMessageW(&mut msg, None, 0, 0, PM_REMOVE).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

fn seconds(v: windows::core::Result<PROPVARIANT>) -> f64 {
    let Ok(v) = v else { return 0.0 };
    unsafe {
        let inner = &v.Anonymous.Anonymous;
        if inner.vt == VT_I8 || inner.vt == VT_UI8 {
            inner.Anonymous.hVal as f64 / 1e7
        } else {
            0.0
        }
    }
}

fn new_player() -> windows::core::Result<IMFPMediaPlayer> {
    let mut p: Option<IMFPMediaPlayer> = None;
    unsafe { MFPCreateMediaPlayer(PCWSTR::null(), false, MFP_CREATION_OPTIONS(0), None::<&IMFPMediaPlayerCallback>, None, Some(&mut p))? };
    p.ok_or_else(|| windows::core::Error::from(windows::Win32::Foundation::E_FAIL))
}

struct Worker {
    player: Option<IMFPMediaPlayer>,
    file: String,
    volume: f32,
}

impl Worker {
    fn stop(&mut self) {
        if let Some(p) = self.player.take() {
            unsafe {
                let _ = p.Stop();
                let _ = p.Shutdown();
            }
        }
        self.file.clear();
    }

    // from: TAudioPlayer.Play
    fn play(&mut self, path: &str, volume: f32) -> Result<(), String> {
        self.stop();
        self.volume = volume.clamp(0.0, 1.0);
        let p = new_player().map_err(|_| PLAYER_MISSING.to_string())?;
        let fail = |p: &IMFPMediaPlayer, e: windows::core::Error| {
            unsafe {
                let _ = p.Shutdown();
            }
            CANNOT_PLAY.replace("%s", &format!("{:08X}", e.code().0 as u32))
        };
        // synchronous, so a file Windows cannot play is reported here and not lost
        let mut item: Option<IMFPMediaItem> = None;
        if let Err(e) = unsafe { p.CreateMediaItemFromURL(&HSTRING::from(path), true, 0, Some(&mut item)) } {
            return Err(fail(&p, e));
        }
        let Some(item) = item else { return Err(fail(&p, windows::Win32::Foundation::E_FAIL.into())) };
        if let Err(e) = unsafe { p.SetMediaItem(&item) } {
            return Err(fail(&p, e));
        }
        // SetMediaItem completes on this thread's messages
        let t0 = Instant::now();
        while unsafe { p.GetMediaItem() }.is_err() {
            if t0.elapsed() > Duration::from_secs(5) {
                return Err(fail(&p, windows::Win32::Foundation::E_FAIL.into()));
            }
            pump();
            std::thread::sleep(Duration::from_millis(5));
        }
        unsafe {
            let _ = p.SetVolume(self.volume);
            if let Err(e) = p.Play() {
                return Err(fail(&p, e));
            }
        }
        self.player = Some(p);
        self.file = path.to_string();
        Ok(())
    }

    fn status(&self) -> PlayerStatus {
        let Some(p) = &self.player else {
            return PlayerStatus { state: PlayerState::Stopped, position: 0.0, duration: 0.0, file: String::new() };
        };
        let state = match unsafe { p.GetState() } {
            Ok(s) if s == MFP_MEDIAPLAYER_STATE_PLAYING => PlayerState::Playing,
            Ok(s) if s == MFP_MEDIAPLAYER_STATE_PAUSED => PlayerState::Paused,
            _ => PlayerState::Stopped,
        };
        PlayerStatus {
            state,
            position: seconds(unsafe { p.GetPosition(&MFP_POSITIONTYPE_100NS) }),
            duration: seconds(unsafe { p.GetDuration(&MFP_POSITIONTYPE_100NS) }),
            file: self.file.clone(),
        }
    }

    fn run(mut self, rx: Receiver<Cmd>) {
        let _ = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) };
        loop {
            pump();
            let cmd = match rx.recv_timeout(Duration::from_millis(20)) {
                Ok(c) => c,
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
                Err(_) => break, // the Player is gone
            };
            match cmd {
                Cmd::Play(path, v, reply) => {
                    let _ = reply.send(self.play(&path, v));
                }
                Cmd::Pause => {
                    if let Some(p) = &self.player {
                        let _ = unsafe { p.Pause() };
                    }
                }
                Cmd::Resume => {
                    if let Some(p) = &self.player {
                        let _ = unsafe { p.Play() };
                    }
                }
                Cmd::Stop(reply) => {
                    self.stop();
                    let _ = reply.send(());
                }
                Cmd::Seek(s) => {
                    if let Some(p) = &self.player {
                        let mut v = PROPVARIANT::default();
                        unsafe {
                            (*v.Anonymous.Anonymous).vt = VT_I8;
                            (*v.Anonymous.Anonymous).Anonymous.hVal = (s.max(0.0) * 1e7).round() as i64;
                            let _ = p.SetPosition(&MFP_POSITIONTYPE_100NS, &v);
                        }
                    }
                }
                Cmd::Volume(v) => {
                    self.volume = v.clamp(0.0, 1.0);
                    if let Some(p) = &self.player {
                        let _ = unsafe { p.SetVolume(self.volume) };
                    }
                }
                Cmd::Status(reply) => {
                    let _ = reply.send(self.status());
                }
            }
        }
        self.stop();
    }
}

impl Player {
    pub fn new() -> Player {
        let (tx, rx) = channel();
        std::thread::spawn(move || Worker { player: None, file: String::new(), volume: 1.0 }.run(rx));
        Player { tx }
    }

    fn ask<T>(&self, make: impl FnOnce(Sender<T>) -> Cmd, fallback: T) -> T {
        let (tx, rx) = channel();
        if self.tx.send(make(tx)).is_err() {
            return fallback;
        }
        rx.recv().unwrap_or(fallback)
    }

    pub fn play(&self, path: &str, volume: f32) -> Result<(), String> {
        self.ask(|r| Cmd::Play(path.to_string(), volume, r), Err(PLAYER_MISSING.to_string()))
    }
    pub fn pause(&self) {
        let _ = self.tx.send(Cmd::Pause);
    }
    pub fn resume(&self) {
        let _ = self.tx.send(Cmd::Resume);
    }
    pub fn stop(&self) {
        self.ask(Cmd::Stop, ())
    }
    pub fn seek(&self, seconds: f64) {
        let _ = self.tx.send(Cmd::Seek(seconds));
    }
    pub fn set_volume(&self, v: f32) {
        let _ = self.tx.send(Cmd::Volume(v));
    }
    pub fn status(&self) -> PlayerStatus {
        self.ask(Cmd::Status, PlayerStatus { state: PlayerState::Stopped, position: 0.0, duration: 0.0, file: String::new() })
    }
}

/// Whether Media Foundation can make a player here (checked once, on a thread of its own).
// from: PlayerAvailable
pub fn player_available() -> bool {
    static AVAILABLE: OnceLock<bool> = OnceLock::new();
    *AVAILABLE.get_or_init(|| {
        std::thread::spawn(|| {
            let _ = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) };
            match new_player() {
                Ok(p) => {
                    unsafe {
                        let _ = p.Shutdown();
                    }
                    true
                }
                Err(_) => false,
            }
        })
        .join()
        .unwrap_or(false)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    fn silent_wav(seconds: u32) -> Vec<u8> {
        let (rate, ch, bits) = (44100u32, 2u16, 16u16);
        let data_len = rate * seconds * u32::from(ch) * u32::from(bits / 8);
        let mut w = Vec::new();
        w.extend(b"RIFF");
        w.extend((36 + data_len).to_le_bytes());
        w.extend(b"WAVEfmt ");
        w.extend(16u32.to_le_bytes());
        w.extend(1u16.to_le_bytes());
        w.extend(ch.to_le_bytes());
        w.extend(rate.to_le_bytes());
        w.extend((rate * u32::from(ch) * u32::from(bits / 8)).to_le_bytes());
        w.extend((ch * bits / 8).to_le_bytes());
        w.extend(bits.to_le_bytes());
        w.extend(b"data");
        w.extend(data_len.to_le_bytes());
        w.resize(w.len() + data_len as usize, 0);
        w
    }

    #[test]
    fn plays_and_stops_silence() {
        if !player_available() {
            return;
        }
        let f = std::env::temp_dir().join(format!("tidytag-player-{}.wav", std::process::id()));
        std::fs::write(&f, silent_wav(3)).unwrap();
        let p = Player::new();
        p.play(&f.to_string_lossy(), 0.0).unwrap();
        let t0 = Instant::now();
        while p.status().state != PlayerState::Playing && t0.elapsed() < Duration::from_secs(3) {
            std::thread::sleep(Duration::from_millis(50));
        }
        let s = p.status();
        assert_eq!(s.state, PlayerState::Playing);
        assert!((2.9..=3.1).contains(&s.duration), "duration {}", s.duration);
        p.stop();
        assert_eq!(p.status().state, PlayerState::Stopped);
        std::fs::remove_file(&f).unwrap();
    }

    #[test]
    fn play_unplayable_file_fails() {
        if !player_available() {
            return;
        }
        let f = std::env::temp_dir().join(format!("tidytag-player-bad-{}.mp3", std::process::id()));
        std::fs::write(&f, (0..100u8).map(|i| i.wrapping_mul(37)).collect::<Vec<_>>()).unwrap();
        let p = Player::new();
        assert!(p.play(&f.to_string_lossy(), 0.0).is_err());
        assert_eq!(p.status().state, PlayerState::Stopped);
        std::fs::remove_file(&f).unwrap();
    }
}
