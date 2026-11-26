//! Writes the editable fields and pictures into a FLAC file's metadata blocks (port of
//! flacwriter.pas). STREAMINFO, SEEKTABLE, CUESHEET, APPLICATION blocks and all Vorbis comments
//! we do not edit (ReplayGain, MusicBrainz IDs, ...) are kept. If the new metadata fits in the
//! old space (incl. padding) the file is updated in place; otherwise it is rewritten.

use super::id3::parse_id3v2;
use crate::fileio::{copy_range, replace_file_with, temp_file_for};
use crate::model::{flag_value, image_dimensions, rg_to_r128, AudioInfo, Picture, TagField as F};
use crate::text::{be24, bytes_are, le32, pascal_trim, read_at, stream_size};
use crate::write::WriteOptions;
use base64::Engine;
use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

const NEW_PADDING: i64 = 4096;
const MAX_BLOCK_LEN: usize = 0xFF_FFFF;

// from: IsManagedKey
fn is_managed_key(key: &str) -> bool {
    matches!(key.to_ascii_uppercase().as_str(),
        "TITLE" | "ARTIST" | "ALBUM" | "DATE" | "YEAR" | "TRACKNUMBER" | "TRACKTOTAL" | "TOTALTRACKS"
        | "DISCNUMBER" | "DISCTOTAL" | "TOTALDISCS" | "GENRE" | "COMMENT" | "DESCRIPTION"
        | "ALBUMARTIST" | "ALBUM ARTIST" | "ALBUM_ARTIST" | "COMPOSER" | "BPM"
        | "METADATA_BLOCK_PICTURE" | "COVERART" | "COVERARTMIME"
        | "LYRICS" | "UNSYNCEDLYRICS" | "CONDUCTOR" | "LYRICIST" | "ORIGINALARTIST" | "ORIGARTIST"
        | "REMIXER" | "LABEL" | "ORGANIZATION" | "PUBLISHER" | "CATALOGNUMBER" | "ISRC" | "COPYRIGHT"
        | "ENCODEDBY" | "ENCODED-BY" | "WEBSITE" | "URL" | "GROUPING" | "SUBTITLE" | "MOOD" | "KEY"
        | "INITIALKEY" | "TITLESORT" | "ARTISTSORT" | "ALBUMARTISTSORT" | "ALBUMSORT" | "COMPOSERSORT"
        | "COMPILATION" | "PODCAST" | "REPLAYGAIN_TRACK_GAIN" | "REPLAYGAIN_TRACK_PEAK"
        | "REPLAYGAIN_ALBUM_GAIN" | "REPLAYGAIN_ALBUM_PEAK" | "R128_TRACK_GAIN" | "R128_ALBUM_GAIN")
}

// from: BuildFlacPicture
pub fn build_flac_picture(pic: &Picture) -> Vec<u8> {
    let (w, h) = image_dimensions(&pic.data).unwrap_or((0, 0));
    let mut b = Vec::with_capacity(pic.data.len() + 64);
    b.extend((pic.pic_type as u32).to_be_bytes());
    b.extend((pic.mime.len() as u32).to_be_bytes());
    b.extend(pic.mime.as_bytes());
    b.extend((pic.description.len() as u32).to_be_bytes());
    b.extend(pic.description.as_bytes());
    b.extend(w.to_be_bytes());
    b.extend(h.to_be_bytes());
    b.extend(24u32.to_be_bytes()); // colour depth: typical value, informational only
    b.extend(0u32.to_be_bytes()); // not an indexed-colour image
    b.extend((pic.data.len() as u32).to_be_bytes());
    b.extend(&pic.data);
    b
}

/// Vorbis comment body (vendor + entries), shared with the Ogg writer. `old` is the existing
/// comment packet/block (entries we do not manage are kept), starting at `old_start`.
// from: BuildVorbisComment
pub fn build_vorbis_comment(old: Option<&[u8]>, old_start: usize, info: &AudioInfo, with_pictures: bool) -> Vec<u8> {
    let mut entries: Vec<Vec<u8>> = Vec::new();
    let mut vendor: Vec<u8> = b"TidyTag".to_vec();
    if let Some(ob) = old.filter(|o| !o.is_empty()) {
        let n = ob.len() as i64;
        let mut p = old_start as i64;
        let vendor_len = le32(ob, p) as i64;
        // RawUTF8: clipped to the buffer, '' when empty (the raw bytes are kept)
        let (vs, ve) = (p + 4, (p + 4 + vendor_len).min(n));
        vendor = if vs < ve { ob[vs as usize..ve as usize].to_vec() } else { Vec::new() };
        p += 4 + vendor_len;
        let count = le32(ob, p);
        p += 4;
        for _ in 0..count {
            if p + 4 > n {
                break;
            }
            let len = le32(ob, p) as i64;
            p += 4;
            if p + len > n {
                break;
            }
            let entry = &ob[p as usize..(p + len) as usize];
            p += len;
            if let Some(eq) = entry.iter().position(|&c| c == b'=') {
                if eq > 0 && !is_managed_key(&String::from_utf8_lossy(&entry[..eq])) {
                    entries.push(entry.to_vec());
                }
            }
        }
    }
    let mut add = |k: &str, v: &str| entries.push(format!("{k}={v}").into_bytes());
    // The reader joins repeated keys with '; ' - split them again.
    let multi = |add: &mut dyn FnMut(&str, &str), k: &str, v: &str| {
        for part in v.split("; ") {
            let t = pascal_trim(part);
            if !t.is_empty() {
                add(k, t);
            }
        }
    };
    let one = |add: &mut dyn FnMut(&str, &str), k: &str, v: &str| {
        if !v.is_empty() {
            add(k, v);
        }
    };
    let pair = |add: &mut dyn FnMut(&str, &str), nk: &str, tk: &str, v: &str| {
        if v.is_empty() {
            return;
        }
        match v.find('/') {
            Some(s) => {
                add(nk, pascal_trim(&v[..s]));
                let total = pascal_trim(&v[s + 1..]);
                if !total.is_empty() {
                    add(tk, total);
                }
            }
            None => add(nk, v),
        }
    };
    let f = |t: F| info.field(t);
    multi(&mut add, "TITLE", f(F::Title));
    multi(&mut add, "ARTIST", f(F::Artist));
    multi(&mut add, "ALBUM", f(F::Album));
    multi(&mut add, "ALBUMARTIST", f(F::AlbumArtist));
    one(&mut add, "DATE", f(F::Year));
    pair(&mut add, "TRACKNUMBER", "TRACKTOTAL", f(F::Track));
    pair(&mut add, "DISCNUMBER", "DISCTOTAL", f(F::Disc));
    multi(&mut add, "GENRE", f(F::Genre));
    multi(&mut add, "COMPOSER", f(F::Composer));
    one(&mut add, "BPM", f(F::Bpm));
    one(&mut add, "COMMENT", f(F::Comment));
    multi(&mut add, "CONDUCTOR", f(F::Conductor));
    multi(&mut add, "LYRICIST", f(F::Lyricist));
    multi(&mut add, "ORIGINALARTIST", f(F::OrigArtist));
    multi(&mut add, "REMIXER", f(F::Remixer));
    multi(&mut add, "LABEL", f(F::Publisher));
    for (k, t) in [("CATALOGNUMBER", F::CatalogNo), ("ISRC", F::Isrc), ("COPYRIGHT", F::Copyright),
        ("ENCODEDBY", F::EncodedBy), ("WEBSITE", F::Url), ("GROUPING", F::Grouping), ("SUBTITLE", F::Subtitle),
        ("MOOD", F::Mood), ("KEY", F::InitialKey), ("TITLESORT", F::SortTitle), ("ARTISTSORT", F::SortArtist),
        ("ALBUMARTISTSORT", F::SortAlbumArtist), ("ALBUMSORT", F::SortAlbum), ("COMPOSERSORT", F::SortComposer)]
    {
        one(&mut add, k, f(t));
    }
    one(&mut add, "COMPILATION", flag_value(f(F::Compilation)));
    one(&mut add, "PODCAST", flag_value(f(F::Podcast)));
    if info.codec == "Opus" {
        // RFC 7845: Opus players use R128 gains (no peaks) and ignore REPLAYGAIN_*
        one(&mut add, "R128_TRACK_GAIN", &rg_to_r128(f(F::RgTrackGain)));
        one(&mut add, "R128_ALBUM_GAIN", &rg_to_r128(f(F::RgAlbumGain)));
    } else {
        one(&mut add, "REPLAYGAIN_TRACK_GAIN", f(F::RgTrackGain));
        one(&mut add, "REPLAYGAIN_TRACK_PEAK", f(F::RgTrackPeak));
        one(&mut add, "REPLAYGAIN_ALBUM_GAIN", f(F::RgAlbumGain));
        one(&mut add, "REPLAYGAIN_ALBUM_PEAK", f(F::RgAlbumPeak));
    }
    one(&mut add, "LYRICS", f(F::Lyrics));
    if with_pictures {
        for p in &info.pictures {
            let b64 = base64::engine::general_purpose::STANDARD.encode(build_flac_picture(p));
            add("METADATA_BLOCK_PICTURE", &b64);
        }
    }
    let mut d = Vec::new();
    d.extend((vendor.len() as u32).to_le_bytes());
    d.extend(&vendor);
    d.extend((entries.len() as u32).to_le_bytes());
    for e in &entries {
        d.extend((e.len() as u32).to_le_bytes());
        d.extend(e);
    }
    d
}

// from: WriteBlock
fn write_block(dest: &mut Vec<u8>, block_type: u8, last: bool, data: &[u8]) -> Result<(), String> {
    if data.len() > MAX_BLOCK_LEN {
        return Err("Metadata-blokken er for stor (billedet er over 16 MB)".into());
    }
    let n = data.len() as u32;
    dest.push(if last { block_type | 0x80 } else { block_type });
    dest.extend([(n >> 16) as u8, (n >> 8) as u8, n as u8]);
    dest.extend(data);
    Ok(())
}

// from: WriteFlacTags
pub fn write(path: &Path, info: &AudioInfo, _opt: &WriteOptions) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut src = File::open(path).map_err(io)?;
    let prefix = parse_id3v2(&mut src).map_err(io)?.1; // keep an ID3v2 prefix as it is
    let h = read_at(&mut src, prefix, 4).map_err(io)?;
    if !bytes_are(&h, 0, "fLaC") {
        return Err("Ikke en gyldig FLAC-fil".into());
    }
    let mut pos = prefix + 4;
    let mut blocks: Vec<(u8, Vec<u8>)> = Vec::new();
    let mut comment_body: Option<Vec<u8>> = None;
    loop {
        let h = read_at(&mut src, pos, 4).map_err(io)?;
        if h.len() < 4 {
            return Err("FLAC-metadata er afkortet".into());
        }
        pos += 4;
        let last = h[0] & 0x80 != 0;
        let block_type = h[0] & 0x7F;
        let len = be24(&h, 1) as u64;
        if block_type == 127 {
            return Err("Ugyldig FLAC-metadatablok".into());
        }
        let data = read_at(&mut src, pos, len).map_err(io)?;
        if data.len() as u64 != len {
            return Err("FLAC-metadata er afkortet".into());
        }
        pos += len;
        if block_type == 4 && comment_body.is_none() && !data.is_empty() {
            comment_body = Some(data.clone());
        }
        blocks.push((block_type, data));
        if last {
            break;
        }
    }
    let audio_start = pos;
    let old_meta_len = (audio_start - (prefix + 4)) as i64;
    if blocks.first().map(|b| b.0) != Some(0) {
        return Err("FLAC-filen mangler STREAMINFO".into());
    }

    // New block order: STREAMINFO, other kept blocks, comments, pictures (padding last).
    let mut kept: Vec<(u8, Vec<u8>)> = blocks.into_iter().filter(|b| ![1, 4, 6].contains(&b.0)).collect();
    kept.push((4, build_vorbis_comment(comment_body.as_deref(), 0, info, false)));
    for p in &info.pictures {
        kept.push((6, build_flac_picture(p)));
    }
    let needed: i64 = kept.iter().map(|b| 4 + b.1.len() as i64).sum();
    let pad_len = if needed == old_meta_len || needed + 4 <= old_meta_len {
        old_meta_len - needed - 4 // -4 = no padding block at all
    } else {
        NEW_PADDING
    };
    let mut meta = Vec::new();
    let n = kept.len();
    for (i, (t, d)) in kept.iter().enumerate() {
        write_block(&mut meta, *t, i == n - 1 && pad_len < 0, d)?;
    }
    if pad_len >= 0 {
        let p = pad_len as u32;
        meta.extend([1 | 0x80, (p >> 16) as u8, (p >> 8) as u8, p as u8]);
        meta.resize(meta.len() + pad_len as usize, 0);
    }

    if meta.len() as i64 == old_meta_len {
        drop(src);
        let mut dst = OpenOptions::new().write(true).open(path).map_err(io)?;
        dst.seek(SeekFrom::Start(prefix + 4)).map_err(io)?;
        dst.write_all(&meta).map_err(io)?;
    } else {
        let temp = temp_file_for(path);
        let result = (|| -> Result<(), String> {
            let mut dst = std::io::BufWriter::new(File::create(&temp).map_err(io)?);
            copy_range(&mut src, &mut dst, 0, prefix + 4)?; // ID3v2 prefix + 'fLaC'
            dst.write_all(&meta).map_err(io)?;
            let size = stream_size(&mut src).map_err(io)?;
            copy_range(&mut src, &mut dst, audio_start, size - audio_start)?;
            dst.flush().map_err(io)
        })();
        drop(src);
        if let Err(e) = result {
            let _ = std::fs::remove_file(&temp);
            return Err(e);
        }
        replace_file_with(&temp, path)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::read::read_audio_info;
    use crate::scenario::test_png;
    use std::path::PathBuf;

    /// A minimal FLAC: STREAMINFO, a comment block with MUSICBRAINZ_TRACKID, `pad` bytes of
    /// padding, then fake audio.
    fn flac(pad: usize) -> Vec<u8> {
        let mut si = vec![0u8; 34];
        si[10] = 0x0A; // 44100 Hz
        si[11] = 0xC4;
        si[12] = 0x42;
        let mut comment = Vec::new();
        comment.extend(3u32.to_le_bytes());
        comment.extend(b"ref");
        comment.extend(1u32.to_le_bytes());
        let e = b"MUSICBRAINZ_TRACKID=abc";
        comment.extend((e.len() as u32).to_le_bytes());
        comment.extend(e);
        let mut v = b"fLaC".to_vec();
        write_block(&mut v, 0, false, &si).unwrap();
        write_block(&mut v, 4, false, &comment).unwrap();
        write_block(&mut v, 1, true, &vec![0; pad]).unwrap();
        v.extend(b"AUDIOAUDIO");
        v
    }

    fn roundtrip(file: Vec<u8>, edit: impl Fn(&mut AudioInfo)) -> (Vec<u8>, AudioInfo) {
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("tidytag-flacw-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.flac");
        std::fs::write(&p, &file).unwrap();
        let mut info = read_audio_info(&p, true);
        edit(&mut info);
        write(&p, &info, &WriteOptions::default()).unwrap();
        let out = std::fs::read(&p).unwrap();
        let back = read_audio_info(&p, true);
        std::fs::remove_dir_all(dir).unwrap();
        (out, back)
    }

    #[test]
    fn in_place_when_padding_fits() {
        let before = flac(1000);
        let (out, back) = roundtrip(before.clone(), |i| i.put(F::Title, "Hej"));
        assert_eq!(out.len(), before.len());
        assert!(out.ends_with(b"AUDIOAUDIO"));
        assert_eq!(back.field(F::Title), "Hej");
    }

    #[test]
    fn unmanaged_comments_kept() {
        let (out, _) = roundtrip(flac(1000), |i| i.put(F::Title, "x"));
        assert!(out.windows(23).any(|w| w == b"MUSICBRAINZ_TRACKID=abc"));
    }

    #[test]
    fn rewrite_when_growing() {
        let before = flac(10);
        let (out, back) = roundtrip(before.clone(), |i| crate::batch::set_front_cover(i, test_png(400 * 1024)));
        assert!(out.len() > before.len() + 400 * 1024);
        assert!(out.ends_with(b"AUDIOAUDIO"));
        assert_eq!(back.pictures.len(), 1);
        let _ = PathBuf::new();
    }
}
