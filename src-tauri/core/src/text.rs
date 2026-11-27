//! Byte helpers and text decoding shared by the tag readers (port of tagutils.pas, reading
//! parts). All functions are bounds-safe and return 0 / "" when out of range, like 1.2.

use std::io::{Read, Seek, SeekFrom};

fn in_range(b: &[u8], p: i64, len: i64) -> bool {
    p >= 0 && len >= 0 && p + len <= b.len() as i64
}

pub fn be16(b: &[u8], p: i64) -> u32 {
    if !in_range(b, p, 2) { return 0; }
    let p = p as usize;
    ((b[p] as u32) << 8) | b[p + 1] as u32
}

pub fn be24(b: &[u8], p: i64) -> u32 {
    if !in_range(b, p, 3) { return 0; }
    let p = p as usize;
    ((b[p] as u32) << 16) | ((b[p + 1] as u32) << 8) | b[p + 2] as u32
}

pub fn be32(b: &[u8], p: i64) -> u32 {
    if !in_range(b, p, 4) { return 0; }
    let p = p as usize;
    u32::from_be_bytes([b[p], b[p + 1], b[p + 2], b[p + 3]])
}

pub fn be64(b: &[u8], p: i64) -> u64 {
    if !in_range(b, p, 8) { return 0; }
    ((be32(b, p) as u64) << 32) | be32(b, p + 4) as u64
}

pub fn le16(b: &[u8], p: i64) -> u32 {
    if !in_range(b, p, 2) { return 0; }
    let p = p as usize;
    b[p] as u32 | ((b[p + 1] as u32) << 8)
}

pub fn le32(b: &[u8], p: i64) -> u32 {
    if !in_range(b, p, 4) { return 0; }
    let p = p as usize;
    u32::from_le_bytes([b[p], b[p + 1], b[p + 2], b[p + 3]])
}

pub fn le64(b: &[u8], p: i64) -> u64 {
    if !in_range(b, p, 8) { return 0; }
    le32(b, p) as u64 | ((le32(b, p + 4) as u64) << 32)
}

pub fn syncsafe32(b: &[u8], p: i64) -> u32 {
    if !in_range(b, p, 4) { return 0; }
    let p = p as usize;
    ((b[p] as u32 & 0x7F) << 21) | ((b[p + 1] as u32 & 0x7F) << 14) | ((b[p + 2] as u32 & 0x7F) << 7) | (b[p + 3] as u32 & 0x7F)
}

/// True if the bytes at p equal the ASCII text s.
pub fn bytes_are(b: &[u8], p: i64, s: &str) -> bool {
    in_range(b, p, s.len() as i64) && &b[p as usize..p as usize + s.len()] == s.as_bytes()
}

pub fn bytes_to_ascii(b: &[u8], p: i64, len: i64) -> String {
    if !in_range(b, p, len) { return String::new(); }
    b[p as usize..(p + len) as usize].iter().map(|&c| if (32..=126).contains(&c) { c as char } else { '?' }).collect()
}

/// Clamps (p, len) to the buffer the way 1.2's text decoders do.
fn clamp(b: &[u8], p: i64, mut len: i64) -> Option<(usize, usize)> {
    if p + len > b.len() as i64 { len = b.len() as i64 - p; }
    if p < 0 || len <= 0 { return None; }
    Some((p as usize, len as usize))
}

pub fn latin1(b: &[u8], p: i64, len: i64) -> String {
    match clamp(b, p, len) {
        Some((p, len)) => b[p..p + len].iter().map(|&c| c as char).collect(),
        None => String::new(),
    }
}

pub fn utf16(b: &[u8], p: i64, len: i64, big_endian: bool) -> String {
    let Some((p, len)) = clamp(b, p, len) else { return String::new() };
    if len < 2 { return String::new(); }
    let units: Vec<u16> = (0..len / 2)
        .map(|i| {
            let (x, y) = (b[p + 2 * i], b[p + 2 * i + 1]);
            if big_endian { u16::from_be_bytes([x, y]) } else { u16::from_le_bytes([x, y]) }
        })
        // BOMs of later values in a multi-value frame
        .filter(|&w| w != 0xFEFF && w != 0xFFFE)
        .collect();
    String::from_utf16_lossy(&units)
}

pub fn raw_utf8(b: &[u8], p: i64, len: i64) -> String {
    match clamp(b, p, len) {
        Some((p, len)) => String::from_utf8_lossy(&b[p..p + len]).into_owned(),
        None => String::new(),
    }
}

/// Pascal's Trim: removes characters <= ' ' at both ends (not other Unicode spaces).
pub fn pascal_trim(s: &str) -> &str {
    s.trim_matches(|c: char| c <= ' ')
}

/// Removes trailing NULs and turns embedded NULs (multi-value separators) into '; '.
pub fn clean_tag_text(s: &str) -> String {
    let t = s.trim_end_matches('\0');
    pascal_trim(&t.replace('\0', "; ")).to_string()
}

/// Pascal's Round: halves go to the even neighbour.
pub fn pascal_round(x: f64) -> i64 {
    x.round_ties_even() as i64
}

/// kbit/s from a byte count and a duration (1.2's Round(Bytes * 8 / Seconds / 1000)).
/// Damaged files can give a negative byte count; 1.2 then shows no bitrate, so this gives 0.
pub fn kbps(bytes: i64, seconds: f64) -> u32 {
    pascal_round(bytes as f64 * 8.0 / seconds / 1000.0).max(0) as u32
}

pub fn stream_size<R: Seek>(s: &mut R) -> std::io::Result<u64> {
    s.seek(SeekFrom::End(0))
}

/// Up to `count` bytes from `pos` (fewer at the end of the stream), like ReadStreamBytes.
pub fn read_at<R: Read + Seek>(s: &mut R, pos: u64, count: u64) -> std::io::Result<Vec<u8>> {
    let size = stream_size(s)?;
    if pos >= size || count == 0 {
        return Ok(Vec::new());
    }
    let n = count.min(size - pos);
    s.seek(SeekFrom::Start(pos))?;
    let mut buf = Vec::with_capacity(n as usize);
    s.take(n).read_to_end(&mut buf)?;
    Ok(buf)
}

const ID3_GENRES: [&str; 192] = [
    "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge",
    "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B",
    "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
    "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient",
    "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical",
    "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
    "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative",
    "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave",
    "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream",
    "Southern Rock", "Comedy", "Cult", "Gangsta", "Top 40", "Christian Rap",
    "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
    "Psychadelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal",
    "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll",
    "Hard Rock", "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion",
    "Bebob", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde",
    "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock",
    "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic", "Humour",
    "Speech", "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony",
    "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam", "Club",
    "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul",
    "Freestyle", "Duet", "Punk Rock", "Drum Solo", "A capella", "Euro-House",
    "Dance Hall", "Goa", "Drum & Bass", "Club-House", "Hardcore", "Terror",
    "Indie", "BritPop", "Afro-Punk", "Polsk Punk", "Beat",
    "Christian Gangsta Rap", "Heavy Metal", "Black Metal", "Crossover",
    "Contemporary Christian", "Christian Rock", "Merengue", "Salsa",
    "Thrash Metal", "Anime", "JPop", "Synthpop", "Abstract", "Art Rock",
    "Baroque", "Bhangra", "Big Beat", "Breakbeat", "Chillout", "Downtempo",
    "Dub", "EBM", "Eclectic", "Electro", "Electroclash", "Emo",
    "Experimental", "Garage", "Global", "IDM", "Illbient", "Industro-Goth",
    "Jam Band", "Krautrock", "Leftfield", "Lounge", "Math Rock",
    "New Romantic", "Nu-Breakz", "Post-Punk", "Post-Rock", "Psytrance",
    "Shoegaze", "Space Rock", "Trop Rock", "World Music", "Neoclassical",
    "Audiobook", "Audio Theatre", "Neue Deutsche Welle", "Podcast",
    "Indie Rock", "G-Funk", "Dubstep", "Garage Rock", "Psybient",
];

/// The standard ID3v1 genre names (1.2's ID3Genres).
pub fn id3_genres() -> &'static [&'static str] {
    &ID3_GENRES
}

pub fn id3_genre_name(index: i64) -> &'static str {
    if (0..ID3_GENRES.len() as i64).contains(&index) { ID3_GENRES[index as usize] } else { "" }
}

/// Index in the ID3v1 genre list (case-insensitive), -1 if not a standard genre.
pub fn id3_genre_index(name: &str) -> i64 {
    ID3_GENRES.iter().position(|g| g.eq_ignore_ascii_case(name)).map(|i| i as i64).unwrap_or(-1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_helpers() {
        assert_eq!(syncsafe32(&[0, 0, 2, 1], 0), 257);
        assert_eq!(be32(&[1, 2, 3], 0), 0);
        assert_eq!(id3_genre_name(17), "Rock");
        assert_eq!(id3_genre_name(255), "");
        assert_eq!(id3_genre_index("rock"), 17);
        assert_eq!(latin1(&[0xC6], 0, 1), "Æ");
        assert_eq!(utf16(b"\xFF\xFEA\x00", 0, 4, false), "A");
        assert_eq!(clean_tag_text("a\0b\0\0"), "a; b");
        assert_eq!(pascal_trim("\u{A0}x "), "\u{A0}x");
        assert_eq!(pascal_round(2.5), 2);
        assert_eq!(pascal_round(3.5), 4);
        // damaged files can give negative byte counts: 1.2 then shows no bitrate
        assert_eq!(kbps(-1000, 1.0), 0);
        assert_eq!(kbps(40_000, 1.0), 320);
    }
}
