//! Writes the editable fields and pictures of an AudioInfo into an MP3's ID3v2 tag (port of
//! id3writer.pas). Frames we do not edit are kept byte for byte. An existing v2.3/v2.4 tag keeps
//! its version; files without a tag (or with v2.2) get ID3v2.3, which every player reads.
//! An existing ID3v1 tag is updated so both tags agree; none is created.

use super::id3::{decode_id3_text, parse_id3v2, skip_terminated, v22_to_v23, Id3Frame};
use crate::fileio::{copy_range, replace_file_with, temp_file_for};
use crate::model::{is_true_flag, AudioInfo, Picture, TagField as F};
use crate::text::{bytes_are, id3_genre_index, read_at, stream_size};
use crate::write::WriteOptions;
use std::fs::{File, OpenOptions};
use std::io::{Cursor, Seek, SeekFrom, Write};
use std::path::Path;

const NEW_TAG_PADDING: usize = 4096;

// from: IsManagedFrame
fn is_managed_frame(id: &str, fr: &Id3Frame) -> bool {
    const MANAGED: [&str; 37] = [
        "TIT2", "TPE1", "TALB", "TYER", "TDAT", "TDRC", "TRCK", "TPOS", "TCON", "TPE2", "TCOM", "TBPM", "APIC", "PIC",
        "TPE3", "TEXT", "TOPE", "TPE4", "TPUB", "TSRC", "TCOP", "TENC", "TIT1", "GRP1", "TIT3", "TMOO", "TKEY",
        "TSOT", "TSOP", "TSO2", "TSOA", "TSOC", "USLT", "TCMP", "PCST", "", "",
    ];
    if MANAGED.iter().any(|m| !m.is_empty() && *m == id) {
        return true;
    }
    let data: &[u8] = fr.data.as_deref().unwrap_or(&[]);
    if id == "TXXX" || id == "WXXX" {
        if data.len() < 2 {
            return true;
        }
        let p = skip_terminated(data, 1, data[0]);
        let desc = decode_id3_text(data, 1, p - 1, data[0]).to_ascii_uppercase();
        if id == "WXXX" {
            return desc.is_empty(); // the plain URL we edit; other links stay
        }
        return matches!(desc.as_str(), "CATALOGNUMBER" | "MOOD" | "LABEL" | "REPLAYGAIN_TRACK_GAIN"
            | "REPLAYGAIN_TRACK_PEAK" | "REPLAYGAIN_ALBUM_GAIN" | "REPLAYGAIN_ALBUM_PEAK");
    }
    if id == "COMM" {
        // iTunes keeps technical data in comments (iTunNORM, iTunSMPB, ...): leave those.
        if data.len() < 4 {
            return true;
        }
        let p = skip_terminated(data, 4, data[0]);
        let desc = decode_id3_text(data, 4, p - 4, data[0]);
        let head: String = desc.chars().take(4).collect();
        return !head.eq_ignore_ascii_case("iTun");
    }
    false
}

/// Pascal's UTF8Decode: the UTF-16 code units of a string.
fn units(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

/// Text encoding byte: v2.4 -> UTF-8; v2.3 -> Latin-1 when possible, else UTF-16 with BOM.
// from: ChooseEncoding
fn choose_encoding(version: u8, texts: &[&str], opt: &WriteOptions) -> u8 {
    if version == 4 {
        return 3;
    }
    if opt.id3_always_unicode {
        return 1;
    }
    if texts.iter().any(|t| units(t).iter().any(|&u| u > 255)) { 1 } else { 0 }
}

// from: WriteEncoded
fn write_encoded(b: &mut Vec<u8>, text: &str, enc: u8, terminate: bool) {
    match enc {
        0 => {
            b.extend(units(text).iter().map(|&u| u as u8));
            if terminate {
                b.push(0);
            }
        }
        1 => {
            b.extend([0xFF, 0xFE]);
            for u in units(text) {
                b.extend(u.to_le_bytes());
            }
            if terminate {
                b.extend([0, 0]);
            }
        }
        _ => {
            b.extend(text.as_bytes());
            if terminate {
                b.push(0);
            }
        }
    }
}

fn syncsafe(n: u32) -> [u8; 4] {
    [((n >> 21) & 0x7F) as u8, ((n >> 14) & 0x7F) as u8, ((n >> 7) & 0x7F) as u8, (n & 0x7F) as u8]
}

// from: WriteFrame
fn write_frame(dest: &mut Vec<u8>, version: u8, id: &str, flags: u16, body: &[u8]) {
    dest.extend(id.as_bytes());
    let n = body.len() as u32;
    if version == 4 {
        dest.extend(syncsafe(n));
    } else {
        dest.extend(n.to_be_bytes());
    }
    dest.extend(flags.to_be_bytes());
    dest.extend(body);
}

// from: AddTextFrame
fn add_text_frame(dest: &mut Vec<u8>, version: u8, id: &str, value: &str, opt: &WriteOptions) {
    if value.is_empty() {
        return;
    }
    let enc = choose_encoding(version, &[value], opt);
    let mut b = vec![enc];
    write_encoded(&mut b, value, enc, false);
    write_frame(dest, version, id, 0, &b);
}

/// COMM and USLT: encoding, 'eng', empty description, text.
// from: AddCommentFrame, AddLyricsFrame
fn add_lang_frame(dest: &mut Vec<u8>, version: u8, id: &str, value: &str, opt: &WriteOptions) {
    if value.is_empty() {
        return;
    }
    let enc = choose_encoding(version, &[value], opt);
    let mut b = vec![enc];
    b.extend(b"eng");
    write_encoded(&mut b, "", enc, true);
    write_encoded(&mut b, value, enc, false);
    write_frame(dest, version, id, 0, &b);
}

/// TXXX: user-defined text with a description such as 'CATALOGNUMBER'.
// from: AddTxxxFrame
fn add_txxx_frame(dest: &mut Vec<u8>, version: u8, desc: &str, value: &str, opt: &WriteOptions) {
    if value.is_empty() {
        return;
    }
    let enc = choose_encoding(version, &[desc, value], opt);
    let mut b = vec![enc];
    write_encoded(&mut b, desc, enc, true);
    write_encoded(&mut b, value, enc, false);
    write_frame(dest, version, "TXXX", 0, &b);
}

/// WXXX: encoding, empty description, URL as Latin-1.
// from: AddUrlFrame
fn add_url_frame(dest: &mut Vec<u8>, version: u8, url: &str) {
    if url.is_empty() {
        return;
    }
    let mut b = vec![0u8, 0];
    b.extend(units(url).iter().map(|&u| if u <= 255 { u as u8 } else { b'?' }));
    write_frame(dest, version, "WXXX", 0, &b);
}

// from: AddPictureFrame
fn add_picture_frame(dest: &mut Vec<u8>, version: u8, pic: &Picture, opt: &WriteOptions) {
    let enc = choose_encoding(version, &[&pic.description], opt);
    let mut b = vec![enc];
    b.extend(pic.mime.as_bytes());
    b.push(0);
    b.push(pic.pic_type);
    write_encoded(&mut b, &pic.description, enc, true);
    b.extend(&pic.data);
    write_frame(dest, version, "APIC", 0, &b);
}

// from: AddYearFrames
fn add_year_frames(dest: &mut Vec<u8>, version: u8, year: &str, opt: &WriteOptions) {
    if year.is_empty() {
        return;
    }
    if version == 4 {
        return add_text_frame(dest, version, "TDRC", year, opt);
    }
    // v2.3 has a 4-digit year (TYER) and a separate DDMM date (TDAT).
    let b = year.as_bytes();
    let copy = |from: usize, n: usize| String::from_utf8_lossy(&b[from.min(b.len())..(from + n).min(b.len())]).into_owned();
    let y = copy(0, 4);
    if b.len() >= 10 && b[4] == b'-' && b[7] == b'-' && y.parse::<i64>().is_ok_and(|n| n >= 0) {
        let (m, d) = (copy(5, 2), copy(8, 2));
        add_text_frame(dest, version, "TYER", &y, opt);
        add_text_frame(dest, version, "TDAT", &format!("{d}{m}"), opt);
    } else {
        add_text_frame(dest, version, "TYER", year, opt);
    }
}

// from: BuildFrames
fn build_frames(version: u8, old_version: u8, old: &[Id3Frame], info: &AudioInfo, opt: &WriteOptions) -> Vec<u8> {
    let mut d = Vec::new();
    // 1. Everything we do not edit, unchanged.
    for fr in old {
        if old_version == 2 {
            let id = v22_to_v23(&fr.id);
            if id.len() != 4 || is_managed_frame(&id, fr) {
                continue; // v2.2-only frame we cannot convert
            }
            write_frame(&mut d, version, &id, 0, fr.data.as_deref().unwrap_or(&[]));
        } else {
            if is_managed_frame(&fr.id, fr) {
                continue;
            }
            write_frame(&mut d, version, &fr.id, fr.flags, &fr.raw);
        }
    }
    // 2. The edited fields.
    let f = |t: F| info.field(t);
    let o = opt;
    add_text_frame(&mut d, version, "TIT2", f(F::Title), o);
    add_text_frame(&mut d, version, "TPE1", f(F::Artist), o);
    add_text_frame(&mut d, version, "TALB", f(F::Album), o);
    add_text_frame(&mut d, version, "TPE2", f(F::AlbumArtist), o);
    add_year_frames(&mut d, version, f(F::Year), o);
    add_text_frame(&mut d, version, "TRCK", f(F::Track), o);
    add_text_frame(&mut d, version, "TPOS", f(F::Disc), o);
    add_text_frame(&mut d, version, "TCON", f(F::Genre), o);
    add_text_frame(&mut d, version, "TCOM", f(F::Composer), o);
    add_text_frame(&mut d, version, "TBPM", f(F::Bpm), o);
    add_lang_frame(&mut d, version, "COMM", f(F::Comment), o);
    add_text_frame(&mut d, version, "TPE3", f(F::Conductor), o);
    add_text_frame(&mut d, version, "TEXT", f(F::Lyricist), o);
    add_text_frame(&mut d, version, "TOPE", f(F::OrigArtist), o);
    add_text_frame(&mut d, version, "TPE4", f(F::Remixer), o);
    add_text_frame(&mut d, version, "TPUB", f(F::Publisher), o);
    add_txxx_frame(&mut d, version, "CATALOGNUMBER", f(F::CatalogNo), o);
    add_text_frame(&mut d, version, "TSRC", f(F::Isrc), o);
    add_text_frame(&mut d, version, "TCOP", f(F::Copyright), o);
    add_text_frame(&mut d, version, "TENC", f(F::EncodedBy), o);
    add_url_frame(&mut d, version, f(F::Url));
    add_text_frame(&mut d, version, "TIT1", f(F::Grouping), o);
    add_text_frame(&mut d, version, "TIT3", f(F::Subtitle), o);
    // TMOO only exists in v2.4; v2.3 players read the TXXX:MOOD convention
    if version == 4 {
        add_text_frame(&mut d, version, "TMOO", f(F::Mood), o);
    } else {
        add_txxx_frame(&mut d, version, "MOOD", f(F::Mood), o);
    }
    add_text_frame(&mut d, version, "TKEY", f(F::InitialKey), o);
    // Sort frames: standard in v2.4, written by iTunes in v2.3 as well
    add_text_frame(&mut d, version, "TSOT", f(F::SortTitle), o);
    add_text_frame(&mut d, version, "TSOP", f(F::SortArtist), o);
    add_text_frame(&mut d, version, "TSO2", f(F::SortAlbumArtist), o);
    add_text_frame(&mut d, version, "TSOA", f(F::SortAlbum), o);
    add_text_frame(&mut d, version, "TSOC", f(F::SortComposer), o);
    // iTunes flags: TCMP "1" = part of a compilation, PCST (4-byte number) = podcast
    if is_true_flag(f(F::Compilation)) {
        add_text_frame(&mut d, version, "TCMP", "1", o);
    }
    if is_true_flag(f(F::Podcast)) {
        write_frame(&mut d, version, "PCST", 0, &[0, 0, 0, 1]);
    }
    add_txxx_frame(&mut d, version, "REPLAYGAIN_TRACK_GAIN", f(F::RgTrackGain), o);
    add_txxx_frame(&mut d, version, "REPLAYGAIN_TRACK_PEAK", f(F::RgTrackPeak), o);
    add_txxx_frame(&mut d, version, "REPLAYGAIN_ALBUM_GAIN", f(F::RgAlbumGain), o);
    add_txxx_frame(&mut d, version, "REPLAYGAIN_ALBUM_PEAK", f(F::RgAlbumPeak), o);
    add_lang_frame(&mut d, version, "USLT", f(F::Lyrics), o);
    for p in &info.pictures {
        add_picture_frame(&mut d, version, p, o);
    }
    d
}

// from: WriteTagHeader
fn tag_header(version: u8, body_size: u32) -> Vec<u8> {
    let mut h = b"ID3".to_vec();
    h.extend([version, 0, 0]); // revision; flags: no unsync, no extended header, no footer
    h.extend(syncsafe(body_size));
    h
}

/// A complete ID3v2 tag (header, frames, `padding` zero bytes) built from an existing tag
/// (`old` may be None); used for the ID3 chunk in WAV and AIFF files.
// from: BuildID3TagBytes
pub fn build_id3_tag_bytes(old: Option<&[u8]>, info: &AudioInfo, padding: usize, opt: &WriteOptions) -> Vec<u8> {
    let parsed = old.and_then(|o| parse_id3v2(&mut Cursor::new(o)).ok()).and_then(|(t, _)| t);
    let (old_version, frames) = match &parsed {
        Some(t) => (t.version, &t.frames[..]),
        None => (0, &[][..]),
    };
    let version = if old_version == 3 || old_version == 4 { old_version } else { 3 };
    let body = build_frames(version, old_version, frames, info, opt);
    let mut out = tag_header(version, (body.len() + padding) as u32);
    out.extend(body);
    out.resize(out.len() + padding, 0);
    out
}

// from: PutLatin1
fn put_latin1(b: &mut [u8], p: usize, max_len: usize, text: &str) {
    b[p..p + max_len].fill(0);
    for (i, u) in units(text).into_iter().take(max_len).enumerate() {
        b[p + i] = if u <= 255 { u as u8 } else { b'?' };
    }
}

/// Updates an existing ID3v1 tag at the end of the file; with `create_if_missing` a new one is
/// appended when there is none.
// from: WriteID3v1
pub fn write_id3v1(path: &Path, info: &AudioInfo, create_if_missing: bool) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut s = OpenOptions::new().read(true).write(true).open(path).map_err(io)?;
    let size = stream_size(&mut s).map_err(io)?;
    let mut b = if size >= 128 { read_at(&mut s, size - 128, 128).map_err(io)? } else { Vec::new() };
    let exists = b.len() == 128 && bytes_are(&b, 0, "TAG");
    let mut new_size = size;
    if !exists {
        if !create_if_missing {
            return Ok(());
        }
        b = vec![0; 128];
        b[..3].copy_from_slice(b"TAG");
        b[127] = 255;
        new_size = size + 128; // the new tag is written at the very end below
        s.set_len(new_size).map_err(io)?;
    }
    put_latin1(&mut b, 3, 30, info.field(F::Title));
    put_latin1(&mut b, 33, 30, info.field(F::Artist));
    put_latin1(&mut b, 63, 30, info.field(F::Album));
    let year: String = String::from_utf8_lossy(&info.field(F::Year).as_bytes()[..info.field(F::Year).len().min(4)]).into_owned();
    put_latin1(&mut b, 93, 4, &year);
    let track_text = info.field(F::Track);
    let track: i64 = track_text.split('/').next().unwrap_or("").parse().unwrap_or(0);
    if (1..=255).contains(&track) {
        put_latin1(&mut b, 97, 28, info.field(F::Comment));
        b[125] = 0;
        b[126] = track as u8;
    } else {
        put_latin1(&mut b, 97, 30, info.field(F::Comment));
    }
    let genre = id3_genre_index(info.field(F::Genre));
    if genre >= 0 {
        b[127] = genre as u8;
    } else if info.field(F::Genre).is_empty() {
        b[127] = 255;
    }
    s.seek(SeekFrom::Start(new_size - 128)).map_err(io)?;
    s.write_all(&b).map_err(io)
}

// from: WriteMp3Tags
pub fn write(path: &Path, info: &AudioInfo, opt: &WriteOptions) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut src = File::open(path).map_err(io)?;
    let (tag, old_tag_size) = parse_id3v2(&mut src).map_err(io)?;
    let (old_version, frames) = match &tag {
        Some(t) => (t.version, &t.frames[..]),
        None if old_tag_size > 0 => {
            let h = read_at(&mut src, 0, 4).map_err(io)?;
            return Err(format!("ID3v2.{} understøttes ikke", h.get(3).copied().unwrap_or(0)));
        }
        None => (0, &[][..]),
    };
    let version = if old_version == 3 || old_version == 4 { old_version } else { 3 };
    let body = build_frames(version, old_version, frames, info, opt);

    if old_tag_size > 0 && 10 + body.len() as u64 <= old_tag_size {
        // Fits in the old tag's space: overwrite it in place, the rest is padding.
        drop(src);
        let padding = (old_tag_size - 10 - body.len() as u64) as usize;
        let mut dst = OpenOptions::new().write(true).open(path).map_err(io)?;
        let mut out = tag_header(version, (body.len() + padding) as u32);
        out.extend(&body);
        out.resize(out.len() + padding, 0);
        dst.write_all(&out).map_err(io)?;
    } else {
        // Too big: write tag + audio to a new file, then swap it in.
        let temp = temp_file_for(path);
        let result = (|| -> Result<(), String> {
            let mut dst = std::io::BufWriter::new(File::create(&temp).map_err(io)?);
            dst.write_all(&tag_header(version, (body.len() + NEW_TAG_PADDING) as u32)).map_err(io)?;
            dst.write_all(&body).map_err(io)?;
            dst.write_all(&[0u8; NEW_TAG_PADDING]).map_err(io)?;
            let size = stream_size(&mut src).map_err(io)?;
            copy_range(&mut src, &mut dst, old_tag_size, size.saturating_sub(old_tag_size))?;
            dst.flush().map_err(io)?;
            Ok(())
        })();
        drop(src);
        if let Err(e) = result {
            let _ = std::fs::remove_file(&temp);
            return Err(e);
        }
        replace_file_with(&temp, path)?;
    }
    write_id3v1(path, info, false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn frames_of(tag: &[u8]) -> Vec<Id3Frame> {
        parse_id3v2(&mut Cursor::new(tag)).unwrap().0.unwrap().frames
    }

    fn info(pairs: &[(F, &str)]) -> AudioInfo {
        let mut i = AudioInfo::new(PathBuf::new(), true);
        for (f, v) in pairs {
            i.put(*f, v);
        }
        i
    }

    #[test]
    fn v23_picks_encoding_per_frame() {
        let i = info(&[(F::Title, "æøå"), (F::Artist, "漢字")]);
        let fr = frames_of(&build_id3_tag_bytes(None, &i, 0, &WriteOptions::default()));
        let enc = |id: &str| fr.iter().find(|f| f.id == id).unwrap().raw.clone();
        assert_eq!(enc("TIT2")[0], 0);
        assert_eq!(&enc("TPE1")[..3], &[1, 0xFF, 0xFE]);
        let uni = WriteOptions { id3_always_unicode: true, ..Default::default() };
        let fr = frames_of(&build_id3_tag_bytes(None, &i, 0, &uni));
        assert!(fr.iter().all(|f| f.raw[0] == 1));
    }

    #[test]
    fn keeps_v24() {
        let old = build_id3_tag_bytes(None, &info(&[(F::Title, "a")]), 0, &WriteOptions::default());
        let mut v24 = old.clone();
        v24[3] = 4; // a v2.4 tag with the same (syncsafe-sized, small) frame
        let out = build_id3_tag_bytes(Some(&v24), &info(&[(F::Title, "æ")]), 0, &WriteOptions::default());
        assert_eq!(out[3], 4);
        assert_eq!(frames_of(&out)[0].raw, [3, 0xC3, 0xA6]); // UTF-8
    }

    #[test]
    fn unknown_frames_kept() {
        let mut d = Vec::new();
        write_frame(&mut d, 3, "PRIV", 0, b"owner\0data");
        let mut old = tag_header(3, d.len() as u32);
        old.extend(&d);
        let out = build_id3_tag_bytes(Some(&old), &info(&[(F::Title, "t")]), 0, &WriteOptions::default());
        let fr = frames_of(&out);
        assert_eq!(fr[0].id, "PRIV");
        assert_eq!(fr[0].raw, b"owner\0data");
    }

    #[test]
    fn id3v1_updated_not_created() {
        let dir = std::env::temp_dir().join(format!("tidytag-id3v1-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.mp3");
        std::fs::write(&p, vec![0u8; 200]).unwrap();
        write_id3v1(&p, &info(&[(F::Title, "x")]), false).unwrap();
        assert_eq!(std::fs::read(&p).unwrap().len(), 200);
        let mut with = vec![0u8; 72];
        let mut tag = vec![0u8; 128];
        tag[..3].copy_from_slice(b"TAG");
        with.extend(tag);
        std::fs::write(&p, &with).unwrap();
        write_id3v1(&p, &info(&[(F::Title, "Hej"), (F::Track, "7/9"), (F::Genre, "rock")]), false).unwrap();
        let b = std::fs::read(&p).unwrap();
        assert_eq!(b.len(), 200);
        assert_eq!(&b[75..78], b"Hej");
        assert_eq!(b[72 + 126], 7);
        assert_eq!(b[72 + 127], 17);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
