//! Writes tags into WMA/ASF files (port of asfwriter.pas). The header object is rebuilt:
//! Content Description and Extended Content Description are replaced, managed records are
//! removed from the Metadata (Library) objects, values over 64 KB (big pictures, long lyrics) go
//! into the Metadata Library. Unknown attributes and all other objects are kept unchanged.
//! If the new header fits into the old one the rest is padded and the file is written in place;
//! otherwise header + the unchanged data/index objects go to a temporary file and the file size
//! in the File Properties object is updated.

use super::asf::{guid_bytes, is_guid, GUID_CONTENT_DESC, GUID_EXT_CONTENT_DESC, GUID_FILE_PROPS, GUID_HEADER,
    GUID_HEADER_EXT, GUID_METADATA, GUID_METADATA_LIBRARY, WM_NAMES};
use crate::fileio::{copy_range, replace_file_with, temp_file_for};
use crate::model::{detect_image_mime, is_true_flag, AudioInfo, Picture, TagField};
use crate::text::{le16, le32, le64, pascal_trim, read_at, stream_size, utf16};
use crate::write::WriteOptions;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::Path;

const GUID_PADDING: &str = "1806D474-CADF-4509-A4BA-9AABCB96AAE8";
const GUID_HEADER_EXT_RESERVED: &str = "ABD3D211-A9BA-11CF-8EE6-00C00C205365";
const ASF_STRING: u16 = 0;
const ASF_BYTES: u16 = 1;
const ASF_BOOL: u16 = 2;
const REWRITE_PADDING: i64 = 4096;
const MAX_IN_PLACE_PADDING: i64 = 64 * 1024;

/// UTF-16LE with a terminating zero character.
// from: Utf16z
pub fn utf16z(s: &str) -> Vec<u8> {
    let mut v: Vec<u8> = s.encode_utf16().flat_map(|u| u.to_le_bytes()).collect();
    v.extend([0, 0]);
    v
}

/// Attribute names written by TidyTag (and their old variants), compared case-insensitively.
// from: IsManagedAttr
pub fn is_managed_attr(name: &str) -> bool {
    WM_NAMES.iter().any(|w| !w.is_empty() && name.eq_ignore_ascii_case(w))
        || ["WM/Track", "TotalTracks", "WM/Picture", "WM/UserWebURL"].iter().any(|w| name.eq_ignore_ascii_case(w))
}

fn object(dest: &mut Vec<u8>, guid: &str, body: &[u8]) {
    dest.extend(guid_bytes(guid));
    dest.extend((24 + body.len() as u64).to_le_bytes());
    dest.extend(body);
}

// from: PictureBlob
fn picture_blob(pic: &Picture) -> Vec<u8> {
    let mut b = vec![pic.pic_type];
    b.extend((pic.data.len() as u32).to_le_bytes());
    let mime = if pic.mime.is_empty() { detect_image_mime(&pic.data, "image/jpeg").to_string() } else { pic.mime.clone() };
    b.extend(utf16z(&mime));
    b.extend(utf16z(&pic.description));
    b.extend(&pic.data);
    b
}

struct Attr {
    name: String,
    data_type: u16,
    value: Vec<u8>,
}

/// Name of an attribute record: the UTF-16 text without its last character (the terminator).
fn attr_name(b: &[u8], p: i64, name_len: i64) -> String {
    utf16(b, p, name_len - if name_len >= 2 { 2 } else { 0 }, false)
}

/// Kept (unknown) attributes of an Extended Content Description body.
// from: KeepExtAttrs
fn keep_ext_attrs(b: &[u8], mut p: i64, limit: i64, l: &mut Vec<Attr>) {
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
        let name = attr_name(b, p + 2, name_len);
        let data_type = le16(b, p + 2 + name_len) as u16;
        let val_len = le16(b, p + 4 + name_len) as i64;
        if p + 6 + name_len + val_len > limit {
            return;
        }
        if !is_managed_attr(&name) {
            let at = (p + 6 + name_len) as usize;
            l.push(Attr { name, data_type, value: b[at..at + val_len as usize].to_vec() });
        }
        p += 6 + name_len + val_len;
    }
}

/// Metadata / Metadata Library body without the managed file-wide records, plus `extra`.
// from: FilterMetadata
fn filter_metadata(b: &[u8], mut p: i64, limit: i64, extra: &[Attr]) -> Vec<u8> {
    let mut d = vec![0u8, 0]; // count, patched below
    let mut kept = 0u32;
    if p + 2 <= limit {
        let count = le16(b, p);
        p += 2;
        for _ in 0..count {
            if p + 12 > limit {
                break;
            }
            let start = p;
            let name_len = le16(b, p + 4) as i64;
            let data_len = le32(b, p + 8) as i64;
            if p + 12 + name_len + data_len > limit {
                break;
            }
            let name = attr_name(b, p + 12, name_len);
            p += 12 + name_len + data_len;
            if le16(b, start + 2) == 0 && is_managed_attr(&name) {
                continue;
            }
            d.extend(&b[start as usize..p as usize]);
            kept += 1;
        }
    }
    for a in extra {
        let rec = utf16z(&a.name);
        d.extend(0u16.to_le_bytes()); // language list index
        d.extend(0u16.to_le_bytes()); // stream 0 = whole file
        d.extend((rec.len() as u16).to_le_bytes());
        d.extend(a.data_type.to_le_bytes());
        d.extend((a.value.len() as u32).to_le_bytes());
        d.extend(&rec);
        d.extend(&a.value);
        kept += 1;
    }
    d[0] = kept as u8;
    d[1] = (kept >> 8) as u8;
    d
}

// from: ContentDescBody
fn content_desc_body(info: &AudioInfo) -> Vec<u8> {
    let text = |f: TagField| {
        let v = info.field(f);
        let t = if v.is_empty() { Vec::new() } else { utf16z(v) };
        if t.len() > 0xFFFF { Vec::new() } else { t } // cannot be stored here
    };
    let texts = [text(TagField::Title), text(TagField::Artist), text(TagField::Copyright), text(TagField::Comment), Vec::new()];
    let mut d = Vec::new();
    for t in &texts {
        d.extend((t.len() as u16).to_le_bytes());
    }
    for t in &texts {
        d.extend(t);
    }
    d
}

// from: ExtContentBody
fn ext_content_body(l: &[Attr]) -> Vec<u8> {
    let mut d = (l.len() as u16).to_le_bytes().to_vec();
    for a in l {
        let name = utf16z(&a.name);
        d.extend((name.len() as u16).to_le_bytes());
        d.extend(&name);
        d.extend(a.data_type.to_le_bytes());
        d.extend((a.value.len() as u16).to_le_bytes());
        d.extend(&a.value);
    }
    d
}

/// Our attributes; values that do not fit a WORD length go to `big` (Metadata Library).
// from: BuildAttrs
fn build_attrs(info: &AudioInfo) -> (Vec<Attr>, Vec<Attr>) {
    let (mut small, mut big) = (Vec::new(), Vec::new());
    let mut put = |name: &str, data_type: u16, value: Vec<u8>| {
        let a = Attr { name: name.to_string(), data_type, value };
        if a.value.len() > 0xFFFF { big.push(a) } else { small.push(a) }
    };
    for (i, f) in TagField::ALL.iter().enumerate() {
        let v = info.field(*f);
        if v.is_empty() || WM_NAMES[i].is_empty() {
            continue;
        }
        match f {
            // WMP writes a BOOL (4 bytes)
            TagField::Compilation => {
                if is_true_flag(v) {
                    put(WM_NAMES[i], ASF_BOOL, vec![1, 0, 0, 0]);
                }
            }
            TagField::Track => {
                let (num, total) = match v.find('/') {
                    Some(s) => (pascal_trim(&v[..s]).to_string(), pascal_trim(&v[s + 1..]).to_string()),
                    None => (v.to_string(), String::new()),
                };
                if !num.is_empty() {
                    put("WM/TrackNumber", ASF_STRING, utf16z(&num));
                }
                if !total.is_empty() {
                    put("TotalTracks", ASF_STRING, utf16z(&total));
                }
            }
            _ => put(WM_NAMES[i], ASF_STRING, utf16z(v)),
        }
    }
    for p in &info.pictures {
        put("WM/Picture", ASF_BYTES, picture_blob(p));
    }
    (small, big)
}

fn ext_body(reserved: &[u8], inner: &[u8]) -> Vec<u8> {
    // reserved GUID + reserved WORD as stored, then the new inner data size
    let mut body = reserved[..18].to_vec();
    body.extend((inner.len() as u32).to_le_bytes());
    body.extend(inner);
    body
}

// from: WriteAsfTags
pub fn write(path: &Path, info: &AudioInfo, _opt: &WriteOptions) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut s = File::open(path).map_err(io)?;
    let b = read_at(&mut s, 0, 30).map_err(io)?;
    if b.len() < 30 || !is_guid(&b, 0, GUID_HEADER) {
        return Err("Ikke en WMA/ASF-fil".into());
    }
    let header_size = le64(&b, 16) as i64;
    let fsize = stream_size(&mut s).map_err(io)? as i64;
    if header_size < 30 || header_size > fsize {
        return Err("Ugyldig ASF-header".into());
    }
    let b = read_at(&mut s, 0, header_size as u64).map_err(io)?;

    // pass 1: unknown attributes of the old Extended Content Description
    let mut kept = Vec::new();
    let mut p = 30i64;
    while p + 24 <= header_size {
        let size = le64(&b, p + 16) as i64;
        if size < 24 || p + size > header_size {
            return Err("Ugyldigt ASF-objekt".into());
        }
        if is_guid(&b, p, GUID_EXT_CONTENT_DESC) {
            keep_ext_attrs(&b, p + 24, p + size, &mut kept);
        }
        p += size;
    }
    let (small_ours, big) = build_attrs(info);
    let mut small = kept;
    small.extend(small_ours);

    // pass 2: assemble the new header objects
    let mut objects = Vec::new();
    let mut count = 0u32;
    let mut file_props_pos: i64 = -1;
    let mut have_ext = false;
    let mut p = 30i64;
    while p + 24 <= header_size {
        let mut size = le64(&b, p + 16) as i64;
        if is_guid(&b, p, GUID_CONTENT_DESC) || is_guid(&b, p, GUID_EXT_CONTENT_DESC) || is_guid(&b, p, GUID_PADDING) {
            // replaced / dropped
        } else if is_guid(&b, p, GUID_HEADER_EXT) && size >= 46 {
            have_ext = true;
            let mut have_library = false;
            let mut inner = Vec::new();
            let mut q = p + 46;
            let ext_end = p + size;
            while q + 24 <= ext_end {
                let sz = le64(&b, q + 16) as i64;
                if sz < 24 || q + sz > ext_end {
                    break;
                }
                if is_guid(&b, q, GUID_METADATA_LIBRARY) {
                    have_library = true;
                    object(&mut inner, GUID_METADATA_LIBRARY, &filter_metadata(&b, q + 24, q + sz, &big));
                } else if is_guid(&b, q, GUID_METADATA) {
                    object(&mut inner, GUID_METADATA, &filter_metadata(&b, q + 24, q + sz, &[]));
                } else if !is_guid(&b, q, GUID_PADDING) {
                    inner.extend(&b[q as usize..(q + sz) as usize]);
                }
                q += sz;
            }
            if !have_library && !big.is_empty() {
                object(&mut inner, GUID_METADATA_LIBRARY, &filter_metadata(&[], 0, 0, &big));
            }
            object(&mut objects, GUID_HEADER_EXT, &ext_body(&b[(p + 24) as usize..(p + 46) as usize], &inner));
            count += 1;
            size = ext_end - p;
        } else {
            if is_guid(&b, p, GUID_FILE_PROPS) {
                // the reader needs 104 bytes too; a shorter one would put the file size elsewhere
                if size < 24 + 80 {
                    return Err("Ugyldigt ASF-objekt".into());
                }
                file_props_pos = 30 + objects.len() as i64;
            }
            objects.extend(&b[p as usize..(p + size) as usize]);
            count += 1;
        }
        p += size;
    }
    if file_props_pos < 0 {
        return Err("ASF-filen mangler File Properties".into());
    }
    if !have_ext && !big.is_empty() {
        let mut inner = Vec::new();
        object(&mut inner, GUID_METADATA_LIBRARY, &filter_metadata(&[], 0, 0, &big));
        let mut reserved = guid_bytes(GUID_HEADER_EXT_RESERVED).to_vec();
        reserved.extend([6, 0]);
        object(&mut objects, GUID_HEADER_EXT, &ext_body(&reserved, &inner));
        count += 1;
    }
    object(&mut objects, GUID_CONTENT_DESC, &content_desc_body(info));
    count += 1;
    if !small.is_empty() {
        object(&mut objects, GUID_EXT_CONTENT_DESC, &ext_content_body(&small));
        count += 1;
    }

    // in place if it fits with room for a padding object (or exactly)
    let pad = header_size - 30 - objects.len() as i64;
    // (a lot of free space, e.g. after removing a big picture, is given back by a rewrite)
    let new_file_size = if pad == 0 || (24..=MAX_IN_PLACE_PADDING).contains(&pad) {
        if pad > 0 {
            objects.extend(guid_bytes(GUID_PADDING));
            objects.extend((pad as u64).to_le_bytes());
            objects.resize(objects.len() + (pad - 24) as usize, 0);
            count += 1;
        }
        fsize
    } else {
        objects.extend(guid_bytes(GUID_PADDING));
        objects.extend((REWRITE_PADDING as u64).to_le_bytes());
        objects.resize(objects.len() + (REWRITE_PADDING - 24) as usize, 0);
        count += 1;
        fsize - header_size + 30 + objects.len() as i64
    };
    let mut new_header = b[..30].to_vec();
    new_header.extend(objects);
    let len = new_header.len() as u64;
    new_header[16..24].copy_from_slice(&len.to_le_bytes());
    new_header[24..28].copy_from_slice(&count.to_le_bytes());
    let at = (file_props_pos + 24 + 16) as usize;
    new_header[at..at + 8].copy_from_slice(&(new_file_size as u64).to_le_bytes());

    if new_header.len() as i64 != header_size {
        let temp = temp_file_for(path);
        let result = (|| -> Result<(), String> {
            let mut dst = std::io::BufWriter::new(File::create(&temp).map_err(io)?);
            dst.write_all(&new_header).map_err(io)?;
            copy_range(&mut s, &mut dst, header_size as u64, (fsize - header_size) as u64)?;
            dst.flush().map_err(io)
        })();
        drop(s);
        if let Err(e) = result {
            let _ = std::fs::remove_file(&temp);
            return Err(e);
        }
        return replace_file_with(&temp, path);
    }
    drop(s);
    let mut s = OpenOptions::new().write(true).open(path).map_err(io)?;
    s.write_all(&new_header).map_err(io)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::read::read_audio_info;

    /// Header with File Properties, an Extended Content Description holding an unknown
    /// attribute, 2 KB padding; then a fake data object.
    fn wma() -> Vec<u8> {
        let mut fp = vec![0u8; 80];
        fp[40..48].copy_from_slice(&(30_000_000u64).to_le_bytes()); // 3 s
        let mut ext = 1u16.to_le_bytes().to_vec();
        let n = utf16z("MyOwnAttr");
        ext.extend((n.len() as u16).to_le_bytes());
        ext.extend(&n);
        ext.extend(ASF_STRING.to_le_bytes());
        let v = utf16z("keep me");
        ext.extend((v.len() as u16).to_le_bytes());
        ext.extend(&v);
        let mut objects = Vec::new();
        object(&mut objects, GUID_FILE_PROPS, &fp);
        object(&mut objects, GUID_EXT_CONTENT_DESC, &ext);
        object(&mut objects, GUID_PADDING, &vec![0u8; 2048]);
        let mut h = guid_bytes(GUID_HEADER).to_vec();
        h.extend((30 + objects.len() as u64).to_le_bytes());
        h.extend(3u32.to_le_bytes());
        h.extend([1, 2]);
        h.extend(objects);
        let size = h.len() as u64 + 40;
        let at = 30 + 24 + 16;
        h[at..at + 8].copy_from_slice(&size.to_le_bytes());
        h.extend(b"DATAOBJECT-DATAOBJECT-DATAOBJECT-DATAOBJ");
        h
    }

    fn edit(f: impl Fn(&mut AudioInfo)) -> (Vec<u8>, AudioInfo) {
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("tidytag-asfw-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.wma");
        std::fs::write(&p, wma()).unwrap();
        let mut info = read_audio_info(&p, true);
        f(&mut info);
        write(&p, &info, &WriteOptions::default()).unwrap();
        let out = std::fs::read(&p).unwrap();
        let back = read_audio_info(&p, true);
        std::fs::remove_dir_all(dir).unwrap();
        (out, back)
    }

    #[test]
    fn short_file_properties_is_an_error_not_a_panic() {
        // a damaged header: File Properties is only 20 bytes
        let mut objects = Vec::new();
        object(&mut objects, GUID_FILE_PROPS, &[0u8; 20]);
        let mut h = guid_bytes(GUID_HEADER).to_vec();
        h.extend((30 + objects.len() as u64).to_le_bytes());
        h.extend(1u32.to_le_bytes());
        h.extend([1, 2]);
        h.extend(objects);
        h.extend(b"DATA");
        let dir = std::env::temp_dir().join(format!("tidytag-asfw-short-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.wma");
        std::fs::write(&p, &h).unwrap();
        let mut values = std::collections::BTreeMap::new();
        values.insert(TagField::Title, "x".to_string());
        let r = crate::batch::update_file_tags(&p, &values, None, &WriteOptions::default());
        assert!(matches!(r, Err((_, false))));
        assert_eq!(std::fs::read(&p).unwrap(), h);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn big_value_goes_to_metadata_library() {
        let long = "x".repeat(70 * 1024 / 2);
        let (out, back) = edit(|i| i.put(TagField::Lyrics, &long));
        assert!(out.windows(16).any(|w| w == guid_bytes(GUID_METADATA_LIBRARY)));
        assert_eq!(back.field(TagField::Lyrics), long);
    }

    #[test]
    fn unknown_attributes_kept() {
        let (out, back) = edit(|i| i.put(TagField::Title, "Hej"));
        let name = utf16z("MyOwnAttr");
        assert!(out.windows(name.len()).any(|w| w == &name[..]));
        assert_eq!(back.field(TagField::Title), "Hej");
        assert_eq!(out.len(), wma().len()); // fitted in the padding: in place
    }

    #[test]
    fn file_size_updated_on_rewrite() {
        let (out, _) = edit(|i| crate::batch::set_front_cover(i, crate::scenario::test_png(20_000)));
        let header = le64(&out, 16) as usize;
        let at = 30 + 24 + 16; // File Properties is still the first object
        assert_eq!(le64(&out, at as i64) as usize, out.len());
        assert!(out[header..].starts_with(b"DATAOBJECT"));
    }
}
