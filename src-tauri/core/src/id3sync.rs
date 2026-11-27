//! ID3v1 <-> ID3v2 sync for MP3 files (port of id3sync.pas).

use crate::fileio::{get_file_stamp, set_file_stamp};
use crate::model::{AudioInfo, TagField};
use crate::read::read_audio_info;
use crate::tags::id3::{read_id3v1, read_id3v2};
use crate::tags::id3_write::write_id3v1;
use crate::text::{read_at, stream_size};
use crate::write::{write_audio_tags, WriteOptions};
use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, serde::Deserialize)]
pub enum SyncDirection {
    V1ToV2,
    V2ToV1,
}

#[derive(Debug, Clone, Copy, PartialEq, serde::Deserialize)]
pub enum SyncExisting {
    Skip,
    BlankOnly,
    Overwrite,
}

const V1_FIELDS: [TagField; 7] =
    [TagField::Title, TagField::Artist, TagField::Album, TagField::Year, TagField::Comment, TagField::Track, TagField::Genre];

// from: ReadSeparately
fn read_separately(path: &Path) -> Result<(AudioInfo, AudioInfo, bool), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut s = File::open(path).map_err(io)?;
    let (mut v1, mut v2) = (AudioInfo::default(), AudioInfo::default());
    read_id3v2(&mut s, &mut v2).map_err(io)?;
    let has_v1 = read_id3v1(&mut s, &mut v1).map_err(io)?;
    Ok((v1, v2, has_v1))
}

/// True when the file was changed. `opt.keep_timestamp` restores the file times; the rest of
/// `opt` is used by the ID3v2 write (1.2's global settings).
// from: SyncID3
pub fn sync_id3(path: &Path, dir: SyncDirection, existing: SyncExisting, opt: &WriteOptions) -> Result<bool, String> {
    let io = |e: std::io::Error| e.to_string();
    let (mut v1, v2, has_v1) = read_separately(path)?;
    let has_v2 = !v2.tag_types.is_empty();
    let mut changed = false;
    if dir == SyncDirection::V1ToV2 {
        if !has_v1 || (has_v2 && existing == SyncExisting::Skip) {
            return Ok(false);
        }
        let mut full = read_audio_info(path, true);
        if !full.error.is_empty() {
            return Err(full.error);
        }
        for f in V1_FIELDS {
            if v1.field(f).is_empty() || (existing == SyncExisting::BlankOnly && !v2.field(f).is_empty()) {
                continue;
            }
            // the reader shows ID3v1 values in empty ID3v2 fields: compare with ID3v2 itself
            if v2.field(f) != v1.field(f) {
                changed = true;
            }
            full.put(f, v1.field(f));
        }
        if !has_v2 {
            changed = true;
        }
        if changed {
            // the MP3 writer also updates ID3v1 from the same values; this direction must
            // leave ID3v1 as it was
            let mut s = File::open(path).map_err(io)?;
            let size = stream_size(&mut s).map_err(io)?;
            let old_v1 = read_at(&mut s, size.saturating_sub(128), 128).map_err(io)?;
            drop(s);
            let stamp = if opt.keep_timestamp { get_file_stamp(path) } else { None };
            write_audio_tags(&mut full, &WriteOptions { keep_timestamp: false, ..opt.clone() })?;
            let mut s = OpenOptions::new().read(true).write(true).open(path).map_err(io)?;
            let size = stream_size(&mut s).map_err(io)?;
            s.seek(SeekFrom::Start(size - old_v1.len() as u64)).map_err(io)?;
            s.write_all(&old_v1).map_err(io)?;
            drop(s);
            if let Some(st) = stamp {
                set_file_stamp(path, &st);
            }
        }
    } else {
        if !has_v2 || (has_v1 && existing == SyncExisting::Skip) {
            return Ok(false);
        }
        for f in V1_FIELDS {
            if v2.field(f).is_empty() || (has_v1 && existing == SyncExisting::BlankOnly && !v1.field(f).is_empty()) {
                continue;
            }
            if v1.field(f) != v2.field(f) {
                changed = true;
            }
            v1.put(f, v2.field(f));
        }
        if !has_v1 {
            changed = true;
        }
        if changed {
            let stamp = if opt.keep_timestamp { get_file_stamp(path) } else { None };
            write_id3v1(path, &v1, true)?;
            if let Some(st) = stamp {
                set_file_stamp(path, &st);
            }
        }
    }
    Ok(changed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tags::id3_write::build_id3_tag_bytes;

    /// ID3v2 with `v2` fields + an MPEG frame + ID3v1 with `v1` fields.
    fn mp3(name: &str, v2: &[(TagField, &str)], v1: &[(TagField, &str)]) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("tidytag-sync-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let mut i2 = AudioInfo::new(Default::default(), true);
        for (f, v) in v2 {
            i2.put(*f, v);
        }
        let mut bytes = build_id3_tag_bytes(None, &i2, 50, &WriteOptions::default());
        let mut frame = vec![0u8; 417];
        frame[..4].copy_from_slice(&[0xFF, 0xFB, 0x90, 0x00]);
        bytes.extend(frame);
        let p = dir.join("a.mp3");
        std::fs::write(&p, &bytes).unwrap();
        let mut i1 = AudioInfo::default();
        for (f, v) in v1 {
            i1.put(*f, v);
        }
        write_id3v1(&p, &i1, true).unwrap();
        p
    }

    fn v2_of(p: &Path) -> AudioInfo {
        read_separately(p).unwrap().1
    }

    #[test]
    fn sync_v1_to_v2_blank_only() {
        let p = mp3("a", &[(TagField::Artist, "A")], &[(TagField::Title, "V1"), (TagField::Artist, "B")]);
        assert!(sync_id3(&p, SyncDirection::V1ToV2, SyncExisting::BlankOnly, &WriteOptions::default()).unwrap());
        let v2 = v2_of(&p);
        assert_eq!(v2.field(TagField::Title), "V1");
        assert_eq!(v2.field(TagField::Artist), "A");
        std::fs::remove_dir_all(p.parent().unwrap()).unwrap();
    }

    #[test]
    fn sync_v2_to_v1_overwrite() {
        let p = mp3("b", &[(TagField::Title, "Ny")], &[(TagField::Title, "Gammel")]);
        assert!(sync_id3(&p, SyncDirection::V2ToV1, SyncExisting::Overwrite, &WriteOptions::default()).unwrap());
        assert_eq!(read_separately(&p).unwrap().0.field(TagField::Title), "Ny");
        std::fs::remove_dir_all(p.parent().unwrap()).unwrap();
    }
}
