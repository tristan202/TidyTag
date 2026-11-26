//! Tauri commands and events: the only way the renderer reaches files and settings.

use base64::Engine;
use serde::Serialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, State};
use tidytag_core::dirs::{self, DirEntry};
use tidytag_core::model::{AudioInfo, TagField, PIC_TYPE_FRONT_COVER};
use tidytag_core::read::read_audio_info;
use tidytag_core::scan;
use tidytag_core::settings::{settings_path, Ini};

fn err(e: impl ToString) -> String {
    e.to_string()
}

// The settings file is read fresh for every call: TidyTag 1.2 may have changed it meanwhile.

#[tauri::command]
pub fn settings_get(section: String, key: String) -> Result<Option<String>, String> {
    Ok(Ini::load(&settings_path()).map_err(err)?.get(&section, &key).map(str::to_string))
}

#[tauri::command]
pub fn settings_set(section: String, key: String, value: String) -> Result<(), String> {
    let mut ini = Ini::load(&settings_path()).map_err(err)?;
    ini.set(&section, &key, &value);
    ini.save().map_err(err)
}

#[tauri::command]
pub fn settings_section(section: String) -> Result<Vec<[String; 2]>, String> {
    Ok(Ini::load(&settings_path()).map_err(err)?.section(&section).into_iter().map(|(k, v)| [k, v]).collect())
}

/// Erase + rewrite in one go (1.2's way of storing lists such as Favorites).
#[tauri::command]
pub fn settings_write_section(section: String, entries: Vec<[String; 2]>) -> Result<(), String> {
    let mut ini = Ini::load(&settings_path()).map_err(err)?;
    ini.erase_section(&section);
    for [k, v] in entries {
        ini.set(&section, &k, &v);
    }
    ini.save().map_err(err)
}

#[tauri::command]
pub fn settings_erase_section(section: String) -> Result<(), String> {
    settings_write_section(section, Vec::new())
}

// async: drives and folders can be slow (network), so they run off the window's thread
#[tauri::command]
pub async fn list_drives() -> Vec<DirEntry> {
    dirs::list_drives()
}

#[tauri::command]
pub async fn list_dirs(path: String) -> Vec<DirEntry> {
    dirs::list_dirs(Path::new(&path))
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct TrackDto {
    path: String,
    folder: String,
    file_name: String,
    file_size: u64,
    fields: BTreeMap<TagField, String>,
    tag_types: String,
    codec: String,
    has_cover: bool,
    duration: f64,
    bitrate: u32,
    sample_rate: u32,
    channels: u32,
    bit_depth: u32,
    supported: bool,
    error: String,
}

impl From<AudioInfo> for TrackDto {
    fn from(i: AudioInfo) -> TrackDto {
        TrackDto {
            folder: i.path.parent().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default(),
            file_name: i.path.file_name().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default(),
            path: i.path.to_string_lossy().into_owned(),
            file_size: i.file_size,
            tag_types: i.tag_types_text(),
            fields: i.fields,
            codec: i.codec,
            has_cover: i.has_cover,
            duration: i.duration,
            bitrate: i.bitrate,
            sample_rate: i.sample_rate,
            channels: i.channels,
            bit_depth: i.bit_depth,
            supported: i.supported,
            error: i.error,
        }
    }
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ScanBatch {
    scan_id: u32,
    tracks: Vec<TrackDto>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ScanProgress {
    scan_id: u32,
    done: usize,
    total: usize,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ScanDone {
    scan_id: u32,
    count: usize,
}

/// The cancel flag of the running scan.
#[derive(Default)]
pub struct ScanState(Mutex<Arc<AtomicBool>>);

/// Starts reading a folder on its own thread; a running scan is cancelled first.
/// Results arrive as `scan-batch`, `scan-progress` and `scan-done` events with this scanId.
#[tauri::command]
pub fn scan_start(app: AppHandle, state: State<ScanState>, path: String, subfolders: bool, scan_id: u32) {
    let cancel = Arc::new(AtomicBool::new(false));
    {
        let mut cur = state.0.lock().unwrap();
        cur.store(true, Ordering::Relaxed);
        *cur = cancel.clone();
    }
    std::thread::spawn(move || {
        let count = scan::scan(
            Path::new(&path),
            subfolders,
            &cancel,
            |batch| {
                let tracks = batch.into_iter().map(TrackDto::from).collect();
                let _ = app.emit("scan-batch", ScanBatch { scan_id, tracks });
            },
            |done, total| {
                let _ = app.emit("scan-progress", ScanProgress { scan_id, done, total });
            },
        );
        let _ = app.emit("scan-done", ScanDone { scan_id, count });
    });
}

#[tauri::command]
pub fn scan_cancel(state: State<ScanState>) {
    state.0.lock().unwrap().store(true, Ordering::Relaxed);
}

#[derive(Serialize)]
pub struct Cover {
    mime: String,
    data: String,
}

fn cover(mime: &str, data: &[u8]) -> Cover {
    Cover { mime: mime.to_string(), data: base64::engine::general_purpose::STANDARD.encode(data) }
}

/// The front cover of a file, otherwise its first picture.
#[tauri::command]
pub async fn read_cover(path: String) -> Option<Cover> {
    let info = read_audio_info(Path::new(&path), true);
    let pic = info.pictures.iter().find(|p| p.pic_type == PIC_TYPE_FRONT_COVER).or(info.pictures.first())?;
    Some(cover(&pic.mime, &pic.data))
}

/// folder.jpg, folder.png, cover.jpg, cover.png, front.jpg, front.png (1.2's order).
#[tauri::command]
pub async fn folder_cover(dir: String) -> Option<Cover> {
    const NAMES: [&str; 6] = ["folder.jpg", "folder.png", "cover.jpg", "cover.png", "front.jpg", "front.png"];
    NAMES.iter().map(|n| PathBuf::from(&dir).join(n)).find(|p| p.is_file()).and_then(|p| {
        let data = std::fs::read(&p).ok()?;
        let mime = tidytag_core::model::detect_image_mime(&data, "image/jpeg").to_string();
        Some(cover(&mime, &data))
    })
}
