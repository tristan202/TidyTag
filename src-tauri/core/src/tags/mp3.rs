//! MP3: ID3v2 + ID3v1 tags and MPEG audio properties incl. Xing/VBRI (port of mp3reader.pas).

use super::id3;
use crate::model::AudioInfo;
use crate::text::*;
use std::io::{Read, Seek};

struct MpegHeader {
    /// 1, 2 or 25 (= 2.5)
    version: i32,
    layer: i32,
    bitrate: i32,
    sample_rate: i32,
    mono: bool,
    frame_len: i64,
    samples_per_frame: i32,
}

const BITRATES_V1: [[i32; 16]; 3] = [
    [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0],
    [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0],
    [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
];
const BITRATES_V2: [[i32; 16]; 3] = [
    [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0],
    [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
    [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
];
const SAMPLE_RATES: [[i32; 3]; 3] = [[44100, 48000, 32000], [22050, 24000, 16000], [11025, 12000, 8000]];

// from: ParseMpegHeader
fn parse_mpeg_header(b: &[u8], p: usize) -> Option<MpegHeader> {
    if p + 4 > b.len() || b[p] != 0xFF || b[p + 1] & 0xE0 != 0xE0 {
        return None;
    }
    let ver_bits = (b[p + 1] >> 3) & 3;
    let layer_bits = (b[p + 1] >> 1) & 3;
    let br_idx = (b[p + 2] >> 4) as usize;
    let sr_idx = ((b[p + 2] >> 2) & 3) as usize;
    let pad = ((b[p + 2] >> 1) & 1) as i64;
    if ver_bits == 1 || layer_bits == 0 || br_idx == 0 || br_idx == 15 || sr_idx == 3 {
        return None;
    }
    let version = match ver_bits { 3 => 1, 2 => 2, _ => 25 };
    let layer = 4 - layer_bits as i32;
    let (bitrate, sample_rate) = if version == 1 {
        (BITRATES_V1[layer as usize - 1][br_idx], SAMPLE_RATES[0][sr_idx])
    } else {
        (BITRATES_V2[layer as usize - 1][br_idx], SAMPLE_RATES[if version == 2 { 1 } else { 2 }][sr_idx])
    };
    let mono = (b[p + 3] >> 6) == 3;
    let (br, sr) = (bitrate as i64, sample_rate as i64);
    let (samples_per_frame, frame_len) = match layer {
        1 => (384, (12 * br * 1000 / sr + pad) * 4),
        2 => (1152, 144 * br * 1000 / sr + pad),
        _ if version == 1 => (1152, 144 * br * 1000 / sr + pad),
        _ => (576, 72 * br * 1000 / sr + pad),
    };
    if frame_len <= 4 {
        return None;
    }
    Some(MpegHeader { version, layer, bitrate, sample_rate, mono, frame_len, samples_per_frame })
}

// from: ReadMpegAudio
fn read_mpeg_audio<R: Read + Seek>(s: &mut R, info: &mut AudioInfo, audio_start: u64, audio_end: u64) -> std::io::Result<()> {
    let b = read_at(s, audio_start, 256 * 1024)?;
    let mut found = None;
    let mut i = 0usize;
    while i + 4 <= b.len() {
        if let Some(h) = parse_mpeg_header(&b, i) {
            // Require a second frame right after, unless the buffer ends first.
            let next = i as i64 + h.frame_len;
            let ok = next + 4 > b.len() as i64
                || parse_mpeg_header(&b, next as usize).is_some_and(|h2| h2.sample_rate == h.sample_rate && h2.layer == h.layer);
            if ok {
                found = Some(h);
                break;
            }
        }
        i += 1;
    }
    let Some(h) = found else { return Ok(()) };

    let ver = if h.version == 25 { "2.5".to_string() } else { h.version.to_string() };
    info.codec = format!("MPEG-{} Layer {}", ver, &"III"[..h.layer as usize]);
    if h.version == 1 && h.layer == 3 {
        info.codec = "MP3".into();
    }
    info.sample_rate = h.sample_rate as u32;
    info.channels = if h.mono { 1 } else { 2 };

    let audio_bytes = audio_end as i64 - (audio_start as i64 + i as i64);
    let xing_off: i64 = match (h.version == 1, h.mono) {
        (true, true) => 4 + 17,
        (true, false) => 4 + 32,
        (false, true) => 4 + 9,
        (false, false) => 4 + 17,
    };
    let i = i as i64;
    let mut frames: u32 = 0;
    if bytes_are(&b, i + xing_off, "Xing") || bytes_are(&b, i + xing_off, "Info") {
        if be32(&b, i + xing_off + 4) & 1 != 0 {
            frames = be32(&b, i + xing_off + 8);
        }
    } else if bytes_are(&b, i + 4 + 32, "VBRI") {
        frames = be32(&b, i + 4 + 32 + 14);
    }

    if frames > 0 {
        info.duration = frames as f64 * h.samples_per_frame as f64 / h.sample_rate as f64;
        if info.duration > 0.0 {
            info.bitrate = pascal_round(audio_bytes as f64 * 8.0 / info.duration / 1000.0) as u32;
        }
    } else {
        info.bitrate = h.bitrate as u32;
        info.duration = audio_bytes as f64 * 8.0 / (h.bitrate as f64 * 1000.0);
    }
    Ok(())
}

// from: ReadMp3
pub fn read<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
    (|| -> std::io::Result<()> {
        info.supported = true;
        let tag_size = id3::read_id3v2(s, info)?;
        let mut audio_end = stream_size(s)?;
        if id3::read_id3v1(s, info)? {
            audio_end -= 128;
        }
        read_mpeg_audio(s, info, tag_size, audio_end)
    })()
    .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use std::path::PathBuf;

    #[test]
    fn xing_duration() {
        // MPEG1 Layer III, 128 kbit/s, 44100 Hz, stereo; Xing header with 1000 frames
        let mut b = vec![0u8; 417];
        b[..4].copy_from_slice(&[0xFF, 0xFB, 0x90, 0x00]);
        b[36..40].copy_from_slice(b"Xing");
        b[40..44].copy_from_slice(&1u32.to_be_bytes());
        b[44..48].copy_from_slice(&1000u32.to_be_bytes());
        let mut info = AudioInfo::new(PathBuf::new(), false);
        read(&mut Cursor::new(b), &mut info).unwrap();
        assert_eq!(info.codec, "MP3");
        assert!((info.duration - 26.1224).abs() < 0.001, "{}", info.duration);
        assert_eq!(info.sample_rate, 44100);
        assert_eq!(info.channels, 2);
    }
}
