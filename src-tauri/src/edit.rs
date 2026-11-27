//! Commands for the tag editors, tag tools and cover tools (phase 3).

use crate::commands::{cover, file_name, run_batch, write_options, Cover, Outcome, PictureDto, TrackDto, WriteState};
use base64::Engine;
use serde::Serialize;
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use tauri::{AppHandle, State};
use tidytag_core::cover::{find_folder_cover, folder_cover_target, main_picture, resize_cover, CoverResize};
use tidytag_core::fileio::recycle_files;
use tidytag_core::id3sync::{sync_id3, SyncDirection, SyncExisting};
use tidytag_core::model::{detect_image_mime, TagField};
use tidytag_core::read::read_audio_info;
use tidytag_core::tagremove::remove_all_tags;
use tidytag_core::write::{can_write_tags, write_audio_tags};

const MAX_IMAGE: u64 = 16 * 1024 * 1024;

#[derive(Serialize)]
pub struct TagDto {
    track: TrackDto,
    pictures: Vec<PictureDto>,
}

/// A file with its pictures, for the tag editor.
#[tauri::command]
pub async fn read_tag(path: String) -> TagDto {
    let info = read_audio_info(Path::new(&path), true);
    let pictures = info.pictures.iter().map(PictureDto::from_picture).collect();
    TagDto { track: TrackDto::from(info), pictures }
}

/// The tag editor's Save: the given fields, and exactly the given pictures.
#[tauri::command]
pub async fn save_tag(
    state: State<'_, WriteState>,
    path: String,
    fields: BTreeMap<String, String>,
    pictures: Vec<PictureDto>,
) -> Result<TrackDto, String> {
    let _busy = state.claim()?;
    let p = Path::new(&path);
    let mut info = read_audio_info(p, true);
    if !info.error.is_empty() {
        return Err(info.error);
    }
    for (k, v) in &fields {
        if let Some(f) = TagField::from_key(k) {
            info.put(f, v);
        }
    }
    info.pictures = pictures.iter().filter_map(PictureDto::to_picture).collect();
    write_audio_tags(&mut info, &write_options())?;
    Ok(TrackDto::from(read_audio_info(p, false)))
}

fn path_of(p: &String) -> &str {
    p
}

/// Fjern tags (1.2's ActRemoveTags).
#[tauri::command]
pub fn remove_tags_batch(app: AppHandle, state: State<WriteState>, paths: Vec<String>, batch_id: u32) -> Result<(), String> {
    run_batch(app, &state, paths, batch_id, path_of, |p, opt| match remove_all_tags(Path::new(p), opt) {
        Ok(()) => Outcome::Saved(read_audio_info(Path::new(p), false)),
        Err(e) => Outcome::Failed(e),
    })
}

/// MP3 tag sync (1.2's RunID3Sync); files that need no change are skipped.
#[tauri::command]
pub fn id3_sync_batch(
    app: AppHandle,
    state: State<WriteState>,
    paths: Vec<String>,
    direction: SyncDirection,
    existing: SyncExisting,
    batch_id: u32,
) -> Result<(), String> {
    run_batch(app, &state, paths, batch_id, path_of, move |p, opt| match sync_id3(Path::new(p), direction, existing, opt) {
        Ok(true) => Outcome::Saved(read_audio_info(Path::new(p), false)),
        Ok(false) => Outcome::Skipped,
        Err(e) => Outcome::Failed(e),
    })
}

/// Which of the folders have a folder cover (folder.jpg ... front.png).
#[tauri::command]
pub async fn folder_covers(dirs: Vec<String>) -> Vec<bool> {
    dirs.iter().map(|d| find_folder_cover(Path::new(d)).is_some()).collect()
}

/// The folder's cover into each file (1.2's ActCoverToTags); files in folders without a
/// JPEG/PNG cover are skipped.
#[tauri::command]
pub fn cover_to_tags_batch(app: AppHandle, state: State<WriteState>, paths: Vec<String>, batch_id: u32) -> Result<(), String> {
    let cache = std::sync::Mutex::new(HashMap::<PathBuf, Option<Vec<u8>>>::new());
    run_batch(app, &state, paths, batch_id, path_of, move |p, opt| {
        let dir = Path::new(p).parent().map(Path::to_path_buf).unwrap_or_default();
        let data = cache
            .lock()
            .unwrap()
            .entry(dir.clone())
            .or_insert_with(|| {
                find_folder_cover(&dir).and_then(|f| std::fs::read(f).ok()).filter(|d| !detect_image_mime(d, "").is_empty())
            })
            .clone();
        match data {
            None => Outcome::Skipped,
            Some(d) => tidytag_core::batch::update_file_tags(Path::new(p), &BTreeMap::new(), Some(d), None, opt).into(),
        }
    })
}

#[derive(Serialize)]
pub struct FolderResult {
    done: usize,
    errors: Vec<String>,
}

/// Each file's cover as folder.jpg/png in its folder, unless the folder has a cover by now
/// (1.2's ActCoverFromTags; the renderer gives one file with a cover per folder).
#[tauri::command]
pub async fn cover_from_tags(paths: Vec<String>) -> FolderResult {
    let mut r = FolderResult { done: 0, errors: Vec::new() };
    for p in &paths {
        let dir = Path::new(p).parent().unwrap_or(Path::new(""));
        if find_folder_cover(dir).is_some() {
            continue;
        }
        let info = read_audio_info(Path::new(p), true);
        let Some(pic) = main_picture(&info) else { continue };
        let target = folder_cover_target(dir, &pic.mime);
        match std::fs::write(&target, &pic.data) {
            Ok(()) => r.done += 1,
            Err(e) => r.errors.push(format!("{}: {e}", target.display())),
        }
    }
    r
}

#[derive(Serialize)]
pub struct AsFolder {
    target: String,
    written: bool,
}

/// The file's cover as folder.jpg/png (1.2's ActCoverAsFolder). An existing target is only
/// replaced with `replace`; otherwise `written` is false and the renderer asks first.
#[tauri::command]
pub async fn cover_as_folder(path: String, replace: bool) -> Result<AsFolder, String> {
    let info = read_audio_info(Path::new(&path), true);
    let pic = main_picture(&info).ok_or("no picture")?;
    let target = folder_cover_target(Path::new(&path).parent().unwrap_or(Path::new("")), &pic.mime);
    let shown = target.to_string_lossy().into_owned();
    if target.exists() && !replace {
        return Ok(AsFolder { target: shown, written: false });
    }
    std::fs::write(&target, &pic.data).map_err(|e| e.to_string())?;
    Ok(AsFolder { target: shown, written: true })
}

/// Skaler cover i filerne (1.2's ResizeFileCovers); files with nothing to resize are skipped.
#[tauri::command]
pub fn resize_file_covers_batch(
    app: AppHandle,
    state: State<WriteState>,
    paths: Vec<String>,
    opt: CoverResize,
    batch_id: u32,
) -> Result<(), String> {
    run_batch(app, &state, paths, batch_id, path_of, move |p, wopt| {
        let path = Path::new(p);
        if !can_write_tags(path) {
            return Outcome::Skipped;
        }
        let mut full = read_audio_info(path, true);
        if !full.error.is_empty() {
            return Outcome::Skipped; // 1.2: no cover to resize
        }
        let mut any = false;
        for pic in &mut full.pictures {
            if let Some((data, mime)) = resize_cover(&pic.data, &opt) {
                pic.data = data;
                pic.mime = mime.to_string();
                any = true;
            }
        }
        if !any {
            return Outcome::Skipped;
        }
        match write_audio_tags(&mut full, wopt) {
            Ok(()) => Outcome::Saved(read_audio_info(path, false)),
            Err(e) => Outcome::Failed(e),
        }
    })
}

/// Skaler mappe-cover (1.2's ResizeFolderCovers). A PNG that became JPEG is saved as .jpg
/// and the PNG goes to the recycle bin.
#[tauri::command]
pub async fn resize_folder_covers(dirs: Vec<String>, opt: CoverResize) -> FolderResult {
    let mut r = FolderResult { done: 0, errors: Vec::new() };
    for d in &dirs {
        let Some(path) = find_folder_cover(Path::new(d)) else { continue };
        let result = (|| -> Result<bool, String> {
            let Some((data, mime)) = resize_cover(&std::fs::read(&path).map_err(|e| e.to_string())?, &opt) else {
                return Ok(false);
            };
            let png = path.extension().is_some_and(|e| e.eq_ignore_ascii_case("png"));
            let target = if mime == "image/jpeg" && png { path.with_extension("jpg") } else { path.clone() };
            std::fs::write(&target, &data).map_err(|e| e.to_string())?;
            if target != path {
                recycle_files(&[path.clone()], &mut r.errors);
            }
            Ok(true)
        })();
        match result {
            Ok(true) => r.done += 1,
            Ok(false) => {}
            Err(e) => r.errors.push(format!("{}: {e}", path.display())),
        }
    }
    r
}

/// "dir", "file" or "none": a dropped folder opens it; an existing folder.jpg is asked about.
#[tauri::command]
pub async fn path_kind(path: String) -> &'static str {
    match std::fs::metadata(&path) {
        Ok(m) if m.is_dir() => "dir",
        Ok(_) => "file",
        Err(_) => "none",
    }
}

/// A JPEG/PNG picture file of at most 16 MB. Errors: "notImage" or "tooLarge".
fn read_image(path: &Path) -> Result<Cover, String> {
    let len = std::fs::metadata(path).map_err(|e| e.to_string())?.len();
    if len > MAX_IMAGE {
        return Err("tooLarge".into());
    }
    let data = std::fs::read(path).map_err(|e| e.to_string())?;
    match detect_image_mime(&data, "") {
        m @ ("image/jpeg" | "image/png") => Ok(cover(m, &data)),
        _ => Err("notImage".into()),
    }
}

#[tauri::command]
pub async fn read_image_file(path: String) -> Result<Cover, String> {
    read_image(Path::new(&path))
}

/// A text file (lyrics): UTF-8 with or without BOM.
#[tauri::command]
pub async fn read_text_file(path: String) -> Result<String, String> {
    let data = std::fs::read(&path).map_err(|e| e.to_string())?;
    let body = data.strip_prefix(b"\xEF\xBB\xBF").unwrap_or(&data);
    // shortcut: non-UTF-8 bytes become U+FFFD, as Lazarus's LoadFromFile also assumes UTF-8
    Ok(String::from_utf8_lossy(body).into_owned())
}

/// "Gem som..." for lyrics and pictures: the bytes (base64) to the chosen file.
#[tauri::command]
pub async fn write_file(path: String, data: String) -> Result<(), String> {
    let bytes = base64::engine::general_purpose::STANDARD.decode(data).map_err(|e| e.to_string())?;
    std::fs::write(&path, bytes).map_err(|e| format!("{}: {e}", file_name(Path::new(&path))))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_image_file_rejects_non_images() {
        let dir = std::env::temp_dir().join(format!("tidytag-readimage-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let txt = dir.join("a.txt");
        std::fs::write(&txt, "hello").unwrap();
        let empty = dir.join("b.jpg");
        std::fs::write(&empty, b"").unwrap();
        let big = dir.join("c.jpg");
        let mut data = vec![0xFF, 0xD8, 0xFF];
        data.resize(17 * 1024 * 1024, 0);
        std::fs::write(&big, &data).unwrap();
        assert_eq!(read_image(&txt).err().as_deref(), Some("notImage"));
        assert_eq!(read_image(&empty).err().as_deref(), Some("notImage"));
        assert_eq!(read_image(&big).err().as_deref(), Some("tooLarge"));
        let ok = dir.join("d.jpg");
        std::fs::write(&ok, [0xFF, 0xD8, 0xFF, 0xE0]).unwrap();
        assert_eq!(read_image(&ok).unwrap().mime, "image/jpeg");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
