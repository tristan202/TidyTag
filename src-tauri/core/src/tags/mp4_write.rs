//! Writes the editable fields and cover art into an MP4/M4A file's iTunes metadata
//! (moov/udta/meta/ilst); items we do not edit are kept (port of mp4writer.pas).
//! Growing or shrinking 'moov' moves the audio data when 'moov' sits before 'mdat'; the chunk
//! offset tables (stco/co64) are then corrected. A 'free' atom right after 'moov' is used as
//! slack first, so most edits only touch the start of the file.

use crate::fileio::{copy_range, replace_file_with, temp_file_for};
use crate::model::{is_true_flag, AudioInfo, TagField as F};
use crate::text::{be32, be64, bytes_are, pascal_trim, raw_utf8, read_at, stream_size};
use crate::write::WriteOptions;
use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

const NEW_FREE_SPACE: i64 = 2048;

// from: FourCC — '@' stands for the copyright sign (0xA9)
fn fourcc(s: &str) -> u32 {
    s.bytes().fold(0u32, |r, c| (r << 8) | if c == b'@' { 0xA9 } else { c } as u32)
}

const CONTAINERS: [&str; 8] = ["moov", "trak", "mdia", "minf", "stbl", "udta", "meta", "ilst"];

struct Atom {
    /// four-character code, big endian
    name: u32,
    /// version/flags of full boxes we descend into ('meta')
    prefix: Vec<u8>,
    /// payload of leaf atoms
    data: Vec<u8>,
    children: Vec<Atom>,
}

impl Atom {
    fn new(name: u32) -> Atom {
        Atom { name, prefix: Vec::new(), data: Vec::new(), children: Vec::new() }
    }
    fn is_container(&self) -> bool {
        CONTAINERS.iter().any(|c| fourcc(c) == self.name)
    }
    fn find(&mut self, name: u32) -> Option<usize> {
        self.children.iter().position(|c| c.name == name)
    }
    fn child(&mut self, name: u32, make: impl FnOnce() -> Atom) -> &mut Atom {
        let i = match self.find(name) {
            Some(i) => i,
            None => {
                self.children.push(make());
                self.children.len() - 1
            }
        };
        &mut self.children[i]
    }
    fn total_size(&self) -> i64 {
        8 + self.prefix.len() as i64
            + if self.is_container() { self.children.iter().map(Atom::total_size).sum() } else { self.data.len() as i64 }
    }
    // from: TAtom.WriteTo
    fn write_to(&self, s: &mut Vec<u8>) -> Result<(), String> {
        let size = self.total_size();
        if size > 0xFFFF_FFFF {
            return Err("Metadata-atom er for stor".into());
        }
        s.extend((size as u32).to_be_bytes());
        s.extend(self.name.to_be_bytes());
        s.extend(&self.prefix);
        if self.is_container() {
            for c in &self.children {
                c.write_to(s)?;
            }
        } else {
            s.extend(&self.data);
        }
        Ok(())
    }
}

/// Parses the atoms in b[p..limit) into parent.
// from: ParseChildren
fn parse_children(parent: &mut Atom, b: &[u8], mut p: i64, limit: i64) -> Result<(), String> {
    while p + 8 <= limit {
        let mut size = be32(b, p) as i64;
        let mut hdr = 8;
        if size == 1 {
            size = be64(b, p + 8) as i64;
            hdr = 16;
        } else if size == 0 {
            size = limit - p;
        }
        if size < hdr || p + size > limit {
            return Err("Ugyldig atom-struktur i moov".into());
        }
        let mut a = Atom::new(be32(b, p + 4));
        let mut body = p + hdr;
        if a.is_container() {
            // Normally a full box; QuickTime-style 'meta' has no version/flags.
            if a.name == fourcc("meta") && !bytes_are(b, body + 4, "hdlr") {
                a.prefix = b[body as usize..(body + 4).min(b.len() as i64) as usize].to_vec();
                body += 4;
            }
            parse_children(&mut a, b, body, p + size)?;
        } else {
            a.data = b[body as usize..(p + size) as usize].to_vec();
        }
        parent.children.push(a);
        p += size;
    }
    Ok(())
}

// from: DataAtom
fn data_atom(type_code: u32, payload: &[u8]) -> Atom {
    let mut a = Atom::new(fourcc("data"));
    a.data.extend(type_code.to_be_bytes());
    a.data.extend(0u32.to_be_bytes()); // locale
    a.data.extend(payload);
    a
}

/// ilst items are containers of 'data' atoms; we build them as leafs with ready bytes.
// from: ItemAtom
fn item_atom(name: &str, items: &[Atom]) -> Result<Atom, String> {
    let mut a = Atom::new(fourcc(name));
    for d in items {
        d.write_to(&mut a.data)?;
    }
    Ok(a)
}

fn add_text(ilst: &mut Atom, name: &str, value: &str) -> Result<(), String> {
    if !value.is_empty() {
        ilst.children.push(item_atom(name, &[data_atom(1, value.as_bytes())])?);
    }
    Ok(())
}

// from: AddNumberPair
fn add_number_pair(ilst: &mut Atom, name: &str, value: &str, extra_zero: bool) -> Result<(), String> {
    if value.is_empty() {
        return Ok(());
    }
    let num = |s: &str| pascal_trim(s).parse::<i64>().unwrap_or(0);
    let (n, t) = match value.find('/') {
        Some(s) => (num(&value[..s]), num(&value[s + 1..])),
        None => (num(value), 0),
    };
    if n <= 0 || n > 0xFFFF || !(0..=0xFFFF).contains(&t) {
        return Ok(());
    }
    let mut b = vec![0u8, 0];
    b.extend((n as u16).to_be_bytes());
    b.extend((t as u16).to_be_bytes());
    if extra_zero {
        b.extend([0, 0]); // trkn has 8 bytes, disk 6
    }
    ilst.children.push(item_atom(name, &[data_atom(0, &b)])?);
    Ok(())
}

// from: IsManagedItem
fn is_managed_item(name: u32) -> bool {
    ["@nam", "@ART", "@alb", "@day", "@gen", "gnre", "@cmt", "aART", "@wrt", "trkn", "disk", "tmpo", "covr", "@lyr",
        "cprt", "@grp", "sonm", "soar", "soaa", "soal", "soco", "cpil", "pcst"]
        .iter()
        .any(|n| fourcc(n) == name)
}

/// Freeform names (----:com.apple.iTunes:NAME) we edit; others are kept.
const MANAGED_FREEFORM: [&str; 18] = [
    "CONDUCTOR", "LYRICIST", "ORIGINALARTIST", "ORIGINAL ARTIST", "REMIXER", "LABEL", "PUBLISHER", "CATALOGNUMBER",
    "ISRC", "ENCODEDBY", "URL", "SUBTITLE", "MOOD", "INITIALKEY", "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK",
    "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK",
];

/// The 'name' of a freeform item, upper case; '' if it has none.
// from: FreeformName
fn freeform_name(item: &Atom) -> String {
    let d = &item.data;
    let mut p: i64 = 0;
    while p + 8 <= d.len() as i64 {
        let size = be32(d, p) as i64;
        if size < 8 || p + size > d.len() as i64 {
            return String::new();
        }
        if bytes_are(d, p + 4, "name") && size > 12 {
            return raw_utf8(d, p + 12, size - 12).to_ascii_uppercase();
        }
        p += size;
    }
    String::new()
}

fn is_managed_freeform(item: &Atom) -> bool {
    item.name == fourcc("----") && MANAGED_FREEFORM.contains(&freeform_name(item).as_str())
}

// from: PrefixedAtom
fn prefixed_atom(name: &str, text: &str) -> Atom {
    let mut a = Atom::new(fourcc(name));
    a.data.extend(0u32.to_be_bytes()); // version/flags
    a.data.extend(text.as_bytes());
    a
}

fn add_freeform(ilst: &mut Atom, name: &str, value: &str) -> Result<(), String> {
    if !value.is_empty() {
        let items = [prefixed_atom("mean", "com.apple.iTunes"), prefixed_atom("name", name), data_atom(1, value.as_bytes())];
        ilst.children.push(item_atom("----", &items)?);
    }
    Ok(())
}

// from: NewHdlr
fn new_hdlr() -> Atom {
    let mut a = Atom::new(fourcc("hdlr"));
    a.data.extend([0u8; 8]); // version/flags, pre-defined
    a.data.extend(b"mdirappl");
    a.data.extend([0u8; 9]); // reserved, empty name
    a
}

// from: UpdateIlst
fn update_ilst(moov: &mut Atom, info: &AudioInfo) -> Result<(), String> {
    let udta = moov.child(fourcc("udta"), || Atom::new(fourcc("udta")));
    let meta = udta.child(fourcc("meta"), || {
        let mut m = Atom::new(fourcc("meta"));
        m.prefix = vec![0; 4];
        m.children.push(new_hdlr());
        m
    });
    let ilst = meta.child(fourcc("ilst"), || Atom::new(fourcc("ilst")));
    // keep the items we do not edit
    ilst.children.retain(|c| !(is_managed_item(c.name) || is_managed_freeform(c)));

    let f = |t: F| info.field(t);
    add_text(ilst, "@nam", f(F::Title))?;
    add_text(ilst, "@ART", f(F::Artist))?;
    add_text(ilst, "@alb", f(F::Album))?;
    add_text(ilst, "aART", f(F::AlbumArtist))?;
    add_text(ilst, "@day", f(F::Year))?;
    add_number_pair(ilst, "trkn", f(F::Track), true)?;
    add_number_pair(ilst, "disk", f(F::Disc), false)?;
    add_text(ilst, "@gen", f(F::Genre))?;
    add_text(ilst, "@wrt", f(F::Composer))?;
    add_text(ilst, "@cmt", f(F::Comment))?;
    add_text(ilst, "@lyr", f(F::Lyrics))?;
    add_text(ilst, "cprt", f(F::Copyright))?;
    add_text(ilst, "@grp", f(F::Grouping))?;
    add_text(ilst, "sonm", f(F::SortTitle))?;
    add_text(ilst, "soar", f(F::SortArtist))?;
    add_text(ilst, "soaa", f(F::SortAlbumArtist))?;
    add_text(ilst, "soal", f(F::SortAlbum))?;
    add_text(ilst, "soco", f(F::SortComposer))?;
    for (n, t) in [("CONDUCTOR", F::Conductor), ("LYRICIST", F::Lyricist), ("ORIGINALARTIST", F::OrigArtist),
        ("REMIXER", F::Remixer), ("LABEL", F::Publisher), ("CATALOGNUMBER", F::CatalogNo), ("ISRC", F::Isrc),
        ("ENCODEDBY", F::EncodedBy), ("URL", F::Url), ("SUBTITLE", F::Subtitle), ("MOOD", F::Mood),
        ("initialkey", F::InitialKey)]
    {
        add_freeform(ilst, n, f(t))?;
    }
    let bpm = pascal_trim(f(F::Bpm)).parse::<i64>().unwrap_or(0);
    if bpm > 0 && bpm <= 0xFFFF {
        ilst.children.push(item_atom("tmpo", &[data_atom(21, &(bpm as u16).to_be_bytes())])?);
    }
    for (n, t) in [("replaygain_track_gain", F::RgTrackGain), ("replaygain_track_peak", F::RgTrackPeak),
        ("replaygain_album_gain", F::RgAlbumGain), ("replaygain_album_peak", F::RgAlbumPeak)]
    {
        add_freeform(ilst, n, f(t))?;
    }
    // flags: one byte, data type 21 (integer)
    if is_true_flag(f(F::Compilation)) {
        ilst.children.push(item_atom("cpil", &[data_atom(21, &[1])])?);
    }
    if is_true_flag(f(F::Podcast)) {
        ilst.children.push(item_atom("pcst", &[data_atom(21, &[1])])?);
    }
    if !info.pictures.is_empty() {
        let covers: Vec<Atom> =
            info.pictures.iter().map(|p| data_atom(if p.mime == "image/png" { 14 } else { 13 }, &p.data)).collect();
        ilst.children.push(item_atom("covr", &covers)?);
    }
    Ok(())
}

/// Adds delta to every chunk offset >= threshold in all stco/co64 tables below a.
// from: ShiftChunkOffsets
fn shift_chunk_offsets(a: &mut Atom, delta: i64, threshold: i64) -> Result<(), String> {
    for c in &mut a.children {
        if c.is_container() {
            shift_chunk_offsets(c, delta, threshold)?;
        } else if c.name == fourcc("stco") {
            let n = be32(&c.data, 4) as i64;
            if 8 + n * 4 > c.data.len() as i64 {
                return Err("Ugyldig stco-tabel".into());
            }
            for j in 0..n {
                let at = (8 + j * 4) as usize;
                let v = be32(&c.data, at as i64) as i64;
                if v < threshold {
                    continue;
                }
                if v + delta > 0xFFFF_FFFF {
                    return Err("Filen bliver for stor til 32-bit chunk-offsets".into());
                }
                c.data[at..at + 4].copy_from_slice(&((v + delta) as u32).to_be_bytes());
            }
        } else if c.name == fourcc("co64") {
            let n = be32(&c.data, 4) as i64;
            if 8 + n * 8 > c.data.len() as i64 {
                return Err("Ugyldig co64-tabel".into());
            }
            for j in 0..n {
                let at = (8 + j * 8) as usize;
                let v = be64(&c.data, at as i64) as i64;
                if v >= threshold {
                    c.data[at..at + 8].copy_from_slice(&((v + delta) as u64).to_be_bytes());
                }
            }
        }
    }
    Ok(())
}

struct Top {
    name: u32,
    pos: i64,
    size: i64,
}

// from: WriteMp4Tags
pub fn write(path: &Path, info: &AudioInfo, _opt: &WriteOptions) -> Result<(), String> {
    let io = |e: std::io::Error| e.to_string();
    let mut src = File::open(path).map_err(io)?;
    let fsize = stream_size(&mut src).map_err(io)? as i64;
    // top-level atom list
    let mut top: Vec<Top> = Vec::new();
    let mut pos = 0i64;
    while pos + 8 <= fsize {
        let h = read_at(&mut src, pos as u64, 16).map_err(io)?;
        let mut size = be32(&h, 0) as i64;
        let mut hdr = 8;
        if size == 1 {
            size = be64(&h, 8) as i64;
            hdr = 16;
        } else if size == 0 {
            size = fsize - pos;
        }
        if size < hdr || pos + size > fsize {
            return Err("Ugyldig MP4-struktur".into());
        }
        top.push(Top { name: be32(&h, 4), pos, size });
        pos += size;
    }
    let mut moov_idx: Option<usize> = None;
    for (i, t) in top.iter().enumerate() {
        if t.name == fourcc("moov") && moov_idx.is_none() {
            moov_idx = Some(i);
        }
        if t.name == fourcc("moof") {
            return Err("Fragmenterede MP4-filer understøttes ikke".into());
        }
    }
    let Some(mi) = moov_idx else { return Err("Ingen moov-atom - ikke en gyldig MP4-fil".into()) };
    let h = read_at(&mut src, top[mi].pos as u64, 16).map_err(io)?;
    let hdr = if be32(&h, 0) == 1 { 16 } else { 8 };
    let moov_bytes = read_at(&mut src, (top[mi].pos + hdr) as u64, (top[mi].size - hdr) as u64).map_err(io)?;
    let mut moov = Atom::new(fourcc("moov")); // the root stands in for 'moov' itself
    parse_children(&mut moov, &moov_bytes, 0, moov_bytes.len() as i64)?;

    update_ilst(&mut moov, info)?;
    let mut delta = moov.total_size() - top[mi].size;

    // Use a following 'free' atom as slack, so nothing behind it moves.
    let last = mi == top.len() - 1;
    let free_follows = !last && top[mi + 1].name == fourcc("free");
    let mut new_free: i64 = -1;
    if free_follows {
        new_free = top[mi + 1].size - delta;
        if new_free != 0 && new_free < 8 {
            new_free = -1; // does not fit
        }
    }

    let mut new_moov = Vec::new();
    if delta == 0 || new_free >= 0 || last {
        // In place: moov (+ shrunk/grown free) occupy exactly the old space, or moov is last.
        moov.write_to(&mut new_moov)?;
        if delta != 0 && new_free > 0 {
            new_moov.extend((new_free as u32).to_be_bytes());
            new_moov.extend(b"free");
            new_moov.resize(new_moov.len() + (new_free - 8) as usize, 0);
        }
        drop(src);
        let mut dst = OpenOptions::new().write(true).open(path).map_err(io)?;
        dst.seek(SeekFrom::Start(top[mi].pos as u64)).map_err(io)?;
        dst.write_all(&new_moov).map_err(io)?;
        if last && delta != 0 && new_free < 0 {
            dst.set_len((top[mi].pos + new_moov.len() as i64) as u64).map_err(io)?; // moov was last
        }
    } else {
        // Rewrite: moov + fresh free space; shift chunk offsets if the audio moves.
        delta += 8 + NEW_FREE_SPACE;
        if free_follows {
            delta -= top[mi + 1].size; // old free is dropped
        }
        // Only data stored after the old moov moves.
        shift_chunk_offsets(&mut moov, delta, top[mi].pos)?;
        moov.write_to(&mut new_moov)?;
        new_moov.extend(((8 + NEW_FREE_SPACE) as u32).to_be_bytes());
        new_moov.extend(b"free");
        new_moov.resize(new_moov.len() + NEW_FREE_SPACE as usize, 0);
        let temp = temp_file_for(path);
        let result = (|| -> Result<(), String> {
            let mut dst = std::io::BufWriter::new(File::create(&temp).map_err(io)?);
            for (i, t) in top.iter().enumerate() {
                if i == mi {
                    dst.write_all(&new_moov).map_err(io)?;
                } else if free_follows && i == mi + 1 {
                    continue;
                } else {
                    copy_range(&mut src, &mut dst, t.pos as u64, t.size as u64)?;
                }
            }
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

    fn atom(name: &[u8], body: &[u8]) -> Vec<u8> {
        let mut v = ((body.len() + 8) as u32).to_be_bytes().to_vec();
        v.extend(name);
        v.extend(body);
        v
    }

    /// ftyp, moov (with a stco pointing at the two chunks in mdat, and an unknown freeform item),
    /// optionally a free atom, then mdat.
    fn mp4(free: usize) -> (Vec<u8>, usize) {
        let mut ff = atom(b"mean", b"\0\0\0\0com.apple.iTunes");
        ff.extend(atom(b"name", b"\0\0\0\0MyOwn"));
        let mut d = 1u32.to_be_bytes().to_vec();
        d.extend([0, 0, 0, 0]);
        d.extend(b"keep me");
        ff.extend(atom(b"data", &d));
        let ilst = atom(b"ilst", &atom(b"----", &ff));
        let mut meta = vec![0u8; 4];
        meta.extend(atom(b"hdlr", &[0u8; 25]));
        meta.extend(ilst);
        let udta = atom(b"udta", &atom(b"meta", &meta));
        let ftyp = atom(b"ftyp", b"M4A \0\0\0\0M4A mp42");
        // first pass to know where mdat starts
        let stco = |off: u32| {
            let mut b = vec![0u8; 4];
            b.extend(2u32.to_be_bytes());
            b.extend(off.to_be_bytes());
            b.extend((off + 4).to_be_bytes());
            atom(b"stco", &b)
        };
        let build = |off: u32| {
            let stbl = atom(b"stbl", &stco(off));
            let trak = atom(b"trak", &atom(b"mdia", &atom(b"minf", &stbl)));
            let mut moov_body = trak;
            moov_body.extend(udta.clone());
            atom(b"moov", &moov_body)
        };
        let moov_len = build(0).len();
        let free_atom = if free > 0 { atom(b"free", &vec![0; free - 8]) } else { Vec::new() };
        let mdat_data_at = ftyp.len() + moov_len + free_atom.len() + 8;
        let mut file = ftyp.clone();
        file.extend(build(mdat_data_at as u32));
        file.extend(&free_atom);
        file.extend(atom(b"mdat", b"AAAABBBB"));
        (file, mdat_data_at)
    }

    fn edit(file: &[u8], f: impl Fn(&mut AudioInfo)) -> Vec<u8> {
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!("tidytag-mp4w-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("a.m4a");
        std::fs::write(&p, file).unwrap();
        let mut info = read_audio_info(&p, true);
        f(&mut info);
        write(&p, &info, &WriteOptions::default()).unwrap();
        let out = std::fs::read(&p).unwrap();
        std::fs::remove_dir_all(dir).unwrap();
        out
    }

    fn stco_offsets(file: &[u8]) -> Vec<u32> {
        let i = file.windows(4).position(|w| w == b"stco").unwrap();
        vec![be32(file, i as i64 + 12), be32(file, i as i64 + 16)]
    }

    #[test]
    fn stco_shifted_when_moov_first() {
        let (file, at) = mp4(0);
        let out = edit(&file, |i| crate::batch::set_front_cover(i, test_png(10_000)));
        let offs = stco_offsets(&out);
        assert_eq!(&out[offs[0] as usize..offs[0] as usize + 4], b"AAAA");
        assert_eq!(&out[offs[1] as usize..offs[1] as usize + 4], b"BBBB");
        assert!(offs[0] as usize > at);
    }

    #[test]
    fn free_atom_used_as_slack() {
        let (file, _) = mp4(500);
        let out = edit(&file, |i| i.put(F::Title, "Hej"));
        assert_eq!(out.len(), file.len()); // nothing behind the free atom moved
        assert_eq!(stco_offsets(&out), stco_offsets(&file));
    }

    #[test]
    fn freeform_kept() {
        let (file, _) = mp4(0);
        let out = edit(&file, |i| i.put(F::Title, "x"));
        assert!(out.windows(7).any(|w| w == b"keep me"));
    }
}
