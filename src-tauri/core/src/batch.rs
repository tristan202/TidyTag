//! Saving a few fields (and optionally a new front cover) in one file, re-reading it with
//! pictures first so nothing else in the file changes (port of batchwrite.pas).

use crate::model::{detect_image_mime, AudioInfo, Picture, TagField, PIC_TYPE_FRONT_COVER};
use crate::read::read_audio_info;
use crate::write::{can_write_tags, write_audio_tags, WriteOptions};
use std::collections::BTreeMap;
use std::path::Path;

/// Puts `data` first as front cover; other pictures (back, booklet, ...) are kept.
// from: SetFrontCover
pub fn set_front_cover(info: &mut AudioInfo, data: Vec<u8>) {
    let mut keep = vec![Picture {
        pic_type: PIC_TYPE_FRONT_COVER,
        mime: detect_image_mime(&data, "image/jpeg").to_string(),
        description: String::new(),
        data,
    }];
    keep.extend(info.pictures.drain(..).filter(|p| p.pic_type != PIC_TYPE_FRONT_COVER));
    info.pictures = keep;
}

/// Writes `values` (empty = clear) and `cover` into the file and returns the file read again.
/// Err holds the error text and whether the file was skipped because its type cannot be
/// written. A file whose read gives an error is never written.
// from: UpdateFileTags
pub fn update_file_tags(
    path: &Path,
    values: &BTreeMap<TagField, String>,
    cover: Option<Vec<u8>>,
    opt: &WriteOptions,
) -> Result<AudioInfo, (String, bool)> {
    if !can_write_tags(path) {
        return Err(("filtypen kan ikke gemmes endnu".into(), true));
    }
    let mut full = read_audio_info(path, true);
    if !full.error.is_empty() {
        return Err((full.error, false));
    }
    for (f, v) in values {
        full.put(*f, v);
    }
    if let Some(c) = cover {
        set_front_cover(&mut full, c);
    }
    // a bug in a writer must not take the whole batch down: it becomes this file's error
    let written = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| write_audio_tags(&mut full, opt)));
    match written {
        Ok(r) => r.map_err(|e| (e, false))?,
        Err(_) => {
            let _ = std::fs::remove_file(crate::fileio::temp_file_for(path));
            return Err(("internal error while writing the file".into(), false));
        }
    }
    Ok(read_audio_info(path, false))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn damaged_file_is_not_written() {
        let dir = std::env::temp_dir().join(format!("tidytag-batch-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("broken.flac");
        std::fs::write(&p, b"fLaC\x00\x00").unwrap(); // truncated metadata
        let mut values = BTreeMap::new();
        values.insert(TagField::Title, "x".to_string());
        let r = update_file_tags(&p, &values, None, &WriteOptions::default());
        assert!(matches!(&r, Err((_, false))), "{:?}", r.as_ref().err());
        assert_eq!(std::fs::read(&p).unwrap(), b"fLaC\x00\x00");
        let dsf = dir.join("a.dsf");
        std::fs::write(&dsf, b"DSD ").unwrap();
        assert!(matches!(update_file_tags(&dsf, &values, None, &WriteOptions::default()), Err((_, true))));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn front_cover_goes_first_and_keeps_the_back() {
        let mut i = AudioInfo::new(Default::default(), true);
        i.pictures = vec![
            Picture { pic_type: 4, mime: "image/jpeg".into(), description: "b".into(), data: vec![1] },
            Picture { pic_type: 3, mime: "image/jpeg".into(), description: "old".into(), data: vec![2] },
        ];
        set_front_cover(&mut i, vec![0x89, b'P', b'N', b'G', 13, 10, 26, 10]);
        assert_eq!(i.pictures.iter().map(|p| p.pic_type).collect::<Vec<_>>(), [3, 4]);
        assert_eq!(i.pictures[0].mime, "image/png");
    }
}
