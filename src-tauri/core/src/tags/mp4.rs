//! MP4/M4A/M4B: iTunes-style metadata (moov/udta/meta/ilst) and audio properties
//! (port of mp4reader.pas).

use super::id3::copy;
use crate::model::{AudioInfo, TagField as F, PIC_TYPE_FRONT_COVER};
use crate::text::*;
use std::io::{Read, Seek};

const MAX_MOOV_SIZE: i64 = 64 * 1024 * 1024;

fn at(b: &[u8], p: i64) -> u8 {
    if p >= 0 && (p as usize) < b.len() { b[p as usize] } else { 0 }
}

/// Atom names use '@' for the copyright sign (byte 0xA9), e.g. '@nam'.
// from: AtomIs
fn atom_is(b: &[u8], p: i64, name: &str) -> bool {
    if p < 0 || p + 4 > b.len() as i64 {
        return false;
    }
    name.bytes().enumerate().all(|(i, c)| b[p as usize + i] == if c == b'@' { 0xA9 } else { c })
}

/// One atom header at p inside [p, limit): (size, header length), None if malformed.
// from: AtomHeader
fn atom_header(b: &[u8], p: i64, limit: i64) -> Option<(i64, i64)> {
    if p + 8 > limit {
        return None;
    }
    let mut size = be32(b, p) as i64;
    let mut hdr = 8;
    if size == 1 {
        if p + 16 > limit {
            return None;
        }
        size = be64(b, p + 8) as i64;
        hdr = 16;
    } else if size == 0 {
        size = limit - p;
    }
    (size >= hdr && p + size <= limit).then_some((size, hdr))
}

/// Payload of the first 'data' child of an ilst item: (pos, len, type).
// from: FindData
fn find_data(b: &[u8], mut p: i64, limit: i64) -> Option<(i64, i64, u32)> {
    while let Some((size, hdr)) = atom_header(b, p, limit) {
        if atom_is(b, p + 4, "data") && size >= hdr + 8 {
            // skip type indicator + locale
            return Some((p + hdr + 8, size - hdr - 8, be32(b, p + hdr) & 0xFF_FFFF));
        }
        p += size;
    }
    None
}

/// 'covr' may hold several 'data' children, one per image (13 = JPEG, 14 = PNG).
// from: ReadCovers
fn read_covers(b: &[u8], mut p: i64, limit: i64, info: &mut AudioInfo) {
    while let Some((size, hdr)) = atom_header(b, p, limit) {
        if atom_is(b, p + 4, "data") && size > hdr + 8 {
            let mime = match be32(b, p + hdr) & 0xFF_FFFF {
                13 => "image/jpeg",
                14 => "image/png",
                _ => "",
            };
            info.add_picture(PIC_TYPE_FRONT_COVER, mime, "", copy(b, p + hdr + 8, size - hdr - 8));
        }
        p += size;
    }
}

/// iTunes freeform item '----': children 'mean' (com.apple.iTunes), 'name' and 'data'.
// from: ReadFreeform
fn read_freeform(b: &[u8], mut p: i64, limit: i64, info: &mut AudioInfo) {
    let mut name = String::new();
    let mut value = String::new();
    while let Some((size, hdr)) = atom_header(b, p, limit) {
        if atom_is(b, p + 4, "name") && size > hdr + 4 {
            name = raw_utf8(b, p + hdr + 4, size - hdr - 4).to_ascii_uppercase();
        } else if atom_is(b, p + 4, "data") && value.is_empty() && size > hdr + 8 {
            value = clean_tag_text(&raw_utf8(b, p + hdr + 8, size - hdr - 8));
        }
        p += size;
    }
    if value.is_empty() {
        return;
    }
    let f = match name.as_str() {
        "CONDUCTOR" => F::Conductor,
        "LYRICIST" => F::Lyricist,
        "ORIGINALARTIST" | "ORIGINAL ARTIST" => F::OrigArtist,
        "REMIXER" => F::Remixer,
        "LABEL" | "PUBLISHER" => F::Publisher,
        "CATALOGNUMBER" => F::CatalogNo,
        "ISRC" => F::Isrc,
        "ENCODEDBY" => F::EncodedBy,
        "URL" => F::Url,
        "SUBTITLE" => F::Subtitle,
        "MOOD" => F::Mood,
        "INITIALKEY" | "KEY" => F::InitialKey,
        "REPLAYGAIN_TRACK_GAIN" => F::RgTrackGain,
        "REPLAYGAIN_TRACK_PEAK" => F::RgTrackPeak,
        "REPLAYGAIN_ALBUM_GAIN" => F::RgAlbumGain,
        "REPLAYGAIN_ALBUM_PEAK" => F::RgAlbumPeak,
        _ => return,
    };
    info.set_field(f, &value, true);
}

// from: ParseIlstItem
fn parse_ilst_item(b: &[u8], p: i64, limit: i64, item_p: i64, info: &mut AudioInfo) {
    if atom_is(b, item_p, "covr") {
        return read_covers(b, p, limit, info);
    }
    if atom_is(b, item_p, "----") {
        return read_freeform(b, p, limit, info);
    }
    let Some((dp, dl, _dt)) = find_data(b, p, limit) else { return };
    let num_pair = || {
        let (n, t) = (be16(b, dp + 2), be16(b, dp + 4));
        match (n, t) {
            (0, _) => String::new(),
            (n, 0) => n.to_string(),
            (n, t) => format!("{n}/{t}"),
        }
    };
    let is = |name: &str| atom_is(b, item_p, name);
    if is("trkn") {
        info.set_field(F::Track, &num_pair(), true);
    } else if is("disk") {
        info.set_field(F::Disc, &num_pair(), true);
    } else if is("gnre") {
        info.set_field(F::Genre, id3_genre_name(be16(b, dp) as i64 - 1), false);
    } else if is("cpil") || is("pcst") {
        if dl > 0 && at(b, dp) != 0 {
            info.set_field(if is("cpil") { F::Compilation } else { F::Podcast }, "1", true);
        }
    } else if is("tmpo") {
        if be16(b, dp) > 0 {
            info.set_field(F::Bpm, &be16(b, dp).to_string(), true);
        }
    } else {
        let txt = clean_tag_text(&raw_utf8(b, dp, dl));
        let f = [
            ("@nam", F::Title), ("@ART", F::Artist), ("@alb", F::Album), ("@day", F::Year),
            ("@gen", F::Genre), ("@cmt", F::Comment), ("aART", F::AlbumArtist), ("@wrt", F::Composer),
            ("@lyr", F::Lyrics), ("cprt", F::Copyright), ("@grp", F::Grouping), ("sonm", F::SortTitle),
            ("soar", F::SortArtist), ("soaa", F::SortAlbumArtist), ("soal", F::SortAlbum), ("soco", F::SortComposer),
        ]
        .into_iter()
        .find(|(n, _)| is(n));
        if let Some((_, f)) = f {
            info.set_field(f, &txt, true);
        }
    }
}

// from: ParseAtoms
fn parse_atoms(b: &[u8], mut p: i64, limit: i64, in_ilst: bool, info: &mut AudioInfo) {
    while let Some((size, hdr)) = atom_header(b, p, limit) {
        let body = p + hdr;
        let is = |name: &str| atom_is(b, p + 4, name);
        if in_ilst {
            parse_ilst_item(b, body, p + size, p + 4, info);
        } else if is("trak") || is("mdia") || is("minf") || is("stbl") || is("udta") {
            parse_atoms(b, body, p + size, false, info);
        } else if is("meta") {
            // Normally a full box (4 bytes version/flags); QuickTime style has no such prefix.
            if atom_is(b, body + 4, "hdlr") {
                parse_atoms(b, body, p + size, false, info);
            } else {
                parse_atoms(b, body + 4, p + size, false, info);
            }
        } else if is("ilst") {
            info.add_tag_type("MP4");
            parse_atoms(b, body, p + size, true, info);
        } else if is("mvhd") {
            let (time_scale, dur) = if at(b, body) == 1 {
                (be32(b, body + 20), be64(b, body + 24))
            } else {
                (be32(b, body + 12), be32(b, body + 16) as u64)
            };
            if time_scale > 0 {
                info.duration = dur as f64 / time_scale as f64;
            }
        } else if is("stsd") && info.codec.is_empty() {
            // version/flags (4), entry count (4), first sample entry
            let e = body + 8;
            for (n, c) in [("mp4a", "AAC"), ("alac", "ALAC"), ("ac-3", "AC-3"), ("Opus", "Opus"), ("fLaC", "FLAC")] {
                if atom_is(b, e + 4, n) {
                    info.codec = c.into();
                    break;
                }
            }
            if !info.codec.is_empty() {
                // audio sample entry: 8 header + 8 reserved/dataref + 8 version/vendor
                info.channels = be16(b, e + 24);
                info.sample_rate = be32(b, e + 32) >> 16;
            }
        }
        p += size;
    }
}

// from: ReadMp4
pub fn read<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    info.supported = true;
    let fsize = stream_size(s).map_err(io)? as i64;
    let mut moov: Option<Vec<u8>> = None;
    let mut mdat_size: i64 = 0;
    let mut pos: i64 = 0;
    while pos + 8 <= fsize {
        let h = read_at(s, pos as u64, 16).map_err(io)?;
        if h.len() < 8 {
            break;
        }
        let mut size = be32(&h, 0) as i64;
        let mut hdr = 8;
        if size == 1 {
            size = be64(&h, 8) as i64;
            hdr = 16;
        } else if size == 0 {
            size = fsize - pos;
        }
        if size < hdr {
            break;
        }
        if atom_is(&h, 4, "moov") {
            if size - hdr > MAX_MOOV_SIZE {
                return Err("moov-atom er for stor".into());
            }
            let m = read_at(s, (pos + hdr) as u64, (size - hdr) as u64).map_err(io)?;
            moov = (!m.is_empty()).then_some(m);
        } else if atom_is(&h, 4, "mdat") {
            mdat_size += size - hdr;
        }
        pos += size;
    }
    let Some(moov) = moov else {
        return Err("Ingen moov-atom - ikke en gyldig MP4-fil".into());
    };
    parse_atoms(&moov, 0, moov.len() as i64, false, info);
    if info.duration > 0.0 {
        if mdat_size == 0 {
            mdat_size = fsize;
        }
        info.bitrate = pascal_round(mdat_size as f64 * 8.0 / info.duration / 1000.0) as u32;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn atom(name: &[u8], body: &[u8]) -> Vec<u8> {
        let mut v = ((body.len() + 8) as u32).to_be_bytes().to_vec();
        v.extend(name);
        v.extend(body);
        v
    }

    fn data(ty: u32, payload: &[u8]) -> Vec<u8> {
        let mut b = ty.to_be_bytes().to_vec();
        b.extend([0, 0, 0, 0]);
        b.extend(payload);
        atom(b"data", &b)
    }

    fn ilst(items: &[Vec<u8>]) -> AudioInfo {
        let il = atom(b"ilst", &items.concat());
        let mut info = AudioInfo::new(PathBuf::new(), true);
        parse_atoms(&il, 0, il.len() as i64, false, &mut info);
        info
    }

    #[test]
    fn track_pair() {
        let info = ilst(&[atom(b"trkn", &data(0, &[0, 0, 0, 2, 0, 12, 0, 0]))]);
        assert_eq!(info.field(F::Track), "2/12");
        assert_eq!(info.tag_types_text(), "MP4");
    }

    #[test]
    fn freeform_isrc() {
        let mut body = atom(b"mean", b"\0\0\0\0com.apple.iTunes");
        body.extend(atom(b"name", b"\0\0\0\0ISRC"));
        body.extend(data(1, b"DKABC8300001"));
        let info = ilst(&[atom(b"----", &body)]);
        assert_eq!(info.field(F::Isrc), "DKABC8300001");
    }

    #[test]
    fn covr_png_flag() {
        let info = ilst(&[atom(b"covr", &data(14, &[1, 2, 3, 4]))]);
        assert_eq!(info.pictures.len(), 1);
        assert_eq!(info.pictures[0].mime, "image/png");
    }
}
