//! Cross-check against TidyTag 1.2: every file in $TIDYTAG_CORPUS\expected.jsonl (written by
//! 1.2's `tagdump --json`, see tools\make-corpus.ps1) must read the same in 2.0.

use serde_json::Value;
use std::path::Path;
use tidytag_core::{dump::json_record, read::read_audio_info};

fn pictures_key(v: &Value) -> Vec<String> {
    v.as_array()
        .map(|a| a.iter().map(|p| format!("{}|{}|{}|{}", p["type"], p["mime"], p["description"], p["size"])).collect())
        .unwrap_or_default()
}

#[test]
fn golden_matches_tidytag_1_2() {
    let Ok(corpus) = std::env::var("TIDYTAG_CORPUS") else {
        println!("skipped: TIDYTAG_CORPUS not set");
        return;
    };
    let text = std::fs::read_to_string(Path::new(&corpus).join("expected.jsonl")).expect("expected.jsonl");
    let mut problems = Vec::new();
    let mut n = 0;
    for line in text.lines().filter(|l| !l.trim().is_empty()) {
        let exp: Value = serde_json::from_str(line.trim_start_matches('\u{FEFF}')).expect("valid JSON");
        let file = exp["file"].as_str().unwrap().to_string();
        let got = json_record(&read_audio_info(Path::new(&file), true));
        n += 1;
        let name = Path::new(&file).file_name().unwrap().to_string_lossy().to_string();
        for key in ["fileSize", "supported", "error", "codec", "tagTypes", "hasCover", "bitrate", "sampleRate", "channels", "bitDepth"] {
            if exp[key] != got[key] {
                problems.push(format!("{name}: {key}: expected {}, got {}", exp[key], got[key]));
            }
        }
        let (de, dg) = (exp["durationMs"].as_i64().unwrap_or(0), got["durationMs"].as_i64().unwrap_or(0));
        if (de - dg).abs() > 1 {
            problems.push(format!("{name}: durationMs: expected {de}, got {dg}"));
        }
        let empty = serde_json::Map::new();
        let (fe, fg) = (exp["fields"].as_object().unwrap_or(&empty), got["fields"].as_object().unwrap_or(&empty));
        let mut keys: Vec<&String> = fe.keys().chain(fg.keys()).collect();
        keys.sort();
        keys.dedup();
        for k in keys {
            if fe.get(k) != fg.get(k) {
                let show = |v: Option<&Value>| v.map(|v| { let s = v.to_string(); if s.len() > 80 { format!("{}…", &s[..s.char_indices().nth(80).map(|c| c.0).unwrap_or(s.len())]) } else { s } }).unwrap_or("(none)".into());
                problems.push(format!("{name}: fields.{k}: expected {}, got {}", show(fe.get(k)), show(fg.get(k))));
            }
        }
        if pictures_key(&exp["pictures"]) != pictures_key(&got["pictures"]) {
            problems.push(format!("{name}: pictures: expected {:?}, got {:?}", pictures_key(&exp["pictures"]), pictures_key(&got["pictures"])));
        }
    }
    for p in &problems {
        println!("{p}");
    }
    println!("{n} files, {} mismatches", problems.len());
    assert!(problems.is_empty(), "{} mismatches against TidyTag 1.2", problems.len());
}
