//! Picks the right reader from the file extension (port of audiotags.pas).

use crate::model::AudioInfo;
use crate::tags;
use std::fs::File;
use std::io::BufReader;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;

/// Extensions whose tags we can read, in 1.2's order.
pub const READABLE_EXTS: [&str; 18] = [
    ".mp3", ".flac", ".ogg", ".oga", ".opus", ".m4a", ".m4b", ".mp4", ".wav", ".aif", ".aiff",
    ".aifc", ".ape", ".wv", ".mpc", ".ofr", ".wma", ".asf",
];
/// Listed but not read.
pub const OTHER_EXTS: [&str; 1] = [".dsf"];

fn ext_of(path: &Path) -> String {
    path.extension().map(|e| format!(".{}", e.to_string_lossy().to_lowercase())).unwrap_or_default()
}

pub fn is_readable_audio_file(path: &Path) -> bool {
    READABLE_EXTS.contains(&ext_of(path).as_str())
}

pub fn is_audio_file(path: &Path) -> bool {
    let e = ext_of(path);
    READABLE_EXTS.contains(&e.as_str()) || OTHER_EXTS.contains(&e.as_str())
}

/// Never panics: read problems end up in `.error`.
/// `want_pictures` keeps cover image data (needed before saving).
pub fn read_audio_info(path: &Path, want_pictures: bool) -> AudioInfo {
    let mut info = AudioInfo::new(path.to_path_buf(), want_pictures);
    // std opens with read/write/delete sharing, like 1.2's fmShareDenyNone
    let file = match File::open(path) {
        Ok(f) => f,
        Err(e) => {
            info.error = e.to_string();
            return info;
        }
    };
    info.file_size = file.metadata().map(|m| m.len()).unwrap_or(0);
    let mut s = BufReader::new(file);
    let ext = ext_of(path);
    let result = catch_unwind(AssertUnwindSafe(|| match ext.as_str() {
        ".mp3" => tags::mp3::read(&mut s, &mut info),
        ".flac" => tags::flac::read(&mut s, &mut info),
        ".ogg" | ".oga" | ".opus" => tags::vorbis::read(&mut s, &mut info),
        ".m4a" | ".m4b" | ".mp4" => tags::mp4::read(&mut s, &mut info),
        ".wav" | ".aif" | ".aiff" | ".aifc" => tags::riff::read(&mut s, &mut info),
        ".ape" | ".wv" | ".mpc" | ".ofr" => tags::ape::read(&mut s, &mut info),
        ".wma" | ".asf" => tags::asf::read(&mut s, &mut info),
        _ => {
            info.supported = false;
            Ok(())
        }
    }));
    match result {
        Ok(Ok(())) => {}
        Ok(Err(e)) => info.error = e,
        Err(_) => info.error = "internal error while reading the file".into(),
    }
    info
}

#[cfg(test)]
mod tests {
    use super::*;

    const ASF_GUID: [u8; 16] = [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C];

    fn magic(ext: &str) -> Vec<u8> {
        match ext {
            ".mp3" => b"ID3\x03\x00\x00\x00\x00\x10\x00".to_vec(),
            ".flac" => b"fLaC".to_vec(),
            ".ogg" | ".oga" | ".opus" => b"OggS".to_vec(),
            ".m4a" | ".m4b" | ".mp4" => b"\x00\x00\x00\x20ftypM4A ".to_vec(),
            ".wav" => b"RIFF\xFF\xFF\xFF\x7FWAVE".to_vec(),
            ".aif" | ".aiff" | ".aifc" => b"FORM\x7F\xFF\xFF\xFFAIFF".to_vec(),
            ".ape" => b"MAC ".to_vec(),
            ".wv" => b"wvpk".to_vec(),
            ".mpc" => b"MPCK".to_vec(),
            ".ofr" => b"OFR ".to_vec(),
            _ => ASF_GUID.to_vec(),
        }
    }

    #[test]
    fn truncated_files_never_panic() {
        let dir = std::env::temp_dir().join("tidytag-truncated");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        for ext in READABLE_EXTS {
            for len in [0usize, 1, 10, 200] {
                // header bytes, then zeros, cut to len
                let mut data = magic(ext);
                data.resize(len.max(data.len()), 0);
                data.truncate(len);
                let p = dir.join(format!("t{len}{ext}"));
                std::fs::write(&p, &data).unwrap();
                let info = read_audio_info(&p, true);
                // 1.2 lists such files (often without an error); what matters is that the
                // reader returned on its own instead of panicking
                assert!(!info.error.starts_with("internal error"), "{}: reader panicked", p.display());
            }
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
}
