//! Commands for file operations (phase 5): Recycle Bin, copy/move, folders, extension changes,
//! playlists, Explorer and the built-in player.

use crate::commands::WriteState;
use crate::player::{player_available, Player, PlayerStatus};
use crate::rename::RenameTrack;
use crate::shell;
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use tauri::{AppHandle, Manager, State};
use tidytag_core::fileio::{recycle_files, write_atomic};
use tidytag_core::fileops::{self, CopyMoveResult};
use tidytag_core::model::AudioInfo;
use tidytag_core::playlist::{mask_text, playlist_text};
use tidytag_core::rename::PlanItem;
use tidytag_core::settings::{settings_path, Ini};

// ---------- helpers (what the commands do, testable without Tauri) ----------

#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Recycled {
    gone: usize,
    errors: Vec<String>,
    /// per file: still there afterwards (1.2 keeps those in the list)
    exists: Vec<bool>,
}

// from: ActDeleteFilesExecute (RecycleFiles + FileExistsL)
fn recycle(paths: &[String]) -> Recycled {
    let files: Vec<PathBuf> = paths.iter().map(PathBuf::from).collect();
    let mut errors = Vec::new();
    let gone = recycle_files(&files, &mut errors);
    Recycled { gone, errors, exists: files.iter().map(|f| f.exists()).collect() }
}

fn copy_move(paths: &[String], dir: &Path, do_move: bool) -> CopyMoveResult {
    let files: Vec<PathBuf> = paths.iter().map(PathBuf::from).collect();
    fileops::copy_or_move_files(&files, dir, do_move)
}

fn create_folder_at(parent: &str, name: &str) -> Result<PathBuf, String> {
    fileops::create_folder(Path::new(parent), name)
}

/// [Playlist] ExtInf (default on) and InfoMask (default '%1 - %2').
fn ini_bool(ini: &Ini, sec: &str, key: &str, default: bool) -> bool {
    ini.get(sec, key).map(|v| v.trim().parse::<i64>().map(|n| n != 0).unwrap_or(default)).unwrap_or(default)
}

// from: WritePlaylist
fn write_playlist(target: &str, tracks: &[RenameTrack], full_paths: bool, ini: &Ini) -> Result<(), String> {
    let infos: Vec<AudioInfo> = tracks.iter().map(|t| t.info()).collect();
    let refs: Vec<&AudioInfo> = infos.iter().collect();
    let text = playlist_text(
        Path::new(target),
        &refs,
        full_paths,
        ini_bool(ini, "Playlist", "ExtInf", true),
        ini.get("Playlist", "InfoMask").unwrap_or("%1 - %2"),
    );
    write_atomic(Path::new(target), text.as_bytes())
}

fn load_ini() -> Result<Ini, String> {
    Ini::load(&settings_path()).map_err(|e| e.to_string())
}

/// ReadList: the values of a section in file order, unquoted.
fn read_list(ini: &Ini, sec: &str) -> Vec<String> {
    let unquote = |s: &str| if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') { s[1..s.len() - 1].to_string() } else { s.to_string() };
    ini.section(sec).into_iter().map(|(_, v)| unquote(&v)).collect()
}

// ---------- commands ----------

#[tauri::command]
pub async fn recycle_cmd(state: State<'_, WriteState>, paths: Vec<String>) -> Result<Recycled, String> {
    let _busy = state.claim()?;
    Ok(recycle(&paths))
}

#[tauri::command]
pub async fn copy_move_cmd(state: State<'_, WriteState>, paths: Vec<String>, dir: String, do_move: bool) -> Result<CopyMoveResult, String> {
    let _busy = state.claim()?;
    Ok(copy_move(&paths, Path::new(&dir), do_move))
}

#[tauri::command]
pub fn folder_cover_files_cmd(dirs: Vec<String>) -> Vec<String> {
    let dirs: Vec<PathBuf> = dirs.iter().map(PathBuf::from).collect();
    fileops::folder_cover_files(&dirs).into_iter().map(|p| p.to_string_lossy().into_owned()).collect()
}

#[tauri::command]
pub fn create_folder_cmd(parent: String, name: String) -> Result<String, String> {
    create_folder_at(&parent, &name).map(|p| p.to_string_lossy().into_owned())
}

#[tauri::command]
pub fn plan_ext_change_cmd(paths: Vec<String>, kind: usize) -> Vec<PlanItem> {
    let files: Vec<PathBuf> = paths.iter().map(PathBuf::from).collect();
    fileops::plan_ext_change(&files, kind)
}

#[tauri::command]
pub async fn save_playlist(target: String, tracks: Vec<RenameTrack>, full_paths: bool) -> Result<(), String> {
    write_playlist(&target, &tracks, full_paths, &load_ini()?)
}

#[tauri::command]
pub fn quick_playlist_name(track: RenameTrack, mask: String) -> String {
    mask_text(&mask, &track.info())
}

/// %TEMP%\TidyTag-afspil.m3u8 with full paths, for an external player.
#[tauri::command]
pub async fn temp_playlist(tracks: Vec<RenameTrack>) -> Result<String, String> {
    let target = std::env::temp_dir().join("TidyTag-afspil.m3u8");
    let t = target.to_string_lossy().into_owned();
    write_playlist(&t, &tracks, true, &load_ini()?)?;
    Ok(t)
}

fn spawn_err(prog: &str, e: std::io::Error) -> String {
    format!("{prog}: {e}")
}

// from: ActShowInExplorerExecute
#[tauri::command]
pub fn show_in_explorer(path: String, select: bool) -> Result<(), String> {
    if !select {
        return open_default(path);
    }
    use std::os::windows::process::CommandExt;
    std::process::Command::new("explorer.exe").raw_arg(format!("/select,\"{path}\"")).spawn().map(|_| ()).map_err(|e| spawn_err("explorer.exe", e))
}

// from: ActPropertiesExecute
#[tauri::command]
pub fn show_properties(app: AppHandle, path: String) -> Result<(), String> {
    use windows_sys::Win32::UI::Shell::{SHObjectProperties, SHOP_FILEPATH};
    let hwnd = app.get_webview_window("main").and_then(|w| w.hwnd().ok()).map(|h| h.0 as *mut core::ffi::c_void).unwrap_or(std::ptr::null_mut());
    let w: Vec<u16> = path.encode_utf16().chain([0]).collect();
    if unsafe { SHObjectProperties(hwnd, SHOP_FILEPATH as u32, w.as_ptr(), std::ptr::null()) } != 0 { Ok(()) } else { Err(path) }
}

/// OpenDocument: the file's default program.
#[tauri::command]
pub fn open_default(path: String) -> Result<(), String> {
    use windows_sys::Win32::UI::Shell::ShellExecuteW;
    use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
    let verb: Vec<u16> = "open".encode_utf16().chain([0]).collect();
    let w: Vec<u16> = path.encode_utf16().chain([0]).collect();
    let r = unsafe { ShellExecuteW(std::ptr::null_mut(), verb.as_ptr(), w.as_ptr(), std::ptr::null(), std::ptr::null(), SW_SHOWNORMAL) };
    if r as isize > 32 { Ok(()) } else { Err(path) }
}

/// Starts a program with one argument; the program keeps running.
#[tauri::command]
pub fn run_program(exe: String, arg: String) -> Result<(), String> {
    std::process::Command::new(&exe).arg(arg).spawn().map(|_| ()).map_err(|e| spawn_err(&exe, e))
}

#[derive(Serialize)]
pub struct PlayWithEntry {
    path: String,
    name: String,
}

// from: RebuildPlayWith
#[tauri::command]
pub async fn play_with_list() -> Vec<PlayWithEntry> {
    let ini = load_ini().ok();
    let list = |sec: &str| ini.as_ref().map(|i| read_list(i, sec)).unwrap_or_default();
    shell::known_players(&list("Players"), &list("ExtraPlayers"))
        .into_iter()
        .map(|p| PlayWithEntry { name: shell::program_name(&p), path: p.to_string_lossy().into_owned() })
        .collect()
}

// ---------- the player ----------

#[derive(Default)]
pub struct PlayerHolder(Mutex<Option<Player>>);

fn with_player<T>(h: &PlayerHolder, f: impl FnOnce(&Player) -> T) -> T {
    let mut g = h.0.lock().unwrap_or_else(|e| e.into_inner());
    f(g.get_or_insert_with(Player::new))
}

#[tauri::command]
pub async fn player_play(h: State<'_, PlayerHolder>, path: String, volume: f32) -> Result<(), String> {
    with_player(&h, |p| p.play(&path, volume))
}
#[tauri::command]
pub fn player_pause(h: State<'_, PlayerHolder>) {
    with_player(&h, |p| p.pause())
}
#[tauri::command]
pub fn player_resume(h: State<'_, PlayerHolder>) {
    with_player(&h, |p| p.resume())
}
#[tauri::command]
pub fn player_stop(h: State<'_, PlayerHolder>) {
    with_player(&h, |p| p.stop())
}
#[tauri::command]
pub fn player_seek(h: State<'_, PlayerHolder>, seconds: f64) {
    with_player(&h, |p| p.seek(seconds))
}
#[tauri::command]
pub fn player_volume(h: State<'_, PlayerHolder>, v: f32) {
    with_player(&h, |p| p.set_volume(v))
}
#[tauri::command]
pub fn player_status(h: State<'_, PlayerHolder>) -> PlayerStatus {
    with_player(&h, |p| p.status())
}
#[tauri::command]
pub async fn player_available_cmd() -> bool {
    player_available()
}

// ---------- the app and its start ----------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppInfo {
    version: String,
    settings_file: String,
}

#[tauri::command]
pub fn app_info(app: AppHandle) -> AppInfo {
    AppInfo { version: app.package_info().version.to_string(), settings_file: settings_path().to_string_lossy().into_owned() }
}

/// The paths this start was given by Explorer; handed out once.
#[derive(Default)]
pub struct StartPaths(pub Mutex<Option<Vec<String>>>);

#[tauri::command]
pub fn start_paths(s: State<'_, StartPaths>) -> Vec<String> {
    s.0.lock().map(|mut g| g.take().unwrap_or_default()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track_of(path: &str) -> RenameTrack {
        serde_json::from_value(serde_json::json!({ "path": path, "fields": {} })).unwrap()
    }

    #[test]
    fn files_commands_round_trip() {
        let d = std::env::temp_dir().join(format!("tidytag-filescmd-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        let a = d.join("a.mp3");
        std::fs::write(&a, b"x").unwrap();
        let sub = create_folder_at(&d.to_string_lossy(), "sub").unwrap();
        let r = copy_move(&[a.to_string_lossy().into_owned()], &sub, false);
        assert_eq!(r.count, 1);
        let copy = r.new_names[0].to_string_lossy().into_owned();
        let rec = recycle(&[copy.clone()]);
        assert_eq!((rec.gone, rec.exists.clone()), (1, vec![false]), "{:?}", rec.errors);
        let target = d.join("x.m3u8");
        let ini = tidytag_core::settings::Ini::load(&d.join("none.ini")).unwrap();
        write_playlist(&target.to_string_lossy(), &[track_of(&a.to_string_lossy())], false, &ini).unwrap();
        let text = std::fs::read_to_string(&target).unwrap();
        assert!(text.starts_with("#EXTM3U\r\n"), "{text}");
        assert!(text.contains("\r\na.mp3\r\n"), "{text}");
        std::fs::remove_dir_all(&d).unwrap();
    }
}
