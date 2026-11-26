//! ID3v2.2/2.3/2.4 and ID3v1 reading (port of the ID3 parts of mp3reader.pas).

use crate::model::{flag_value, AudioInfo, TagField as F};
use crate::text::*;
use std::io::{Read, Seek};

#[derive(Debug, Clone)]
pub struct Id3Frame {
    /// as stored: 3 chars for v2.2, 4 chars otherwise
    pub id: String,
    /// frame flags as stored (0 for v2.2)
    pub flags: u16,
    /// frame body as stored (tag-level unsynchronisation already removed)
    pub raw: Vec<u8>,
    /// body ready for decoding; None if compressed or encrypted
    pub data: Option<Vec<u8>>,
}

// from: RemoveUnsync
fn remove_unsync(b: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        out.push(b[i]);
        if b[i] == 0xFF && i + 1 < b.len() && b[i + 1] == 0x00 {
            i += 1;
        }
        i += 1;
    }
    out
}

// from: DecodeID3Text
pub fn decode_id3_text(b: &[u8], p: i64, len: i64, enc: u8) -> String {
    let at = |i: i64| if i >= 0 && (i as usize) < b.len() { b[i as usize] } else { 0 };
    let s = match enc {
        1 => {
            if len >= 2 && at(p) == 0xFE && at(p + 1) == 0xFF {
                utf16(b, p + 2, len - 2, true)
            } else if len >= 2 && at(p) == 0xFF && at(p + 1) == 0xFE {
                utf16(b, p + 2, len - 2, false)
            } else {
                utf16(b, p, len, false)
            }
        }
        2 => utf16(b, p, len, true),
        3 => raw_utf8(b, p, len),
        _ => latin1(b, p, len),
    };
    clean_tag_text(&s)
}

// from: SkipTerminated — position just after the NUL terminator of a string starting at p
pub fn skip_terminated(b: &[u8], mut p: i64, enc: u8) -> i64 {
    let n = b.len() as i64;
    if enc == 1 || enc == 2 {
        while p + 1 < n {
            if p >= 0 && b[p as usize] == 0 && b[p as usize + 1] == 0 {
                return p + 2;
            }
            p += 2;
        }
    } else {
        while p < n {
            if p >= 0 && b[p as usize] == 0 {
                return p + 1;
            }
            p += 1;
        }
    }
    n
}

/// Pascal's Copy(B, P, Count) on a byte array: clamped, never fails.
pub fn copy(b: &[u8], p: i64, count: i64) -> Vec<u8> {
    if p < 0 || p >= b.len() as i64 || count <= 0 {
        return Vec::new();
    }
    let end = (p + count).min(b.len() as i64);
    b[p as usize..end as usize].to_vec()
}

// from: NormalizeGenre — '(17)', '17', '(17)Rock', 'Rock', 'RX', 'CR' -> readable genre
pub fn normalize_genre(g: &str) -> String {
    let mut result = g.to_string();
    let mut rest = g.to_string();
    while rest.starts_with('(') {
        let Some(p) = rest.find(')') else { break };
        let inner = &rest[1..p];
        if let Ok(n) = inner.parse::<i64>() {
            result = id3_genre_name(n).to_string();
        } else if inner == "RX" {
            result = "Remix".into();
        } else if inner == "CR" {
            result = "Cover".into();
        }
        rest = rest[p + 1..].to_string();
    }
    if rest != g {
        if !rest.is_empty() {
            result = rest; // refinement text wins over the number
        }
    } else if let Ok(n) = g.parse::<i64>() {
        result = id3_genre_name(n).to_string();
    }
    result
}

// from: V22ToV23
pub fn v22_to_v23(id: &str) -> String {
    const MAP: [(&str, &str); 26] = [
        ("TT2", "TIT2"), ("TP1", "TPE1"), ("TAL", "TALB"), ("TYE", "TYER"),
        ("TRK", "TRCK"), ("TPA", "TPOS"), ("TCO", "TCON"), ("COM", "COMM"),
        ("TP2", "TPE2"), ("TCM", "TCOM"), ("TBP", "TBPM"), ("PIC", "APIC"),
        ("TP3", "TPE3"), ("TXT", "TEXT"), ("TOA", "TOPE"), ("TP4", "TPE4"),
        ("TPB", "TPUB"), ("TRC", "TSRC"), ("TCR", "TCOP"), ("TEN", "TENC"),
        ("TT1", "TIT1"), ("TT3", "TIT3"), ("TKE", "TKEY"), ("ULT", "USLT"),
        ("WXX", "WXXX"), ("TXX", "TXXX"),
    ];
    MAP.iter().find(|m| m.0 == id).map(|m| m.1.to_string()).unwrap_or_else(|| id.to_string())
}

// from: ReadApicFrame — encoding, MIME<NUL>, picture type, description<NUL>, data
fn read_apic_frame(f: &[u8], info: &mut AudioInfo) {
    if f.len() < 4 {
        return;
    }
    let enc = f[0];
    let q = skip_terminated(f, 1, 0);
    let mut mime = latin1(f, 1, q - 2);
    if q >= f.len() as i64 {
        return;
    }
    let pic_type = f[q as usize];
    let p = skip_terminated(f, q + 1, enc);
    let desc = decode_id3_text(f, q + 1, p - q - 1, enc);
    if !mime.contains('/') {
        mime.clear(); // e.g. 'JPG' written by broken taggers
    }
    info.add_picture(pic_type, &mime, &desc, copy(f, p, f.len() as i64 - p));
}

// from: ReadPicFrame — v2.2 PIC: encoding, 3-char image format, picture type, description<NUL>, data
fn read_pic_frame(f: &[u8], info: &mut AudioInfo) {
    if f.len() < 6 {
        return;
    }
    let enc = f[0];
    let p = skip_terminated(f, 5, enc);
    let desc = decode_id3_text(f, 5, p - 5, enc);
    info.add_picture(f[4], "", &desc, copy(f, p, f.len() as i64 - p));
}

// from: ProcessFrame
fn process_frame(id: &str, f: &[u8], info: &mut AudioInfo, comment_is_default: &mut bool) {
    if f.is_empty() {
        return;
    }
    let n = f.len() as i64;
    if id != "TXXX" && id.starts_with('T') {
        let txt = decode_id3_text(f, 1, n - 1, f[0]);
        let t = txt.as_str();
        match id {
            "TIT2" => info.set_field(F::Title, t, true),
            "TPE1" => info.set_field(F::Artist, t, true),
            "TALB" => info.set_field(F::Album, t, true),
            "TDRC" => info.set_field(F::Year, t, true),
            "TYER" => info.set_field(F::Year, t, false),
            "TRCK" => info.set_field(F::Track, t, true),
            "TPOS" => info.set_field(F::Disc, t, true),
            "TCON" => info.set_field(F::Genre, &normalize_genre(t), true),
            "TPE2" => info.set_field(F::AlbumArtist, t, true),
            "TCOM" => info.set_field(F::Composer, t, true),
            "TBPM" => info.set_field(F::Bpm, t, true),
            "TPE3" => info.set_field(F::Conductor, t, true),
            "TEXT" => info.set_field(F::Lyricist, t, true),
            "TOPE" => info.set_field(F::OrigArtist, t, true),
            "TPE4" => info.set_field(F::Remixer, t, true),
            "TPUB" => info.set_field(F::Publisher, t, true),
            "TSRC" => info.set_field(F::Isrc, t, true),
            "TCOP" => info.set_field(F::Copyright, t, true),
            "TENC" => info.set_field(F::EncodedBy, t, true),
            "TIT1" => info.set_field(F::Grouping, t, true),
            "TIT3" => info.set_field(F::Subtitle, t, true),
            "TMOO" => info.set_field(F::Mood, t, true),
            "TKEY" => info.set_field(F::InitialKey, t, true),
            "TSOT" => info.set_field(F::SortTitle, t, true),
            "TSOP" => info.set_field(F::SortArtist, t, true),
            "TSO2" => info.set_field(F::SortAlbumArtist, t, true),
            "TSOA" => info.set_field(F::SortAlbum, t, true),
            "TSOC" => info.set_field(F::SortComposer, t, true),
            "TCMP" => info.set_field(F::Compilation, flag_value(t), true),
            _ => {}
        }
    } else if id == "PCST" {
        if f.iter().any(|&c| c != 0) {
            info.set_field(F::Podcast, "1", true);
        }
    } else if id == "TXXX" {
        // encoding, description<NUL>, value
        let enc = f[0];
        let p = skip_terminated(f, 1, enc);
        let desc = decode_id3_text(f, 1, p - 1, enc).to_uppercase();
        let txt = decode_id3_text(f, p, n - p, enc);
        match desc.as_str() {
            "CATALOGNUMBER" => info.set_field(F::CatalogNo, &txt, true),
            "MOOD" => info.set_field(F::Mood, &txt, false),
            "LABEL" => info.set_field(F::Publisher, &txt, false),
            "REPLAYGAIN_TRACK_GAIN" => info.set_field(F::RgTrackGain, &txt, true),
            "REPLAYGAIN_TRACK_PEAK" => info.set_field(F::RgTrackPeak, &txt, true),
            "REPLAYGAIN_ALBUM_GAIN" => info.set_field(F::RgAlbumGain, &txt, true),
            "REPLAYGAIN_ALBUM_PEAK" => info.set_field(F::RgAlbumPeak, &txt, true),
            _ => {}
        }
    } else if id == "USLT" {
        // encoding, language, description<NUL>, lyrics; prefer the one without description
        let enc = f[0];
        let p = skip_terminated(f, 4, enc);
        let desc = decode_id3_text(f, 4, p - 4, enc);
        let txt = decode_id3_text(f, p, n - p, enc);
        info.set_field(F::Lyrics, &txt, desc.is_empty());
    } else if id == "WXXX" {
        // encoding, description<NUL>, URL (always Latin-1)
        let enc = f[0];
        let p = skip_terminated(f, 1, enc);
        let desc = decode_id3_text(f, 1, p - 1, enc);
        info.set_field(F::Url, &clean_tag_text(&latin1(f, p, n - p)), desc.is_empty());
    } else if id == "COMM" {
        // encoding, 3-byte language, description<NUL>, text
        let enc = f[0];
        let p = skip_terminated(f, 4, enc);
        let desc = decode_id3_text(f, 4, p - 4, enc);
        let txt = decode_id3_text(f, p, n - p, enc);
        if desc.is_empty() {
            if !*comment_is_default {
                info.set_field(F::Comment, &txt, true);
                *comment_is_default = !txt.is_empty();
            }
        } else if !desc.chars().take(4).collect::<String>().eq_ignore_ascii_case("iTun") {
            info.set_field(F::Comment, &txt, false);
        }
    } else if id == "APIC" {
        read_apic_frame(f, info);
    }
}

fn valid_frame_id(id: &str) -> bool {
    !id.is_empty() && id.bytes().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit())
}

pub struct Id3v2 {
    pub version: u8,
    pub frames: Vec<Id3Frame>,
    /// total tag length incl. header/footer
    pub tag_size: u64,
}

/// Splits an ID3v2 tag at the start of the stream into frames.
/// `Ok(None)` if there is no (supported) tag; `tag_size` is then still returned in the error-free
/// tuple form by `id3v2_tag_size`.
// from: ParseID3v2
pub fn parse_id3v2<R: Read + Seek>(s: &mut R) -> std::io::Result<(Option<Id3v2>, u64)> {
    let h = read_at(s, 0, 10)?;
    if h.len() < 10 || !bytes_are(&h, 0, "ID3") {
        return Ok((None, 0));
    }
    let version = h[3];
    let flags = h[5];
    let size = syncsafe32(&h, 6);
    let mut tag_size = 10 + size as u64;
    if version >= 4 && flags & 0x10 != 0 {
        tag_size += 10; // footer
    }
    if !(2..=4).contains(&version) {
        return Ok((None, tag_size));
    }

    let mut body = read_at(s, 10, size as u64)?;
    if version < 4 && flags & 0x80 != 0 {
        body = remove_unsync(&body);
    }
    let blen = body.len() as i64;

    let mut p: i64 = 0;
    if flags & 0x40 != 0 {
        // extended header
        if version == 3 {
            p = 4 + be32(&body, 0) as i64;
        } else if version == 4 {
            p = syncsafe32(&body, 0) as i64;
        }
    }

    let hdr_len: i64 = if version == 2 { 6 } else { 10 };
    let mut frames = Vec::new();
    while p + hdr_len <= blen {
        if body[p as usize] == 0 {
            break; // padding
        }
        let (id, mut ffl, fsize): (String, u16, i64);
        if version == 2 {
            id = bytes_to_ascii(&body, p, 3);
            fsize = be24(&body, p + 3) as i64;
            ffl = 0;
        } else {
            id = bytes_to_ascii(&body, p, 4);
            ffl = be16(&body, p + 8) as u16;
            if version == 4 {
                let mut fs = syncsafe32(&body, p + 4) as i64;
                // Some writers (old iTunes) store plain sizes in v2.4.
                let plain = be32(&body, p + 4) as i64;
                if (plain & 0x8080_8080) != 0
                    || (p + hdr_len + fs + 4 <= blen
                        && body[(p + hdr_len + fs) as usize] != 0
                        && !valid_frame_id(&bytes_to_ascii(&body, p + hdr_len + fs, 4))
                        && valid_frame_id(&bytes_to_ascii(&body, p + hdr_len + plain, 4)))
                {
                    fs = plain;
                }
                fsize = fs;
            } else {
                fsize = be32(&body, p + 4) as i64;
            }
        }
        if !valid_frame_id(&id) {
            break;
        }
        if p + hdr_len + fsize > blen {
            break;
        }

        // A v2.4 tag-wide unsync flag means every frame is unsynchronised.
        if version == 4 && flags & 0x80 != 0 {
            ffl |= 0x0002;
        }

        let raw = body[(p + hdr_len) as usize..(p + hdr_len + fsize) as usize].to_vec();
        let mut data_p = p + hdr_len;
        let mut data_len = fsize;
        p = data_p + data_len;

        let mut usable = true;
        if version == 3 {
            if ffl & 0x00C0 != 0 {
                usable = false; // compressed / encrypted
            }
            if ffl & 0x0020 != 0 {
                data_p += 1; // grouping id
                data_len -= 1;
            }
        } else if version == 4 {
            if ffl & 0x000C != 0 {
                usable = false;
            }
            if ffl & 0x0040 != 0 {
                data_p += 1;
                data_len -= 1;
            }
            if ffl & 0x0001 != 0 {
                data_p += 4; // data length indicator
                data_len -= 4;
            }
        }
        let mut frame = Id3Frame { id, flags: ffl, raw, data: None };
        if usable && data_len > 0 {
            let mut d = copy(&body, data_p, data_len);
            if version == 4 && (ffl & 0x0002 != 0 || flags & 0x80 != 0) {
                d = remove_unsync(&d);
            }
            frame.data = Some(d);
        }
        frames.push(frame);
    }
    Ok((Some(Id3v2 { version, frames, tag_size }), tag_size))
}

/// Reads an ID3v2 tag at the start of the stream (if any). Returns the total tag length,
/// 0 if there is none.
// from: ReadID3v2
pub fn read_id3v2<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> std::io::Result<u64> {
    let (tag, tag_size) = parse_id3v2(s)?;
    let Some(tag) = tag else { return Ok(tag_size) };
    let ver = tag.version;
    info.add_tag_type(&format!("ID3v2.{ver}"));
    let mut comment_is_default = false;
    for fr in &tag.frames {
        let Some(d) = &fr.data else { continue };
        if ver == 2 && fr.id == "PIC" {
            read_pic_frame(d, info);
        } else if ver == 2 {
            process_frame(&v22_to_v23(&fr.id), d, info, &mut comment_is_default);
        } else {
            process_frame(&fr.id, d, info, &mut comment_is_default);
        }
    }
    // v2.3 keeps the day and month (DDMM) in TDAT; show the full date like v2.4 does.
    if ver == 3 {
        for fr in &tag.frames {
            let (true, Some(d)) = (fr.id == "TDAT", &fr.data) else { continue };
            let date = decode_id3_text(d, 1, d.len() as i64 - 1, d[0]);
            let year = info.field(F::Year).to_string();
            let num = |s: &str| s.parse::<i64>().map(|n| n >= 0).unwrap_or(false);
            if date.chars().count() == 4 && num(&date) && year.chars().count() == 4 && num(&year) {
                info.fields.insert(F::Year, format!("{}-{}-{}", year, &date[2..4], &date[0..2]));
            }
        }
    }
    Ok(tag_size)
}

// from: ID3v1Text
fn id3v1_text(b: &[u8], p: usize, len: usize) -> String {
    let e = b[p..p + len].iter().position(|&c| c == 0).unwrap_or(len);
    pascal_trim(&latin1(b, p as i64, e as i64)).to_string()
}

/// Fills only empty fields from an ID3v1 tag at the end of the stream. True if found.
// from: ReadID3v1
pub fn read_id3v1<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> std::io::Result<bool> {
    let size = stream_size(s)?;
    if size < 128 {
        return Ok(false);
    }
    let b = read_at(s, size - 128, 128)?;
    if b.len() < 128 || !bytes_are(&b, 0, "TAG") {
        return Ok(false);
    }
    info.add_tag_type("ID3v1");
    info.set_field(F::Title, &id3v1_text(&b, 3, 30), false);
    info.set_field(F::Artist, &id3v1_text(&b, 33, 30), false);
    info.set_field(F::Album, &id3v1_text(&b, 63, 30), false);
    info.set_field(F::Year, &id3v1_text(&b, 93, 4), false);
    if b[125] == 0 && b[126] != 0 {
        info.set_field(F::Comment, &id3v1_text(&b, 97, 28), false);
        info.set_field(F::Track, &b[126].to_string(), false);
    } else {
        info.set_field(F::Comment, &id3v1_text(&b, 97, 30), false);
    }
    info.set_field(F::Genre, id3_genre_name(b[127] as i64), false);
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use std::path::PathBuf;

    fn frame23(id: &str, body: &[u8]) -> Vec<u8> {
        let mut v = id.as_bytes().to_vec();
        v.extend((body.len() as u32).to_be_bytes());
        v.extend([0, 0]);
        v.extend(body);
        v
    }

    fn tag23(frames: &[Vec<u8>]) -> Vec<u8> {
        let body: Vec<u8> = frames.concat();
        let n = body.len() as u32;
        let mut v = b"ID3\x03\x00\x00".to_vec();
        v.extend([(n >> 21) as u8 & 0x7F, (n >> 14) as u8 & 0x7F, (n >> 7) as u8 & 0x7F, n as u8 & 0x7F]);
        v.extend(body);
        v
    }

    #[test]
    fn decodes_text_encodings() {
        assert_eq!(decode_id3_text(b"\xFF\xFEA\x00", 0, 4, 1), "A");
        assert_eq!(decode_id3_text(&[0xC6], 0, 1, 0), "Æ");
        assert_eq!(decode_id3_text("Ø".as_bytes(), 0, 2, 3), "Ø");
        assert_eq!(normalize_genre("(17)"), "Rock");
        assert_eq!(normalize_genre("(17)Indie"), "Indie");
        assert_eq!(normalize_genre("13"), "Pop");
    }

    #[test]
    fn reads_v23_frames_and_tdat() {
        let tag = tag23(&[
            frame23("TIT2", b"\x01\xFF\xFEA\x00b\x00"),
            frame23("TYER", b"\x002003"),
            frame23("TDAT", b"\x002412"),
            frame23("TXXX", b"\x00REPLAYGAIN_TRACK_GAIN\x00-6.52 dB"),
            frame23("COMM", b"\x00engiTunNORM\x00x"),
            frame23("COMM", b"\x00eng\x00hello"),
        ]);
        let mut info = AudioInfo::new(PathBuf::new(), false);
        let size = read_id3v2(&mut Cursor::new(tag.clone()), &mut info).unwrap();
        assert_eq!(size, tag.len() as u64);
        assert_eq!(info.field(F::Title), "Ab");
        assert_eq!(info.field(F::Year), "2003-12-24");
        assert_eq!(info.field(F::RgTrackGain), "-6.52 dB");
        assert_eq!(info.field(F::Comment), "hello");
        assert_eq!(info.tag_types_text(), "ID3v2.3");
    }

    #[test]
    fn reads_id3v1_track() {
        let mut b = vec![0u8; 128];
        b[..3].copy_from_slice(b"TAG");
        b[3..8].copy_from_slice(b"Title");
        b[126] = 7;
        b[127] = 17;
        let mut info = AudioInfo::new(PathBuf::new(), false);
        assert!(read_id3v1(&mut Cursor::new(b), &mut info).unwrap());
        assert_eq!(info.field(F::Title), "Title");
        assert_eq!(info.field(F::Track), "7");
        assert_eq!(info.field(F::Genre), "Rock");
    }
}
