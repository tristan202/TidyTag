//! Drives and subfolders for the folder tree.

use serde::Serialize;
use std::path::Path;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DirEntry {
    pub name: String,
    pub path: String,
    pub has_children: bool,
}

#[cfg(windows)]
fn hidden_or_system(m: &std::fs::Metadata) -> bool {
    use std::os::windows::fs::MetadataExt;
    const HIDDEN: u32 = 0x2;
    const SYSTEM: u32 = 0x4;
    m.file_attributes() & (HIDDEN | SYSTEM) != 0
}

#[cfg(not(windows))]
fn hidden_or_system(_m: &std::fs::Metadata) -> bool {
    false
}

fn visible_dirs(path: &Path) -> impl Iterator<Item = std::fs::DirEntry> {
    std::fs::read_dir(path).into_iter().flatten().flatten().filter(|e| {
        e.metadata().map(|m| m.is_dir() && !hidden_or_system(&m)).unwrap_or(false)
    })
}

/// Subfolders without hidden and system folders (as 1.2's tree), in name order.
pub fn list_dirs(path: &Path) -> Vec<DirEntry> {
    let mut v: Vec<DirEntry> = visible_dirs(path)
        .map(|e| {
            let p = e.path();
            DirEntry {
                name: e.file_name().to_string_lossy().into_owned(),
                has_children: visible_dirs(&p).next().is_some(),
                path: p.to_string_lossy().into_owned(),
            }
        })
        .collect();
    v.sort_by_key(|d| d.name.to_lowercase());
    v
}

/// The drives, as "C:\" with the volume label in `name` ("Lokal disk (C:)").
#[cfg(windows)]
pub fn list_drives() -> Vec<DirEntry> {
    use windows_sys::Win32::Storage::FileSystem::{GetDriveTypeW, GetLogicalDrives, GetVolumeInformationW};
    const DRIVE_REMOTE: u32 = 4;
    const DRIVE_CDROM: u32 = 5;
    let mask = unsafe { GetLogicalDrives() };
    (0..26)
        .filter(|i| mask & (1 << i) != 0)
        .map(|i| {
            let root = format!("{}:\\", (b'A' + i as u8) as char);
            let wide: Vec<u16> = root.encode_utf16().chain([0]).collect();
            // network and optical drives can take many seconds to answer (or never):
            // they are listed without asking them; their folders load when opened
            let kind = unsafe { GetDriveTypeW(wide.as_ptr()) };
            if kind == DRIVE_REMOTE || kind == DRIVE_CDROM {
                return DirEntry { name: root[..2].to_string(), path: root, has_children: true };
            }
            let mut label = [0u16; 261];
            let ok = unsafe {
                GetVolumeInformationW(wide.as_ptr(), label.as_mut_ptr(), label.len() as u32,
                    std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut(), std::ptr::null_mut(), 0)
            };
            let len = label.iter().position(|&c| c == 0).unwrap_or(0);
            let label = if ok != 0 { String::from_utf16_lossy(&label[..len]) } else { String::new() };
            let letter = &root[..2];
            DirEntry {
                name: if label.is_empty() { letter.to_string() } else { format!("{label} ({letter})") },
                has_children: ok != 0 && visible_dirs(Path::new(&root)).next().is_some(),
                path: root,
            }
        })
        .collect()
}

#[cfg(not(windows))]
pub fn list_drives() -> Vec<DirEntry> {
    vec![DirEntry { name: "/".into(), path: "/".into(), has_children: true }]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_visible_subfolders_in_order() {
        let d = std::env::temp_dir().join(format!("tidytag-dirs-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(d.join("b").join("inner")).unwrap();
        std::fs::create_dir_all(d.join("A")).unwrap();
        std::fs::write(d.join("file.mp3"), b"").unwrap();
        let v = list_dirs(&d);
        assert_eq!(v.iter().map(|e| e.name.as_str()).collect::<Vec<_>>(), ["A", "b"]);
        assert_eq!(v.iter().map(|e| e.has_children).collect::<Vec<_>>(), [false, true]);
        std::fs::remove_dir_all(d).unwrap();
        assert!(list_drives().iter().any(|e| e.path == "C:\\"));
    }
}
