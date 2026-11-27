//! Rename cross-check against TidyTag 1.2: every case in $TIDYTAG_CORPUS\rename.jsonl (written by
//! tools\make-rename-corpus.ps1 with 1.2's renamedump) must give the same result in 2.0. The mask
//! lists below must match tools\renamedump.lpr.

use std::collections::BTreeMap;
use std::path::Path;
use tidytag_core::filename_tags::match_file_name;
use tidytag_core::model::TagField;
use tidytag_core::read::read_audio_info;
use tidytag_core::rename::{expand_rename_mask, plan_folder_rename, status_text, CaseMode, RenameOptions};

const FILE_MASKS: [&str; 10] = [
    "%1 - %2", "%6 - %2", "%6 - %1 - %2", "%1 - %3 - %6 - %2", "%1\\%3\\%6 - %2", "%aa\\%4 - %3\\%6 - %2",
    "%7 (%0 kbit, %t)", "%cat %key %khz %ext %grp", "%# %b %9 %5", "%rt %enc %dbit %cp %co %lb %rb %md",
];
const FOLDER_MASKS: [&str; 2] = ["%1 - %4 - %3", "%aa\\%3"];
const F2T_MASKS: [&str; 7] = ["%1 - %2", "%6 - %2", "%6 - %1 - %2", "%6. %2", "%6 %1 - %2", "%1\\%3\\%6 - %2", "%1\\%4 - %3\\%6 - %2"];

fn options(case: i64, us: bool, words: bool) -> RenameOptions {
    let mut o = RenameOptions { case_mode: CaseMode::from_index(case), spaces_to_underscores: us, pad_track: true, ..Default::default() };
    if words {
        o.keep_case_words = vec!["AC/DC".into(), "ABBA".into()];
        o.replace_from = vec![" & ".into()];
        o.replace_to = vec![" and ".into()];
    }
    o
}

/// renamedump's Placeholders: the file's folder as '<dir>', its parent as '<parent>'.
/// Also: 1.2's ExpandFileName goes through the ANSI code page (1252), so every character it
/// cannot hold becomes '?' — 1.2 then cannot rename such a file at all, as '?' is not allowed
/// in a file name. 2.0 keeps the characters; for the comparison they count as '?'. U+FFFD (2.0's
/// reading of invalid UTF-8, which 1.2 decodes as '?') falls under the same rule.
fn placeholders(s: &str, dir: &str, parent: &str) -> String {
    let s = &fffd(s);
    let starts = |p: &str| s.len() >= p.len() && s.is_char_boundary(p.len()) && s[..p.len()].to_lowercase() == p.to_lowercase();
    if !dir.is_empty() && starts(dir) {
        format!("<dir>\\{}", &s[dir.len()..])
    } else if !parent.is_empty() && starts(parent) {
        format!("<parent>\\{}", &s[parent.len()..])
    } else {
        s.to_string()
    }
}

fn fffd(s: &str) -> String {
    const CP1252: &str = "€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ";
    s.chars().map(|c| if (c as u32) < 0x100 || CP1252.contains(c) { c } else { '?' }).collect()
}

type Key =(String, String, String, i64, bool, bool);

fn cases_for(path: &str) -> BTreeMap<Key, (String, String, String)> {
    let info = read_audio_info(Path::new(path), false);
    let dir = format!("{}\\", &path[..path.rfind('\\').unwrap()]);
    let parent = format!("{}\\", &dir[..dir[..dir.len() - 1].rfind('\\').unwrap()]);
    let name = path.rsplit('\\').next().unwrap().to_string();
    let ph = |s: &str| placeholders(s, &dir, &parent);
    let mut out = BTreeMap::new();
    for case in 0..5 {
        for us in [false, true] {
            for words in [false, true] {
                let o = options(case, us, words);
                for m in FILE_MASKS {
                    let (r, missing) = expand_rename_mask(m, &info, 1, 2, &o);
                    out.insert((name.clone(), "file".into(), m.into(), case, us, words), (ph(&r), String::new(), fffd(&missing)));
                }
                for m in FOLDER_MASKS {
                    let p = plan_folder_rename(&[&info], m, &o);
                    out.insert(
                        (name.clone(), "folder".into(), m.into(), case, us, words),
                        (ph(&p[0].new_name), status_text(p[0].status).into(), p[0].detail.clone()),
                    );
                }
            }
        }
    }
    let mut subjects = vec![path.to_string()];
    for m in FILE_MASKS {
        let (r, _) = expand_rename_mask(m, &info, 1, 2, &options(0, false, false));
        if !r.is_empty() {
            subjects.push(r);
        }
    }
    for s in &subjects {
        for m in F2T_MASKS {
            for case in 0..2 {
                let mt = match_file_name(m, s, case == 0, CaseMode::from_index(case));
                let mut vals = String::new();
                if mt.ok {
                    for f in &mt.used {
                        let ord = TagField::ALL.iter().position(|x| x == f).unwrap();
                        vals.push_str(&format!("{ord}={};", mt.values[f]));
                    }
                }
                out.insert(
                    (name.clone(), "f2t".into(), format!("{m} @ {}", ph(s)), case, case == 0, false),
                    (fffd(&vals), if mt.ok { "ok" } else { "no" }.into(), String::new()),
                );
            }
        }
    }
    out
}

#[test]
fn golden_rename_matches_tidytag_1_2() {
    let Ok(corpus) = std::env::var("TIDYTAG_CORPUS") else {
        println!("skipped: TIDYTAG_CORPUS not set");
        return;
    };
    let corpus = corpus.replace('/', "\\");
    let text = std::fs::read_to_string(format!("{corpus}\\rename.jsonl")).expect("run tools\\make-rename-corpus.ps1 first");
    let mut by_file: BTreeMap<String, BTreeMap<Key, (String, String, String)>> = BTreeMap::new();
    let mut problems = Vec::new();
    let mut lines = 0;
    for line in text.lines().filter(|l| !l.trim().is_empty()) {
        lines += 1;
        let j: serde_json::Value = serde_json::from_str(line).unwrap();
        let s = |k: &str| j[k].as_str().unwrap_or_default().to_string();
        let file = s("file");
        let ours = by_file.entry(file.clone()).or_insert_with(|| cases_for(&format!("{corpus}\\files\\{file}")));
        let key = (file, s("kind"), s("mask"), j["case"].as_i64().unwrap(), j["us"].as_bool().unwrap(), j["words"].as_bool().unwrap());
        let want = (s("result"), s("status"), s("missing"));
        match ours.get(&key) {
            Some(got) if *got == want => {}
            Some(got) => problems.push(format!("{key:?}\n   1.2: {want:?}\n   2.0: {got:?}")),
            None => problems.push(format!("{key:?}: no such case in 2.0")),
        }
    }
    for p in problems.iter().take(30) {
        println!("{p}");
    }
    println!("{lines} lines, {} mismatches", problems.len());
    assert!(problems.is_empty(), "{} mismatches against TidyTag 1.2", problems.len());
}
