//! tagset <file> key=value ...  |  tagset --scenario N <file>  |  tagset --remove <file>
//! The same command line as 1.2's tools\tagset.exe. Prints 'ok' or 'FEJL: <text>' (exit code 1).

use std::path::Path;
use tidytag_core::model::TagField;
use tidytag_core::read::read_audio_info;
use tidytag_core::write::{write_audio_tags, WriteOptions};
use tidytag_core::scenario;
use tidytag_core::tagremove::remove_all_tags;

const NAMES: [&str; 37] = [
    "title", "artist", "album", "year", "track", "disc", "genre", "comment", "albumartist", "composer", "bpm",
    "lyrics", "conductor", "lyricist", "origartist", "remixer", "label", "catalog", "isrc", "copyright",
    "encodedby", "url", "grouping", "subtitle", "mood", "key", "sorttitle", "sortartist", "sortalbumartist",
    "sortalbum", "sortcomposer", "compilation", "podcast", "replaygain_track_gain", "replaygain_track_peak",
    "replaygain_album_gain", "replaygain_album_peak",
];

fn fail(msg: &str) -> ! {
    println!("FEJL: {msg}");
    std::process::exit(1);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() == 2 && args[0] == "--remove" {
        if let Err(e) = remove_all_tags(Path::new(&args[1]), &WriteOptions::default()) {
            fail(&e);
        }
        println!("ok");
        return;
    }
    let (scen, first) = match args.first().map(String::as_str) {
        Some("--scenario") if args.len() >= 3 => (args[1].parse::<u8>().ok(), 2),
        _ => (None, 0),
    };
    if args.len() < first + 1 || (scen.is_none() && args.len() < 2) {
        println!("Brug: tagset <fil> felt=værdi ...  |  tagset --scenario N <fil>");
        std::process::exit(2);
    }
    let mut info = read_audio_info(Path::new(&args[first]), true);
    if !info.error.is_empty() {
        fail(&info.error.clone());
    }
    match scen {
        Some(n) => scenario::apply(&mut info, n),
        None => {
            for a in &args[first + 1..] {
                let (k, v) = a.split_once('=').unwrap_or((a, ""));
                match NAMES.iter().position(|n| *n == k.to_lowercase()) {
                    Some(i) => info.put(TagField::ALL[i], v),
                    None => {
                        println!("Ukendt felt: {k}");
                        std::process::exit(2);
                    }
                }
            }
        }
    }
    if let Err(e) = write_audio_tags(&mut info, &WriteOptions::default()) {
        fail(&e);
    }
    println!("ok");
}
