//! 1.2's tools/renametest.lpr cases (TestCase, TestExpand, TestWords, TestFolderPlan,
//! TestRenameAndUndo) with the same expected values, plus phase 4's Review Focus tests.

use super::*;
use crate::model::{AudioInfo, TagField as F};
use std::path::PathBuf;

fn opt(case_mode: CaseMode, us: bool, pad: bool) -> RenameOptions {
    RenameOptions { case_mode, spaces_to_underscores: us, pad_track: pad, ..Default::default() }
}

// from: MakeInfo
fn info(path: &str, artist: &str, title: &str, album: &str, track: &str) -> AudioInfo {
    let mut i = AudioInfo::new(PathBuf::from(path), false);
    i.put(F::Artist, artist);
    i.put(F::Title, title);
    i.put(F::Album, album);
    i.put(F::Track, track);
    i.put(F::Year, "1999");
    i.bitrate = 320;
    i.duration = 185.0;
    i
}

fn expand(mask: &str, i: &AudioInfo, n: usize, o: &RenameOptions) -> String {
    expand_rename_mask(mask, i, n, 2, o).0
}

#[test]
fn case_modes() {
    assert_eq!(apply_case("hELLO wORLD (live at øresund)", CaseMode::Title), "Hello World (Live At Øresund)");
    assert_eq!(apply_case("don't stop-me now", CaseMode::Title), "Don't Stop-Me Now");
    assert_eq!(apply_case("  01 æBLE OG PÆRE", CaseMode::Sentence), "  01 Æble og pære");
    assert_eq!(apply_case("Ærø Å", CaseMode::Lower), "ærø å");
    assert_eq!(apply_case("ærø å", CaseMode::Upper), "ÆRØ Å");
}

#[test]
fn masks() {
    let mut o = opt(CaseMode::None, false, true);
    let mut i = info("C:\\Musik\\gammel.mp3", "AC/DC", "What? \"Now\": <Live>*", "Album", "7/12");
    assert_eq!(expand("%6 - %1 - %2", &i, 1, &o), "C:\\Musik\\07 - AC-DC - What 'Now' - (Live).mp3");
    assert_eq!(expand("%1\\%4 - %3\\%6 %2", &i, 1, &o), "C:\\Musik\\AC-DC\\1999 - Album\\07 What 'Now' - (Live).mp3");
    assert_eq!(expand("D:\\Ny\\%1 - %3", &i, 1, &o), "D:\\Ny\\AC-DC - Album.mp3");
    assert_eq!(expand("%8 %7 [%0kbps] %t", &i, 3, &o), "C:\\Musik\\03 gammel [320kbps] 3.05.mp3");
    let (r, missing) = expand_rename_mask("%1 - %cp", &i, 1, 2, &o);
    assert_eq!((r.as_str(), missing.as_str()), ("", "Komponist"));
    assert_eq!(expand("%3. ", &i, 1, &o), "C:\\Musik\\Album.mp3");
    o.spaces_to_underscores = true;
    o.case_mode = CaseMode::Upper;
    assert_eq!(expand("%1 - %3", &i, 1, &o), "C:\\Musik\\AC-DC_-_ALBUM.mp3");
    o = opt(CaseMode::None, false, false);
    assert_eq!(expand("%6 %2x", &i, 1, &o), "C:\\Musik\\7-12 What 'Now' - (Live)x.mp3");
    i.put(F::Year, "2001-02-03");
    i.put(F::EncodedBy, "LAME");
    i.bit_depth = 24;
    assert_eq!(expand("%4 %rt %enc %dbit", &i, 1, &o), "C:\\Musik\\2001 2001-02-03 LAME 24.mp3");
    assert_eq!(expand("%rnd", &i, 1, &o).rsplit('\\').next().unwrap().len(), "0000.mp3".len());
    i.bit_depth = 0;
    assert_eq!(expand("%2 [%dbit]", &i, 1, &o), "C:\\Musik\\What 'Now' - (Live) [].mp3");
}

#[test]
fn words_and_log_mapping() {
    let o = RenameOptions {
        keep_case_words: vec!["AC/DC".into(), "ABBA".into(), "feat.".into()],
        replace_from: vec![" & ".into(), "Feat.".into()],
        replace_to: vec![" and ".into(), "ft.".into()],
        ..opt(CaseMode::Title, false, true)
    };
    assert_eq!(adjust_words("Ac/Dc Og Abba Feat. Abbatar", &o), "AC/DC Og ABBA feat. Abbatar");
    let i = info("C:\\Musik\\x.mp3", "ac/dc & abba", "live feat. someone", "Album", "1");
    assert_eq!(expand("%1 - %2", &i, 1, &o), "C:\\Musik\\AC-DC and ABBA - Live feat. Someone.mp3");
    let log = vec![
        LogItem { old_name: "C:\\M\\a\\1.mp3".into(), new_name: "C:\\M\\a\\One.mp3".into() },
        LogItem { old_name: "C:\\M\\a".into(), new_name: "C:\\M\\Album".into() },
    ];
    assert_eq!(map_renamed_path("C:\\M\\a\\1.mp3", &log, false), "C:\\M\\Album\\One.mp3");
    assert_eq!(map_renamed_path("C:\\M\\Album\\One.mp3", &log, true), "C:\\M\\a\\1.mp3");
}

#[test]
fn folder_plans() {
    let mut items = vec![
        info("C:\\Musik\\x\\1.mp3", "Gasolin'", "A", "Gas 5", "1"),
        info("C:\\Musik\\x\\2.mp3", "Gasolin'", "B", "Gas 5", "2"),
        info("C:\\Musik\\komp\\1.mp3", "Kunstner A", "A", "Hits", "1"),
        info("C:\\Musik\\komp\\2.mp3", "Kunstner B", "B", "Hits", "2"),
        info("C:\\Musik\\komp2\\1.mp3", "Kunstner C", "A", "Hits 2", "1"),
    ];
    items[2].put(F::AlbumArtist, "Diverse");
    items[3].put(F::AlbumArtist, "Diverse");
    let refs: Vec<&AudioInfo> = items.iter().collect();
    let v = common_folder_values(&refs, "C:\\Musik\\komp");
    assert_eq!(v.fields[&F::Artist], "Diverse");
    assert!(v.different.contains(&F::Title));
    let o = opt(CaseMode::None, false, true);
    let p = plan_folder_rename(&refs, "%1 - %4 - %3", &o);
    assert_eq!(p.len(), 3);
    assert_eq!(p[0].new_name, "C:\\Musik\\Diverse - 1999 - Hits");
    assert_eq!(p[1].new_name, "C:\\Musik\\Kunstner C - 1999 - Hits 2");
    assert_eq!(p[2].new_name, "C:\\Musik\\Gasolin' - 1999 - Gas 5");
    let p = plan_folder_rename(&refs, "%2", &o);
    assert_eq!((p[0].status, p[0].detail.as_str()), (RenameStatus::Missing, "Titel (forskellige)"));
    assert_eq!(plan_folder_rename(&refs, "%1\\%3", &o)[2].new_name, "C:\\Musik\\Gasolin'\\Gas 5");
    assert_eq!(plan_folder_rename(&refs, "%f", &o)[0].status, RenameStatus::Unchanged);

    let nested = [info("C:\\Musik\\A\\1.mp3", "K", "T", "Alb", "1"), info("C:\\Musik\\A\\B\\1.mp3", "K", "T", "Alb2", "1")];
    let refs: Vec<&AudioInfo> = nested.iter().collect();
    let p = plan_folder_rename(&refs, "%3", &o);
    assert_eq!((p[0].status, p[1].status), (RenameStatus::Invalid, RenameStatus::Ok));
}

/// A fresh folder below %TEMP% (with a trailing backslash), as TestRenameAndUndo makes.
fn test_dir(name: &str) -> String {
    let d = std::env::temp_dir().join(format!("tidytag-rename-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    format!("{}\\", d.to_string_lossy().trim_end_matches('\\'))
}

fn touch(p: &str) {
    std::fs::create_dir_all(std::path::Path::new(p).parent().unwrap()).unwrap();
    std::fs::write(p, b"").unwrap();
}

fn exists(p: &str) -> bool {
    std::path::Path::new(p).exists()
}

fn names_in(dir: &str) -> Vec<String> {
    std::fs::read_dir(dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect()
}

#[test]
fn rename_and_undo_on_disk() {
    let dir = test_dir("undo");
    for f in ["a.mp3", "b.mp3", "c.mp3", "d.mp3", "Blokeret - Titel.mp3"] {
        touch(&format!("{dir}{f}"));
    }
    let items = [
        info(&format!("{dir}a.mp3"), "Kunstner", "Første", "Album", "1"),
        info(&format!("{dir}b.mp3"), "Kunstner", "Første", "Album", "2"),
        info(&format!("{dir}c.mp3"), "Blokeret", "Titel", "Album", "3"),
        info(&format!("{dir}d.mp3"), "", "Uden kunstner", "Album", "4"),
    ];
    let refs: Vec<&AudioInfo> = items.iter().collect();
    let o = opt(CaseMode::None, false, true);
    let p = plan_rename(&refs, "%1 - %2", &o);
    let st: Vec<_> = p.iter().map(|r| r.status).collect();
    assert_eq!(st, [RenameStatus::Ok, RenameStatus::Duplicate, RenameStatus::Exists, RenameStatus::Missing]);

    let mut p = plan_rename(&refs, "%1\\%3\\%6 - %2", &o);
    assert_eq!(count_status(&p, RenameStatus::Ok), 3);
    let log = execute_rename(&mut p);
    assert_eq!(log.len(), 3);
    assert!(exists(&format!("{dir}Kunstner\\Album\\01 - Første.mp3")) && !exists(&format!("{dir}a.mp3")));
    let mut errors = Vec::new();
    assert_eq!(undo_rename(&log, &mut errors), 3);
    assert!(errors.is_empty(), "{errors:?}");
    assert!(exists(&format!("{dir}a.mp3")) && exists(&format!("{dir}b.mp3")) && exists(&format!("{dir}c.mp3")));
    assert!(!exists(&format!("{dir}Kunstner")));

    // folder rename + undo
    touch(&format!("{dir}album\\x.mp3"));
    let mut f = info(&format!("{dir}album\\x.mp3"), "Mappekunstner", "Første", "Mappealbum", "2");
    f.put(F::Artist, "Mappekunstner");
    let mut p = plan_folder_rename(&[&f], "%1\\%3", &o);
    assert_eq!(p[0].status, RenameStatus::Ok);
    let log = execute_rename(&mut p);
    assert!(log.len() == 1 && exists(&format!("{dir}Mappekunstner\\Mappealbum\\x.mp3")));
    assert_eq!(map_renamed_path(&format!("{dir}album\\x.mp3"), &log, false), format!("{dir}Mappekunstner\\Mappealbum\\x.mp3"));
    assert_eq!(undo_rename(&log, &mut errors), 1);
    assert!(exists(&format!("{dir}album\\x.mp3")) && !exists(&format!("{dir}Mappekunstner")));
    assert_eq!(map_renamed_path(&format!("{dir}Mappekunstner\\Mappealbum\\x.mp3"), &log, true), format!("{dir}album\\x.mp3"));
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn rename_case_only_changes_name() {
    let dir = test_dir("case");
    touch(&format!("{dir}abc.mp3"));
    let i = info(&format!("{dir}abc.mp3"), "K", "Abc", "A", "1");
    let o = opt(CaseMode::None, false, true);
    assert_eq!(plan_rename(&[&i], "%7", &o)[0].status, RenameStatus::Unchanged);
    let mut p = plan_rename(&[&i], "%2", &o);
    assert_eq!(p[0].status, RenameStatus::Ok);
    assert_eq!(execute_rename(&mut p).len(), 1);
    assert_eq!(names_in(&dir), ["Abc.mp3"]);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn mask_values_are_sanitized() {
    let i = info("C:\\Musik\\x.mp3", "AC/DC", "What?: a. ", "A", "1");
    let o = opt(CaseMode::None, false, true);
    let r = expand("%1 %2", &i, 1, &o);
    assert_eq!(r, "C:\\Musik\\AC-DC What - a.mp3");
}

#[test]
fn duplicate_targets_rename_only_the_first() {
    let dir = test_dir("dup");
    touch(&format!("{dir}1.mp3"));
    touch(&format!("{dir}2.mp3"));
    let a = info(&format!("{dir}1.mp3"), "K", "Samme", "A", "1");
    let b = info(&format!("{dir}2.mp3"), "K", "Samme", "A", "2");
    let mut p = plan_rename(&[&a, &b], "%2", &opt(CaseMode::None, false, true));
    assert_eq!((p[0].status, p[1].status), (RenameStatus::Ok, RenameStatus::Duplicate));
    execute_rename(&mut p);
    let mut names = names_in(&dir);
    names.sort();
    assert_eq!(names, ["2.mp3", "Samme.mp3"]);
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn undo_reports_missing_and_taken() {
    let dir = test_dir("taken");
    let mut items = Vec::new();
    for (n, artist) in [("1", "A1"), ("2", "A2"), ("3", "A3")] {
        touch(&format!("{dir}{n}.mp3"));
        items.push(info(&format!("{dir}{n}.mp3"), artist, &format!("T{n}"), "Alb", n));
    }
    let refs: Vec<&AudioInfo> = items.iter().collect();
    let mut p = plan_rename(&refs, "%1\\%2", &opt(CaseMode::None, false, true));
    let log = execute_rename(&mut p);
    assert_eq!(log.len(), 3);
    std::fs::remove_file(&log[0].new_name).unwrap(); // renamed file 1 deleted
    touch(&format!("{dir}2.mp3")); // old name 2 taken again
    let mut errors = Vec::new();
    assert_eq!(undo_rename(&log, &mut errors), 1);
    assert_eq!(errors.len(), 2);
    assert!(errors.iter().any(|e| e.ends_with(": der ligger allerede en fil med det navn")), "{errors:?}");
    assert!(errors.iter().any(|e| e.ends_with(": findes ikke længere")), "{errors:?}");
    assert!(exists(&format!("{dir}3.mp3")) && !exists(&format!("{dir}A3")));
    std::fs::remove_dir_all(dir).unwrap();
}
