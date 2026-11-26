//! The settings file shared with TidyTag 1.2 (%LOCALAPPDATA%\TidyTag\tidytag.ini).
//! Saving is round-trip safe: the BOM, line endings, section and key order, comments, blank
//! lines and unknown keys stay byte for byte; only changed values are rewritten. Section and
//! key names are case-insensitive, as in TIniFile.

use std::io;
use std::path::{Path, PathBuf};

pub struct Ini {
    path: PathBuf,
    bom: bool,
    newline: &'static str,
    trailing_newline: bool,
    /// the file is not UTF-8 (an old ANSI file): it is read and written as Windows-1252
    ansi: bool,
    lines: Vec<String>,
}

/// Windows-1252 bytes 0x80..0x9F; the five unused ones map to the same code point.
const CP1252: [u32; 32] = [
    0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
    0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];

fn cp1252_char(b: u8) -> char {
    if (0x80..0xA0).contains(&b) { char::from_u32(CP1252[b as usize - 0x80]).unwrap() } else { b as char }
}

fn cp1252_byte(c: char) -> u8 {
    let u = c as u32;
    if let Some(i) = CP1252.iter().position(|&x| x == u) {
        return 0x80 + i as u8;
    }
    if u < 0x100 && !(0x80..0xA0).contains(&u) { u as u8 } else { b'?' }
}

fn section_name(line: &str) -> Option<&str> {
    let t = line.trim();
    if t.starts_with('[') {
        t.find(']').map(|e| t[1..e].trim())
    } else {
        None
    }
}

/// (key, value) of a key line; comments and other lines give None.
fn key_value(line: &str) -> Option<(&str, &str)> {
    let t = line.trim_start();
    if t.is_empty() || t.starts_with(';') || t.starts_with('#') || t.starts_with('[') {
        return None;
    }
    let eq = line.find('=')?;
    Some((line[..eq].trim(), line[eq + 1..].trim()))
}

impl Ini {
    /// A missing file gives an empty Ini that is created on save.
    pub fn load(path: &Path) -> io::Result<Ini> {
        let bytes = match std::fs::read(path) {
            Ok(b) => b,
            Err(e) if e.kind() == io::ErrorKind::NotFound => Vec::new(),
            Err(e) => return Err(e),
        };
        let (bom, body) = match bytes.strip_prefix(b"\xEF\xBB\xBF") {
            Some(rest) => (true, rest),
            None => (false, &bytes[..]),
        };
        let (text, ansi) = match std::str::from_utf8(body) {
            Ok(s) => (s.to_string(), false),
            Err(_) => (body.iter().map(|&c| cp1252_char(c)).collect(), true),
        };
        let newline = if text.contains("\r\n") || text.is_empty() { "\r\n" } else { "\n" };
        let trailing_newline = text.is_empty() || text.ends_with('\n');
        let mut lines: Vec<String> = text.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l).to_string()).collect();
        if trailing_newline {
            lines.pop(); // the empty piece after the last newline
        }
        Ok(Ini { path: path.to_path_buf(), bom, newline, trailing_newline, ansi, lines })
    }

    /// Line range of a section's body: (header index, end index exclusive).
    fn find_section(&self, section: &str) -> Option<(usize, usize)> {
        let start = self.lines.iter().position(|l| section_name(l).is_some_and(|n| n.eq_ignore_ascii_case(section)))?;
        let end = self.lines[start + 1..].iter().position(|l| section_name(l).is_some()).map(|i| start + 1 + i).unwrap_or(self.lines.len());
        Some((start, end))
    }

    fn find_key(&self, section: &str, key: &str) -> Option<usize> {
        let (s, e) = self.find_section(section)?;
        (s + 1..e).find(|&i| key_value(&self.lines[i]).is_some_and(|(k, _)| k.eq_ignore_ascii_case(key)))
    }

    pub fn get(&self, section: &str, key: &str) -> Option<&str> {
        self.find_key(section, key).and_then(|i| key_value(&self.lines[i])).map(|(_, v)| v)
    }

    pub fn set(&mut self, section: &str, key: &str, value: &str) {
        if let Some(i) = self.find_key(section, key) {
            let eq = self.lines[i].find('=').unwrap();
            let new = format!("{}={}", &self.lines[i][..eq], value);
            if new != self.lines[i] {
                self.lines[i] = new;
            }
            return;
        }
        let line = format!("{key}={value}");
        match self.find_section(section) {
            Some((s, e)) => {
                // after the section's last non-blank line, before blank lines that separate it
                let mut at = e;
                while at > s + 1 && self.lines[at - 1].trim().is_empty() {
                    at -= 1;
                }
                self.lines.insert(at, line);
            }
            None => {
                if self.lines.last().is_some_and(|l| !l.trim().is_empty()) {
                    self.lines.push(String::new());
                }
                self.lines.push(format!("[{section}]"));
                self.lines.push(line);
            }
        }
    }

    pub fn section(&self, section: &str) -> Vec<(String, String)> {
        let Some((s, e)) = self.find_section(section) else { return Vec::new() };
        self.lines[s + 1..e].iter().filter_map(|l| key_value(l)).map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    /// Removes the section's keys; the header stays where it is, so a rewrite lands in place.
    pub fn erase_section(&mut self, section: &str) {
        let Some((s, e)) = self.find_section(section) else { return };
        let keep: Vec<String> = self.lines[s + 1..e].iter().filter(|l| key_value(l).is_none()).cloned().collect();
        self.lines.splice(s + 1..e, keep);
    }

    pub fn to_bytes(&self) -> Vec<u8> {
        let mut text = self.lines.join(self.newline);
        if self.trailing_newline && !self.lines.is_empty() {
            text.push_str(self.newline);
        }
        let mut out = if self.bom { b"\xEF\xBB\xBF".to_vec() } else { Vec::new() };
        if self.ansi {
            out.extend(text.chars().map(cp1252_byte));
        } else {
            out.extend(text.into_bytes());
        }
        out
    }

    pub fn save(&self) -> io::Result<()> {
        if let Some(dir) = self.path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let bytes = self.to_bytes();
        if std::fs::read(&self.path).ok().as_deref() == Some(&bytes[..]) {
            return Ok(()); // nothing changed: leave the file and its date alone
        }
        std::fs::write(&self.path, bytes)
    }
}

/// %LOCALAPPDATA%\TidyTag\tidytag.ini. The program's former name was TagKlon: its settings are
/// copied over the first time (the old file stays where it was), as in settingsfile.pas.
pub fn settings_path() -> PathBuf {
    // development and test runs can point at a copy instead of the real settings
    if let Some(p) = std::env::var_os("TIDYTAG_INI") {
        return PathBuf::from(p);
    }
    let base = std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let file = base.join("TidyTag").join("tidytag.ini");
    if !file.exists() {
        let old = base.join("TagKlon").join("tagklon.ini");
        if old.exists() {
            let _ = std::fs::create_dir_all(base.join("TidyTag"));
            let _ = std::fs::copy(&old, &file); // a failed copy just means default settings
        }
    }
    file
}

#[cfg(test)]
mod tests {
    use super::*;

    const INPUT: &str = "\u{FEFF}[Main]\r\nLastFolder=C:\\x\r\n; note\r\n\r\n[Odd]\r\nZ=1\r\n[View]\r\nFolders=1\r\n";

    fn ini(text: &str) -> (Ini, PathBuf) {
        let dir = std::env::temp_dir().join(format!("tidytag-ini-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        // one file per test: the tests run in parallel
        static N: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
        let p = dir.join(format!("{}.ini", N.fetch_add(1, std::sync::atomic::Ordering::SeqCst)));
        std::fs::write(&p, text).unwrap();
        (Ini::load(&p).unwrap(), p)
    }

    fn saved(i: &Ini, p: &Path) -> String {
        i.save().unwrap();
        let s = String::from_utf8(std::fs::read(p).unwrap()).unwrap();
        let _ = std::fs::remove_file(p);
        s
    }

    #[test]
    fn roundtrip_keeps_bytes() {
        let (mut i, p) = ini(INPUT);
        i.set("main", "lastfolder", "D:\\y");
        assert_eq!(saved(&i, &p), INPUT.replace("C:\\x", "D:\\y"));
    }

    #[test]
    fn set_new_key_appends_to_section() {
        let (mut i, p) = ini(INPUT);
        i.set("View", "Address", "0");
        assert_eq!(saved(&i, &p), INPUT.replace("Folders=1\r\n", "Folders=1\r\nAddress=0\r\n"));
    }

    #[test]
    fn set_new_section_appends_at_end() {
        let (mut i, p) = ini(INPUT);
        i.set("TidyTag2", "K", "V");
        assert_eq!(saved(&i, &p), format!("{INPUT}\r\n[TidyTag2]\r\nK=V\r\n"));
    }

    #[test]
    fn erase_then_write_section() {
        let text = "[Favorites]\r\nDir0=A\r\nDir1=B\r\n\r\n[View]\r\nFolders=1\r\n";
        let (mut i, p) = ini(text);
        i.erase_section("Favorites");
        i.set("Favorites", "Dir0", "C");
        assert_eq!(saved(&i, &p), "[Favorites]\r\nDir0=C\r\n\r\n[View]\r\nFolders=1\r\n");
    }

    #[test]
    fn ansi_file_keeps_its_other_bytes() {
        // an ANSI (cp1252) file: 0xE6 = 'æ' and 0x96 = '–' are not valid UTF-8
        let input: &[u8] = b"[Main]\r\nName=\xE6ble \x96 x\r\nLastFolder=C:\\x\r\n";
        let dir = std::env::temp_dir().join(format!("tidytag-ini-ansi-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("ansi.ini");
        std::fs::write(&p, input).unwrap();
        let mut i = Ini::load(&p).unwrap();
        assert_eq!(i.get("Main", "Name"), Some("æble – x"));
        i.set("Main", "LastFolder", "D:\\y");
        i.save().unwrap();
        assert_eq!(std::fs::read(&p).unwrap(), b"[Main]\r\nName=\xE6ble \x96 x\r\nLastFolder=D:\\y\r\n");
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn get_is_case_insensitive() {
        let (i, p) = ini(INPUT);
        assert_eq!(i.get("MAIN", "lastFOLDER"), Some("C:\\x"));
        assert_eq!(i.get("Odd", "z"), Some("1"));
        assert_eq!(i.section("view"), vec![("Folders".to_string(), "1".to_string())]);
        let _ = std::fs::remove_file(p);
    }
}
