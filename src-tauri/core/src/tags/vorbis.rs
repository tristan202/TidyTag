//! FLAC (metadata blocks) and Ogg Vorbis/Opus/FLAC, which share Vorbis comments
//! (port of vorbisreader.pas).

use super::id3::{self, copy};
use crate::model::{flag_value, r128_to_rg, AudioInfo, TagField as F};
use crate::text::*;
use base64::Engine;
use std::io::{Read, Seek};

/// A stream with a position, like Pascal's TStream (ReadStreamBytes / Seek soCurrent).
struct Cur<'a, R> {
    s: &'a mut R,
    pos: i64,
    size: i64,
}

impl<'a, R: Read + Seek> Cur<'a, R> {
    fn new(s: &'a mut R) -> std::io::Result<Self> {
        let size = stream_size(s)? as i64;
        Ok(Cur { s, pos: 0, size })
    }
    fn read(&mut self, n: i64) -> std::io::Result<Vec<u8>> {
        if n <= 0 || self.pos < 0 {
            return Ok(Vec::new());
        }
        let b = read_at(self.s, self.pos as u64, n as u64)?;
        self.pos += b.len() as i64;
        Ok(b)
    }
}

fn at(b: &[u8], p: i64) -> u8 {
    if p >= 0 && (p as usize) < b.len() { b[p as usize] } else { 0 }
}

/// FLAC PICTURE block body (also used base64-encoded in Vorbis comments).
// from: ParseFlacPicture
pub fn parse_flac_picture(b: &[u8], info: &mut AudioInfo) {
    let pic_type = be32(b, 0);
    let mime_len = be32(b, 4) as i64;
    let mut p: i64 = 8;
    let mime = raw_utf8(b, p, mime_len);
    p += mime_len;
    let desc_len = be32(b, p) as i64;
    p += 4;
    let desc = raw_utf8(b, p, desc_len);
    p += desc_len + 16; // width, height, depth, colours
    let data_len = be32(b, p) as i64;
    p += 4;
    if p + data_len > b.len() as i64 {
        return;
    }
    info.add_picture((pic_type & 0xFF) as u8, &mime, &desc, copy(b, p, data_len));
}

// from: ParseBase64Picture
fn parse_base64_picture(value: &str, info: &mut AudioInfo) {
    if !info.want_pictures {
        info.has_cover = true;
        return;
    }
    // like FPC's non-strict DecodeStringBase64: characters outside the alphabet are skipped
    let clean: String = value.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '+' || *c == '/').collect();
    let engine = base64::engine::GeneralPurpose::new(
        &base64::alphabet::STANDARD,
        base64::engine::GeneralPurposeConfig::new()
            .with_decode_padding_mode(base64::engine::DecodePaddingMode::Indifferent)
            .with_decode_allow_trailing_bits(true),
    );
    let b = engine.decode(clean.as_bytes()).unwrap_or_default();
    parse_flac_picture(&b, info);
}

/// Parses a Vorbis comment block (little-endian lengths) starting at p.
// from: ParseVorbisComment
fn parse_vorbis_comment(b: &[u8], mut p: i64, info: &mut AudioInfo) {
    info.add_tag_type("Vorbis");
    let mut track_total = String::new();
    let mut disc_total = String::new();
    let vendor_len = le32(b, p) as i64;
    p += 4 + vendor_len;
    let count = le32(b, p);
    p += 4;
    let n = b.len() as i64;
    for _ in 0..count {
        if p + 4 > n {
            break;
        }
        let len = le32(b, p) as i64;
        p += 4;
        if p + len > n {
            break;
        }
        let entry = raw_utf8(b, p, len);
        p += len;
        let Some(eq) = entry.find('=') else { continue };
        if eq < 1 {
            continue;
        }
        let key = entry[..eq].to_ascii_uppercase();
        let v = &entry[eq + 1..];
        match key.as_str() {
            "TITLE" => info.append_field(F::Title, v),
            "ARTIST" => info.append_field(F::Artist, v),
            "ALBUM" => info.append_field(F::Album, v),
            "DATE" => info.set_field(F::Year, v, true),
            "YEAR" => info.set_field(F::Year, v, false),
            "TRACKNUMBER" => info.set_field(F::Track, v, true),
            "TRACKTOTAL" | "TOTALTRACKS" => track_total = pascal_trim(v).to_string(),
            "DISCNUMBER" => info.set_field(F::Disc, v, true),
            "DISCTOTAL" | "TOTALDISCS" => disc_total = pascal_trim(v).to_string(),
            "GENRE" => info.append_field(F::Genre, v),
            "COMMENT" => info.set_field(F::Comment, v, true),
            "DESCRIPTION" => info.set_field(F::Comment, v, false),
            "ALBUMARTIST" | "ALBUM ARTIST" | "ALBUM_ARTIST" => info.append_field(F::AlbumArtist, v),
            "COMPOSER" => info.append_field(F::Composer, v),
            "BPM" => info.set_field(F::Bpm, v, true),
            "LYRICS" => info.set_field(F::Lyrics, v, true),
            "UNSYNCEDLYRICS" => info.set_field(F::Lyrics, v, false),
            "CONDUCTOR" => info.append_field(F::Conductor, v),
            "LYRICIST" => info.append_field(F::Lyricist, v),
            "ORIGINALARTIST" | "ORIGARTIST" => info.append_field(F::OrigArtist, v),
            "REMIXER" => info.append_field(F::Remixer, v),
            "LABEL" => info.append_field(F::Publisher, v),
            "ORGANIZATION" | "PUBLISHER" => info.set_field(F::Publisher, v, false),
            "CATALOGNUMBER" => info.set_field(F::CatalogNo, v, true),
            "ISRC" => info.set_field(F::Isrc, v, true),
            "COPYRIGHT" => info.set_field(F::Copyright, v, true),
            "ENCODEDBY" | "ENCODED-BY" => info.set_field(F::EncodedBy, v, true),
            "WEBSITE" | "URL" => info.set_field(F::Url, v, false),
            "GROUPING" => info.set_field(F::Grouping, v, true),
            "SUBTITLE" => info.set_field(F::Subtitle, v, true),
            "MOOD" => info.set_field(F::Mood, v, true),
            "KEY" | "INITIALKEY" => info.set_field(F::InitialKey, v, false),
            "TITLESORT" => info.set_field(F::SortTitle, v, true),
            "ARTISTSORT" => info.set_field(F::SortArtist, v, true),
            "ALBUMARTISTSORT" => info.set_field(F::SortAlbumArtist, v, true),
            "ALBUMSORT" => info.set_field(F::SortAlbum, v, true),
            "COMPOSERSORT" => info.set_field(F::SortComposer, v, true),
            "COMPILATION" => info.set_field(F::Compilation, flag_value(v), true),
            "PODCAST" => info.set_field(F::Podcast, flag_value(v), true),
            "REPLAYGAIN_TRACK_GAIN" => info.set_field(F::RgTrackGain, v, false),
            "REPLAYGAIN_TRACK_PEAK" => info.set_field(F::RgTrackPeak, v, true),
            "REPLAYGAIN_ALBUM_GAIN" => info.set_field(F::RgAlbumGain, v, false),
            "REPLAYGAIN_ALBUM_PEAK" => info.set_field(F::RgAlbumPeak, v, true),
            "R128_TRACK_GAIN" => info.set_field(F::RgTrackGain, &r128_to_rg(v), true),
            "R128_ALBUM_GAIN" => info.set_field(F::RgAlbumGain, &r128_to_rg(v), true),
            "METADATA_BLOCK_PICTURE" => parse_base64_picture(v, info),
            "COVERART" => info.has_cover = true, // old, non-standard; not loaded
            _ => {}
        }
    }
    for (f, total) in [(F::Track, track_total), (F::Disc, disc_total)] {
        let cur = info.field(f).to_string();
        if !total.is_empty() && !cur.is_empty() && !cur.contains('/') {
            info.fields.insert(f, format!("{cur}/{total}"));
        }
    }
}

/// STREAMINFO block body -> sample rate, channels, duration.
// from: ParseStreamInfo
fn parse_stream_info(b: &[u8], p: i64, info: &mut AudioInfo) {
    let g = |i: i64| at(b, p + i) as u32;
    info.sample_rate = (g(10) << 12) | (g(11) << 4) | (g(12) >> 4);
    info.channels = ((g(12) >> 1) & 7) + 1;
    info.bit_depth = (((g(12) & 1) << 4) | (g(13) >> 4)) + 1;
    let total = ((g(13) as u64 & 0x0F) << 32) | be32(b, p + 14) as u64;
    if info.sample_rate > 0 {
        info.duration = total as f64 / info.sample_rate as f64;
    }
}

// from: ReadFlac
pub fn read_flac<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    info.supported = true;
    info.codec = "FLAC".into();
    let skip = id3::read_id3v2(s, info).map_err(io)? as i64; // rare, but some taggers prepend ID3v2
    let mut c = Cur::new(s).map_err(io)?;
    c.pos = skip;
    let h = c.read(4).map_err(io)?;
    if !bytes_are(&h, 0, "fLaC") {
        return Err("Ikke en gyldig FLAC-fil".into());
    }
    loop {
        let h = c.read(4).map_err(io)?;
        if h.len() < 4 {
            break;
        }
        let last = h[0] & 0x80 != 0;
        let block_type = h[0] & 0x7F;
        let len = be24(&h, 1) as i64;
        match block_type {
            0 => {
                let b = c.read(len).map_err(io)?;
                if b.len() >= 18 {
                    parse_stream_info(&b, 0, info);
                }
            }
            4 => {
                let b = c.read(len).map_err(io)?;
                parse_vorbis_comment(&b, 0, info);
            }
            6 if info.want_pictures => {
                let b = c.read(len).map_err(io)?;
                parse_flac_picture(&b, info);
            }
            6 => {
                info.has_cover = true;
                c.pos += len;
            }
            _ => c.pos += len,
        }
        if last || c.pos >= c.size {
            break;
        }
    }
    if info.duration > 0.0 {
        info.bitrate = pascal_round((c.size - c.pos) as f64 * 8.0 / info.duration / 1000.0).max(0) as u32;
    }
    Ok(())
}

/// Reads the first `count` packets of the first logical stream.
// from: ReadOggPackets
fn read_ogg_packets<R: Read + Seek>(s: &mut R, count: usize) -> std::io::Result<Vec<Vec<u8>>> {
    const MAX_BYTES: i64 = 32 * 1024 * 1024;
    let mut c = Cur::new(s)?;
    let mut result: Vec<Vec<u8>> = Vec::new();
    let mut cur: Vec<u8> = Vec::new();
    let mut total: i64 = 0;
    while result.len() < count {
        let h = c.read(27)?;
        if h.len() < 27 || !bytes_are(&h, 0, "OggS") {
            break;
        }
        let nseg = h[26] as usize;
        let segs = c.read(nseg as i64)?;
        if segs.len() < nseg {
            break;
        }
        let data_len: i64 = segs.iter().map(|&x| x as i64).sum();
        let data = c.read(data_len)?;
        total += data_len;
        if (data.len() as i64) < data_len || total > MAX_BYTES {
            break;
        }
        let mut dp = 0usize;
        for &seg in &segs {
            cur.extend_from_slice(&data[dp..dp + seg as usize]);
            dp += seg as usize;
            if seg < 255 {
                // packet ends here
                result.push(std::mem::take(&mut cur));
                if result.len() >= count {
                    break;
                }
            }
        }
    }
    Ok(result)
}

/// Granule position of the last Ogg page = total samples.
// from: LastGranule
fn last_granule<R: Read + Seek>(s: &mut R) -> std::io::Result<i64> {
    let size = stream_size(s)? as i64;
    let start = (size - 65536).max(0);
    let b = read_at(s, start as u64, 65536)?;
    let mut i = b.len() as i64 - 27;
    while i >= 0 {
        if bytes_are(&b, i, "OggS") {
            return Ok(le64(&b, i + 6) as i64);
        }
        i -= 1;
    }
    Ok(0)
}

// from: ReadOgg
pub fn read<R: Read + Seek>(s: &mut R, info: &mut AudioInfo) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    info.supported = true;
    let pk = read_ogg_packets(s, 2).map_err(io)?;
    if pk.is_empty() {
        return Err("Ikke en gyldig Ogg-fil".into());
    }
    let p0 = &pk[0];
    let p1 = pk.get(1);
    let rate_for_duration: u32;
    let mut pre_skip: i64 = 0;
    if p0.len() >= 30 && p0[0] == 1 && bytes_are(p0, 1, "vorbis") {
        info.codec = "Vorbis".into();
        info.channels = p0[11] as u32;
        info.sample_rate = le32(p0, 12);
        rate_for_duration = info.sample_rate;
        if let Some(p1) = p1 {
            if at(p1, 0) == 3 && bytes_are(p1, 1, "vorbis") {
                parse_vorbis_comment(p1, 7, info);
            }
        }
    } else if bytes_are(p0, 0, "OpusHead") {
        info.codec = "Opus".into();
        info.channels = at(p0, 9) as u32;
        pre_skip = le16(p0, 10) as i64;
        info.sample_rate = le32(p0, 12);
        rate_for_duration = 48000; // Opus granule positions are always 48 kHz
        if let Some(p1) = p1 {
            if bytes_are(p1, 0, "OpusTags") {
                parse_vorbis_comment(p1, 8, info);
            }
        }
    } else if p0.len() >= 13 + 34 && p0[0] == 0x7F && bytes_are(p0, 1, "FLAC") {
        // Ogg FLAC: mapping header (9 bytes) + 'fLaC' + STREAMINFO block header (4)
        info.codec = "FLAC (Ogg)".into();
        parse_stream_info(p0, 17, info);
        rate_for_duration = info.sample_rate;
        if let Some(p1) = p1 {
            if p1.len() > 4 && (p1[0] & 0x7F) == 4 {
                parse_vorbis_comment(p1, 4, info);
            }
        }
    } else {
        return Err("Ukendt Ogg-codec".into());
    }

    if rate_for_duration > 0 {
        let granule = last_granule(s).map_err(io)? - pre_skip;
        if granule > 0 {
            info.duration = granule as f64 / rate_for_duration as f64;
        }
    }
    if info.duration > 0.0 {
        let size = stream_size(s).map_err(io)?;
        info.bitrate = pascal_round(size as f64 * 8.0 / info.duration / 1000.0) as u32;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn comment_block(entries: &[&str]) -> Vec<u8> {
        let mut b = 0u32.to_le_bytes().to_vec(); // empty vendor
        b.extend((entries.len() as u32).to_le_bytes());
        for e in entries {
            b.extend((e.len() as u32).to_le_bytes());
            b.extend(e.as_bytes());
        }
        b
    }

    #[test]
    fn repeated_title_is_joined() {
        let mut info = AudioInfo::new(PathBuf::new(), false);
        parse_vorbis_comment(&comment_block(&["TITLE=a", "title=b", "TRACKNUMBER=2", "TRACKTOTAL=12"]), 0, &mut info);
        assert_eq!(info.field(F::Title), "a; b");
        assert_eq!(info.field(F::Track), "2/12");
    }

    #[test]
    fn opus_r128_gain() {
        let mut info = AudioInfo::new(PathBuf::new(), false);
        parse_vorbis_comment(&comment_block(&["R128_TRACK_GAIN=-512"]), 0, &mut info);
        assert_eq!(info.field(F::RgTrackGain), "3.00 dB");
    }

    #[test]
    fn metadata_block_picture() {
        let mut pic = 3u32.to_be_bytes().to_vec();
        pic.extend(10u32.to_be_bytes());
        pic.extend(b"image/jpeg");
        pic.extend(0u32.to_be_bytes());
        pic.extend([0u8; 16]);
        pic.extend(3u32.to_be_bytes());
        pic.extend([0xFF, 0xD8, 0xFF]);
        let b64 = base64::engine::general_purpose::STANDARD.encode(&pic);
        let mut info = AudioInfo::new(PathBuf::new(), true);
        parse_vorbis_comment(&comment_block(&[&format!("METADATA_BLOCK_PICTURE={b64}")]), 0, &mut info);
        assert_eq!(info.pictures.len(), 1);
        assert_eq!(info.pictures[0].pic_type, 3);
        assert_eq!(info.pictures[0].mime, "image/jpeg");
    }
}
