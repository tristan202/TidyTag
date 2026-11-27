//! Renaming files and folders from their tags with a mask such as '%1 - %2' or
//! '%1\%3\%6 - %2' (port of renamecore.pas). Plan (preview), execute and undo are plain
//! functions. Paths are Windows path strings, compared without regard to case as Windows does.

use crate::model::{AudioInfo, TagField};
use crate::text::{pascal_round, pascal_trim};
use std::collections::{BTreeMap, BTreeSet};

// from: TCaseMode — the ini's Case value is the index
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, serde::Serialize, serde::Deserialize)]
pub enum CaseMode {
    #[default]
    None,
    Title,
    Sentence,
    Lower,
    Upper,
}

impl CaseMode {
    pub fn from_index(i: i64) -> CaseMode {
        [CaseMode::None, CaseMode::Title, CaseMode::Sentence, CaseMode::Lower, CaseMode::Upper]
            .get(i.max(0) as usize)
            .copied()
            .unwrap_or_default()
    }
}

// from: TRenameOptions
#[derive(Debug, Clone, Default)]
pub struct RenameOptions {
    pub case_mode: CaseMode,
    pub spaces_to_underscores: bool,
    /// '7/12' -> '07'
    pub pad_track: bool,
    /// applied to every inserted value after the case change: words that keep their spelling
    /// (whole words, any case, e.g. 'AC/DC'), then text replacements
    pub keep_case_words: Vec<String>,
    pub replace_from: Vec<String>,
    pub replace_to: Vec<String>,
}

// from: TRenameStatus
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum RenameStatus {
    Ok,
    Unchanged,
    Missing,
    Exists,
    Duplicate,
    Invalid,
    Done,
    Failed,
}

// from: RenameStatusText (Danish source texts; the renderer translates them)
pub fn status_text(s: RenameStatus) -> &'static str {
    match s {
        RenameStatus::Ok => "Omdøbes",
        RenameStatus::Unchanged => "Uændret",
        RenameStatus::Missing => "Mangler felt",
        RenameStatus::Exists => "Findes allerede",
        RenameStatus::Duplicate => "Samme navn som en anden fil",
        RenameStatus::Invalid => "Ugyldigt navn",
        RenameStatus::Done => "Omdøbt",
        RenameStatus::Failed => "Fejl",
    }
}

const FORSKELLIGE: &str = " (forskellige)";
const INDEHOLDER_ANDEN: &str = "indeholder en anden valgt mappe";
const IND_I_SIG_SELV: &str = "kan ikke flyttes ind i sig selv";
const FOR_LANG: &str = "stien er for lang";
const KUNNE_IKKE_OPRETTE: &str = "kunne ikke oprette mappen ";
const FINDES_IKKE: &str = ": findes ikke længere";
const ALLEREDE_EN_FIL: &str = ": der ligger allerede en fil med det navn";

// from: TRenamePlanItem (the caller keeps the link to its own list by index)
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanItem {
    pub old_name: String,
    /// full path; '' when it could not be built
    pub new_name: String,
    pub status: RenameStatus,
    /// missing field names or an OS error
    pub detail: String,
}

// from: TRenameLogItem
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogItem {
    pub old_name: String,
    pub new_name: String,
}

// from: TMaskValues — for folders only fields shared by all files are set
#[derive(Debug, Clone, Default)]
pub struct MaskValues {
    pub fields: BTreeMap<TagField, String>,
    /// fields whose value differs between the folder's files
    pub different: BTreeSet<TagField>,
    pub file_name: String,
    pub file_number: String,
    pub bitrate: String,
    pub duration: String,
    pub ext: String,
    pub sample_rate: String,
    pub folder_name: String,
    pub bit_depth: String,
}

// from: TagFieldCaptions (audiotypes.pas)
pub fn field_caption(f: TagField) -> &'static str {
    const CAPTIONS: [&str; 37] = [
        "Titel", "Kunstner", "Album", "År", "Spor", "Disc", "Genre", "Kommentar", "Albumkunstner", "Komponist", "BPM",
        "Sangtekst", "Dirigent", "Tekstforfatter", "Oprindelig kunstner", "Remixet af", "Pladeselskab", "Katalognr.",
        "ISRC", "Copyright", "Kodet af", "URL", "Gruppering", "Undertitel", "Stemning", "Toneart", "Sortér titel",
        "Sortér kunstner", "Sortér albumkunstner", "Sortér album", "Sortér komponist", "Del af opsamling", "Podcast",
        "ReplayGain spor", "ReplayGain spor-peak", "ReplayGain album", "ReplayGain album-peak",
    ];
    CAPTIONS[TagField::ALL.iter().position(|x| *x == f).unwrap()]
}

// ---------- Windows text and path helpers (WideUpperCase, SameFileName, SysUtils paths) ----------

/// Windows' own upper/lower case of UTF-16 text, as Lazarus's WideUpperCase/WideLowerCase.
#[cfg(windows)]
fn win_case(mut u: Vec<u16>, upper: bool) -> Vec<u16> {
    use windows_sys::Win32::UI::WindowsAndMessaging::{CharLowerBuffW, CharUpperBuffW};
    if !u.is_empty() {
        unsafe {
            if upper {
                CharUpperBuffW(u.as_mut_ptr(), u.len() as u32);
            } else {
                CharLowerBuffW(u.as_mut_ptr(), u.len() as u32);
            }
        }
    }
    u
}

#[cfg(not(windows))]
fn win_case(u: Vec<u16>, upper: bool) -> Vec<u16> {
    // shortcut: 1:1 mapping per UTF-16 unit, only used off Windows (tests on other systems)
    u.into_iter()
        .map(|c| match char::from_u32(c as u32) {
            Some(ch) => {
                let m: Vec<char> = if upper { ch.to_uppercase().collect() } else { ch.to_lowercase().collect() };
                if m.len() == 1 && (m[0] as u32) < 0x10000 { m[0] as u32 as u16 } else { c }
            }
            None => c,
        })
        .collect()
}

fn utf16(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

fn from16(u: &[u16]) -> String {
    String::from_utf16_lossy(u)
}

fn lower16(u: &[u16]) -> Vec<u16> {
    win_case(u.to_vec(), false)
}

fn upper_unit(c: u16) -> u16 {
    win_case(vec![c], true)[0]
}

// from: IsLetter
fn is_letter(c: u16) -> bool {
    win_case(vec![c], true) != win_case(vec![c], false)
}

fn is_digit16(c: u16) -> bool {
    (b'0' as u16..=b'9' as u16).contains(&c)
}

/// SameFileName: equal without regard to case.
fn same_file_name(a: &str, b: &str) -> bool {
    lower16(&utf16(a)) == lower16(&utf16(b))
}

fn is_delim(c: u8) -> bool {
    c == b'\\' || c == b'/'
}

// from: ExtractFileDir (FPC: keeps the delimiter right after a drive)
fn extract_file_dir(p: &str) -> String {
    let b = p.as_bytes();
    let mut i = b.iter().rposition(|&c| is_delim(c) || c == b':').map(|x| x + 1).unwrap_or(0);
    if i > 1 && is_delim(b[i - 1]) && !(is_delim(b[i - 2]) || b[i - 2] == b':') {
        i -= 1;
    }
    p[..i].to_string()
}

// from: ExtractFileName
fn extract_file_name(p: &str) -> &str {
    let i = p.as_bytes().iter().rposition(|&c| is_delim(c) || c == b':').map(|x| x + 1).unwrap_or(0);
    &p[i..]
}

// from: ExtractFileExt — '.mp3', or '' when the name has no dot
fn extract_file_ext(p: &str) -> &str {
    let name = extract_file_name(p);
    match name.rfind('.') {
        Some(i) => &name[i..],
        None => "",
    }
}

fn include_trailing(p: &str) -> String {
    if p.ends_with('\\') || p.ends_with('/') { p.to_string() } else { format!("{p}\\") }
}

fn exclude_trailing(p: &str) -> String {
    let t = p.trim_end_matches(['\\', '/']);
    if t.len() == 2 && t.ends_with(':') { format!("{t}\\") } else { t.to_string() }
}

// from: ExpandFileName — '/' becomes '\', and '.' and '..' parts are resolved
fn expand_file_name(p: &str) -> String {
    let p = p.replace('/', "\\");
    let (root, rest) = if p.starts_with("\\\\") {
        // \\server\share
        let mut parts = p[2..].splitn(3, '\\');
        let (s, sh, r) = (parts.next().unwrap_or(""), parts.next().unwrap_or(""), parts.next().unwrap_or(""));
        (format!("\\\\{s}\\{sh}"), r.to_string())
    } else if p.len() >= 2 && p.as_bytes()[1] == b':' {
        (p[..2].to_string(), p[2..].to_string())
    } else {
        (String::new(), p.clone())
    };
    let mut out: Vec<&str> = Vec::new();
    for part in rest.split('\\') {
        match part {
            "" | "." => {}
            ".." => {
                out.pop();
            }
            x => out.push(x),
        }
    }
    let mut r = root;
    for part in out {
        r.push('\\');
        r.push_str(part);
    }
    if r.len() == 2 && r.ends_with(':') {
        r.push('\\');
    }
    r
}

fn path_exists(p: &str) -> bool {
    std::path::Path::new(p).exists()
}

fn utf16_len(s: &str) -> usize {
    s.encode_utf16().count()
}

/// Moves a file or folder without ever replacing an existing target (MoveFileW).
#[cfg(windows)]
fn move_no_replace(from: &str, to: &str) -> Result<(), String> {
    use windows_sys::Win32::Storage::FileSystem::MoveFileW;
    let (a, b) = (utf16(from).into_iter().chain([0]).collect::<Vec<_>>(), utf16(to).into_iter().chain([0]).collect::<Vec<_>>());
    if unsafe { MoveFileW(a.as_ptr(), b.as_ptr()) } != 0 {
        Ok(())
    } else {
        Err(os_error_text())
    }
}

#[cfg(not(windows))]
fn move_no_replace(from: &str, to: &str) -> Result<(), String> {
    if path_exists(to) && !same_file_name(from, to) {
        return Err("exists".into());
    }
    std::fs::rename(from, to).map_err(|e| e.to_string())
}

/// SysErrorMessage(GetLastOSError) without Rust's " (os error N)" suffix.
fn os_error_text() -> String {
    let e = std::io::Error::last_os_error().to_string();
    match e.rfind(" (os error") {
        Some(i) => e[..i].trim_end().to_string(),
        None => e,
    }
}

// ---------- names ----------

// from: ApplyCase
pub fn apply_case(s: &str, mode: CaseMode) -> String {
    const SEPARATORS: &str = " ([{-._\"/&+";
    match mode {
        CaseMode::None => return s.to_string(),
        CaseMode::Lower => return from16(&win_case(utf16(s), false)),
        CaseMode::Upper => return from16(&win_case(utf16(s), true)),
        _ => {}
    }
    let mut u = win_case(utf16(s), false);
    if mode == CaseMode::Sentence {
        if let Some(i) = u.iter().position(|&c| is_letter(c)) {
            u[i] = upper_unit(u[i]);
        }
    } else {
        let seps = utf16(SEPARATORS);
        let mut start = true;
        for i in 0..u.len() {
            if is_letter(u[i]) {
                if start {
                    u[i] = upper_unit(u[i]);
                }
                start = false;
            } else if is_digit16(u[i]) {
                start = false;
            } else {
                start = seps.contains(&u[i]);
            }
        }
    }
    from16(&u)
}

// from: SanitizeNamePart — safe as one file/folder name component (no \ / : * ? " < > |)
pub fn sanitize_name_part(s: &str) -> String {
    let mut r = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' | '/' | '|' => r.push('-'),
            ':' => r.push_str(" -"),
            '*' | '?' => {}
            '"' => r.push('\''),
            '<' => r.push('('),
            '>' => r.push(')'),
            '\u{0}'..='\u{1f}' => {}
            _ => r.push(c),
        }
    }
    pascal_trim(&r.replace("  ", " ")).to_string()
}

// from: LeadingNumber
fn leading_number(s: &str) -> &str {
    let n = s.bytes().take_while(|b| b.is_ascii_digit()).count();
    &s[..n]
}

// from: CleanComponent — trailing dots/spaces, which Windows silently drops from names
fn clean_component(s: &str) -> String {
    let mut r = pascal_trim(s).to_string();
    while (r.ends_with('.') || r.ends_with(' ')) && r != ".." {
        r.pop();
    }
    r
}

// from: IsAbsoluteMaskPath
fn is_absolute_mask_path(s: &str) -> bool {
    let b = s.as_bytes();
    b.len() >= 3 && b[1] == b':' && b[2] == b'\\'
}

// from: IsWordChar
fn is_word_char(c: u16) -> bool {
    is_letter(c) || is_digit16(c)
}

// from: AdjustWords — keep-case words (whole words), then the replacements
pub fn adjust_words(s: &str, opt: &RenameOptions) -> String {
    let mut w = utf16(s);
    for kw in &opt.keep_case_words {
        let word = utf16(pascal_trim(kw));
        if word.is_empty() {
            continue;
        }
        let low = lower16(&word);
        let mut p = 0;
        while p + word.len() <= w.len() {
            let end = p + word.len();
            if lower16(&w[p..end]) == low && (p == 0 || !is_word_char(w[p - 1])) && (end >= w.len() || !is_word_char(w[end])) {
                w.splice(p..end, word.iter().copied());
                p = end;
            } else {
                p += 1;
            }
        }
    }
    let mut r = from16(&w);
    for (from, to) in opt.replace_from.iter().zip(&opt.replace_to) {
        if !from.is_empty() {
            r = r.replace(from.as_str(), to);
        }
    }
    r
}

fn random4() -> String {
    let n = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.subsec_nanos()).unwrap_or(0);
    format!("{:04}", n % 10000)
}

// from: ExpandMaskPath — the variables expanded and a clean path text rebuilt (relative or
// 'X:\...'); ('', missing captions) when a needed field is empty, ('', '') when a part is empty
fn expand_mask_path(mask: &str, v: &MaskValues, opt: &RenameOptions) -> (String, String) {
    const LONG: [&str; 15] = ["aa", "cp", "co", "lb", "rb", "md", "ext", "khz", "key", "grp", "cat", "rt", "rnd", "dbit", "enc"];
    let m = mask.as_bytes();
    let mut res: Vec<u8> = Vec::new();
    let mut missing = String::new();
    let field = |f: TagField| v.fields.get(&f).cloned().unwrap_or_default();
    let mut i = 0;
    while i < m.len() {
        if m[i] != b'%' || i == m.len() - 1 {
            res.push(m[i]);
            i += 1;
            continue;
        }
        // longest codes first: %dbit %ext %aa ..., then single characters
        let mut code: Vec<u8> = Vec::new();
        for j in (1..=4).rev() {
            if code.is_empty() && i + j < m.len() {
                let c = m[i + 1..=i + j].to_ascii_lowercase();
                if LONG.iter().any(|l| l.as_bytes() == c.as_slice()) {
                    code = c;
                }
            }
        }
        if code.is_empty() {
            code = vec![m[i + 1]];
        }
        let mut need: Option<TagField> = None;
        let value: String = match code.as_slice() {
            b"1" => { need = Some(TagField::Artist); field(TagField::Artist) }
            b"2" => { need = Some(TagField::Title); field(TagField::Title) }
            b"3" => { need = Some(TagField::Album); field(TagField::Album) }
            b"4" => {
                // the year of a full date (2001-02-03); %rt gives the whole date
                need = Some(TagField::Year);
                let y = field(TagField::Year);
                if y.len() > 4 && leading_number(&y).len() == 4 { leading_number(&y).to_string() } else { y }
            }
            b"rt" => { need = Some(TagField::Year); field(TagField::Year) }
            b"enc" => { need = Some(TagField::EncodedBy); field(TagField::EncodedBy) }
            b"rnd" => random4(),
            b"dbit" => v.bit_depth.clone(),
            b"5" => { need = Some(TagField::Genre); field(TagField::Genre) }
            b"6" => {
                need = Some(TagField::Track);
                let t = field(TagField::Track);
                if opt.pad_track && !leading_number(&t).is_empty() {
                    format!("{:02}", leading_number(&t).parse::<i64>().unwrap_or(0))
                } else {
                    t
                }
            }
            b"#" => {
                need = Some(TagField::Disc);
                let d = field(TagField::Disc);
                if leading_number(&d).is_empty() { d } else { leading_number(&d).to_string() }
            }
            b"9" => { need = Some(TagField::Comment); field(TagField::Comment) }
            b"b" => { need = Some(TagField::Bpm); field(TagField::Bpm) }
            b"aa" => { need = Some(TagField::AlbumArtist); field(TagField::AlbumArtist) }
            b"cp" => { need = Some(TagField::Composer); field(TagField::Composer) }
            b"co" => { need = Some(TagField::Conductor); field(TagField::Conductor) }
            b"lb" => { need = Some(TagField::Publisher); field(TagField::Publisher) }
            b"rb" => { need = Some(TagField::Remixer); field(TagField::Remixer) }
            b"md" => { need = Some(TagField::Mood); field(TagField::Mood) }
            b"key" => { need = Some(TagField::InitialKey); field(TagField::InitialKey) }
            b"grp" => { need = Some(TagField::Grouping); field(TagField::Grouping) }
            b"cat" => { need = Some(TagField::CatalogNo); field(TagField::CatalogNo) }
            b"7" => v.file_name.clone(),
            b"8" => v.file_number.clone(),
            b"0" => v.bitrate.clone(),
            b"t" => v.duration.clone(),
            b"ext" => v.ext.clone(),
            b"khz" => v.sample_rate.clone(),
            b"f" | b"F" => v.folder_name.clone(),
            _ => {
                // unknown code: kept literally
                res.push(b'%');
                res.extend_from_slice(&code);
                i += 1 + code.len();
                continue;
            }
        };
        let mut value = value;
        if let Some(f) = need {
            if sanitize_name_part(&value).is_empty() {
                value.clear();
                if !missing.is_empty() {
                    missing.push_str(", ");
                }
                missing.push_str(field_caption(f));
                if v.different.contains(&f) {
                    missing.push_str(FORSKELLIGE);
                }
            }
        }
        res.extend_from_slice(sanitize_name_part(&adjust_words(&apply_case(&value, opt.case_mode), opt)).as_bytes());
        i += 1 + code.len();
    }
    if !missing.is_empty() {
        return (String::new(), missing);
    }
    let mut res = String::from_utf8_lossy(&res).into_owned();
    if opt.spaces_to_underscores {
        res = res.replace(' ', "_");
    }
    // rebuild the path from cleaned components; '/' in the mask also separates folders
    res = res.replace('/', "\\");
    let absolute = is_absolute_mask_path(&res);
    let mut out = String::new();
    for (n, part) in res.split('\\').enumerate() {
        if absolute && n == 0 {
            out = part.to_string();
            continue;
        }
        let c = clean_component(part);
        if c.is_empty() {
            return (String::new(), String::new());
        }
        if !out.is_empty() {
            out.push('\\');
        }
        out.push_str(&c);
    }
    (out, String::new())
}

// from: FormatDuration (tagutils.pas)
fn format_duration(seconds: f64) -> String {
    if seconds <= 0.0 {
        return String::new();
    }
    let t = pascal_round(seconds);
    if t >= 3600 {
        format!("{}:{:02}:{:02}", t / 3600, (t / 60) % 60, t % 60)
    } else {
        format!("{}:{:02}", t / 60, t % 60)
    }
}

fn path_of(i: &AudioInfo) -> String {
    i.path.to_string_lossy().into_owned()
}

/// The new full path for one file and '' (or '' and the captions of the empty fields the
/// mask needs). `file_number` is 1-based; `number_width` pads it.
// from: ExpandRenameMask
pub fn expand_rename_mask(mask: &str, info: &AudioInfo, file_number: usize, number_width: usize, opt: &RenameOptions) -> (String, String) {
    let path = path_of(info);
    let name = extract_file_name(&path);
    let ext = extract_file_ext(&path);
    let positive = |n: u32| if n > 0 { n.to_string() } else { String::new() };
    let v = MaskValues {
        fields: TagField::ALL.iter().map(|&f| (f, info.field(f).to_string())).collect(),
        different: BTreeSet::new(),
        file_name: name[..name.len() - ext.len()].to_string(),
        file_number: format!("{:0width$}", file_number, width = number_width),
        bitrate: positive(info.bitrate),
        duration: format_duration(info.duration).replace(':', "."),
        ext: ext.trim_start_matches('.').to_string(),
        sample_rate: positive(info.sample_rate),
        folder_name: extract_file_name(&extract_file_dir(&path)).to_string(),
        bit_depth: positive(info.bit_depth),
    };
    let (res, missing) = expand_mask_path(mask, &v, opt);
    if res.is_empty() || res.ends_with(':') {
        return (String::new(), missing);
    }
    let mut res = res + ext;
    if !is_absolute_mask_path(&res) {
        res = include_trailing(&extract_file_dir(&path)) + &res;
    }
    (expand_file_name(&res), String::new())
}

/// TStringList (Sorted, CaseSensitive False) lookups.
fn seen_contains(seen: &[Vec<u16>], name: &str) -> bool {
    let l = lower16(&utf16(name));
    seen.contains(&l)
}

// from: PlanRename
pub fn plan_rename(items: &[&AudioInfo], mask: &str, opt: &RenameOptions) -> Vec<PlanItem> {
    let width = items.len().to_string().len().max(2);
    let mut seen: Vec<Vec<u16>> = Vec::new();
    let mut plan = Vec::with_capacity(items.len());
    for (i, info) in items.iter().enumerate() {
        let old = path_of(info);
        let mut item = PlanItem { old_name: old.clone(), new_name: String::new(), status: RenameStatus::Ok, detail: String::new() };
        if pascal_trim(mask).is_empty() {
            item.status = RenameStatus::Invalid;
            plan.push(item);
            continue;
        }
        let (new, missing) = expand_rename_mask(mask, info, i + 1, width, opt);
        item.new_name = new;
        if !missing.is_empty() {
            item.status = RenameStatus::Missing;
            item.detail = missing;
        } else if item.new_name.is_empty() {
            item.status = RenameStatus::Invalid;
        } else if item.new_name == old {
            item.status = RenameStatus::Unchanged;
        } else if utf16_len(&item.new_name) >= 260 {
            item.status = RenameStatus::Invalid;
            item.detail = FOR_LANG.into();
        } else if seen_contains(&seen, &item.new_name) {
            item.status = RenameStatus::Duplicate;
        } else if path_exists(&item.new_name) && !same_file_name(&item.new_name, &old) {
            item.status = RenameStatus::Exists;
        }
        if !item.new_name.is_empty() {
            seen.push(lower16(&utf16(&item.new_name)));
        }
        plan.push(item);
    }
    plan
}

// from: CommonFolderValues — values shared by all files of one folder (artist falls back to
// the album artist)
pub fn common_folder_values(items: &[&AudioInfo], dir: &str) -> MaskValues {
    let mut v = MaskValues { folder_name: extract_file_name(dir).to_string(), ..Default::default() };
    for f in TagField::ALL {
        v.fields.insert(f, String::new());
    }
    let mut first = true;
    for info in items {
        if !same_file_name(&extract_file_dir(&path_of(info)), dir) {
            continue;
        }
        for f in TagField::ALL {
            if first {
                v.fields.insert(f, info.field(f).to_string());
            } else if info.field(f) != v.fields[&f] {
                v.different.insert(f);
            }
        }
        first = false;
    }
    for f in v.different.clone() {
        v.fields.insert(f, String::new());
    }
    // a compilation has different artists but one album artist
    if v.different.contains(&TagField::Artist) && !v.fields[&TagField::AlbumArtist].is_empty() {
        let aa = v.fields[&TagField::AlbumArtist].clone();
        v.fields.insert(TagField::Artist, aa);
        v.different.remove(&TagField::Artist);
    }
    v
}

// from: IsInside
fn is_inside(path: &str, dir: &str) -> bool {
    let d = include_trailing(dir);
    path.len() >= d.len() && path.is_char_boundary(d.len()) && same_file_name(&path[..d.len()], &d)
}

// from: PlanFolderRename — one entry per folder that holds some of `items`, sorted by name
pub fn plan_folder_rename(items: &[&AudioInfo], mask: &str, opt: &RenameOptions) -> Vec<PlanItem> {
    let mut dirs: Vec<String> = Vec::new();
    for info in items {
        let d = extract_file_dir(&path_of(info));
        if !dirs.iter().any(|x| same_file_name(x, &d)) {
            dirs.push(d);
        }
    }
    // shortcut: ordinal order of the lower-cased names; 1.2 sorts with Windows' locale
    // (AnsiCompareText), which only differs for letters such as æøå
    dirs.sort_by_key(|d| lower16(&utf16(d)));
    let mut seen: Vec<Vec<u16>> = Vec::new();
    let mut plan = Vec::with_capacity(dirs.len());
    for (i, dir) in dirs.iter().enumerate() {
        let mut item = PlanItem { old_name: dir.clone(), new_name: String::new(), status: RenameStatus::Ok, detail: String::new() };
        // renaming a folder that holds another chosen folder would move that one too
        if dirs.iter().enumerate().any(|(j, other)| j != i && is_inside(other, dir)) {
            item.status = RenameStatus::Invalid;
            item.detail = INDEHOLDER_ANDEN.into();
            plan.push(item);
            continue;
        }
        if pascal_trim(mask).is_empty() || extract_file_dir(dir) == *dir {
            item.status = RenameStatus::Invalid; // empty mask or a drive root
            plan.push(item);
            continue;
        }
        let v = common_folder_values(items, dir);
        let (rel, missing) = expand_mask_path(mask, &v, opt);
        if !missing.is_empty() {
            item.status = RenameStatus::Missing;
            item.detail = missing;
            plan.push(item);
            continue;
        }
        if rel.is_empty() || rel.ends_with(':') {
            item.status = RenameStatus::Invalid;
            plan.push(item);
            continue;
        }
        let rel = if is_absolute_mask_path(&rel) { rel } else { include_trailing(&extract_file_dir(dir)) + &rel };
        item.new_name = exclude_trailing(&expand_file_name(&rel));
        if item.new_name == *dir {
            item.status = RenameStatus::Unchanged;
        } else if is_inside(&item.new_name, dir) {
            item.status = RenameStatus::Invalid;
            item.detail = IND_I_SIG_SELV.into();
        } else if utf16_len(&item.new_name) >= 248 {
            item.status = RenameStatus::Invalid;
            item.detail = FOR_LANG.into();
        } else if seen_contains(&seen, &item.new_name) {
            item.status = RenameStatus::Duplicate;
        } else if path_exists(&item.new_name) && !same_file_name(&item.new_name, dir) {
            item.status = RenameStatus::Exists;
        }
        if !item.new_name.is_empty() {
            seen.push(lower16(&utf16(&item.new_name)));
        }
        plan.push(item);
    }
    plan
}

// from: MapRenamedPath — exact matches and paths inside renamed folders; `reverse` maps new
// names back to old ones (after undo). Every entry in turn (backwards when undoing): a log may
// hold file renames followed by the renames of their folders.
pub fn map_renamed_path(path: &str, log: &[LogItem], reverse: bool) -> String {
    let mut r = path.to_string();
    for j in 0..log.len() {
        let (from, to) = if reverse {
            let it = &log[log.len() - 1 - j];
            (&it.new_name, &it.old_name)
        } else {
            (&log[j].old_name, &log[j].new_name)
        };
        if r == *from {
            r = to.clone();
        } else if is_inside(&r, from) {
            r = include_trailing(to) + &r[include_trailing(from).len()..];
        }
    }
    r
}

// from: ExecuteRename — renames every Ok item and sets Done/Failed; returns what was done
pub fn execute_rename(plan: &mut [PlanItem]) -> Vec<LogItem> {
    let mut log = Vec::new();
    for item in plan.iter_mut() {
        if item.status != RenameStatus::Ok {
            continue;
        }
        let dir = extract_file_dir(&item.new_name);
        if !path_exists(&dir) && std::fs::create_dir_all(&dir).is_err() {
            item.status = RenameStatus::Failed;
            item.detail = format!("{KUNNE_IKKE_OPRETTE}{dir}");
            continue;
        }
        // a target that appeared after the preview must not be overwritten
        if path_exists(&item.new_name) && !same_file_name(&item.new_name, &item.old_name) {
            item.status = RenameStatus::Exists;
            continue;
        }
        match move_no_replace(&item.old_name, &item.new_name) {
            Ok(()) => {
                item.status = RenameStatus::Done;
                log.push(LogItem { old_name: item.old_name.clone(), new_name: item.new_name.clone() });
            }
            Err(e) => {
                item.status = RenameStatus::Failed;
                item.detail = e;
            }
        }
    }
    log
}

// from: RemoveEmptyDirs — removes `dir` and its parents while they are empty, stopping at `stop`
fn remove_empty_dirs(mut dir: String, stop: &str) {
    while !dir.is_empty() && !same_file_name(&dir, stop) && dir.len() > 3 {
        if std::fs::remove_dir(&dir).is_err() {
            return; // not empty (or in use): leave it
        }
        dir = extract_file_dir(&dir);
    }
}

// from: UndoRename — moves things back; returns how many, problems go to `errors`
pub fn undo_rename(log: &[LogItem], errors: &mut Vec<String>) -> usize {
    let mut n = 0;
    for it in log.iter().rev() {
        if !path_exists(&it.new_name) {
            errors.push(format!("{}{FINDES_IKKE}", it.new_name));
            continue;
        }
        if path_exists(&it.old_name) && !same_file_name(&it.old_name, &it.new_name) {
            errors.push(format!("{}{ALLEREDE_EN_FIL}", it.old_name));
            continue;
        }
        let _ = std::fs::create_dir_all(extract_file_dir(&it.old_name));
        match move_no_replace(&it.new_name, &it.old_name) {
            Ok(()) => {
                n += 1;
                remove_empty_dirs(extract_file_dir(&it.new_name), &extract_file_dir(&it.old_name));
            }
            Err(e) => errors.push(format!("{}: {e}", it.new_name)),
        }
    }
    n
}

// from: CountStatus
pub fn count_status(plan: &[PlanItem], s: RenameStatus) -> usize {
    plan.iter().filter(|p| p.status == s).count()
}

#[cfg(test)]
#[path = "rename_tests.rs"]
mod tests;
