//! WMA/ASF: audio properties from the File and Stream Properties objects, tags from the
//! Content Description (title, author, copyright, description), the Extended Content
//! Description (WM/* attributes) and the Metadata (Library) objects inside the Header
//! Extension, where large values such as big WM/Picture items live (port of asfreader.pas).

use super::id3::copy;
use crate::model::{flag_value, AudioInfo, TagField};
use crate::text::*;
use std::io::{Read, Seek};

pub const GUID_HEADER: &str = "75B22630-668E-11CF-A6D9-00AA0062CE6C";
pub const GUID_FILE_PROPS: &str = "8CABDCA1-A947-11CF-8EE4-00C00C205365";
pub const GUID_STREAM_PROPS: &str = "B7DC0791-A9B7-11CF-8EE6-00C00C205365";
pub const GUID_AUDIO_MEDIA: &str = "F8699E40-5B4D-11CF-A8FD-00805F5C442B";
pub const GUID_CONTENT_DESC: &str = "75B22633-668E-11CF-A6D9-00AA0062CE6C";
pub const GUID_EXT_CONTENT_DESC: &str = "D2D0A440-E307-11D2-97F0-00A0C95EA850";
pub const GUID_HEADER_EXT: &str = "5FBF03B5-A92E-11CF-8EE3-00C00C205365";
pub const GUID_METADATA: &str = "C5F8CBEA-5BAF-4877-8467-AA8C44FA4CCA";
pub const GUID_METADATA_LIBRARY: &str = "44231C94-9498-49D1-A141-1D134E457054";

const ASF_STRING: u32 = 0;
const ASF_BYTES: u32 = 1;
const ASF_BOOL: u32 = 2;
const ASF_DWORD: u32 = 3;
const ASF_QWORD: u32 = 4;
const ASF_WORD: u32 = 5;

/// Extended attribute per field; '' = stored in the Content Description object.
pub const WM_NAMES: [&str; 37] = [
    "", "", "WM/AlbumTitle", "WM/Year", "WM/TrackNumber", "WM/PartOfSet", "WM/Genre", "",
    "WM/AlbumArtist", "WM/Composer", "WM/BeatsPerMinute", "WM/Lyrics", "WM/Conductor",
    "WM/Writer", "WM/OriginalArtist", "WM/ModifiedBy", "WM/Publisher", "WM/CatalogNo",
    "WM/ISRC", "", "WM/EncodedBy", "WM/AuthorURL", "WM/ContentGroupDescription",
    "WM/SubTitle", "WM/Mood", "WM/InitialKey", "WM/TitleSortOrder", "WM/ArtistSortOrder",
    "WM/AlbumArtistSortOrder", "WM/AlbumSortOrder", "WM/ComposerSortOrder", "WM/IsCompilation",
    "", "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK", "REPLAYGAIN_ALBUM_GAIN",
    "REPLAYGAIN_ALBUM_PEAK",
];

/// The GUID text as stored: Data1 (4 bytes), Data2 and Data3 (2 bytes each) little-endian.
// from: GuidBytes
pub fn guid_bytes(g: &str) -> [u8; 16] {
    let hex: String = g.chars().filter(|&c| c != '-').collect();
    let mut raw = [0u8; 16];
    for (i, r) in raw.iter_mut().enumerate() {
        *r = u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).unwrap_or(0);
    }
    [raw[3], raw[2], raw[1], raw[0], raw[5], raw[4], raw[7], raw[6],
     raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]]
}

pub fn is_guid(b: &[u8], p: i64, g: &str) -> bool {
    p >= 0 && p + 16 <= b.len() as i64 && b[p as usize..p as usize + 16] == guid_bytes(g)
}

/// Text without the trailing zero character(s).
// from: Utf16Text
fn utf16_text(b: &[u8], p: i64, mut len: i64) -> String {
    let at = |i: i64| if i >= 0 && (i as usize) < b.len() { b[i as usize] } else { 1 };
    while len >= 2 && at(p + len - 2) == 0 && at(p + len - 1) == 0 {
        len -= 2;
    }
    utf16(b, p, len, false)
}

// from: ValueText
fn value_text(b: &[u8], p: i64, len: i64, data_type: u32) -> String {
    match data_type {
        ASF_STRING => utf16_text(b, p, len),
        ASF_BOOL if len >= 2 => if b.get(p as usize).copied().unwrap_or(0) != 0 { "True" } else { "False" }.into(),
        ASF_DWORD if len >= 4 => le32(b, p).to_string(),
        ASF_QWORD if len >= 8 => le64(b, p).to_string(),
        ASF_WORD if len >= 2 => le16(b, p).to_string(),
        _ => String::new(),
    }
}

/// Ends after the zero character of a UTF-16 string starting at p.
// from: SkipUtf16z
fn skip_utf16z(b: &[u8], mut p: i64) -> i64 {
    while p + 1 < b.len() as i64 && !(b[p as usize] == 0 && b[p as usize + 1] == 0) {
        p += 2;
    }
    p + 2
}

#[derive(Default)]
struct TrackParts {
    number: String,
    total: String,
    zero_based: i64,
}

// from: AddPictureBlob
fn add_picture_blob(b: &[u8], p: i64, len: i64, info: &mut AudioInfo) {
    if len < 9 {
        return;
    }
    let pic_type = b.get(p as usize).copied().unwrap_or(0);
    let data_len = le32(b, p + 1) as i64;
    let mime_end = skip_utf16z(b, p + 5);
    let desc_end = skip_utf16z(b, mime_end);
    if desc_end + data_len > p + len {
        return;
    }
    info.has_cover = true;
    let mime = utf16_text(b, p + 5, mime_end - p - 5);
    let desc = utf16_text(b, mime_end, desc_end - mime_end);
    info.add_picture(pic_type, &mime, &desc, copy(b, desc_end, data_len));
}

// from: HandleAttr
fn handle_attr(name: &str, b: &[u8], p: i64, len: i64, data_type: u32, info: &mut AudioInfo, track: &mut TrackParts) {
    let is = |n: &str| name.eq_ignore_ascii_case(n);
    if is("WM/Picture") {
        if data_type == ASF_BYTES {
            add_picture_blob(b, p, len, info);
        }
        return;
    }
    let v = value_text(b, p, len, data_type);
    if v.is_empty() {
        return;
    }
    if is("WM/TrackNumber") {
        track.number = pascal_trim(&v).to_string();
    } else if is("TotalTracks") {
        track.total = pascal_trim(&v).to_string();
    } else if is("WM/Track") {
        track.zero_based = pascal_trim(&v).parse().unwrap_or(-1);
    } else if is("WM/UserWebURL") {
        info.set_field(TagField::Url, &v, false);
    } else if let Some(i) = WM_NAMES.iter().position(|w| !w.is_empty() && is(w)) {
        let f = TagField::ALL[i];
        match f {
            TagField::Compilation => info.set_field(f, flag_value(&v), true),
            TagField::Lyrics => info.set_field(f, &v, false),
            _ => info.append_field(f, &clean_tag_text(&v)),
        }
    }
}

// from: ReadContentDesc
fn read_content_desc(b: &[u8], p: i64, limit: i64, info: &mut AudioInfo) {
    if p + 10 > limit {
        return;
    }
    let lens: Vec<i64> = (0..5).map(|i| le16(b, p + i * 2) as i64).collect();
    let mut q = p + 10;
    let mut texts = Vec::new();
    for len in lens {
        if q + len > limit {
            return;
        }
        texts.push(clean_tag_text(&utf16_text(b, q, len)));
        q += len;
    }
    info.set_field(TagField::Title, &texts[0], true);
    info.set_field(TagField::Artist, &texts[1], true);
    info.set_field(TagField::Copyright, &texts[2], true);
    info.set_field(TagField::Comment, &texts[3], true);
}

// from: ReadExtContentDesc
fn read_ext_content_desc(b: &[u8], mut p: i64, limit: i64, info: &mut AudioInfo, track: &mut TrackParts) {
    if p + 2 > limit {
        return;
    }
    let count = le16(b, p);
    p += 2;
    for _ in 0..count {
        if p + 2 > limit {
            return;
        }
        let name_len = le16(b, p) as i64;
        if p + 6 + name_len > limit {
            return;
        }
        let name = utf16_text(b, p + 2, name_len);
        let data_type = le16(b, p + 2 + name_len);
        let val_len = le16(b, p + 4 + name_len) as i64;
        p += 6 + name_len;
        if p + val_len > limit {
            return;
        }
        handle_attr(&name, b, p, val_len, data_type, info, track);
        p += val_len;
    }
}

/// Metadata and Metadata Library objects share their record layout.
// from: ReadMetadataRecords
fn read_metadata_records(b: &[u8], mut p: i64, limit: i64, info: &mut AudioInfo, track: &mut TrackParts) {
    if p + 2 > limit {
        return;
    }
    let count = le16(b, p);
    p += 2;
    for _ in 0..count {
        if p + 12 > limit {
            return;
        }
        let name_len = le16(b, p + 4) as i64;
        let data_type = le16(b, p + 6);
        let data_len = le32(b, p + 8) as i64;
        if p + 12 + name_len + data_len > limit {
            return;
        }
        // only file-wide values (stream 0)
        if le16(b, p + 2) == 0 {
            let name = utf16_text(b, p + 12, name_len);
            handle_attr(&name, b, p + 12 + name_len, data_len, data_type, info, track);
        }
        p += 12 + name_len + data_len;
    }
}

// from: ReadAsf
pub fn read<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    info.supported = true;
    let b = read_at(s, 0, 30).map_err(io)?;
    if b.len() < 30 || !is_guid(&b, 0, GUID_HEADER) {
        return Err("Ikke en WMA/ASF-fil".into());
    }
    let header_size = le64(&b, 16) as i64;
    let fsize = stream_size(s).map_err(io)? as i64;
    if header_size < 30 || header_size > fsize || header_size > 256 * 1024 * 1024 {
        return Err("Ugyldig ASF-header".into());
    }
    let b = read_at(s, 0, header_size as u64).map_err(io)?;
    info.codec = "WMA".into();
    let mut track = TrackParts { zero_based: -1, ..Default::default() };
    let mut any_tag = false;
    let mut p: i64 = 30;
    while p + 24 <= header_size {
        let mut size = le64(&b, p + 16) as i64;
        if size < 24 || p + size > header_size {
            break;
        }
        if is_guid(&b, p, GUID_FILE_PROPS) && size >= 24 + 80 {
            let duration = le64(&b, p + 24 + 40);
            let preroll = le64(&b, p + 24 + 56);
            info.duration = (duration as f64 / 1e7 - preroll as f64 / 1000.0).max(0.0);
        } else if is_guid(&b, p, GUID_STREAM_PROPS) && is_guid(&b, p + 24, GUID_AUDIO_MEDIA) && size >= 24 + 54 + 16 {
            let q = p + 24 + 54;
            let codec = le16(&b, q);
            info.channels = le16(&b, q + 2);
            info.sample_rate = le32(&b, q + 4);
            info.bitrate = pascal_round(le32(&b, q + 8) as f64 * 8.0 / 1000.0) as u32;
            let name = match codec {
                0x0160 => Some("WMA v1"),
                0x0161 => Some("WMA"),
                0x0162 => Some("WMA Pro"),
                0x0163 => Some("WMA Lossless"),
                0x000A => Some("WMA Voice"),
                0x0055 => Some("MP3 (ASF)"),
                _ => None,
            };
            if let Some(n) = name {
                info.codec = n.into();
            }
        } else if is_guid(&b, p, GUID_CONTENT_DESC) {
            read_content_desc(&b, p + 24, p + size, info);
            any_tag = true;
        } else if is_guid(&b, p, GUID_EXT_CONTENT_DESC) {
            read_ext_content_desc(&b, p + 24, p + size, info, &mut track);
            any_tag = true;
        } else if is_guid(&b, p, GUID_HEADER_EXT) && size >= 46 {
            let mut q = p + 46;
            let ext_end = p + size;
            while q + 24 <= ext_end {
                let sz = le64(&b, q + 16) as i64;
                if sz < 24 || q + sz > ext_end {
                    break;
                }
                if is_guid(&b, q, GUID_METADATA_LIBRARY) || is_guid(&b, q, GUID_METADATA) {
                    read_metadata_records(&b, q + 24, q + sz, info, &mut track);
                }
                q += sz;
            }
            size = ext_end - p;
        }
        p += size;
    }
    if any_tag {
        info.add_tag_type("ASF");
    }
    if track.number.is_empty() && track.zero_based >= 0 {
        track.number = (track.zero_based + 1).to_string();
    }
    if !track.number.is_empty() {
        let t = if track.total.is_empty() { track.number.clone() } else { format!("{}/{}", track.number, track.total) };
        info.set_field(TagField::Track, &t, true);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use std::path::PathBuf;

    fn u16z(s: &str) -> Vec<u8> {
        let mut v: Vec<u8> = s.encode_utf16().flat_map(|w| w.to_le_bytes()).collect();
        v.extend([0, 0]);
        v
    }

    fn object(guid: &str, body: &[u8]) -> Vec<u8> {
        let mut v = guid_bytes(guid).to_vec();
        v.extend((body.len() as u64 + 24).to_le_bytes());
        v.extend(body);
        v
    }

    fn asf(objects: &[Vec<u8>]) -> AudioInfo {
        let body: Vec<u8> = objects.concat();
        let mut v = guid_bytes(GUID_HEADER).to_vec();
        v.extend((body.len() as u64 + 30).to_le_bytes());
        v.extend((objects.len() as u32).to_le_bytes());
        v.extend([1, 2]);
        v.extend(body);
        let mut info = AudioInfo::new(PathBuf::new(), true);
        read(&mut Cursor::new(v), &mut info).unwrap();
        info
    }

    #[test]
    fn content_description_title_author() {
        let (t, a) = (u16z("Titel"), u16z("Kunstner"));
        let mut body = Vec::new();
        for l in [t.len(), a.len(), 0, 0, 0] {
            body.extend((l as u16).to_le_bytes());
        }
        body.extend(&t);
        body.extend(&a);
        let info = asf(&[object(GUID_CONTENT_DESC, &body)]);
        assert_eq!(info.field(TagField::Title), "Titel");
        assert_eq!(info.field(TagField::Artist), "Kunstner");
        assert_eq!(info.tag_types_text(), "ASF");
    }

    fn ext_attr(name: &str, ty: u16, val: &[u8]) -> Vec<u8> {
        let n = u16z(name);
        let mut v = (n.len() as u16).to_le_bytes().to_vec();
        v.extend(&n);
        v.extend(ty.to_le_bytes());
        v.extend((val.len() as u16).to_le_bytes());
        v.extend(val);
        v
    }

    #[test]
    fn track_number_dword_and_picture() {
        let mut pic = vec![3u8];
        pic.extend(3u32.to_le_bytes());
        pic.extend(u16z("image/jpeg"));
        pic.extend(u16z(""));
        pic.extend([0xFF, 0xD8, 0xFF]);
        let mut body = 2u16.to_le_bytes().to_vec();
        body.extend(ext_attr("WM/TrackNumber", 3, &5u32.to_le_bytes()));
        body.extend(ext_attr("WM/Picture", 1, &pic));
        let info = asf(&[object(GUID_EXT_CONTENT_DESC, &body)]);
        assert_eq!(info.field(TagField::Track), "5");
        assert_eq!(info.pictures.len(), 1);
        assert_eq!(info.pictures[0].pic_type, 3);
        assert_eq!(info.pictures[0].mime, "image/jpeg");
    }
}
