//! Finds audio files in a folder and reads their tags in batches (port of scanthread.pas).

use crate::model::AudioInfo;
use crate::read::{is_audio_file, read_audio_info};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

pub const BATCH: usize = 200;

fn sort_key(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().to_lowercase()).unwrap_or_default()
}

// from: TScanThread.CollectFiles — a folder's files first (name order), then its subfolders
fn collect(dir: &Path, subfolders: bool, cancel: &AtomicBool, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    let mut files = Vec::new();
    let mut dirs = Vec::new();
    for e in rd.flatten() {
        if cancel.load(Ordering::Relaxed) {
            return;
        }
        let p = e.path();
        match e.file_type() {
            Ok(t) if t.is_dir() => {
                if subfolders {
                    dirs.push(p);
                }
            }
            Ok(_) if is_audio_file(&p) => files.push(p),
            _ => {}
        }
    }
    files.sort_by_key(|p| sort_key(p));
    dirs.sort_by_key(|p| sort_key(p));
    out.extend(files);
    for d in dirs {
        collect(&d, true, cancel, out);
    }
}

/// Lists the audio files, then reads them (without picture data) and hands them over in
/// batches of `BATCH`. Checks `cancel` between files. Returns the number of files read.
pub fn scan(
    dir: &Path,
    subfolders: bool,
    cancel: &AtomicBool,
    mut on_batch: impl FnMut(Vec<AudioInfo>),
    mut on_progress: impl FnMut(usize, usize),
) -> usize {
    let mut files = Vec::new();
    collect(dir, subfolders, cancel, &mut files);
    let total = files.len();
    on_progress(0, total);
    let mut batch = Vec::with_capacity(BATCH);
    let mut done = 0;
    for f in &files {
        if cancel.load(Ordering::Relaxed) {
            break;
        }
        batch.push(read_audio_info(f, false));
        done += 1;
        if batch.len() == BATCH {
            on_batch(std::mem::take(&mut batch));
            on_progress(done, total);
        }
    }
    if !batch.is_empty() {
        on_batch(batch);
        on_progress(done, total);
    }
    done
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(name: &str, n: usize) -> PathBuf {
        let d = std::env::temp_dir().join(format!("tidytag-scan-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        for i in 0..n {
            std::fs::write(d.join(format!("{i:04}.mp3")), b"").unwrap();
        }
        d
    }

    #[test]
    fn scan_streams_batches() {
        let d = folder("batches", 450);
        let mut sizes = Vec::new();
        let n = scan(&d, false, &AtomicBool::new(false), |b| sizes.push(b.len()), |_, _| {});
        assert_eq!(n, 450);
        assert_eq!(sizes, vec![200, 200, 50]);
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn cancel_stops_scan() {
        let d = folder("cancel", 450);
        let cancel = AtomicBool::new(false);
        let mut got = 0;
        let n = scan(&d, false, &cancel, |b| { got += b.len(); cancel.store(true, Ordering::Relaxed); }, |_, _| {});
        assert!(n < 450 && got < 450, "read {n}");
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn scan_reads_unicode_and_long_paths() {
        let d = folder("unicode", 0);
        std::fs::write(d.join("Ægir — 東京.mp3"), b"").unwrap();
        let mut deep = d.clone();
        while deep.as_os_str().len() < 300 {
            deep = deep.join("en meget lang mappe med et langt navn");
        }
        std::fs::create_dir_all(&deep).unwrap();
        std::fs::write(deep.join("dyb.mp3"), b"").unwrap();
        let mut names = Vec::new();
        scan(&d, true, &AtomicBool::new(false), |b| names.extend(b.into_iter().map(|i| (i.path, i.error))), |_, _| {});
        assert_eq!(names.len(), 2, "{names:?}");
        assert!(names.iter().all(|(_, e)| e.is_empty()), "{names:?}");
        assert!(names.iter().any(|(p, _)| p.to_string_lossy().contains("東京")));
        assert!(names.iter().any(|(p, _)| p.as_os_str().len() > 300));
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn subfolders_flag() {
        let d = folder("sub", 1);
        std::fs::create_dir_all(d.join("sub")).unwrap();
        std::fs::write(d.join("sub").join("x.flac"), b"").unwrap();
        let count = |sub| scan(&d, sub, &AtomicBool::new(false), |_| {}, |_, _| {});
        assert_eq!(count(false), 1);
        assert_eq!(count(true), 2);
        std::fs::remove_dir_all(d).unwrap();
    }
}
