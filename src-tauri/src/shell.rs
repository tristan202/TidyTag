//! Explorer integration and other Windows shell work.
// from: shellintegration.pas

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use windows_sys::Win32::Foundation::ERROR_SUCCESS;
use windows_sys::Win32::System::Registry::{
    RegCloseKey, RegCreateKeyExW, RegDeleteTreeW, RegGetValueW, RegSetValueExW, HKEY, HKEY_CURRENT_USER, KEY_WRITE,
    REG_OPTION_NON_VOLATILE, REG_SZ, RRF_RT_REG_SZ,
};

const VERB_KEY: &str = "TidyTag";
pub const CLASSES: &str = "Software\\Classes";

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain([0]).collect()
}

// ---------- registry (HKCU only) ----------

fn reg_set(key: &str, name: &str, value: &str) -> bool {
    let mut h: HKEY = std::ptr::null_mut();
    let k = wide(key);
    let ok = unsafe {
        RegCreateKeyExW(HKEY_CURRENT_USER, k.as_ptr(), 0, std::ptr::null(), REG_OPTION_NON_VOLATILE, KEY_WRITE, std::ptr::null(), &mut h, std::ptr::null_mut())
    } == ERROR_SUCCESS;
    if !ok {
        return false;
    }
    let n = wide(name);
    let v = wide(value);
    let r = unsafe { RegSetValueExW(h, if name.is_empty() { std::ptr::null() } else { n.as_ptr() }, 0, REG_SZ, v.as_ptr() as *const u8, (v.len() * 2) as u32) };
    unsafe { RegCloseKey(h) };
    r == ERROR_SUCCESS
}

pub(crate) fn reg_read(key: &str, name: &str) -> Option<String> {
    let k = wide(key);
    let n = wide(name);
    let np = if name.is_empty() { std::ptr::null() } else { n.as_ptr() };
    let mut size: u32 = 0;
    if unsafe { RegGetValueW(HKEY_CURRENT_USER, k.as_ptr(), np, RRF_RT_REG_SZ, std::ptr::null_mut(), std::ptr::null_mut(), &mut size) } != ERROR_SUCCESS {
        return None;
    }
    let mut buf = vec![0u16; (size as usize).div_ceil(2)];
    if unsafe { RegGetValueW(HKEY_CURRENT_USER, k.as_ptr(), np, RRF_RT_REG_SZ, std::ptr::null_mut(), buf.as_mut_ptr() as *mut _, &mut size) } != ERROR_SUCCESS {
        return None;
    }
    let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    Some(String::from_utf16_lossy(&buf[..end]))
}

fn reg_key_exists(key: &str) -> bool {
    use windows_sys::Win32::System::Registry::{RegOpenKeyExW, KEY_READ};
    let k = wide(key);
    let mut h: HKEY = std::ptr::null_mut();
    if unsafe { RegOpenKeyExW(HKEY_CURRENT_USER, k.as_ptr(), 0, KEY_READ, &mut h) } != ERROR_SUCCESS {
        return false;
    }
    unsafe { RegCloseKey(h) };
    true
}

pub(crate) fn reg_delete_tree(key: &str) {
    let k = wide(key);
    unsafe { RegDeleteTreeW(HKEY_CURRENT_USER, k.as_ptr()) };
    // RegDeleteTreeW empties the key; delete the key itself too
    unsafe { windows_sys::Win32::System::Registry::RegDeleteKeyW(HKEY_CURRENT_USER, k.as_ptr()) };
}

// ---------- the Explorer menu ----------

/// Every key we write, with its command argument.
// from: ListKeys
pub fn menu_keys(classes: &str, exts: &[&str]) -> Vec<(String, &'static str)> {
    let mut keys = vec![
        (format!("{classes}\\Directory\\shell\\{VERB_KEY}"), "%1"),
        (format!("{classes}\\Directory\\Background\\shell\\{VERB_KEY}"), "%V"),
        (format!("{classes}\\Drive\\shell\\{VERB_KEY}"), "%1"),
    ];
    for e in exts {
        keys.push((format!("{classes}\\SystemFileAssociations\\{e}\\shell\\{VERB_KEY}"), "%1"));
    }
    keys
}

fn exe_command(exe: &str, arg: &str) -> String {
    format!("\"{exe}\" \"{arg}\"")
}

// from: ExplorerMenuInstalled
pub fn explorer_menu_installed(classes: &str) -> bool {
    let key = format!("{classes}\\Directory\\shell\\{VERB_KEY}\\command");
    reg_key_exists(&key)
}

// from: InstallExplorerMenu
pub fn install_explorer_menu(classes: &str, caption: &str, exe: &str, exts: &[&str]) -> Result<(), String> {
    let mut ok = true;
    for (key, arg) in menu_keys(classes, exts) {
        ok &= reg_set(&key, "", caption);
        ok &= reg_set(&key, "Icon", &format!("\"{exe}\",0"));
        // without it the entry disappears when more than 15 files are selected
        if key.contains("SystemFileAssociations") {
            ok &= reg_set(&key, "MultiSelectModel", "Player");
        }
        ok &= reg_set(&format!("{key}\\command"), "", &exe_command(exe, arg));
    }
    if ok { Ok(()) } else { Err(std::io::Error::last_os_error().to_string()) }
}

// from: RemoveExplorerMenu
pub fn remove_explorer_menu(classes: &str, exts: &[&str]) {
    for (key, _) in menu_keys(classes, exts) {
        reg_delete_tree(&key);
    }
}

/// Rewrites installed entries that point to another exe or use another caption.
// from: RefreshExplorerMenu
pub fn refresh_explorer_menu(classes: &str, caption: &str, exe: &str, exts: &[&str]) {
    if !explorer_menu_installed(classes) {
        return;
    }
    let key = format!("{classes}\\Directory\\shell\\{VERB_KEY}");
    let stale = reg_read(&key, "").as_deref() != Some(caption)
        || reg_read(&format!("{key}\\command"), "").as_deref() != Some(exe_command(exe, "%1").as_str());
    if stale {
        let _ = install_explorer_menu(classes, caption, exe, exts);
    }
}

/// Only an installed TidyTag refreshes the menu: a dev build must not point the user's
/// Explorer menu at target\debug.
pub fn should_refresh_menu_at_start() -> bool {
    cfg!(not(debug_assertions))
}

/// The audio extensions the menu is offered for.
pub fn menu_exts() -> Vec<&'static str> {
    tidytag_core::read::READABLE_EXTS.iter().chain(tidytag_core::read::OTHER_EXTS.iter()).copied().collect()
}

// ---------- the menu caption in the user's language ----------

static TRANSLATIONS: &str = include_str!("../../languages/src/translations.json");

/// 'Åbn i TidyTag' in `lang` (the same rule as I18N.effectiveLanguage: unknown → en).
pub fn menu_caption_for(lang: &str) -> String {
    const KEY: &str = "Åbn i TidyTag";
    if lang == "da" {
        return KEY.into();
    }
    let lang = if ["en", "de", "es", "fr", "it", "sv"].contains(&lang) { lang } else { "en" };
    let json: serde_json::Value = serde_json::from_str(TRANSLATIONS).unwrap_or_default();
    json[KEY][lang].as_str().unwrap_or(KEY).to_string()
}

/// The language from [Main] Language, or Windows' UI language when it is empty.
pub fn effective_language() -> String {
    let setting = tidytag_core::settings::Ini::load(&tidytag_core::settings::settings_path())
        .ok()
        .and_then(|i| i.get("Main", "Language").map(|s| s.to_lowercase()))
        .unwrap_or_default();
    if ["da", "en", "de", "es", "fr", "it", "sv"].contains(&setting.as_str()) {
        return setting;
    }
    let id = unsafe { windows_sys::Win32::Globalization::GetUserDefaultUILanguage() } & 0x3ff;
    match id {
        0x06 | 0x14 => "da", // nb → da, as in 1.2
        0x07 => "de",
        0x0a => "es",
        0x0c => "fr",
        0x10 => "it",
        0x1d => "sv",
        _ => "en",
    }
    .into()
}

pub fn menu_caption() -> String {
    menu_caption_for(&effective_language())
}

// ---------- paths from Explorer ----------

/// The existing files and folders named on the command line (switches skipped).
// from: CommandLinePaths
pub fn command_line_paths(args: &[OsString]) -> Vec<String> {
    let mut out = Vec::new();
    for a in args.iter().skip(1) {
        if a.to_string_lossy().starts_with("--") {
            return Vec::new(); // developer modes take no part
        }
        let p = Path::new(a);
        if p.exists() {
            out.push(std::path::absolute(p).unwrap_or_else(|_| p.to_path_buf()).to_string_lossy().into_owned());
        }
    }
    out
}

// ---------- "Play with" ----------

/// The program's own name ('VLC media player') from its version info, else the file name.
// from: ProgramName
pub fn program_name(exe: &Path) -> String {
    let mut name = product_name(exe).unwrap_or_default().trim().to_string();
    if name.len() >= 12 && name[name.len() - 12..].eq_ignore_ascii_case(" Application") {
        name.truncate(name.len() - 12); // 'foobar2000 Application'
    }
    if name.is_empty() {
        name = exe.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    }
    name
}

fn product_name(exe: &Path) -> Option<String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
    let p: Vec<u16> = exe.as_os_str().encode_wide().chain([0]).collect();
    let size = unsafe { GetFileVersionInfoSizeW(p.as_ptr(), std::ptr::null_mut()) };
    if size == 0 {
        return None;
    }
    let mut data = vec![0u8; size as usize];
    if unsafe { GetFileVersionInfoW(p.as_ptr(), 0, size, data.as_mut_ptr() as *mut _) } == 0 {
        return None;
    }
    // the first translation's string table
    let mut ptr: *mut core::ffi::c_void = std::ptr::null_mut();
    let mut len: u32 = 0;
    let q = wide("\\VarFileInfo\\Translation");
    if unsafe { VerQueryValueW(data.as_ptr() as *const _, q.as_ptr(), &mut ptr, &mut len) } == 0 || len < 4 {
        return None;
    }
    let (lang, cp) = unsafe { (*(ptr as *const u16), *(ptr as *const u16).add(1)) };
    let q = wide(&format!("\\StringFileInfo\\{lang:04x}{cp:04x}\\ProductName"));
    if unsafe { VerQueryValueW(data.as_ptr() as *const _, q.as_ptr(), &mut ptr, &mut len) } == 0 || len == 0 {
        return None;
    }
    let s = unsafe { std::slice::from_raw_parts(ptr as *const u16, len as usize) };
    let end = s.iter().position(|&c| c == 0).unwrap_or(s.len());
    Some(String::from_utf16_lossy(&s[..end]))
}

/// Players we know of: the configured ones, the ones added by hand and common players found
/// in their usual folders.
// from: RebuildPlayWith
pub fn known_players(players: &[String], extra: &[String]) -> Vec<PathBuf> {
    const KNOWN: [&str; 10] = [
        "%ProgramFiles%\\foobar2000\\foobar2000.exe", "%ProgramFiles(x86)%\\foobar2000\\foobar2000.exe",
        "%ProgramFiles%\\VideoLAN\\VLC\\vlc.exe", "%ProgramFiles(x86)%\\VideoLAN\\VLC\\vlc.exe",
        "%ProgramFiles(x86)%\\MusicBee\\MusicBee.exe", "%ProgramFiles%\\AIMP\\AIMP.exe",
        "%ProgramFiles(x86)%\\AIMP\\AIMP.exe", "%ProgramFiles(x86)%\\Winamp\\winamp.exe",
        "%ProgramFiles%\\MPC-HC\\mpc-hc64.exe", "%ProgramFiles%\\DAUM\\PotPlayer\\PotPlayerMini64.exe",
    ];
    let env = |k: &str| std::env::var(k).unwrap_or_default();
    let mut out: Vec<PathBuf> = Vec::new();
    let mut add = |p: &str| {
        let mut q = p.trim();
        if q.len() >= 2 && q.starts_with('"') && q.ends_with('"') {
            q = &q[1..q.len() - 1];
        }
        if q.is_empty() || !Path::new(q).is_file() {
            return;
        }
        if out.iter().any(|o| o.to_string_lossy().to_lowercase() == q.to_lowercase()) {
            return;
        }
        out.push(PathBuf::from(q));
    };
    for p in players {
        if let Some(e) = p.find('=') {
            if e > 0 {
                add(&p[e + 1..]);
            }
        }
    }
    for p in extra {
        add(p);
    }
    for p in KNOWN {
        add(&p.replace("%ProgramFiles(x86)%", &env("ProgramFiles(x86)")).replace("%ProgramFiles%", &env("ProgramFiles")));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::OsString;

    const TEST_ROOT: &str = "Software\\TidyTag2Test";
    const TEST_CLASSES: &str = "Software\\TidyTag2Test\\Classes";

    // one test at a time touches the test root
    static REG_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn explorer_menu_round_trip_in_test_root() {
        let _g = REG_LOCK.lock().unwrap();
        let exe = "C:\\x\\TidyTag.exe";
        install_explorer_menu(TEST_CLASSES, "Åbn i TidyTag", exe, &[".mp3"]).unwrap();
        assert!(explorer_menu_installed(TEST_CLASSES));
        assert_eq!(
            reg_read(&format!("{TEST_CLASSES}\\Directory\\shell\\TidyTag\\command"), "").as_deref(),
            Some("\"C:\\x\\TidyTag.exe\" \"%1\"")
        );
        assert_eq!(
            reg_read(&format!("{TEST_CLASSES}\\SystemFileAssociations\\.mp3\\shell\\TidyTag"), "MultiSelectModel").as_deref(),
            Some("Player")
        );
        remove_explorer_menu(TEST_CLASSES, &[".mp3"]);
        assert!(!explorer_menu_installed(TEST_CLASSES));
        reg_delete_tree(TEST_ROOT);
    }

    #[test]
    fn refresh_rewrites_only_stale() {
        let _g = REG_LOCK.lock().unwrap();
        refresh_explorer_menu(TEST_CLASSES, "Åbn i TidyTag", "C:\\b\\TidyTag.exe", &[".mp3"]);
        assert!(!explorer_menu_installed(TEST_CLASSES), "refresh must not install");
        install_explorer_menu(TEST_CLASSES, "Åbn i TidyTag", "C:\\a\\TidyTag.exe", &[".mp3"]).unwrap();
        refresh_explorer_menu(TEST_CLASSES, "Åbn i TidyTag", "C:\\b\\TidyTag.exe", &[".mp3"]);
        assert_eq!(
            reg_read(&format!("{TEST_CLASSES}\\Directory\\shell\\TidyTag\\command"), "").as_deref(),
            Some("\"C:\\b\\TidyTag.exe\" \"%1\"")
        );
        reg_delete_tree(TEST_ROOT);
    }

    #[test]
    fn dev_build_never_refreshes_menu() {
        assert!(!should_refresh_menu_at_start());
    }

    #[test]
    fn command_line_paths_skip_switches() {
        let f = std::env::temp_dir().join(format!("tidytag-clp-{}.mp3", std::process::id()));
        std::fs::write(&f, b"x").unwrap();
        let exe = OsString::from("tidytag.exe");
        let got = command_line_paths(&[exe.clone(), f.clone().into(), OsString::from("C:\\nope\\nope.mp3")]);
        assert_eq!(got, vec![f.to_string_lossy().into_owned()]);
        assert!(command_line_paths(&[exe, OsString::from("--selftest"), f.clone().into()]).is_empty());
        std::fs::remove_file(&f).unwrap();
    }

    #[test]
    fn program_name_falls_back_to_stem() {
        let f = std::env::temp_dir().join(format!("tidytag-foo-{}.exe", std::process::id()));
        std::fs::write(&f, b"not a real exe").unwrap();
        assert_eq!(program_name(&f), format!("tidytag-foo-{}", std::process::id()));
        std::fs::remove_file(&f).unwrap();
    }

    #[test]
    fn menu_caption_follows_language() {
        assert_eq!(menu_caption_for("da"), "Åbn i TidyTag");
        assert_eq!(menu_caption_for("en"), "Open in TidyTag");
        assert_eq!(menu_caption_for("sv"), "Öppna i TidyTag");
        assert_eq!(menu_caption_for("xx"), "Open in TidyTag");
    }
}
