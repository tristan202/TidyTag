//! Writes Vorbis comments (incl. pictures as METADATA_BLOCK_PICTURE) into Ogg Vorbis and Ogg
//! Opus files (port of oggwriter.pas). The comment header packet (plus the Vorbis setup header
//! that shares its pages) is put on new pages; all following pages of the stream get new
//! sequence numbers and checksums. Audio data is copied unchanged. The file is always rewritten
//! via a temporary file. Multiplexed/chained streams and Ogg FLAC are refused.

use super::flac_write::build_vorbis_comment;
use crate::fileio::{copy_range, replace_file_with, temp_file_for};
use crate::model::AudioInfo;
use crate::text::{bytes_are, le32, read_at, stream_size};
use crate::write::WriteOptions;
use std::fs::File;
use std::io::Write;
use std::path::Path;
use std::sync::OnceLock;

fn crc_table() -> &'static [u32; 256] {
    static T: OnceLock<[u32; 256]> = OnceLock::new();
    T.get_or_init(|| {
        let mut t = [0u32; 256];
        for (i, e) in t.iter_mut().enumerate() {
            let mut r = (i as u32) << 24;
            for _ in 0..8 {
                r = if r & 0x8000_0000 != 0 { (r << 1) ^ 0x04C1_1DB7 } else { r << 1 };
            }
            *e = r;
        }
        t
    })
}

/// Ogg page checksum over the whole page with the CRC field set to zero.
// from: OggCrc
pub fn ogg_crc(b: &[u8]) -> u32 {
    let t = crc_table();
    b.iter().fold(0u32, |r, &c| (r << 8) ^ t[(((r >> 24) ^ c as u32) & 0xFF) as usize])
}

struct Page {
    /// complete page as read (header, segment table, data)
    raw: Vec<u8>,
    header_type: u8,
    serial: u32,
    seq: u32,
    segs: Vec<u8>,
    /// start of the data inside raw
    data_ofs: usize,
}

/// Reads the page at `*pos`; None at the end of the file.
// from: ReadPage
fn read_page(s: &mut File, pos: &mut u64) -> Result<Option<Page>, String> {
    let io = |e: std::io::Error| e.to_string();
    let h = read_at(s, *pos, 27).map_err(io)?;
    if h.is_empty() {
        return Ok(None);
    }
    if h.len() < 27 || !bytes_are(&h, 0, "OggS") {
        return Err("Ugyldig Ogg-side (filen er beskadiget eller ikke Ogg)".into());
    }
    let n = h[26] as u64;
    let segs = read_at(s, *pos + 27, n).map_err(io)?;
    let data_len: u64 = segs.iter().map(|&x| x as u64).sum();
    let data = read_at(s, *pos + 27 + segs.len() as u64, data_len).map_err(io)?;
    if (segs.len() as u64) < n || (data.len() as u64) < data_len {
        return Err("Ogg-filen er afkortet".into());
    }
    let mut raw = h.clone();
    raw.extend(&segs);
    raw.extend(&data);
    *pos += raw.len() as u64;
    Ok(Some(Page { header_type: h[5], serial: le32(&h, 14), seq: le32(&h, 18), data_ofs: 27 + n as usize, segs, raw }))
}

// from: SetSeqAndCrc
fn set_seq_and_crc(raw: &mut [u8], seq: u32) {
    raw[18..22].copy_from_slice(&seq.to_le_bytes());
    raw[22..26].fill(0);
    let crc = ogg_crc(raw);
    raw[22..26].copy_from_slice(&crc.to_le_bytes());
}

/// Lays out packets on new pages (max 255 segments each), starting at sequence `first_seq`.
/// Returns the number of pages written.
// from: WritePackets
fn write_packets(dest: &mut impl Write, packets: &[Vec<u8>], serial: u32, first_seq: u32) -> Result<usize, String> {
    let mut lacing: Vec<u8> = Vec::new();
    let mut ends: Vec<bool> = Vec::new(); // segment i ends a packet
    let mut all = Vec::new();
    for p in packets {
        let mut len = p.len();
        loop {
            let l = len.min(255) as u8;
            lacing.push(l);
            len -= l as usize;
            ends.push(l < 255);
            if l < 255 {
                break;
            }
        }
        all.extend(p);
    }
    let (mut pages, mut seq, mut seg_start, mut data_pos, mut continued) = (0, first_seq, 0usize, 0usize, false);
    while seg_start < lacing.len() {
        let seg_count = (lacing.len() - seg_start).min(255);
        let page_data: usize = lacing[seg_start..seg_start + seg_count].iter().map(|&x| x as usize).sum();
        let any_end = ends[seg_start..seg_start + seg_count].iter().any(|&e| e);
        let mut page = vec![0u8; 27 + seg_count + page_data];
        page[..4].copy_from_slice(b"OggS");
        page[5] = continued as u8;
        // header pages: granule 0 when a packet ends here, else -1 ("no packet completes")
        if !any_end {
            page[6..14].fill(0xFF);
        }
        page[14..18].copy_from_slice(&serial.to_le_bytes());
        page[26] = seg_count as u8;
        page[27..27 + seg_count].copy_from_slice(&lacing[seg_start..seg_start + seg_count]);
        page[27 + seg_count..].copy_from_slice(&all[data_pos..data_pos + page_data]);
        set_seq_and_crc(&mut page, seq);
        dest.write_all(&page).map_err(|e| e.to_string())?;
        pages += 1;
        seq = seq.wrapping_add(1);
        data_pos += page_data;
        continued = !ends[seg_start + seg_count - 1];
        seg_start += seg_count;
    }
    Ok(pages)
}

// from: WriteOggTags
pub fn write(path: &Path, info: &AudioInfo, _opt: &WriteOptions) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut src = File::open(path).map_err(io)?;
    let mut pos = 0u64;
    // ---- read the header packets
    let first = match read_page(&mut src, &mut pos)? {
        Some(p) if p.header_type & 2 != 0 => p,
        _ => return Err("Ugyldig Ogg-fil".into()),
    };
    let serial = first.serial;
    if first.segs.last().is_none_or(|&l| l == 255) {
        return Err("Uventet Ogg-struktur (identifikationspakken fylder mere end én side)".into());
    }
    let body = &first.raw[first.data_ofs..];
    let (is_opus, needed) = if body.len() >= 7 && body[0] == 1 && bytes_are(body, 1, "vorbis") {
        (false, 2) // comment + setup after the identification packet
    } else if bytes_are(body, 0, "OpusHead") {
        (true, 1) // tags
    } else {
        return Err("Kun Ogg Vorbis og Ogg Opus kan gemmes".into());
    };
    if first.segs.len() > 1 {
        // the first page must hold the identification packet only
        let i = first.segs.iter().take_while(|&&s| s == 255).count();
        if i != first.segs.len() - 1 {
            return Err("Uventet Ogg-struktur (første side)".into());
        }
    }

    let mut packets: Vec<Vec<u8>> = Vec::new();
    let mut cur = Vec::new();
    let mut header_pages = 1;
    'pages: loop {
        let Some(pg) = read_page(&mut src, &mut pos)? else {
            return Err("Ogg-filen slutter før header-pakkerne".into());
        };
        if pg.serial != serial {
            return Err("Ogg-filer med flere strømme kan ikke gemmes endnu".into());
        }
        header_pages += 1;
        let mut off = 0usize;
        for (i, &seg) in pg.segs.iter().enumerate() {
            cur.extend(&pg.raw[pg.data_ofs + off..pg.data_ofs + off + seg as usize]);
            off += seg as usize;
            if seg < 255 {
                packets.push(std::mem::take(&mut cur));
                if packets.len() == needed {
                    if i != pg.segs.len() - 1 {
                        return Err("Uventet Ogg-struktur (lyd på samme side som header)".into());
                    }
                    break 'pages;
                }
            }
        }
    }

    // ---- new comment packet (pictures as base64 METADATA_BLOCK_PICTURE)
    let mut nc = Vec::new();
    if is_opus {
        if !bytes_are(&packets[0], 0, "OpusTags") {
            return Err("Mangler OpusTags".into());
        }
        nc.extend(b"OpusTags");
        nc.extend(build_vorbis_comment(Some(&packets[0]), 8, info, true));
    } else {
        if packets[0].first() != Some(&3) || !bytes_are(&packets[0], 1, "vorbis") {
            return Err("Mangler Vorbis-kommentarpakken".into());
        }
        nc.push(3);
        nc.extend(b"vorbis");
        nc.extend(build_vorbis_comment(Some(&packets[0]), 7, info, true));
        nc.push(1); // framing bit
    }
    packets[0] = nc;

    // ---- write: first page, new header pages, then the rest renumbered
    let temp = temp_file_for(path);
    let result = (|| -> Result<(), String> {
        let mut dst = std::io::BufWriter::new(File::create(&temp).map_err(io)?);
        dst.write_all(&first.raw).map_err(io)?;
        let new_pages = write_packets(&mut dst, &packets, serial, 1)?;
        let delta = new_pages as i64 - (header_pages - 1) as i64;
        if delta == 0 {
            // same page count: the audio pages stay byte for byte
            let size = stream_size(&mut src).map_err(io)?;
            copy_range(&mut src, &mut dst, pos, size - pos)?;
        } else {
            while let Some(mut pg) = read_page(&mut src, &mut pos)? {
                if pg.serial != serial {
                    return Err("Ogg-filer med flere strømme kan ikke gemmes endnu".into());
                }
                set_seq_and_crc(&mut pg.raw, (pg.seq as i64 + delta) as u32);
                dst.write_all(&pg.raw).map_err(io)?;
            }
        }
        dst.flush().map_err(io)
    })();
    drop(src);
    if let Err(e) = result {
        let _ = std::fs::remove_file(&temp);
        return Err(e);
    }
    replace_file_with(&temp, path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::TagField;
    use std::path::PathBuf;

    #[test]
    fn ogg_crc_check_value() {
        // CRC-32 poly 0x04C11DB7, init 0, no reflection, no final xor: check = 0x89A1897F
        assert_eq!(ogg_crc(b"123456789"), 0x89A1_897F);
    }

    #[test]
    fn opus_writes_r128() {
        let mut i = AudioInfo::new(PathBuf::new(), true);
        i.codec = "Opus".into();
        i.put(TagField::RgTrackGain, "3.00 dB");
        i.put(TagField::RgTrackPeak, "0.5");
        let c = build_vorbis_comment(None, 0, &i, true);
        let has = |s: &[u8]| c.windows(s.len()).any(|w| w == s);
        assert!(has(b"R128_TRACK_GAIN=-512"));
        assert!(!has(b"REPLAYGAIN_TRACK_PEAK"));
    }

    #[test]
    fn ogg_flac_refused() {
        let dir = std::env::temp_dir().join(format!("tidytag-oggw-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.oga");
        let mut packet = vec![0x7F];
        packet.extend(b"FLAC");
        packet.resize(51, 0);
        let mut f = Vec::new();
        write_packets(&mut f, &[packet], 7, 0).unwrap();
        f[5] = 2; // beginning of stream
        std::fs::write(&p, &f).unwrap();
        let info = AudioInfo::new(p.clone(), true);
        assert_eq!(write(&p, &info, &WriteOptions::default()).unwrap_err(), "Kun Ogg Vorbis og Ogg Opus kan gemmes");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
