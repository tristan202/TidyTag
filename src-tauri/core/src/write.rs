//! Entry point for saving tags: picks the writer from the file extension (port of tagwriter.pas).

use crate::fileio::{get_file_stamp, set_file_stamp};
use crate::model::{AudioInfo, TagField};
use crate::tags;
use std::path::Path;

/// The settings that change a write; read from the ini for every batch.
#[derive(Debug, Clone, Default)]
pub struct WriteOptions {
    /// [Tags] ID3Unicode: ID3v2.3 text is always UTF-16 (otherwise Latin-1 when it fits)
    pub id3_always_unicode: bool,
    /// [Main] AlbumArtistRule: 0 = none, 1 = copy Artist if Album artist is empty, 2 = always
    pub album_artist_rule: u8,
    /// [Editor] KeepTimestamp
    pub keep_timestamp: bool,
}

const WRITABLE: [&str; 18] = [
    "mp3", "flac", "m4a", "m4b", "mp4", "ogg", "oga", "opus", "wav", "aif", "aiff", "aifc", "ape", "wv", "mpc",
    "ofr", "wma", "asf",
];

fn ext(path: &Path) -> String {
    path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default()
}

// from: CanWriteTags
pub fn can_write_tags(path: &Path) -> bool {
    WRITABLE.contains(&ext(path).as_str())
}

// from: ApplyAlbumArtistRule
pub fn apply_album_artist_rule(info: &mut AudioInfo, rule: u8) {
    let artist = info.field(TagField::Artist).to_string();
    if artist.is_empty() {
        return;
    }
    match rule {
        1 if info.field(TagField::AlbumArtist).is_empty() => info.put(TagField::AlbumArtist, &artist),
        2 => info.put(TagField::AlbumArtist, &artist),
        _ => {}
    }
}

/// Writes info's fields and pictures into its file. The info must have been read with
/// pictures, otherwise existing pictures would be lost. The original is never left
/// half-written.
// from: WriteAudioTags
pub fn write_audio_tags(info: &mut AudioInfo, opt: &WriteOptions) -> Result<(), String> {
    if !info.want_pictures {
        return Err("Intern fejl: filen er læst uden billeder".into());
    }
    if !can_write_tags(&info.path) {
        return Err("Skrivning af denne filtype understøttes ikke endnu".into());
    }
    apply_album_artist_rule(info, opt.album_artist_rule);
    let stamp = if opt.keep_timestamp { get_file_stamp(&info.path) } else { None };
    let path = info.path.clone();
    let result = match ext(&path).as_str() {
        "mp3" => tags::id3_write::write(&path, info, opt),
        "flac" => tags::flac_write::write(&path, info, opt),
        "m4a" | "m4b" | "mp4" => tags::mp4_write::write(&path, info, opt),
        "ogg" | "oga" | "opus" => tags::ogg_write::write(&path, info, opt),
        "wav" | "aif" | "aiff" | "aifc" => tags::riff_write::write(&path, info, opt),
        "ape" | "wv" | "mpc" | "ofr" => tags::ape_write::write(&path, info, opt),
        _ => tags::asf_write::write(&path, info, opt),
    };
    if let (Ok(()), Some(st)) = (&result, stamp) {
        set_file_stamp(&path, &st);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn refuses_unread_pictures() {
        let mut i = AudioInfo::new(PathBuf::from("x.mp3"), false);
        assert_eq!(write_audio_tags(&mut i, &WriteOptions::default()).unwrap_err(), "Intern fejl: filen er læst uden billeder");
    }

    #[test]
    fn refuses_unknown_type() {
        let mut i = AudioInfo::new(PathBuf::from("x.dsf"), true);
        assert_eq!(write_audio_tags(&mut i, &WriteOptions::default()).unwrap_err(), "Skrivning af denne filtype understøttes ikke endnu");
    }

    /// A small valid MP3: an ID3v2.3 tag with a title and one MPEG frame.
    pub(crate) fn tiny_mp3() -> Vec<u8> {
        let mut v = b"ID3\x03\x00\x00\x00\x00\x00\x11TIT2\x00\x00\x00\x03\x00\x00\x00Hi".to_vec();
        let mut frame = vec![0u8; 417];
        frame[..4].copy_from_slice(&[0xFF, 0xFB, 0x90, 0x00]);
        v.extend(frame);
        v
    }

    #[test]
    fn readonly_file_fails_cleanly() {
        let d = std::env::temp_dir().join(format!("tidytag-write-ro-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        let p = d.join("a.mp3");
        std::fs::write(&p, tiny_mp3()).unwrap();
        let mut perm = std::fs::metadata(&p).unwrap().permissions();
        perm.set_readonly(true);
        std::fs::set_permissions(&p, perm.clone()).unwrap();
        let mut info = crate::read::read_audio_info(&p, true);
        assert_eq!(info.field(TagField::Title), "Hi");
        info.put(TagField::Title, &"x".repeat(5000)); // forces a rewrite
        assert!(write_audio_tags(&mut info, &WriteOptions::default()).is_err());
        assert_eq!(std::fs::read(&p).unwrap(), tiny_mp3());
        assert!(!crate::fileio::temp_file_for(&p).exists());
        perm.set_readonly(false);
        std::fs::set_permissions(&p, perm).unwrap();
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn album_artist_rule() {
        let case = |rule, album_artist: &str| {
            let mut i = AudioInfo::new(PathBuf::new(), true);
            i.put(TagField::Artist, "A");
            i.put(TagField::AlbumArtist, album_artist);
            apply_album_artist_rule(&mut i, rule);
            i.field(TagField::AlbumArtist).to_string()
        };
        assert_eq!(case(0, ""), "");
        assert_eq!(case(1, ""), "A");
        assert_eq!(case(1, "B"), "B");
        assert_eq!(case(2, "B"), "A");
    }
}
