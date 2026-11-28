//! M3U8 playlists.
// from: WritePlaylist, MaskText (mainform.pas)

use crate::model::AudioInfo;
use crate::rename::{expand_rename_mask, same_file_name, RenameOptions};
use std::path::Path;

/// A mask expanded for one file as plain text (no folders, no extension); '' when a field is missing.
// from: MaskText
pub fn mask_text(mask: &str, info: &AudioInfo) -> String {
    let (res, _) = expand_rename_mask(mask, info, 1, 2, &RenameOptions::default());
    if res.is_empty() {
        return res;
    }
    let p = Path::new(&res);
    p.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default()
}

/// The playlist file's text: UTF-8 without BOM, CRLF after every line (TStringList.SaveToFile).
// from: WritePlaylist
pub fn playlist_text(target: &Path, items: &[&AudioInfo], full_paths: bool, ext_inf: bool, info_mask: &str) -> String {
    let dir = target.parent().map(|d| d.to_string_lossy().into_owned()).unwrap_or_default();
    let dir = if dir.ends_with('\\') { dir } else { dir + "\\" };
    let mut out = String::from("#EXTM3U\r\n");
    for info in items {
        if ext_inf {
            let mut name = mask_text(info_mask, info);
            if name.is_empty() {
                name = info.path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
            }
            out += &format!("#EXTINF:{},{}\r\n", info.duration.round() as i64, name);
        }
        let path = info.path.to_string_lossy().into_owned();
        // relative paths keep the playlist working when the music folder moves
        let prefix: String = path.chars().take(dir.chars().count()).collect();
        if !full_paths && same_file_name(&prefix, &dir) {
            out += &path[prefix.len()..];
        } else {
            out += &path;
        }
        out += "\r\n";
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{AudioInfo, TagField};
    use std::path::{Path, PathBuf};

    fn info(path: &str, duration: f64, artist: &str, title: &str) -> AudioInfo {
        let mut i = AudioInfo::new(PathBuf::from(path), false);
        i.duration = duration;
        if !artist.is_empty() {
            i.fields.insert(TagField::Artist, artist.into());
        }
        if !title.is_empty() {
            i.fields.insert(TagField::Title, title.into());
        }
        i
    }

    #[test]
    fn playlist_relative_paths_and_utf8() {
        let a = info("c:\\musik\\漢字.mp3", 183.4, "A", "T");
        let b = info("D:\\o\\b.flac", 0.0, "", "");
        let target = Path::new("C:\\Musik\\x.m3u8");
        assert_eq!(
            playlist_text(target, &[&a, &b], false, true, "%1 - %2"),
            "#EXTM3U\r\n#EXTINF:183,A - T\r\n漢字.mp3\r\n#EXTINF:0,b\r\nD:\\o\\b.flac\r\n"
        );
        let full = playlist_text(target, &[&a], true, true, "%1 - %2");
        assert!(full.contains("\r\nc:\\musik\\漢字.mp3\r\n"), "{full}");
        assert_eq!(playlist_text(target, &[&b], false, false, "%1 - %2"), "#EXTM3U\r\nD:\\o\\b.flac\r\n");
    }

    #[test]
    fn mask_text_is_the_bare_name() {
        let a = info("C:\\m\\x.mp3", 1.0, "A", "T");
        assert_eq!(mask_text("%1 - %2", &a), "A - T");
        assert_eq!(mask_text("%f", &a), "m"); // folder name, 1.2's quick playlist default
        assert_eq!(mask_text("%7", &a), "x");
        assert_eq!(mask_text("%3", &a), "");
    }
}
