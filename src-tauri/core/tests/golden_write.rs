//! Write cross-check against TidyTag 1.2: every corpus file goes through tagtest's scenarios
//! 0, 1 and 2 with 2.0's writers, and after each step must be byte for byte what 1.2 wrote
//! ($TIDYTAG_CORPUS\written\<name>.s<N>, made by tools\make-write-corpus.ps1), or give the same
//! error text (<name>.s<N>.err).

use std::path::Path;
use tidytag_core::dump::json_record;
use tidytag_core::read::read_audio_info;
use tidytag_core::scenario;
use tidytag_core::write::{write_audio_tags, WriteOptions};

#[test]
fn golden_write_matches_tidytag_1_2() {
    let Ok(corpus) = std::env::var("TIDYTAG_CORPUS") else {
        println!("skipped: TIDYTAG_CORPUS not set");
        return;
    };
    let corpus = Path::new(&corpus);
    let only = std::env::var("TIDYTAG_ONLY").unwrap_or_default(); // e.g. "mp3" while porting
    let work = std::env::temp_dir().join(format!("tidytag-golden-write-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&work);
    std::fs::create_dir_all(&work).unwrap();
    let mut files: Vec<_> = std::fs::read_dir(corpus.join("files")).unwrap().flatten().map(|e| e.path()).collect();
    files.sort();
    let mut problems = Vec::new();
    let mut steps = 0;
    for src in files {
        let name = src.file_name().unwrap().to_string_lossy().to_string();
        let ext = src.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
        if !only.is_empty() && !only.split(',').any(|o| o == ext) {
            continue;
        }
        let copy = work.join(&name);
        std::fs::copy(&src, &copy).unwrap();
        for s in 0..3u8 {
            steps += 1;
            let expected = corpus.join("written").join(format!("{name}.s{s}"));
            let expected_err = corpus.join("written").join(format!("{name}.s{s}.err"));
            let mut info = read_audio_info(&copy, true);
            let result = if info.error.is_empty() {
                scenario::apply(&mut info, s);
                write_audio_tags(&mut info, &WriteOptions::default())
            } else {
                Err(info.error.clone())
            };
            match (result, expected_err.exists()) {
                (Err(e), true) => {
                    let want = std::fs::read_to_string(&expected_err).unwrap();
                    if e.trim() != want.trim() {
                        problems.push(format!("{name} s{s}: error {e:?}, 1.2 said {want:?}"));
                    }
                }
                (Err(e), false) => problems.push(format!("{name} s{s}: 2.0 failed: {e}")),
                (Ok(()), true) => problems.push(format!("{name} s{s}: 2.0 wrote, 1.2 failed")),
                (Ok(()), false) => {
                    let (got, want) = (std::fs::read(&copy).unwrap(), std::fs::read(&expected).unwrap());
                    if got != want {
                        let at = got.iter().zip(&want).position(|(a, b)| a != b).unwrap_or(got.len().min(want.len()));
                        problems.push(format!("{name} s{s}: first difference at byte {at} (1.2 {}, 2.0 {})", want.len(), got.len()));
                        // reading must at least agree: 2.0's reading of both files
                        let theirs = work.join(format!("1.2-{name}"));
                        std::fs::write(&theirs, &want).unwrap();
                        let (a, mut b) = (json_record(&read_audio_info(&copy, true)), json_record(&read_audio_info(&theirs, true)));
                        b["file"] = a["file"].clone();
                        if a != b {
                            problems.push(format!("{name} s{s}:   ...and the tags read differently"));
                        }
                        // carry on from 1.2's file so later steps are compared fairly
                        std::fs::write(&copy, &want).unwrap();
                    }
                }
            }
        }
    }
    let _ = std::fs::remove_dir_all(&work);
    for p in &problems {
        println!("{p}");
    }
    println!("{steps} steps, {} mismatches", problems.len());
    assert!(problems.is_empty(), "{} mismatches against TidyTag 1.2", problems.len());
}
