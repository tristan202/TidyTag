//! Writes tags into WAV and AIFF files (port of wavwriter.pas): an ID3v2 chunk (all fields and
//! pictures) and, for WAV, a LIST/INFO chunk with the basic fields so that Windows and older
//! players show them too. Both chunks are placed after the audio. When the tag chunks already
//! are the last chunks the file is updated in place (cut and appended); otherwise it is
//! rewritten via a temporary file. Audio and other chunks are copied unchanged.

use super::id3_write::build_id3_tag_bytes;
use super::riff::{info_field, is_id3_chunk_id, read_chunk_file, Chunk};
use crate::fileio::{copy_range, replace_file_with, temp_file_for};
use crate::model::AudioInfo;
use crate::text::{bytes_are, bytes_to_ascii, le32, read_at, stream_size};
use crate::write::WriteOptions;
use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

const TOO_BIG: &str = "Filen bliver større end 4 GB, hvilket WAV/AIFF ikke tillader";

// from: WriteSize
fn size_bytes(v: u64, big_endian: bool) -> Result<[u8; 4], String> {
    if v > u32::MAX as u64 {
        return Err(TOO_BIG.into());
    }
    Ok(if big_endian { (v as u32).to_be_bytes() } else { (v as u32).to_le_bytes() })
}

// from: WriteChunk
fn write_chunk(s: &mut Vec<u8>, id: &str, data: &[u8], big_endian: bool) -> Result<(), String> {
    s.extend(id.as_bytes());
    s.extend(size_bytes(data.len() as u64, big_endian)?);
    s.extend(data);
    if data.len() % 2 == 1 {
        s.push(0);
    }
    Ok(())
}

/// Text for an INFO item: Latin-1 when every character fits, else UTF-8; zero-terminated.
// from: InfoBytes
fn info_bytes(value: &str) -> Vec<u8> {
    let w: Vec<u16> = value.encode_utf16().collect();
    let latin = w.iter().all(|&u| u <= 0xFF && !(0x80..0xA0).contains(&u));
    let mut r: Vec<u8> = if latin { w.iter().map(|&u| u as u8).collect() } else { value.as_bytes().to_vec() };
    r.push(0);
    r
}

/// New LIST/INFO body: unmanaged items of the old list are kept, managed ones rebuilt.
/// None when the list would be empty.
// from: BuildInfoList
fn build_info_list(old: &[u8], info: &AudioInfo) -> Result<Option<Vec<u8>>, String> {
    const ITEMS: [&str; 10] = ["INAM", "IART", "IPRD", "ICRD", "ITRK", "IGNR", "ICMT", "ICOP", "IMUS", "IENC"];
    let mut any = false;
    let mut b = b"INFO".to_vec();
    let mut p: i64 = 4;
    let n = old.len() as i64;
    while p + 8 <= n {
        let id = bytes_to_ascii(old, p, 4);
        let size = le32(old, p + 4) as i64;
        if p + 8 + size > n {
            break;
        }
        if info_field(&id).is_none() {
            write_chunk(&mut b, &id, &old[(p + 8) as usize..(p + 8 + size) as usize], false)?;
            any = true;
        }
        p = p + 8 + size + (size & 1);
    }
    for id in ITEMS {
        if let Some(f) = info_field(id) {
            if !info.field(f).is_empty() {
                write_chunk(&mut b, id, &info_bytes(info.field(f)), false)?;
                any = true;
            }
        }
    }
    Ok(any.then_some(b))
}

/// The ID3 chunk and the RIFF LIST/INFO chunk are the only chunks the writer replaces.
// from: IsTagChunk
fn is_tag_chunk(s: &mut File, c: &Chunk) -> Result<bool, String> {
    if is_id3_chunk_id(&c.id) {
        return Ok(true);
    }
    if c.id == "LIST" && c.size >= 4 {
        let h = read_at(s, c.data_pos as u64, 4).map_err(|e| e.to_string())?;
        return Ok(bytes_are(&h, 0, "INFO"));
    }
    Ok(false)
}

// from: WriteWavAiffTags
pub fn write(path: &Path, info: &AudioInfo, opt: &WriteOptions) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut s = File::open(path).map_err(io)?;
    let cf = read_chunk_file(&mut s)?;
    let mut id3_id = if cf.is_aiff { "ID3 " } else { "id3 " }.to_string();
    let mut old_id3: Option<Vec<u8>> = None;
    let mut old_info: Option<Vec<u8>> = None;
    let mut last_audio: Option<usize> = None;
    let mut tag_flags = Vec::with_capacity(cf.chunks.len());
    for (i, c) in cf.chunks.iter().enumerate() {
        let tag = is_tag_chunk(&mut s, c)?;
        tag_flags.push(tag);
        if tag {
            let data = read_at(&mut s, c.data_pos as u64, c.size.max(0) as u64).map_err(io)?;
            if is_id3_chunk_id(&c.id) {
                if old_id3.is_none() {
                    old_id3 = Some(data).filter(|d| !d.is_empty());
                    id3_id = c.id.clone();
                }
            } else if old_info.is_none() {
                old_info = Some(data).filter(|d| !d.is_empty());
            }
        } else {
            last_audio = Some(i);
        }
    }
    let Some(last_audio) = last_audio else { return Err("Filen indeholder ingen lyd".into()) };

    let new_id3 = build_id3_tag_bytes(old_id3.as_deref(), info, 0, opt);
    let new_info = if cf.is_aiff { None } else { build_info_list(old_info.as_deref().unwrap_or(&[]), info)? };
    let mut tail = Vec::new();
    write_chunk(&mut tail, &id3_id, &new_id3, cf.is_aiff)?;
    if let Some(ni) = &new_info {
        write_chunk(&mut tail, "LIST", ni, false)?;
    }

    // in place when no tag chunk sits before the last audio/other chunk
    let mut in_place = !tag_flags[..last_audio].iter().any(|&t| t);
    let la = &cf.chunks[last_audio];
    let keep_end = la.data_pos + la.size + (la.size & 1);
    let fsize = stream_size(&mut s).map_err(io)? as i64;
    // a truncated last chunk is repaired by the rewrite
    if la.data_pos + la.size > fsize {
        in_place = false;
    }

    if !in_place {
        let temp = temp_file_for(path);
        let result = (|| -> Result<(), String> {
            let mut dst = File::create(&temp).map_err(io)?;
            {
                let mut w = std::io::BufWriter::new(&mut dst);
                w.write_all(if cf.is_aiff { b"FORM" } else { b"RIFF" }).map_err(io)?;
                w.write_all(&size_bytes(0, cf.is_aiff)?).map_err(io)?;
                w.write_all(cf.form_type.as_bytes()).map_err(io)?;
                for (c, tag) in cf.chunks.iter().zip(&tag_flags) {
                    if *tag {
                        continue;
                    }
                    w.write_all(c.id.as_bytes()).map_err(io)?;
                    w.write_all(&size_bytes(c.size as u64, cf.is_aiff)?).map_err(io)?;
                    copy_range(&mut s, &mut w, c.data_pos as u64, c.size as u64)?;
                    if c.size % 2 == 1 {
                        w.write_all(&[0]).map_err(io)?;
                    }
                }
                w.write_all(&tail).map_err(io)?;
                w.flush().map_err(io)?;
            }
            let len = dst.metadata().map_err(io)?.len();
            dst.seek(SeekFrom::Start(4)).map_err(io)?;
            dst.write_all(&size_bytes(len - 8, cf.is_aiff)?).map_err(io)
        })();
        drop(s);
        if let Err(e) = result {
            let _ = std::fs::remove_file(&temp);
            return Err(e);
        }
        return replace_file_with(&temp, path);
    }
    drop(s);

    if keep_end + tail.len() as i64 - 8 > u32::MAX as i64 {
        return Err(TOO_BIG.into());
    }
    let mut s = OpenOptions::new().read(true).write(true).open(path).map_err(io)?;
    s.set_len(keep_end as u64).map_err(io)?; // also restores a missing pad byte after the audio
    s.seek(SeekFrom::Start(keep_end as u64)).map_err(io)?;
    s.write_all(&tail).map_err(io)?;
    let len = keep_end as u64 + tail.len() as u64;
    s.seek(SeekFrom::Start(4)).map_err(io)?;
    s.write_all(&size_bytes(len - 8, cf.is_aiff)?).map_err(io)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TagField as F;
    use crate::read::read_audio_info;

    fn wav(extra_first: &[u8]) -> Vec<u8> {
        let mut fmt = vec![1u8, 0, 2, 0];
        fmt.extend(44100u32.to_le_bytes());
        fmt.extend((44100u32 * 4).to_le_bytes());
        fmt.extend([4, 0, 16, 0]);
        let mut body = b"WAVE".to_vec();
        body.extend(extra_first);
        write_chunk(&mut body, "fmt ", &fmt, false).unwrap();
        write_chunk(&mut body, "data", b"PCMPCMPCM", false).unwrap();
        let mut v = b"RIFF".to_vec();
        v.extend((body.len() as u32).to_le_bytes());
        v.extend(body);
        v
    }

    fn edit(file: &[u8], ext: &str, f: impl Fn(&mut AudioInfo)) -> Vec<u8> {
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("tidytag-riffw-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join(format!("a.{ext}"));
        std::fs::write(&p, file).unwrap();
        let mut info = read_audio_info(&p, true);
        f(&mut info);
        write(&p, &info, &WriteOptions::default()).unwrap();
        let out = std::fs::read(&p).unwrap();
        assert_eq!(read_audio_info(&p, true).field(F::Title), "Hej");
        std::fs::remove_dir_all(dir).unwrap();
        out
    }

    #[test]
    fn tags_after_audio() {
        // an INFO list before the audio forces the rewrite; afterwards the tags are last
        let mut info = b"INFO".to_vec();
        write_chunk(&mut info, "INAM", b"old\0", false).unwrap();
        let mut list = Vec::new();
        write_chunk(&mut list, "LIST", &info, false).unwrap();
        let out = edit(&wav(&list), "wav", |i| i.put(F::Title, "Hej"));
        let data = out.windows(4).position(|w| w == b"data").unwrap();
        let id3 = out.windows(4).position(|w| w == b"id3 ").unwrap();
        assert!(id3 > data);
        assert_eq!(&out[data + 8..data + 17], b"PCMPCMPCM");
    }

    #[test]
    fn riff_size_updated() {
        let out = edit(&wav(&[]), "wav", |i| i.put(F::Title, "Hej"));
        assert_eq!(le32(&out, 4) as usize, out.len() - 8);
    }

    #[test]
    fn aiff_has_no_info_chunk() {
        let mut comm = 2u16.to_be_bytes().to_vec();
        comm.extend(3u32.to_be_bytes());
        comm.extend(16u16.to_be_bytes());
        comm.extend([0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]); // 44100 as 80-bit float
        let mut body = b"AIFF".to_vec();
        write_chunk(&mut body, "COMM", &comm, true).unwrap();
        write_chunk(&mut body, "SSND", b"\x00\x00\x00\x00\x00\x00\x00\x00ABCD", true).unwrap();
        let mut v = b"FORM".to_vec();
        v.extend((body.len() as u32).to_be_bytes());
        v.extend(body);
        let out = edit(&v, "aif", |i| i.put(F::Title, "Hej"));
        assert!(out.windows(4).any(|w| w == b"ID3 "));
        assert!(!out.windows(4).any(|w| w == b"LIST"));
    }
}
