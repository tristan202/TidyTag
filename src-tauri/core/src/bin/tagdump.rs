//! tagdump --json <file|dir> [-r]: one JSON record per audio file, the same format as 1.2's
//! tools\tagdump.exe --json, so the two can be compared.

use std::path::{Path, PathBuf};
use tidytag_core::{dump::json_record, read};

fn walk(dir: &Path, recursive: bool) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    let mut files: Vec<PathBuf> = Vec::new();
    let mut dirs: Vec<PathBuf> = Vec::new();
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() {
            dirs.push(p);
        } else if read::is_audio_file(&p) {
            files.push(p);
        }
    }
    files.sort_by_key(|p| p.to_string_lossy().to_lowercase());
    dirs.sort_by_key(|p| p.to_string_lossy().to_lowercase());
    for f in files {
        println!("{}", json_record(&read::read_audio_info(&f, true)));
    }
    if recursive {
        for d in dirs {
            walk(&d, true);
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let recursive = args.iter().any(|a| a == "-r");
    let Some(target) = args.iter().find(|a| !a.starts_with('-')) else {
        eprintln!("usage: tagdump --json <folder-or-file> [-r]");
        std::process::exit(1);
    };
    let p = Path::new(target);
    if p.is_dir() {
        walk(p, recursive);
    } else {
        println!("{}", json_record(&read::read_audio_info(p, true)));
    }
}
