//! Monkey's Audio (.ape), WavPack (.wv), Musepack (.mpc, SV7/SV8) and OptimFROG (.ofr):
//! audio properties from the stream header, tags from APEv2 with ID3v2 (at the start) and
//! ID3v1 as fallback (port of apereader.pas and the reading parts of apetag.pas).

use super::id3::{self, copy};
use crate::model::{flag_value, AudioInfo, TagField};
use crate::text::*;
use std::io::{Read, Seek};

const FLAG_HAS_HEADER: u32 = 1 << 31;
const FLAG_IS_HEADER: u32 = 1 << 29;
const ITEM_BINARY: u32 = 1 << 1;

const FIELD_KEYS: [&str; 37] = [
    "Title", "Artist", "Album", "Year", "Track", "Disc", "Genre", "Comment", "Album Artist",
    "Composer", "BPM", "Lyrics", "Conductor", "Lyricist", "Original Artist", "MixArtist", "Label",
    "CatalogNumber", "ISRC", "Copyright", "EncodedBy", "Weblink", "Grouping", "Subtitle", "Mood",
    "Key", "TitleSort", "ArtistSort", "AlbumArtistSort", "AlbumSort", "ComposerSort",
    "Compilation", "Podcast", "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK",
    "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK",
];

const PIC_NAMES: [&str; 21] = [
    "Other", "Png Icon", "Icon", "Front", "Back", "Leaflet", "Media", "Lead Artist", "Artist",
    "Conductor", "Band", "Composer", "Lyricist", "Recording Location", "During Recording",
    "During Performance", "Video Capture", "Fish", "Illustration", "Band Logotype",
    "Publisher Logotype",
];

// from: KeyField — key -> field, case-insensitive, incl. common alternative spellings
fn key_field(key: &str) -> Option<TagField> {
    let k = key.to_lowercase();
    if let Some(i) = FIELD_KEYS.iter().position(|f| f.to_lowercase() == k) {
        return Some(TagField::ALL[i]);
    }
    use TagField::*;
    Some(match k.as_str() {
        "albumartist" | "album_artist" => AlbumArtist,
        "date" => Year,
        "tracknumber" => Track,
        "discnumber" => Disc,
        "publisher" | "organization" => Publisher,
        "catalog" => CatalogNo,
        "unsyncedlyrics" | "unsynced lyrics" => Lyrics,
        "initialkey" | "initial key" => InitialKey,
        "encoded by" | "encoder" => EncodedBy,
        "url" | "related" => Url,
        "remixer" => Remixer,
        "originalartist" | "origartist" => OrigArtist,
        _ => return None,
    })
}

fn starts_with_ci(s: &str, prefix: &str) -> bool {
    s.len() >= prefix.len() && s.is_char_boundary(prefix.len()) && s[..prefix.len()].eq_ignore_ascii_case(prefix)
}

// from: PicKeyType — 'Cover Art (Front)' -> 3; None if the key is no picture
fn pic_key_type(key: &str) -> Option<u8> {
    if !starts_with_ci(key, "Cover Art (") {
        return None;
    }
    Some(PIC_NAMES.iter().position(|n| key.eq_ignore_ascii_case(&format!("Cover Art ({n})"))).unwrap_or(0) as u8)
}

#[derive(Debug, Default)]
pub struct ApeLocation {
    pub found: bool,
    /// first byte of the tag (header, or first item if there is no header)
    pub start: i64,
    /// whole tag incl. header and footer
    pub size: i64,
    pub version: u32,
    pub has_id3v1: bool,
    /// where the tag starts, or where it would go
    pub audio_end: i64,
}

// from: FindApeTag
pub fn find_ape_tag<R: Read + Seek>(s: &mut R) -> std::io::Result<ApeLocation> {
    let mut loc = ApeLocation::default();
    let size = stream_size(s)? as i64;
    let mut footer_pos = size - 32;
    if size >= 128 {
        let b = read_at(s, (size - 128) as u64, 3)?;
        if bytes_are(&b, 0, "TAG") {
            loc.has_id3v1 = true;
            footer_pos -= 128;
        }
    }
    loc.audio_end = footer_pos + 32;
    if footer_pos < 0 {
        return Ok(loc);
    }
    let b = read_at(s, footer_pos as u64, 32)?;
    if b.len() < 32 || !bytes_are(&b, 0, "APETAGEX") {
        return Ok(loc);
    }
    let flags = le32(&b, 20);
    if flags & FLAG_IS_HEADER != 0 {
        return Ok(loc);
    }
    let mut tag_size = le32(&b, 12) as i64; // items + footer
    if flags & FLAG_HAS_HEADER != 0 {
        tag_size += 32;
    }
    if tag_size < 32 || tag_size > footer_pos + 32 {
        return Ok(loc);
    }
    loc.found = true;
    loc.version = le32(&b, 8);
    loc.size = tag_size;
    loc.start = footer_pos + 32 - tag_size;
    loc.audio_end = loc.start;
    Ok(loc)
}

struct ApeItem {
    key: String,
    flags: u32,
    value: Vec<u8>,
}

// from: ParseItems
fn parse_items<R: Read + Seek>(s: &mut R, loc: &ApeLocation) -> std::io::Result<Vec<ApeItem>> {
    let b = read_at(s, loc.start as u64, loc.size as u64)?;
    let mut items = Vec::new();
    let mut p: i64 = if bytes_are(&b, 0, "APETAGEX") { 32 } else { 0 }; // header
    let stop = b.len() as i64 - 32;
    while p + 8 < stop {
        let len = le32(&b, p) as i64;
        let mut key_end = p + 8;
        while key_end < stop && b[key_end as usize] != 0 {
            key_end += 1;
        }
        if key_end >= stop || key_end + 1 + len > stop {
            break;
        }
        items.push(ApeItem {
            flags: le32(&b, p + 4),
            key: bytes_to_ascii(&b, p + 8, key_end - p - 8),
            value: copy(&b, key_end + 1, len),
        });
        p = key_end + 1 + len;
    }
    Ok(items)
}

/// Reads the APE tag (if any). True when one was found.
// from: ReadApeTag
pub fn read_ape_tag<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> std::io::Result<bool> {
    let loc = find_ape_tag(s)?;
    if !loc.found {
        return Ok(false);
    }
    info.add_tag_type(if loc.version >= 2000 { "APEv2" } else { "APEv1" });
    for it in parse_items(s, &loc)? {
        let t = pic_key_type(&it.key);
        if let (Some(t), true) = (t, it.flags & 6 == ITEM_BINARY) {
            let Some(z) = it.value.iter().position(|&c| c == 0) else { continue };
            let mut file_name = raw_utf8(&it.value, 0, z as i64);
            // the stored name is a file name; 'cover.jpg' etc. carry no description
            if starts_with_ci(&file_name, "cover.") {
                file_name.clear();
            }
            info.has_cover = true;
            info.add_picture(t, "", &file_name, it.value[z + 1..].to_vec());
        } else if it.flags & 6 == 0 {
            let Some(f) = key_field(&it.key) else { continue };
            let v = raw_utf8(&it.value, 0, it.value.len() as i64).replace('\0', "; ");
            if matches!(f, TagField::Compilation | TagField::Podcast) {
                info.set_field(f, flag_value(&v), true);
            } else if f == TagField::Lyrics {
                let empty = info.field(f).is_empty();
                info.set_field(f, &v, empty);
            } else {
                info.append_field(f, &clean_tag_text(&v));
            }
        }
    }
    Ok(true)
}

fn at(b: &[u8], p: i64) -> u8 {
    if p >= 0 && (p as usize) < b.len() { b[p as usize] } else { 0 }
}

// from: SetLength_
fn set_length(info: &mut AudioInfo, samples: f64, audio_bytes: i64) {
    if info.sample_rate == 0 {
        return;
    }
    info.duration = samples / info.sample_rate as f64;
    if info.duration > 0.0 {
        info.bitrate = kbps(audio_bytes, info.duration);
    }
}

// from: ReadMonkeys
fn read_monkeys(b: &[u8], info: &mut AudioInfo, audio_bytes: i64) {
    let ver = le16(b, 4) as i64;
    let (blocks_per_frame, final_blocks, frames, bits): (i64, i64, i64, i64);
    if ver >= 3980 {
        let desc = le32(b, 8) as i64;
        if (b.len() as i64) < desc + 24 {
            return;
        }
        blocks_per_frame = le32(b, desc + 4) as i64;
        final_blocks = le32(b, desc + 8) as i64;
        frames = le32(b, desc + 12) as i64;
        bits = le16(b, desc + 16) as i64;
        info.channels = le16(b, desc + 18);
        info.sample_rate = le32(b, desc + 20);
    } else {
        let compression = le16(b, 6);
        let flags = le16(b, 8);
        info.channels = le16(b, 10);
        info.sample_rate = le32(b, 12);
        frames = le32(b, 24) as i64;
        final_blocks = le32(b, 28) as i64;
        blocks_per_frame = if ver >= 3950 {
            73728 * 4
        } else if ver >= 3900 || (ver >= 3800 && compression == 4000) {
            73728
        } else {
            9216
        };
        bits = if flags & 1 != 0 { 8 } else if flags & 8 != 0 { 24 } else { 16 };
    }
    info.codec = format!("Monkey's Audio {}.{:02} ({}-bit)", ver / 1000, (ver % 1000) / 10, bits);
    info.bit_depth = bits as u32;
    if frames > 0 {
        set_length(info, ((frames - 1) * blocks_per_frame + final_blocks) as f64, audio_bytes);
    }
}

// from: ReadWavPack
fn read_wavpack(b: &[u8], info: &mut AudioInfo, audio_bytes: i64) {
    const RATES: [u32; 15] = [6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000, 192000];
    let flags = le32(b, 24);
    let idx = ((flags >> 23) & 0xF) as usize;
    info.sample_rate = if idx < 15 { RATES[idx] } else { 0 };
    info.channels = if flags & 4 != 0 { 1 } else { 2 };
    let bits = ((flags & 3) + 1) * 8;
    info.codec = format!("WavPack {bits}-bit");
    info.bit_depth = bits;
    if flags & 8 != 0 {
        info.codec.push_str(" (hybrid)");
    }
    let total = le32(b, 12);
    if total != 0xFFFF_FFFF {
        let samples = total as i64 + ((at(b, 11) as i64) << 32);
        set_length(info, samples as f64, audio_bytes);
    }
}

// from: ReadVarint
fn read_varint(b: &[u8], p: &mut i64) -> u64 {
    let mut r: u64 = 0;
    loop {
        if *p >= b.len() as i64 {
            return r;
        }
        let c = b[*p as usize];
        *p += 1;
        r = (r << 7) | (c & 0x7F) as u64;
        if c & 0x80 == 0 {
            return r;
        }
    }
}

// from: ReadMusepack
fn read_musepack(b: &[u8], info: &mut AudioInfo, audio_bytes: i64) {
    const RATES: [u32; 4] = [44100, 48000, 37800, 32000];
    if bytes_are(b, 0, "MPCK") {
        let mut p: i64 = 4;
        while p + 2 < b.len() as i64 {
            let start = p;
            p += 2;
            let size = read_varint(b, &mut p);
            if bytes_are(b, start, "SH") {
                p += 4; // CRC
                let ver = at(b, p);
                p += 1;
                let samples = read_varint(b, &mut p);
                let silence = read_varint(b, &mut p);
                if p + 1 >= b.len() as i64 {
                    return;
                }
                info.sample_rate = RATES.get((b[p as usize] >> 5) as usize).copied().unwrap_or(0);
                info.channels = (b[p as usize + 1] >> 4) as u32 + 1;
                info.codec = format!("Musepack SV{ver}");
                set_length(info, samples.wrapping_sub(silence) as f64, audio_bytes);
                return;
            }
            if size < 3 {
                return;
            }
            p = start + size as i64;
        }
    } else if bytes_are(b, 0, "MP+") {
        let ver = at(b, 3) & 0x0F;
        info.codec = format!("Musepack SV{ver}");
        info.channels = 2;
        if ver >= 7 {
            info.sample_rate = RATES[((le32(b, 8) >> 16) & 3) as usize];
            set_length(info, le32(b, 4) as f64 * 1152.0, audio_bytes);
        }
    } else {
        info.codec = "Musepack".into();
    }
}

// from: ReadOptimFrog
fn read_optimfrog(b: &[u8], info: &mut AudioInfo, audio_bytes: i64) {
    const BITS: [u32; 7] = [8, 8, 16, 16, 24, 24, 32];
    // 'OFR ', header size, total samples (48-bit), sample type, channel config, rate
    let samples = le32(b, 8) as i64 + ((le16(b, 12) as i64) << 32);
    let sample_type = at(b, 14) as usize;
    info.channels = at(b, 15) as u32 + 1;
    info.sample_rate = le32(b, 16);
    if sample_type < BITS.len() {
        info.codec = format!("OptimFROG {}-bit", BITS[sample_type]);
        info.bit_depth = BITS[sample_type];
    } else {
        info.codec = "OptimFROG".into();
    }
    if info.channels > 0 {
        set_length(info, samples as f64 / info.channels as f64, audio_bytes);
    }
}

// from: ReadApeFamily
pub fn read<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    info.supported = true;
    let has_ape = read_ape_tag(s, info).map_err(io)?;
    // ID3v2 at the start (seen on some .mpc/.ape files) and ID3v1 are only used when there
    // is no APE tag: the APE writer leaves the ID3v2 tag alone, so it must not shadow it.
    let tag_size = if has_ape {
        id3::parse_id3v2(s).map_err(io)?.1
    } else {
        id3::read_id3v2(s, info).map_err(io)?
    };
    let loc = find_ape_tag(s).map_err(io)?;
    let audio_end = loc.audio_end;
    if !has_ape {
        id3::read_id3v1(s, info).map_err(io)?;
    }
    let b = read_at(s, tag_size, 4096).map_err(io)?;
    if b.len() < 32 {
        return Err("Filen er for kort".into());
    }
    let ext = info.path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
    let audio_bytes = audio_end - tag_size as i64;
    if bytes_are(&b, 0, "MAC ") {
        read_monkeys(&b, info, audio_bytes);
    } else if bytes_are(&b, 0, "wvpk") {
        read_wavpack(&b, info, audio_bytes);
    } else if bytes_are(&b, 0, "MPCK") || bytes_are(&b, 0, "MP+") {
        read_musepack(&b, info, audio_bytes);
    } else if bytes_are(&b, 0, "OFR ") {
        read_optimfrog(&b, info, audio_bytes);
    } else if ext == "mpc" {
        info.codec = "Musepack".into();
    } else {
        return Err("Ukendt lydformat".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    use std::path::PathBuf;

    fn ape_tag(items: &[(&str, u32, &[u8])], header: bool) -> Vec<u8> {
        let mut body = Vec::new();
        for (k, flags, v) in items {
            body.extend((v.len() as u32).to_le_bytes());
            body.extend(flags.to_le_bytes());
            body.extend(k.as_bytes());
            body.push(0);
            body.extend(*v);
        }
        let hf = |is_header: bool| {
            let mut h = b"APETAGEX".to_vec();
            h.extend(2000u32.to_le_bytes());
            h.extend((body.len() as u32 + 32).to_le_bytes());
            h.extend((items.len() as u32).to_le_bytes());
            let mut f = if header { FLAG_HAS_HEADER } else { 0 };
            if is_header {
                f |= FLAG_IS_HEADER;
            }
            h.extend(f.to_le_bytes());
            h.extend([0u8; 8]);
            h
        };
        let mut out = Vec::new();
        if header {
            out.extend(hf(true));
        }
        out.extend(&body);
        out.extend(hf(false));
        out
    }

    fn read_tag(file: Vec<u8>) -> AudioInfo {
        let mut info = AudioInfo::new(PathBuf::from("x.ape"), true);
        assert!(read_ape_tag(&mut Cursor::new(file), &mut info).unwrap());
        info
    }

    #[test]
    fn footer_found_with_and_without_id3v1() {
        let mut file = vec![0u8; 100];
        file.extend(ape_tag(&[("Title", 0, b"Hej")], true));
        assert_eq!(read_tag(file.clone()).field(TagField::Title), "Hej");
        let mut v1 = vec![0u8; 128];
        v1[..3].copy_from_slice(b"TAG");
        file.extend(v1);
        let info = read_tag(file);
        assert_eq!(info.field(TagField::Title), "Hej");
        assert_eq!(info.tag_types_text(), "APEv2");
    }

    #[test]
    fn cover_art_front_is_a_type_3_picture() {
        let mut v = b"cover.jpg\0".to_vec();
        v.extend([0xFF, 0xD8, 0xFF, 0xE0]);
        let mut file = vec![0u8; 10];
        file.extend(ape_tag(&[("Cover Art (Front)", ITEM_BINARY, &v)], false));
        let info = read_tag(file);
        assert_eq!(info.pictures.len(), 1);
        assert_eq!(info.pictures[0].pic_type, 3);
        assert_eq!(info.pictures[0].mime, "image/jpeg");
        assert_eq!(info.pictures[0].description, "");
    }
}
