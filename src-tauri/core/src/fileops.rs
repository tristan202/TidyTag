//! File operations on the list's files: copy or move to a folder, new folders, folder covers
//! and extension changes. Existing files at the target are never overwritten.
// from: fileops.pas (phone paths come with phase 9)

use crate::rename::{os_error_text, same_file_name, sanitize_name_part, PlanItem, RenameStatus};
use std::path::{Path, PathBuf};

const EXISTS_IN_TARGET: &str = "findes allerede i målmappen";
const CANNOT_CREATE: &str = "Mappen kunne ikke oprettes:";

pub const FOLDER_COVER_NAMES: [&str; 6] = ["folder.jpg", "folder.png", "cover.jpg", "cover.png", "front.jpg", "front.png"];

#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CopyMoveResult {
    pub done: Vec<bool>,
    pub new_names: Vec<PathBuf>,
    pub errors: Vec<String>,
    pub count: usize,
}

fn name_of(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

#[cfg(windows)]
fn wide(p: &Path) -> Vec<u16> {
    use std::os::windows::ffi::OsStrExt;
    p.as_os_str().encode_wide().chain([0]).collect()
}

#[cfg(windows)]
fn copy_or_move_one(src: &Path, target: &Path, do_move: bool) -> bool {
    use windows_sys::Win32::Storage::FileSystem::{CopyFileW, MoveFileExW, MOVEFILE_COPY_ALLOWED};
    let (a, b) = (wide(src), wide(target));
    unsafe {
        if do_move {
            MoveFileExW(a.as_ptr(), b.as_ptr(), MOVEFILE_COPY_ALLOWED) != 0
        } else {
            CopyFileW(a.as_ptr(), b.as_ptr(), 1) != 0 // fail if it exists
        }
    }
}

#[cfg(not(windows))]
fn copy_or_move_one(src: &Path, target: &Path, do_move: bool) -> bool {
    !target.exists() && if do_move { std::fs::rename(src, target).is_ok() } else { std::fs::copy(src, target).is_ok() }
}

// from: CopyOrMoveFiles
pub fn copy_or_move_files(files: &[PathBuf], dir: &Path, do_move: bool) -> CopyMoveResult {
    let mut r = CopyMoveResult { done: vec![false; files.len()], new_names: files.to_vec(), ..Default::default() };
    for (i, f) in files.iter().enumerate() {
        let target = dir.join(f.file_name().unwrap_or_default());
        let abs = |p: &Path| std::path::absolute(p).unwrap_or_else(|_| p.to_path_buf()).to_string_lossy().into_owned();
        if same_file_name(&abs(&target), &abs(f)) {
            continue;
        }
        if target.exists() {
            r.errors.push(format!("{}: {EXISTS_IN_TARGET}", name_of(f)));
            continue;
        }
        if copy_or_move_one(f, &target, do_move) {
            r.done[i] = true;
            r.new_names[i] = target;
            r.count += 1;
        } else {
            r.errors.push(format!("{}: {}", name_of(f), os_error_text()));
        }
    }
    r
}

/// The folder covers that exist in `dirs`, folder by folder in 1.2's name order.
// from: ActDeleteFolderCoversExecute
pub fn folder_cover_files(dirs: &[PathBuf]) -> Vec<PathBuf> {
    dirs.iter().flat_map(|d| FOLDER_COVER_NAMES.iter().map(move |n| d.join(n))).filter(|p| p.is_file()).collect()
}

/// `Err("")` for a name that is empty after cleaning, otherwise 1.2's error text.
// from: ActNewFolderExecute
pub fn create_folder(parent: &Path, name: &str) -> Result<PathBuf, String> {
    let name = sanitize_name_part(name);
    if name.is_empty() {
        return Err(String::new());
    }
    let dir = parent.join(&name);
    if dir.exists() || std::fs::create_dir_all(&dir).is_err() {
        return Err(CANNOT_CREATE.into());
    }
    Ok(dir)
}

/// The renames of an extension change; an existing target is `Exists` (the caller shows
/// rsFiltypeFindes with the new name).
// from: ActChangeExtExecute
pub fn plan_ext_change(files: &[PathBuf], kind: usize) -> Vec<PlanItem> {
    const FROM_EXT: [&str; 3] = [".mp4", ".mp4.m4a.m4p", ".m4b"];
    const TO_EXT: [&str; 3] = [".m4a", ".m4b", ".m4a"];
    let (from, to) = (FROM_EXT[kind.min(2)], TO_EXT[kind.min(2)]);
    let mut plan = Vec::new();
    for f in files {
        let ext = f.extension().map(|e| format!(".{}", e.to_string_lossy().to_lowercase())).unwrap_or_default();
        if ext.is_empty() || !from.contains(&ext) || ext == to {
            continue;
        }
        let new_name = f.with_extension(&to[1..]);
        let status = if new_name.exists() { RenameStatus::Exists } else { RenameStatus::Ok };
        plan.push(PlanItem {
            old_name: f.to_string_lossy().into_owned(),
            new_name: new_name.to_string_lossy().into_owned(),
            status,
            detail: String::new(),
        });
    }
    plan
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rename::RenameStatus;
    use std::fs;
    use std::path::PathBuf;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("tidytag-fileops-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn copy_move_never_overwrites() {
        let d = tmp("cm");
        let dst = d.join("dst");
        fs::create_dir(&dst).unwrap();
        fs::write(d.join("a.mp3"), b"aaa").unwrap();
        fs::write(d.join("b.mp3"), b"bbb").unwrap();
        fs::write(dst.join("b.mp3"), b"old").unwrap();
        let files = [d.join("a.mp3"), d.join("b.mp3")];
        let r = copy_or_move_files(&files, &dst, false);
        assert_eq!(r.count, 1);
        assert_eq!(r.done, vec![true, false]);
        assert_eq!(r.errors.len(), 1);
        assert!(r.errors[0].ends_with(": findes allerede i målmappen"), "{:?}", r.errors);
        assert_eq!(fs::read(dst.join("b.mp3")).unwrap(), b"old");
        assert_eq!(fs::read(dst.join("a.mp3")).unwrap(), b"aaa");
        assert!(d.join("a.mp3").exists());
        // onto itself: skipped silently
        let r = copy_or_move_files(&files, &d, false);
        assert_eq!(r.count, 0);
        assert!(r.errors.is_empty(), "{:?}", r.errors);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn move_renames_across_folders() {
        let d = tmp("mv");
        let dst = d.join("dst");
        fs::create_dir(&dst).unwrap();
        fs::write(d.join("a.mp3"), b"aaa").unwrap();
        let r = copy_or_move_files(&[d.join("a.mp3")], &dst, true);
        assert_eq!(r.count, 1);
        assert_eq!(r.new_names[0], dst.join("a.mp3"));
        assert!(!d.join("a.mp3").exists());
        assert!(dst.join("a.mp3").exists());
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn folder_covers_found_in_order() {
        let d = tmp("fc");
        fs::write(d.join("cover.png"), b"x").unwrap();
        fs::write(d.join("folder.jpg"), b"x").unwrap();
        assert_eq!(folder_cover_files(&[d.clone()]), vec![d.join("folder.jpg"), d.join("cover.png")]);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn new_folder_sanitized() {
        let d = tmp("nf");
        let p = create_folder(&d, "AC/DC: Live?").unwrap();
        let name = p.file_name().unwrap().to_string_lossy().into_owned();
        assert!(!name.contains(['/', ':', '?']), "{name}");
        assert!(p.is_dir());
        assert_eq!(create_folder(&d, "AC/DC: Live?"), Err("Mappen kunne ikke oprettes:".to_string()));
        assert_eq!(create_folder(&d, "  "), Err(String::new()));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn ext_change_plans_only_matching() {
        let d = tmp("ext");
        for f in ["a.mp4", "b.m4a", "c.m4b", "d.mp3"] {
            fs::write(d.join(f), b"x").unwrap();
        }
        let files: Vec<PathBuf> = ["a.mp4", "b.m4a", "c.m4b", "d.mp3"].iter().map(|f| d.join(f)).collect();
        let plan = plan_ext_change(&files, 1);
        assert_eq!(plan.len(), 2);
        assert!(plan[0].new_name.ends_with("a.m4b"));
        assert!(plan[1].new_name.ends_with("b.m4b"));
        assert!(plan.iter().all(|p| p.status == RenameStatus::Ok));
        fs::write(d.join("b.m4b"), b"x").unwrap();
        let plan = plan_ext_change(&files, 1);
        assert_eq!(plan[1].status, RenameStatus::Exists);
        fs::remove_dir_all(&d).unwrap();
    }
}
