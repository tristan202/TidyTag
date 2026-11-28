//! Commands for renaming (phase 4): plans, running them, undo and renaming one item by hand.

use crate::commands::WriteState;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;
use tauri::State;
use tidytag_core::filename_tags::{mask_fields, match_file_name, FileNameMatch};
use tidytag_core::model::{AudioInfo, TagField};
use tidytag_core::rename::{
    execute_rename, map_renamed_path, plan_folder_rename, plan_rename, undo_rename, CaseMode, LogItem, PlanItem,
    RenameOptions, RenameStatus,
};
use tidytag_core::settings::{settings_path, Ini};

/// A renderer track (a subset of TrackDto): what a mask can use.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameTrack {
    path: String,
    fields: BTreeMap<String, String>,
    #[serde(default)]
    bitrate: u32,
    #[serde(default)]
    duration: f64,
    #[serde(default)]
    sample_rate: u32,
    #[serde(default)]
    bit_depth: u32,
}

impl RenameTrack {
    pub(crate) fn info(&self) -> AudioInfo {
        let mut i = AudioInfo::new(PathBuf::from(&self.path), false);
        for (k, v) in &self.fields {
            if let Some(f) = TagField::from_key(k) {
                i.put(f, v);
            }
        }
        i.bitrate = self.bitrate;
        i.duration = self.duration;
        i.sample_rate = self.sample_rate;
        i.bit_depth = self.bit_depth;
        i
    }
}

/// The tab's / dialog's options: [Rename] Case (index), Underscores, PadTrack.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RenameOpt {
    case_mode: i64,
    underscores: bool,
    pad_track: bool,
}

/// [RenameReplace] and [RenameKeepCase]
#[derive(Default, Debug)]
pub struct Words {
    from: Vec<String>,
    to: Vec<String>,
    keep: Vec<String>,
}

// from: Unquote (appsettings.pas)
fn unquote(s: &str) -> String {
    if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') { s[1..s.len() - 1].to_string() } else { s.to_string() }
}

// from: LoadRenameWords
fn words_from(ini: &Ini) -> Words {
    let count = |sec: &str| ini.get(sec, "Count").and_then(|v| v.trim().parse::<usize>().ok()).unwrap_or(0);
    let get = |sec: &str, key: String| unquote(ini.get(sec, &key).unwrap_or(""));
    let mut w = Words::default();
    for i in 1..=count("RenameReplace") {
        w.from.push(get("RenameReplace", format!("From{i}")));
        w.to.push(get("RenameReplace", format!("To{i}")));
    }
    for i in 1..=count("RenameKeepCase") {
        w.keep.push(get("RenameKeepCase", format!("Word{i}")));
    }
    w
}

fn load_words() -> Words {
    Ini::load(&settings_path()).map(|i| words_from(&i)).unwrap_or_default()
}

// from: RenameOptions + ApplyRenameWords
fn options(opt: &RenameOpt, w: &Words) -> RenameOptions {
    RenameOptions {
        case_mode: CaseMode::from_index(opt.case_mode),
        spaces_to_underscores: opt.underscores,
        pad_track: opt.pad_track,
        keep_case_words: w.keep.clone(),
        replace_from: w.from.clone(),
        replace_to: w.to.clone(),
    }
}

fn plan_tracks(tracks: &[RenameTrack], mask: &str, opt: &RenameOpt, folders: bool, w: &Words) -> Vec<PlanItem> {
    let infos: Vec<AudioInfo> = tracks.iter().map(RenameTrack::info).collect();
    let refs: Vec<&AudioInfo> = infos.iter().collect();
    if folders { plan_folder_rename(&refs, mask, &options(opt, w)) } else { plan_rename(&refs, mask, &options(opt, w)) }
}

fn execute_rows(mut rows: Vec<PlanItem>) -> (Vec<PlanItem>, Vec<LogItem>) {
    let log = execute_rename(&mut rows);
    (rows, log)
}

// from: ValidFileName (mainform.pas)
fn valid_file_name(s: &str) -> bool {
    !tidytag_core::text::pascal_trim(s).is_empty() && s != "." && s != ".." && !s.contains(['\\', '/', ':', '*', '?', '"', '<', '>', '|'])
}

/// RenamePaths for one file or folder in its own folder. Errors: "invalid", "exists" or the
/// OS text.
fn rename_path(old: &str, new_name: &str) -> Result<LogItem, String> {
    if !valid_file_name(new_name) {
        return Err("invalid".into());
    }
    let dir = &old[..old.rfind('\\').map(|i| i + 1).unwrap_or(0)];
    let mut plan = vec![PlanItem { old_name: old.to_string(), new_name: format!("{dir}{new_name}"), status: RenameStatus::Ok, detail: String::new() }];
    let mut log = execute_rename(&mut plan);
    match plan[0].status {
        RenameStatus::Done => Ok(log.remove(0)),
        RenameStatus::Exists => Err("exists".into()),
        _ => Err(plan[0].detail.clone()),
    }
}

#[tauri::command]
pub async fn plan_rename_cmd(tracks: Vec<RenameTrack>, mask: String, opt: RenameOpt, folders: bool) -> Vec<PlanItem> {
    plan_tracks(&tracks, &mask, &opt, folders, &load_words())
}

#[derive(Serialize)]
pub struct Executed {
    rows: Vec<PlanItem>,
    log: Vec<LogItem>,
}

/// Runs the Ok rows of a plan; the others are left as they are.
#[tauri::command]
pub async fn execute_rename_cmd(state: State<'_, WriteState>, rows: Vec<PlanItem>) -> Result<Executed, String> {
    let _busy = state.claim()?;
    let (rows, log) = execute_rows(rows);
    Ok(Executed { rows, log })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Undone {
    restored: usize,
    /// the entries really moved back: only these move the list (ApplyRenameLog)
    restored_log: Vec<LogItem>,
    errors: Vec<String>,
}

#[tauri::command]
pub async fn undo_rename_cmd(state: State<'_, WriteState>, log: Vec<LogItem>) -> Result<Undone, String> {
    let _busy = state.claim()?;
    let mut errors = Vec::new();
    let restored_log = undo_rename(&log, &mut errors);
    Ok(Undone { restored: restored_log.len(), restored_log, errors })
}

/// ApplyRenameLog's mapping: a path moves only when its new place exists.
#[tauri::command]
pub fn map_paths(paths: Vec<String>, log: Vec<LogItem>, reverse: bool) -> Vec<String> {
    paths
        .into_iter()
        .map(|p| {
            let m = map_renamed_path(&p, &log, reverse);
            if m != p && std::path::Path::new(&m).exists() { m } else { p }
        })
        .collect()
}

#[tauri::command]
pub async fn rename_one(state: State<'_, WriteState>, old_path: String, new_name: String) -> Result<LogItem, String> {
    let _busy = state.claim()?;
    rename_path(&old_path, &new_name)
}

/// MaskFields: the fields a tags-from-filename mask fills (the preview's columns).
#[tauri::command]
pub fn mask_fields_cmd(mask: String) -> Vec<TagField> {
    mask_fields(&mask)
}

#[tauri::command]
pub async fn match_file_names(paths: Vec<String>, mask: String, underscores: bool, case_mode: i64) -> Vec<FileNameMatch> {
    paths.iter().map(|p| match_file_name(&mask, p, underscores, CaseMode::from_index(case_mode))).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(name: &str) -> String {
        let d = std::env::temp_dir().join(format!("tidytag-rencmd-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d.to_string_lossy().trim_end_matches('\\').to_string()
    }

    fn track(path: &str, track: &str, title: &str) -> RenameTrack {
        RenameTrack {
            path: path.into(),
            fields: [("track".to_string(), track.to_string()), ("title".to_string(), title.to_string())].into(),
            bitrate: 320,
            duration: 185.0,
            sample_rate: 44100,
            bit_depth: 0,
        }
    }

    #[test]
    fn plan_and_execute_from_dto() {
        let d = dir("dto");
        for n in ["a.mp3", "b.mp3"] {
            std::fs::write(format!("{d}\\{n}"), b"").unwrap();
        }
        let tracks = [track(&format!("{d}\\a.mp3"), "1", "Én"), track(&format!("{d}\\b.mp3"), "2", "To")];
        let opt = RenameOpt { case_mode: 0, underscores: false, pad_track: true };
        let rows = plan_tracks(&tracks, "%6 - %2", &opt, false, &Words::default());
        assert!(rows.iter().all(|r| r.status == RenameStatus::Ok), "{rows:?}");
        let (rows, log) = execute_rows(rows);
        assert_eq!(log.len(), 2);
        assert!(rows.iter().all(|r| r.status == RenameStatus::Done));
        assert!(std::path::Path::new(&format!("{d}\\01 - Én.mp3")).exists());
        let mut errors = Vec::new();
        assert_eq!(tidytag_core::rename::undo_rename(&log, &mut errors).len(), 2);
        assert!(std::path::Path::new(&format!("{d}\\a.mp3")).exists());
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn rename_one_refuses_invalid_and_existing() {
        let d = dir("one");
        std::fs::write(format!("{d}\\a.mp3"), b"").unwrap();
        std::fs::write(format!("{d}\\b.mp3"), b"").unwrap();
        assert_eq!(rename_path(&format!("{d}\\a.mp3"), "x?.mp3").unwrap_err(), "invalid");
        assert_eq!(rename_path(&format!("{d}\\a.mp3"), " ").unwrap_err(), "invalid");
        assert_eq!(rename_path(&format!("{d}\\a.mp3"), "b.mp3").unwrap_err(), "exists");
        let log = rename_path(&format!("{d}\\a.mp3"), "c.mp3").unwrap();
        assert_eq!(log.new_name, format!("{d}\\c.mp3"));
        assert!(std::path::Path::new(&log.new_name).exists());
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn words_come_unquoted_from_the_ini() {
        let p = std::path::PathBuf::from(dir("ini")).join("t.ini");
        std::fs::write(&p, "[RenameReplace]\r\nCount=1\r\nFrom1=\" & \"\r\nTo1=\" and \"\r\n[RenameKeepCase]\r\nCount=1\r\nWord1=\"AC/DC\"\r\n").unwrap();
        let w = words_from(&tidytag_core::settings::Ini::load(&p).unwrap());
        std::fs::remove_dir_all(p.parent().unwrap()).unwrap();
        assert_eq!((w.from, w.to, w.keep), (vec![" & ".to_string()], vec![" and ".to_string()], vec!["AC/DC".to_string()]));
    }
}
