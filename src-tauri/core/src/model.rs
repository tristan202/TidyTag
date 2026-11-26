//! Format-independent result of reading one audio file (port of audiotypes.pas).

use serde::Serialize;
use std::collections::BTreeMap;
use std::path::PathBuf;

/// The tag fields, in 1.2's `TTagField` order. The serde names are the shared keys used by
/// both tagdumps and the renderer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum TagField {
    Title, Artist, Album, Year, Track, Disc, Genre, Comment, AlbumArtist, Composer, Bpm,
    Lyrics, Conductor, Lyricist, OrigArtist, Remixer, Publisher, CatalogNo, Isrc, Copyright,
    EncodedBy, Url, Grouping, Subtitle, Mood, InitialKey,
    SortTitle, SortArtist, SortAlbumArtist, SortAlbum, SortComposer,
    Compilation, Podcast,
    RgTrackGain, RgTrackPeak, RgAlbumGain, RgAlbumPeak,
}

use TagField::*;

impl TagField {
    pub const ALL: [TagField; 37] = [
        Title, Artist, Album, Year, Track, Disc, Genre, Comment, AlbumArtist, Composer, Bpm,
        Lyrics, Conductor, Lyricist, OrigArtist, Remixer, Publisher, CatalogNo, Isrc, Copyright,
        EncodedBy, Url, Grouping, Subtitle, Mood, InitialKey,
        SortTitle, SortArtist, SortAlbumArtist, SortAlbum, SortComposer,
        Compilation, Podcast,
        RgTrackGain, RgTrackPeak, RgAlbumGain, RgAlbumPeak,
    ];

    pub fn key(self) -> &'static str {
        const KEYS: [&str; 37] = [
            "title", "artist", "album", "year", "track", "disc", "genre", "comment", "albumArtist",
            "composer", "bpm", "lyrics", "conductor", "lyricist", "origArtist", "remixer",
            "publisher", "catalogNo", "isrc", "copyright", "encodedBy", "url", "grouping",
            "subtitle", "mood", "initialKey", "sortTitle", "sortArtist", "sortAlbumArtist",
            "sortAlbum", "sortComposer", "compilation", "podcast", "rgTrackGain", "rgTrackPeak",
            "rgAlbumGain", "rgAlbumPeak",
        ];
        KEYS[self as usize]
    }

    pub fn from_key(k: &str) -> Option<TagField> {
        TagField::ALL.iter().copied().find(|f| f.key() == k)
    }
}

pub const PIC_TYPE_FRONT_COVER: u8 = 3;

#[derive(Debug, Clone, Default)]
pub struct Picture {
    pub pic_type: u8,
    pub mime: String,
    pub description: String,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, Default)]
pub struct AudioInfo {
    pub path: PathBuf,
    pub file_size: u64,
    pub fields: BTreeMap<TagField, String>,
    pub tag_types: Vec<String>,
    pub codec: String,
    pub has_cover: bool,
    /// seconds
    pub duration: f64,
    /// kbit/s
    pub bitrate: u32,
    pub sample_rate: u32,
    pub channels: u32,
    /// bits per sample of lossless/PCM audio, 0 = unknown/lossy
    pub bit_depth: u32,
    /// false = listed, but tags are not read
    pub supported: bool,
    pub error: String,
    /// set before reading to keep picture data (the file list only needs has_cover)
    pub want_pictures: bool,
    pub pictures: Vec<Picture>,
}

impl AudioInfo {
    pub fn new(path: PathBuf, want_pictures: bool) -> AudioInfo {
        AudioInfo { path, want_pictures, supported: true, ..Default::default() }
    }

    pub fn field(&self, f: TagField) -> &str {
        self.fields.get(&f).map(String::as_str).unwrap_or("")
    }

    /// Empty values never erase an existing field.
    pub fn set_field(&mut self, f: TagField, v: &str, overwrite: bool) {
        let t = v.trim();
        if t.is_empty() {
            return;
        }
        if overwrite || self.field(f).is_empty() {
            self.fields.insert(f, t.to_string());
        }
    }

    /// Adds a further value ('A; B'), used for repeated Vorbis comments.
    pub fn append_field(&mut self, f: TagField, v: &str) {
        let t = v.trim();
        if t.is_empty() {
            return;
        }
        let e = self.fields.entry(f).or_default();
        if e.is_empty() {
            *e = t.to_string();
        } else {
            e.push_str("; ");
            e.push_str(t);
        }
    }

    pub fn add_tag_type(&mut self, t: &str) {
        self.tag_types.push(t.to_string());
    }

    pub fn tag_types_text(&self) -> String {
        self.tag_types.join(", ")
    }

    pub fn add_picture(&mut self, pic_type: u8, mime: &str, description: &str, data: Vec<u8>) {
        if data.is_empty() {
            return;
        }
        self.has_cover = true;
        if !self.want_pictures {
            return;
        }
        let mime = if mime.is_empty() || !mime.contains('/') {
            detect_image_mime(&data, "image/jpeg").to_string()
        } else {
            mime.to_lowercase()
        };
        self.pictures.push(Picture { pic_type, mime, description: description.to_string(), data });
    }
}

/// True for '1', 'true', 'yes' and other non-zero numbers: flag fields in files vary.
pub fn is_true_flag(s: &str) -> bool {
    let t = s.trim().to_lowercase();
    t == "true" || t == "yes" || t.parse::<i64>().map(|n| n != 0).unwrap_or(false)
}

/// '1' or '' for a flag field.
pub fn flag_value(s: &str) -> &'static str {
    if is_true_flag(s) { "1" } else { "" }
}

/// FormatFloat-style fixed decimals: halves round away from zero.
fn fixed(v: f64, decimals: i32) -> String {
    let m = 10f64.powi(decimals);
    let r = (v * m).round() / m;
    let r = if r == 0.0 { 0.0 } else { r }; // no "-0.00"
    format!("{:.*}", decimals as usize, r)
}

/// ReplayGain values as written in tags: '-6.52 dB' (always with a point).
pub fn rg_gain_text(db: f64) -> String {
    format!("{} dB", fixed(db, 2))
}

/// '0.988553'
pub fn rg_peak_text(peak: f64) -> String {
    fixed(peak, 6)
}

/// Reads '-6.52 dB', '+1.2 dB' or '-6,52'; None if s holds no number.
pub fn parse_rg_gain(s: &str) -> Option<f64> {
    let mut t = String::new();
    for c in s.chars() {
        if c.is_ascii_digit() || matches!(c, '-' | '+' | '.' | ',') {
            t.push(c);
        } else if !t.is_empty() && c != ' ' {
            break;
        }
    }
    let t = t.replacen(',', ".", 1);
    let t = t.strip_prefix('+').unwrap_or(&t);
    t.parse::<f64>().ok()
}

/// Opus R128_*_GAIN (Q7.8 integer relative to -23 LUFS) -> ReplayGain text (-18 LUFS).
pub fn r128_to_rg(s: &str) -> String {
    match s.trim().parse::<i32>() {
        Ok(q) => rg_gain_text(q as f64 / 256.0 + 5.0),
        Err(_) => String::new(),
    }
}

pub fn rg_to_r128(s: &str) -> String {
    match parse_rg_gain(s) {
        Some(db) => (((db - 5.0) * 256.0).round() as i64).to_string(),
        None => String::new(),
    }
}

/// 'image/png' / 'image/jpeg' from the data signature; fallback if unknown.
pub fn detect_image_mime<'a>(data: &[u8], fallback: &'a str) -> &'a str {
    if data.len() >= 8 && data[0] == 0x89 && &data[1..4] == b"PNG" {
        "image/png"
    } else if data.len() >= 3 && data[0] == 0xFF && data[1] == 0xD8 {
        "image/jpeg"
    } else if data.len() >= 6 && &data[0..3] == b"GIF" {
        "image/gif"
    } else if data.len() >= 2 && &data[0..2] == b"BM" {
        "image/bmp"
    } else {
        fallback
    }
}

/// Pixel size from PNG/JPEG headers.
pub fn image_dimensions(data: &[u8]) -> Option<(u32, u32)> {
    let be = |i: usize| ((data[i] as u32) << 8) | data[i + 1] as u32;
    match detect_image_mime(data, "") {
        "image/png" => {
            if data.len() < 24 {
                return None;
            }
            let w = u32::from_be_bytes([data[16], data[17], data[18], data[19]]);
            let h = u32::from_be_bytes([data[20], data[21], data[22], data[23]]);
            Some((w, h))
        }
        "image/jpeg" => {
            let mut p = 2usize;
            while p + 9 < data.len() {
                if data[p] != 0xFF {
                    return None;
                }
                let m = data[p + 1];
                if m == 0xFF {
                    p += 1; // fill byte
                    continue;
                }
                if m == 0xD8 || (0xD0..=0xD7).contains(&m) || m == 0x01 {
                    p += 2;
                    continue;
                }
                let seg_len = be(p + 2) as usize;
                // SOF0..SOF15 except DHT (C4), JPG (C8), DAC (CC)
                if (0xC0..=0xCF).contains(&m) && ![0xC4, 0xC8, 0xCC].contains(&m) {
                    return Some((be(p + 7), be(p + 5)));
                }
                p += 2 + seg_len;
            }
            None
        }
        _ => None,
    }
}

/// Danish source text (translated by the renderer).
pub fn picture_type_name(t: u8) -> &'static str {
    match t {
        0 => "Andet",
        1 | 2 => "Fil-ikon",
        3 => "Forside",
        4 => "Bagside",
        5 => "Indlægsseddel",
        6 => "Medie (CD)",
        7 => "Solist",
        8 => "Kunstner",
        9 => "Dirigent",
        10 => "Orkester",
        11 => "Komponist",
        12 => "Tekstforfatter",
        13 => "Optagested",
        14 | 15 => "Under optagelse",
        18 => "Illustration",
        19 => "Kunstnerlogo",
        20 => "Udgiverlogo",
        _ => "Billede",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn helpers_match_pascal() {
        assert_eq!(rg_gain_text(-6.524), "-6.52 dB");
        assert_eq!(rg_peak_text(0.9885531), "0.988553");
        assert_eq!(parse_rg_gain("+1,2 dB"), Some(1.2));
        assert_eq!(r128_to_rg("-512"), "3.00 dB");
        assert_eq!(rg_to_r128("3.00 dB"), "-512");
        assert!(is_true_flag("yes") && is_true_flag("1") && !is_true_flag("0") && !is_true_flag(""));
        assert_eq!(detect_image_mime(&[0x89, b'P', b'N', b'G', 13, 10, 26, 10], "image/jpeg"), "image/png");
        assert_eq!(detect_image_mime(&[0x89, b'P', b'N', b'G'], "image/jpeg"), "image/jpeg");
        assert_eq!(TagField::ALL.len(), 37);
        assert_eq!(TagField::RgAlbumPeak.key(), "rgAlbumPeak");
        assert_eq!(TagField::from_key("albumArtist"), Some(TagField::AlbumArtist));
    }

    #[test]
    fn set_and_append_keep_pascal_semantics() {
        let mut a = AudioInfo::new(PathBuf::new(), false);
        a.set_field(Title, " a ", true);
        a.set_field(Title, "", true);
        assert_eq!(a.field(Title), "a");
        a.set_field(Title, "b", false);
        assert_eq!(a.field(Title), "a");
        a.append_field(Title, "b");
        assert_eq!(a.field(Title), "a; b");
        a.add_picture(3, "", "", vec![0xFF, 0xD8, 0xFF]);
        assert!(a.has_cover && a.pictures.is_empty());
    }
}
