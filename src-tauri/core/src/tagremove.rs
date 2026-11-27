//! Removing all tags (port of tagremove.pas). MP3/APE-family files lose their ID3v2, APE and
//! ID3v1 tags entirely, WAV/AIFF their tag chunks; other formats get their fields (except
//! ReplayGain) and pictures cleared.

use crate::fileio::{copy_range, get_file_stamp, replace_file_with, set_file_stamp, temp_file_for};
use crate::model::TagField;
use crate::read::read_audio_info;
use crate::tags::ape::find_ape_tag;
use crate::tags::id3::parse_id3v2;
use crate::tags::riff::{is_id3_chunk_id, read_chunk_file, Chunk, ChunkFile};
use crate::text::{bytes_are, read_at, stream_size};
use crate::write::{can_write_tags, write_audio_tags, WriteOptions};
use std::fs::File;
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

fn ext(path: &Path) -> String {
    path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default()
}

/// True: the format loses its tags completely (else fields and pictures are cleared).
// from: RemovesWholeTag
pub fn removes_whole_tag(path: &Path) -> bool {
    matches!(ext(path).as_str(), "mp3" | "mp2" | "ape" | "wv" | "mpc" | "ofr" | "wav" | "aif" | "aiff" | "aifc")
}

fn rewrite(path: &Path, src: File, body: impl FnOnce(File, &mut std::io::BufWriter<File>) -> Result<(), String>) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let temp = temp_file_for(path);
    let result = (|| {
        let mut dst = std::io::BufWriter::new(File::create(&temp).map_err(io)?);
        body(src, &mut dst)?;
        dst.flush().map_err(io)
    })();
    if let Err(e) = result {
        let _ = std::fs::remove_file(&temp);
        return Err(e);
    }
    replace_file_with(&temp, path)
}

/// ID3v2 at the start, APE tag and ID3v1 at the end.
// from: StripEnds
fn strip_ends(path: &Path) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut s = File::open(path).map_err(io)?;
    let start = parse_id3v2(&mut s).map_err(io)?.1 as i64;
    let stop = find_ape_tag(&mut s).map_err(io)?.audio_end;
    let size = stream_size(&mut s).map_err(io)? as i64;
    if start == 0 && stop == size {
        return Ok(()); // no tags
    }
    if stop <= start {
        return Err("Uventet tag-struktur".into());
    }
    rewrite(path, s, |mut s, dst| copy_range(&mut s, dst, start as u64, (stop - start) as u64))
}

/// ID3/LIST-INFO chunks and, for AIFF, the NAME/AUTH/ANNO/(c) text chunks.
// from: IsRemovedChunk
fn is_removed_chunk(s: &mut File, cf: &ChunkFile, c: &Chunk) -> Result<bool, String> {
    if is_id3_chunk_id(&c.id) {
        return Ok(true);
    }
    if c.id == "LIST" && c.size >= 4 {
        let h = read_at(s, c.data_pos as u64, 4).map_err(|e| e.to_string())?;
        if bytes_are(&h, 0, "INFO") {
            return Ok(true);
        }
    }
    Ok(cf.is_aiff && ["NAME", "AUTH", "ANNO", "(c) "].contains(&c.id.as_str()))
}

// from: StripChunks
fn strip_chunks(path: &Path) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut s = File::open(path).map_err(io)?;
    let cf = read_chunk_file(&mut s)?;
    let mut removed = Vec::new();
    for c in &cf.chunks {
        removed.push(is_removed_chunk(&mut s, &cf, c)?);
    }
    if !removed.iter().any(|&r| r) {
        return Ok(());
    }
    let temp = temp_file_for(path);
    let result = (|| -> Result<(), String> {
        let mut dst = File::create(&temp).map_err(io)?;
        {
            let mut w = std::io::BufWriter::new(&mut dst);
            w.write_all(if cf.is_aiff { b"FORM" } else { b"RIFF" }).map_err(io)?;
            w.write_all(&[0; 4]).map_err(io)?;
            w.write_all(cf.form_type.as_bytes()).map_err(io)?;
            for (c, r) in cf.chunks.iter().zip(&removed) {
                if *r {
                    continue;
                }
                w.write_all(c.id.as_bytes()).map_err(io)?;
                let size = c.size as u32;
                w.write_all(&if cf.is_aiff { size.to_be_bytes() } else { size.to_le_bytes() }).map_err(io)?;
                copy_range(&mut s, &mut w, c.data_pos as u64, c.size as u64)?;
                if c.size % 2 == 1 {
                    w.write_all(&[0]).map_err(io)?;
                }
            }
            w.flush().map_err(io)?;
        }
        let len = dst.metadata().map_err(io)?.len() as u32 - 8;
        dst.seek(SeekFrom::Start(4)).map_err(io)?;
        dst.write_all(&if cf.is_aiff { len.to_be_bytes() } else { len.to_le_bytes() }).map_err(io)
    })();
    drop(s);
    if let Err(e) = result {
        let _ = std::fs::remove_file(&temp);
        return Err(e);
    }
    replace_file_with(&temp, path)
}

// from: ClearFields — everything but ReplayGain, and no pictures
fn clear_fields(path: &Path, opt: &WriteOptions) -> Result<(), String> {
    let mut info = read_audio_info(path, true);
    if !info.error.is_empty() {
        return Err(info.error);
    }
    for f in TagField::ALL {
        if !matches!(f, TagField::RgTrackGain | TagField::RgTrackPeak | TagField::RgAlbumGain | TagField::RgAlbumPeak) {
            info.put(f, "");
        }
    }
    info.pictures.clear();
    write_audio_tags(&mut info, opt)
}

/// `opt` gives the settings the write of other formats uses (1.2's globals) and KeepTimestamp.
// from: RemoveAllTags
pub fn remove_all_tags(path: &Path, opt: &WriteOptions) -> Result<(), String> {
    if !removes_whole_tag(path) {
        if !can_write_tags(path) {
            return Err("Skrivning af denne filtype understøttes ikke endnu".into());
        }
        return clear_fields(path, opt);
    }
    let stamp = if opt.keep_timestamp { get_file_stamp(path) } else { None };
    match ext(path).as_str() {
        "wav" | "aif" | "aiff" | "aifc" => strip_chunks(path)?,
        _ => strip_ends(path)?,
    }
    if let Some(st) = stamp {
        set_file_stamp(path, &st);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tags::id3_write::{build_id3_tag_bytes, write_id3v1};

    /// ID3v2 (title) + one MPEG frame + ID3v1.
    pub(crate) fn mp3_with_tags(dir: &Path) -> std::path::PathBuf {
        let mut i = crate::model::AudioInfo::new(Default::default(), true);
        i.put(TagField::Title, "T");
        let mut v = build_id3_tag_bytes(None, &i, 100, &WriteOptions::default());
        let mut frame = vec![0x11u8; 417];
        frame[..4].copy_from_slice(&[0xFF, 0xFB, 0x90, 0x00]);
        v.extend(&frame);
        let p = dir.join("a.mp3");
        std::fs::write(&p, &v).unwrap();
        write_id3v1(&p, &i, true).unwrap();
        p
    }

    #[test]
    fn remove_tags_keeps_audio_fingerprint() {
        let dir = std::env::temp_dir().join(format!("tidytag-remove-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = mp3_with_tags(&dir);
        remove_all_tags(&p, &WriteOptions::default()).unwrap();
        let out = std::fs::read(&p).unwrap();
        assert_eq!(out.len(), 417);
        assert_eq!(&out[..4], &[0xFF, 0xFB, 0x90, 0x00]);
        assert!(read_audio_info(&p, false).tag_types.is_empty());
        std::fs::remove_dir_all(dir).unwrap();
    }
}
