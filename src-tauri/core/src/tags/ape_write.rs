//! Writes APEv2 tags (Monkey's Audio, WavPack, Musepack, OptimFROG; port of the writing part of
//! apetag.pas). The tag sits at the end of the file, before an optional ID3v1 tag, and is
//! replaced in place (the audio before it is never touched); unknown items are kept, pictures
//! are stored as "Cover Art (Front)" etc. (file name, zero byte, image data). An existing ID3v1
//! tag is kept and updated so both agree.

use super::ape::{find_ape_tag, key_field, parse_items, pic_key_type, FIELD_KEYS, FLAG_HAS_HEADER, FLAG_IS_HEADER, ITEM_BINARY, PIC_NAMES};
use super::id3_write::write_id3v1;
use crate::model::{is_true_flag, AudioInfo, TagField};
use crate::text::{read_at, stream_size};
use crate::write::WriteOptions;
use std::fs::OpenOptions;
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

// from: AddItem
fn add_item(dest: &mut Vec<u8>, key: &str, flags: u32, value: &[u8], count: &mut u32) {
    dest.extend((value.len() as u32).to_le_bytes());
    dest.extend(flags.to_le_bytes());
    dest.extend(key.as_bytes());
    dest.push(0);
    dest.extend(value);
    *count += 1;
}

// from: WriteHeaderFooter
fn header_footer(items_size: usize, count: u32, is_header: bool) -> Vec<u8> {
    let mut d = b"APETAGEX".to_vec();
    d.extend(2000u32.to_le_bytes());
    d.extend((items_size as u32 + 32).to_le_bytes());
    d.extend(count.to_le_bytes());
    let flags = FLAG_HAS_HEADER | if is_header { FLAG_IS_HEADER } else { 0 };
    d.extend(flags.to_le_bytes());
    d.extend([0u8; 8]);
    d
}

// from: WriteApeTags
pub fn write(path: &Path, info: &AudioInfo, _opt: &WriteOptions) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut s = OpenOptions::new().read(true).write(true).open(path).map_err(io)?;
    let loc = find_ape_tag(&mut s).map_err(io)?;
    let old = if loc.found { parse_items(&mut s, &loc).map_err(io)? } else { Vec::new() };
    let v1 = if loc.has_id3v1 {
        let size = stream_size(&mut s).map_err(io)?;
        read_at(&mut s, size - 128, 128).map_err(io)?
    } else {
        Vec::new()
    };

    let mut count = 0u32;
    let mut tag = Vec::new();
    // unknown items first, in their old order
    for it in &old {
        if pic_key_type(&it.key).is_none() && !(it.flags & 6 == 0 && key_field(&it.key).is_some()) {
            add_item(&mut tag, &it.key, it.flags & 7, &it.value, &mut count);
        }
    }
    for (i, f) in TagField::ALL.iter().enumerate() {
        let v = info.field(*f);
        if matches!(f, TagField::Compilation | TagField::Podcast) {
            if is_true_flag(v) {
                add_item(&mut tag, FIELD_KEYS[i], 0, b"1", &mut count);
            }
        } else if !v.is_empty() {
            add_item(&mut tag, FIELD_KEYS[i], 0, v.as_bytes(), &mut count);
        }
    }
    let mut used = [false; 21];
    for p in &info.pictures {
        let t = p.pic_type as usize;
        if t > 20 || used[t] {
            continue; // one picture per type
        }
        used[t] = true;
        let name = if !p.description.is_empty() {
            p.description.clone()
        } else if p.mime == "image/png" {
            "cover.png".into()
        } else {
            "cover.jpg".into()
        };
        let mut data = name.into_bytes();
        data.push(0);
        data.extend(&p.data);
        add_item(&mut tag, &format!("Cover Art ({})", PIC_NAMES[t]), ITEM_BINARY, &data, &mut count);
    }

    s.set_len(loc.audio_end as u64).map_err(io)?;
    s.seek(SeekFrom::Start(loc.audio_end as u64)).map_err(io)?;
    let mut out = Vec::new();
    if count > 0 {
        out.extend(header_footer(tag.len(), count, true));
        out.extend(&tag);
        out.extend(header_footer(tag.len(), count, false));
    }
    out.extend(&v1);
    s.write_all(&out).map_err(io)?;
    drop(s);
    if loc.has_id3v1 {
        write_id3v1(path, info, false)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::read::read_audio_info;
    use crate::scenario::test_png;

    /// A Monkey's Audio file (old header, version 3.97) with an APE tag holding a Title and an
    /// unknown item, plus an ID3v1 tag.
    fn ape() -> Vec<u8> {
        let mut v = b"MAC ".to_vec();
        v.extend(3970u16.to_le_bytes());
        v.resize(4096, 0x55);
        let mut tag = Vec::new();
        let mut n = 0;
        add_item(&mut tag, "Title", 0, b"Gammel", &mut n);
        add_item(&mut tag, "MyOwnKey", 0, b"keep me", &mut n);
        v.extend(header_footer(tag.len(), n, true));
        v.extend(&tag);
        v.extend(header_footer(tag.len(), n, false));
        let mut v1 = vec![0u8; 128];
        v1[..3].copy_from_slice(b"TAG");
        v.extend(v1);
        v
    }

    fn edit(f: impl Fn(&mut AudioInfo)) -> (Vec<u8>, AudioInfo) {
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("tidytag-apew-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.ape");
        std::fs::write(&p, ape()).unwrap();
        let mut info = read_audio_info(&p, true);
        f(&mut info);
        write(&p, &info, &WriteOptions::default()).unwrap();
        let out = std::fs::read(&p).unwrap();
        let back = read_audio_info(&p, true);
        std::fs::remove_dir_all(dir).unwrap();
        (out, back)
    }

    #[test]
    fn replaces_in_place_before_id3v1() {
        let (out, back) = edit(|i| i.put(TagField::Title, "Ny titel"));
        assert_eq!(&out[..4096], &ape()[..4096]); // audio untouched
        assert_eq!(&out[out.len() - 128..out.len() - 125], b"TAG");
        assert_eq!(back.field(TagField::Title), "Ny titel");
        assert_eq!(&out[out.len() - 125..out.len() - 117], b"Ny titel"); // ID3v1 agrees
    }

    #[test]
    fn unknown_items_kept() {
        let (out, _) = edit(|i| i.put(TagField::Title, "x"));
        assert!(out.windows(8).any(|w| w == b"MyOwnKey"));
    }

    #[test]
    fn picture_as_cover_art_front() {
        let (out, back) = edit(|i| crate::batch::set_front_cover(i, test_png(0)));
        assert!(out.windows(17).any(|w| w == b"Cover Art (Front)"));
        assert_eq!(back.pictures.len(), 1);
        assert_eq!(back.pictures[0].pic_type, 3);
    }
}
