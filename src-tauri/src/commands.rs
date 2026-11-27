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
    let mime = tidytag_core::model::safe_image_mime(mime, data);
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

// ---------- writing tags ----------

#[derive(serde::Deserialize)]
pub struct WriteItem {
    path: String,
    /// field key -> value ('' clears the field)
    values: BTreeMap<String, String>,
    /// a new front cover, base64
    cover: Option<String>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct WriteProgress {
    batch_id: u32,
    done: usize,
    total: usize,
}

#[derive(Serialize, Clone)]
struct WriteError {
    file: String,
    error: String,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct WriteDone {
    batch_id: u32,
    saved: usize,
    failed: usize,
    skipped: usize,
    errors: Vec<WriteError>,
    tracks: Vec<TrackDto>,
}

/// Set while a batch runs; a second batch is refused.
#[derive(Default)]
pub struct WriteState(Arc<AtomicBool>);

/// The settings that change a write ([Tags] ID3Unicode, [Main] AlbumArtistRule,
/// [Editor] KeepTimestamp), read fresh for every batch; defaults if the file cannot be read.
fn write_options() -> tidytag_core::write::WriteOptions {
    let ini = Ini::load(&settings_path()).ok();
    let get = |s: &str, k: &str| ini.as_ref().and_then(|i| i.get(s, k).map(str::to_string));
    let bool = |s: &str, k: &str| get(s, k).is_some_and(|v| !matches!(v.to_ascii_lowercase().as_str(), "" | "0" | "false"));
    tidytag_core::write::WriteOptions {
        id3_always_unicode: bool("Tags", "ID3Unicode"),
        album_artist_rule: get("Main", "AlbumArtistRule").and_then(|v| v.trim().parse().ok()).unwrap_or(0).min(2),
        keep_timestamp: bool("Editor", "KeepTimestamp"),
    }
}

/// Writes each item's values (and cover) on its own thread, like 1.2's WriteFieldsBatch.
/// Progress arrives as `write-progress`, the result as `write-done` with the files read again.
#[tauri::command]
pub fn write_tags_batch(app: AppHandle, state: State<WriteState>, items: Vec<WriteItem>, batch_id: u32) -> Result<(), String> {
    if state.0.swap(true, Ordering::SeqCst) {
        return Err("busy".into());
    }
    let busy = state.0.clone();
    std::thread::spawn(move || {
        let opt = write_options();
        let total = items.len();
        let mut done = WriteDone { batch_id, saved: 0, failed: 0, skipped: 0, errors: Vec::new(), tracks: Vec::new() };
        for (i, it) in items.into_iter().enumerate() {
            let _ = app.emit("write-progress", WriteProgress { batch_id, done: i + 1, total });
            let values = it.values.iter().filter_map(|(k, v)| TagField::from_key(k).map(|f| (f, v.clone()))).collect();
            let cover = it.cover.and_then(|c| base64::engine::general_purpose::STANDARD.decode(c).ok());
            match tidytag_core::batch::update_file_tags(Path::new(&it.path), &values, cover, &opt) {
                Ok(info) => {
                    done.saved += 1;
                    done.tracks.push(TrackDto::from(info));
                }
                Err((_, true)) => done.skipped += 1,
                Err((e, false)) => {
                    done.failed += 1;
                    if done.errors.len() < 20 {
                        let file = Path::new(&it.path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                        done.errors.push(WriteError { file, error: e });
                    }
                }
            }
        }
        busy.store(false, Ordering::SeqCst);
        let _ = app.emit("write-done", done);
    });
    Ok(())
}

/// 1.2's GenreList: the ID3 genres minus [HiddenGenres], plus [CustomGenres], sorted and
/// without duplicates, both case-insensitively.
#[tauri::command]
pub fn genre_list() -> Vec<String> {
    let ini = Ini::load(&settings_path()).ok();
    let values = |sec: &str| -> Vec<String> {
        ini.as_ref().map(|i| i.section(sec).into_iter().map(|(_, v)| v).collect()).unwrap_or_default()
    };
    let unquote = |s: &str| if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') { s[1..s.len() - 1].to_string() } else { s.to_string() };
    let hidden = values("HiddenGenres");
    let mut list: Vec<String> = tidytag_core::text::id3_genres()
        .iter()
        .filter(|g| !hidden.iter().any(|h| h.eq_ignore_ascii_case(g)))
        .map(|g| g.to_string())
        .collect();
    list.extend(values("CustomGenres").iter().map(|c| unquote(c).trim().to_string()).filter(|c| !c.is_empty()));
    list.sort_by_key(|g| g.to_lowercase());
    list.dedup_by(|a, b| a.eq_ignore_ascii_case(b));
    list
}
