//! Writing helpers from tagutils.pas: temp file + replace, copying audio, file times.

use std::fs::{File, FileTimes};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// Name of a temporary file next to `target` (1.2's TempFileFor).
pub fn temp_file_for(target: &Path) -> PathBuf {
    let mut s = target.as_os_str().to_owned();
    s.push(".tidytag-tmp");
    PathBuf::from(s)
}

/// Replaces `target` by `temp` (same folder), as atomically as Windows allows. On failure the
/// temporary file is deleted, so the original stays as it was and nothing is left behind.
// from: ReplaceFileWith
pub fn replace_file_with(temp: &Path, target: &Path) -> Result<(), String> {
    match move_replace(temp, target) {
        Ok(()) => Ok(()),
        Err(code) => {
            let _ = std::fs::remove_file(temp);
            Err(format!(
                "Kunne ikke erstatte filen (Windows-fejl {code}): {}",
                std::io::Error::from_raw_os_error(code as i32)
            ))
        }
    }
}

#[cfg(windows)]
fn move_replace(temp: &Path, target: &Path) -> Result<(), u32> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Foundation::GetLastError;
    use windows_sys::Win32::Storage::FileSystem::{MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH};
    let wide = |p: &Path| p.as_os_str().encode_wide().chain([0]).collect::<Vec<u16>>();
    let (a, b) = (wide(temp), wide(target));
    if unsafe { MoveFileExW(a.as_ptr(), b.as_ptr(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) } != 0 {
        Ok(())
    } else {
        Err(unsafe { GetLastError() })
    }
}

#[cfg(not(windows))]
fn move_replace(temp: &Path, target: &Path) -> Result<(), u32> {
    std::fs::rename(temp, target).map_err(|e| e.raw_os_error().unwrap_or(0) as u32)
}

/// Copies `count` bytes from `src` at `from` to `dst`.
// from: CopyStreamRange
pub fn copy_range(src: &mut File, dst: &mut impl Write, from: u64, count: u64) -> Result<(), String> {
    src.seek(SeekFrom::Start(from)).map_err(|e| e.to_string())?;
    let copied = std::io::copy(&mut Read::by_ref(src).take(count), dst).map_err(|e| e.to_string())?;
    if copied != count {
        return Err("Kunne ikke kopiere lyddata".into());
    }
    Ok(())
}

/// Creation, access and write time of a file (1.2's TFileStamp).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FileStamp {
    pub created: SystemTime,
    pub accessed: SystemTime,
    pub modified: SystemTime,
}

pub fn get_file_stamp(path: &Path) -> Option<FileStamp> {
    let m = std::fs::metadata(path).ok()?;
    Some(FileStamp { created: m.created().ok()?, accessed: m.accessed().ok()?, modified: m.modified().ok()? })
}

pub fn set_file_stamp(path: &Path, st: &FileStamp) {
    let Ok(f) = std::fs::OpenOptions::new().write(true).open(path) else { return };
    let times = FileTimes::new().set_accessed(st.accessed).set_modified(st.modified);
    #[cfg(windows)]
    let times = {
        use std::os::windows::fs::FileTimesExt;
        times.set_created(st.created)
    };
    let _ = f.set_times(times);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("tidytag-fileio-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn set_readonly(p: &Path, ro: bool) {
        let mut perm = std::fs::metadata(p).unwrap().permissions();
        perm.set_readonly(ro);
        std::fs::set_permissions(p, perm).unwrap();
    }

    #[test]
    fn failed_replace_removes_temp() {
        let d = dir("replace");
        let (target, temp) = (d.join("a.mp3"), temp_file_for(&d.join("a.mp3")));
        std::fs::write(&target, b"original").unwrap();
        std::fs::write(&temp, b"new").unwrap();
        set_readonly(&target, true);
        let r = replace_file_with(&temp, &target);
        assert!(r.is_err(), "{r:?}");
        assert!(!temp.exists());
        assert_eq!(std::fs::read(&target).unwrap(), b"original");
        set_readonly(&target, false);
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn stamp_roundtrip() {
        let d = dir("stamp");
        let p = d.join("a.mp3");
        std::fs::write(&p, b"x").unwrap();
        let old = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000_000);
        let st = FileStamp { created: old, accessed: old, modified: old };
        set_file_stamp(&p, &st);
        std::fs::OpenOptions::new().append(true).open(&p).unwrap().write_all(b"y").unwrap();
        set_file_stamp(&p, &st);
        let got = get_file_stamp(&p).unwrap();
        assert_eq!(got.modified, old);
        assert_eq!(got.created, old);
        std::fs::remove_dir_all(d).unwrap();
    }
}

/// Puts each file in the recycle bin, one call per file so a failure stays with its own file.
/// Returns how many went; the others are in `errors` as "<name>: <text>".
// from: RecycleFiles (fileops.pas; phone files come with the phone phase)
#[cfg(windows)]
pub fn recycle_files(files: &[PathBuf], errors: &mut Vec<String>) -> usize {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::UI::Shell::{
        SHFileOperationW, FOF_ALLOWUNDO, FOF_NOCONFIRMATION, FOF_NOERRORUI, FOF_SILENT, FO_DELETE, SHFILEOPSTRUCTW,
    };
    let mut n = 0;
    for f in files {
        let mut from: Vec<u16> = f.as_os_str().encode_wide().collect();
        from.extend([0, 0]);
        let mut op: SHFILEOPSTRUCTW = unsafe { std::mem::zeroed() };
        op.wFunc = FO_DELETE;
        op.pFrom = from.as_ptr();
        op.fFlags = (FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI) as u16;
        let ok = unsafe { SHFileOperationW(&mut op) } == 0 && op.fAnyOperationsAborted == 0 && !f.exists();
        if ok {
            n += 1;
        } else {
            let name = f.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            errors.push(format!("{name}: kunne ikke lægges i papirkurven"));
        }
    }
    n
}
