//! tagtest's three write scenarios (tools/tagtest.lpr `Scenario`), shared by the Rust tagset and
//! the write cross-check. 1.2's `tagset --scenario N` applies exactly the same edits.

use crate::model::{AudioInfo, Picture, TagField as F, PIC_TYPE_FRONT_COVER};

/// tagtest's 1x1 PNG, padded to `size` with byte i = (i * 31 + 7) mod 256.
pub fn test_png(size: usize) -> Vec<u8> {
    const TINY: [u8; 67] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00,
        0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00,
        0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
        0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    let size = size.max(TINY.len());
    let mut v = TINY.to_vec();
    v.extend((TINY.len()..size).map(|i| ((i * 31 + 7) % 256) as u8));
    v
}

fn set_picture(info: &mut AudioInfo, size: usize) {
    info.pictures = vec![Picture {
        pic_type: PIC_TYPE_FRONT_COVER,
        mime: "image/png".into(),
        description: "Forside æøå".into(),
        data: test_png(size),
    }];
}

/// 0 = all fields + a small cover, 1 = a 400 KB cover, 2 = some fields cleared and no pictures.
pub fn apply(info: &mut AudioInfo, n: u8) {
    match n {
        0 => {
            let values: [(F, &str); 37] = [
                (F::Title, "Titel A – æøå ÆØÅ"), (F::Artist, "Kunstner 漢字 Ünïcödé"), (F::Album, "Album Ålborg"),
                (F::Year, "2001-02-03"), (F::Track, "5/9"), (F::Disc, "2/3"), (F::Genre, "Rock"),
                (F::Comment, "En kommentar"), (F::AlbumArtist, "Diverse kunstnere"), (F::Composer, "Carl Nielsen"),
                (F::Bpm, "120"), (F::Lyrics, "Første linje æøå\r\nAnden linje\r\n漢字"), (F::Conductor, "Dirigent Ø"),
                (F::Lyricist, "Tekstforfatter"), (F::OrigArtist, "Oprindelig"), (F::Remixer, "Remixer"),
                (F::Publisher, "Pladeselskab A/S"), (F::CatalogNo, "CAT 123"), (F::Isrc, "DKABC2400001"),
                (F::Copyright, "© 2001 Nogen"), (F::EncodedBy, "TidyTag"), (F::Url, "https://example.com/a?b=1"),
                (F::Grouping, "Gruppe"), (F::Subtitle, "Undertitel"), (F::Mood, "Glad"), (F::InitialKey, "Am"),
                (F::SortTitle, "Sort titel"), (F::SortArtist, "Kunstner, Sort"), (F::SortAlbumArtist, "Kunstnere, Diverse"),
                (F::SortAlbum, "Ålborg, Album"), (F::SortComposer, "Nielsen, Carl"), (F::Compilation, "1"),
                (F::Podcast, "1"), (F::RgTrackGain, "-6.52 dB"), (F::RgTrackPeak, "0.988553"),
                (F::RgAlbumGain, "-7.10 dB"), (F::RgAlbumPeak, "1.000000"),
            ];
            for (f, v) in values {
                info.put(f, v);
            }
            set_picture(info, 0);
        }
        1 => set_picture(info, 400 * 1024),
        2 => {
            for f in [F::Comment, F::Composer, F::Lyrics, F::Mood, F::CatalogNo, F::Url] {
                info.put(f, "");
            }
            info.pictures.clear();
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_png_matches_tagset() {
        assert_eq!(test_png(0).len(), 67);
        let big = test_png(400 * 1024);
        assert_eq!(big.len(), 400 * 1024);
        assert_eq!(big[67], ((67 * 31 + 7) % 256) as u8);
    }
}
