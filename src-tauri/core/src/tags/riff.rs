//! WAV (RIFF) and AIFF/AIFC: audio properties from 'fmt '/'data' resp. 'COMM', tags from an
//! ID3v2 chunk ('id3 ' / 'ID3 '). RIFF LIST/INFO fills fields the ID3 tag does not set;
//! AIFF NAME/AUTH/ANNO/(c) text chunks are only read when there is no ID3 chunk
//! (port of wavreader.pas).

use super::id3;
use crate::model::{AudioInfo, TagField as F};
use crate::text::*;
use std::io::{Cursor, Read, Seek};

#[derive(Debug, Clone)]
pub struct Chunk {
    /// four characters as stored
    pub id: String,
    /// position of the chunk ID
    pub header_pos: i64,
    /// position of the chunk data
    pub data_pos: i64,
    /// data size as stored (without pad byte), clipped to the file
    pub size: i64,
}

pub struct ChunkFile {
    /// big-endian FORM container instead of RIFF
    pub is_aiff: bool,
    /// 'WAVE', 'AIFF' or 'AIFC'
    pub form_type: String,
    pub chunks: Vec<Chunk>,
}

/// Lists the top-level chunks. Errors if the file is not RIFF/WAVE or FORM/AIFF.
// from: ReadChunkFile
pub fn read_chunk_file<R: Read + Seek>(s: &mut R) -> Result<ChunkFile, String> {
    let io = |e: std::io::Error| e.to_string();
    let h = read_at(s, 0, 12).map_err(io)?;
    let is_aiff = if h.len() == 12 && bytes_are(&h, 0, "RIFF") && bytes_are(&h, 8, "WAVE") {
        false
    } else if h.len() == 12 && bytes_are(&h, 0, "FORM") && (bytes_are(&h, 8, "AIFF") || bytes_are(&h, 8, "AIFC")) {
        true
    } else if h.len() == 12 && bytes_are(&h, 0, "RF64") {
        return Err("RF64-filer (WAV over 4 GB) understøttes ikke".into());
    } else {
        return Err("Ikke en WAV- eller AIFF-fil".into());
    };
    let form_type = bytes_to_ascii(&h, 8, 4);
    let limit = stream_size(s).map_err(io)? as i64;
    let mut chunks = Vec::new();
    let mut p: i64 = 12;
    while p + 8 <= limit {
        let h = read_at(s, p as u64, 8).map_err(io)?;
        let size = if is_aiff { be32(&h, 4) } else { le32(&h, 4) } as i64;
        if !(32..=126).contains(&h[0]) {
            break; // garbage after the last chunk
        }
        chunks.push(Chunk {
            id: bytes_to_ascii(&h, 0, 4),
            header_pos: p,
            data_pos: p + 8,
            // a truncated last chunk (often 'data') is clipped to the file
            size: size.min(limit - p - 8),
        });
        p = p + 8 + size + (size & 1);
    }
    Ok(ChunkFile { is_aiff, form_type, chunks })
}

pub fn is_id3_chunk_id(id: &str) -> bool {
    id == "id3 " || id == "ID3 " || id == "ID32"
}

/// RIFF INFO id -> field; None for ids the program does not manage.
// from: InfoField
pub fn info_field(id: &str) -> Option<F> {
    Some(match id {
        "INAM" => F::Title,
        "IART" => F::Artist,
        "IPRD" => F::Album,
        "ICRD" => F::Year,
        "IPRT" | "ITRK" => F::Track,
        "IGNR" => F::Genre,
        "ICMT" => F::Comment,
        "ICOP" => F::Copyright,
        "IMUS" => F::Composer,
        "IENC" => F::EncodedBy,
        _ => return None,
    })
}

/// 1.2's UTF-8 check (lead byte + continuation bytes; no overlong/surrogate checks).
fn looks_utf8(b: &[u8]) -> bool {
    let cont = |i: usize| i < b.len() && b[i] & 0xC0 == 0x80;
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            0x00..=0x7F => i += 1,
            0xC2..=0xDF if cont(i + 1) => i += 2,
            0xE0..=0xEF if cont(i + 1) && cont(i + 2) => i += 3,
            0xF0..=0xF4 if cont(i + 1) && cont(i + 2) && cont(i + 3) => i += 4,
            _ => return false,
        }
    }
    true
}

/// RIFF text: UTF-8 if the bytes are valid UTF-8, else Windows-1252 (stored as Latin-1 here).
// from: InfoText
fn info_text(b: &[u8], p: i64, mut len: i64) -> String {
    while len > 0 && p + len - 1 < b.len() as i64 && b[(p + len - 1) as usize] == 0 {
        len -= 1;
    }
    let s = if p >= 0 && len > 0 && p + len <= b.len() as i64 && !looks_utf8(&b[p as usize..(p + len) as usize]) {
        latin1(b, p, len)
    } else {
        raw_utf8(b, p, len)
    };
    clean_tag_text(&s)
}

// from: ReadInfoList
fn read_info_list(b: &[u8], info: &mut AudioInfo) {
    let mut any = false;
    let mut p: i64 = 4; // after 'INFO'
    let n = b.len() as i64;
    while p + 8 <= n {
        let mut size = le32(b, p + 4) as i64;
        if p + 8 + size > n {
            size = n - p - 8;
        }
        if let Some(f) = info_field(&bytes_to_ascii(b, p, 4)) {
            let empty = info.field(f).is_empty();
            info.set_field(f, &info_text(b, p + 8, size), empty);
            any = true;
        }
        p = p + 8 + size + (size & 1);
    }
    if any {
        info.add_tag_type("RIFF INFO");
    }
}

/// 80-bit IEEE 754 extended (big-endian), as used for the AIFF sample rate.
// from: Extended80
fn extended80(b: &[u8], p: i64) -> f64 {
    let expo = (be16(b, p) & 0x7FFF) as i32;
    let mant = be64(b, p + 2);
    if expo == 0 && mant == 0 {
        return 0.0;
    }
    let r = mant as f64 * 2f64.powi(expo - 16383 - 63);
    if p >= 0 && (p as usize) < b.len() && b[p as usize] & 0x80 != 0 { -r } else { r }
}

// from: ReadWavAiff
pub fn read<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    info.supported = true;
    let cf = read_chunk_file(s)?;
    info.codec = if cf.is_aiff { cf.form_type.clone() } else { "WAV".into() };
    let mut data_size: i64 = -1;
    let mut byte_rate: i64 = 0;
    let mut have_id3 = false;
    // ID3 first so that the text chunks only fill gaps
    for c in &cf.chunks {
        if is_id3_chunk_id(&c.id) && !have_id3 {
            let tag = read_at(s, c.data_pos as u64, c.size.max(0) as u64).map_err(io)?;
            let tag_size = id3::read_id3v2(&mut Cursor::new(tag), info).map_err(io)?;
            have_id3 = tag_size > 0;
        }
    }
    for c in &cf.chunks {
        if !cf.is_aiff {
            if c.id == "fmt " && c.size >= 16 {
                let b = read_at(s, c.data_pos as u64, 16).map_err(io)?;
                let format_tag = le16(&b, 0);
                info.channels = le16(&b, 2);
                info.sample_rate = le32(&b, 4);
                byte_rate = le32(&b, 8) as i64;
                let bits = le16(&b, 14);
                info.bit_depth = bits;
                info.codec = match format_tag {
                    1 | 0xFFFE => format!("WAV PCM {bits}-bit"),
                    3 => format!("WAV float {bits}-bit"),
                    0x55 => "WAV (MP3)".into(),
                    t => format!("WAV (format ${t:04X})"),
                };
            } else if c.id == "data" {
                data_size = c.size;
            } else if c.id == "LIST" && c.size >= 4 && c.size < 16 * 1024 * 1024 {
                let b = read_at(s, c.data_pos as u64, c.size as u64).map_err(io)?;
                if bytes_are(&b, 0, "INFO") {
                    read_info_list(&b, info);
                }
            }
        } else if c.id == "COMM" && c.size >= 18 {
            let b = read_at(s, c.data_pos as u64, c.size.min(22) as u64).map_err(io)?;
            info.channels = be16(&b, 0);
            let frames = be32(&b, 2) as f64;
            let bits = be16(&b, 6);
            info.bit_depth = bits;
            info.sample_rate = pascal_round(extended80(&b, 8)).max(0) as u32;
            if info.sample_rate > 0 {
                info.duration = frames / info.sample_rate as f64;
                info.bitrate = pascal_round(info.sample_rate as f64 * info.channels as f64 * bits as f64 / 1000.0) as u32;
            }
            info.codec = if cf.form_type == "AIFC" && b.len() >= 22 {
                format!("AIFC {}", pascal_trim(&bytes_to_ascii(&b, 18, 4)))
            } else {
                format!("AIFF PCM {bits}-bit")
            };
        } else if !have_id3 && ["NAME", "AUTH", "ANNO", "(c) "].contains(&c.id.as_str()) && c.size < 65536 {
            // AIFF text chunks belong to other programs and are never written by us: once an
            // ID3 chunk exists it is the only source, so cleared fields do not come back.
            let b = read_at(s, c.data_pos as u64, c.size.max(0) as u64).map_err(io)?;
            if !info.tag_types.iter().any(|t| t.contains("AIFF-tekst")) {
                info.add_tag_type("AIFF-tekst");
            }
            let f = match c.id.as_str() {
                "NAME" => F::Title,
                "AUTH" => F::Artist,
                "ANNO" => F::Comment,
                _ => F::Copyright,
            };
            let empty = info.field(f).is_empty();
            info.set_field(f, &info_text(&b, 0, b.len() as i64), empty);
        }
    }
    if !cf.is_aiff && data_size >= 0 && byte_rate > 0 {
        info.duration = data_size as f64 / byte_rate as f64;
        info.bitrate = pascal_round(byte_rate as f64 * 8.0 / 1000.0) as u32;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn chunk_le(id: &[u8], body: &[u8]) -> Vec<u8> {
        let mut v = id.to_vec();
        v.extend((body.len() as u32).to_le_bytes());
        v.extend(body);
        if body.len() % 2 == 1 {
            v.push(0);
        }
        v
    }

    fn wav(chunks: &[Vec<u8>]) -> Vec<u8> {
        let body: Vec<u8> = chunks.concat();
        let mut v = b"RIFF".to_vec();
        v.extend((body.len() as u32 + 4).to_le_bytes());
        v.extend(b"WAVE");
        v.extend(body);
        v
    }

    fn info_list(items: &[(&[u8], &[u8])]) -> Vec<u8> {
        let mut b = b"INFO".to_vec();
        for (id, t) in items {
            b.extend(chunk_le(id, t));
        }
        chunk_le(b"LIST", &b)
    }

    fn read_bytes(b: Vec<u8>) -> AudioInfo {
        let mut info = AudioInfo::new(PathBuf::new(), false);
        read(&mut Cursor::new(b), &mut info).unwrap();
        info
    }

    #[test]
    fn info_inam_is_title() {
        let info = read_bytes(wav(&[info_list(&[(b"INAM", b"Hej\0")])]));
        assert_eq!(info.field(F::Title), "Hej");
        assert_eq!(info.tag_types_text(), "RIFF INFO");
    }

    #[test]
    fn id3_chunk_wins_over_info() {
        // ID3v2.3 tag with TIT2 "Fra ID3"
        let mut fr = b"TIT2".to_vec();
        fr.extend(8u32.to_be_bytes());
        fr.extend([0, 0, 0]);
        fr.extend(b"Fra ID3");
        let mut tag = b"ID3\x03\x00\x00\x00\x00\x00".to_vec();
        tag.push(fr.len() as u8);
        tag.extend(fr);
        let info = read_bytes(wav(&[info_list(&[(b"INAM", b"Fra INFO"), (b"IART", b"Kunstner")]), chunk_le(b"id3 ", &tag)]));
        assert_eq!(info.field(F::Title), "Fra ID3");
        assert_eq!(info.field(F::Artist), "Kunstner");
    }

    #[test]
    fn aiff_name_is_title() {
        let mut body = b"AIFF".to_vec();
        body.extend(b"NAME");
        body.extend(4u32.to_be_bytes());
        body.extend(b"Navn");
        let mut v = b"FORM".to_vec();
        v.extend((body.len() as u32).to_be_bytes());
        v.extend(body);
        let info = read_bytes(v);
        assert_eq!(info.field(F::Title), "Navn");
        assert_eq!(info.tag_types_text(), "AIFF-tekst");
    }
}
