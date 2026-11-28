//! Discogs API: the JSON parsers. Results use the same records as MusicBrainz.
// from: discogs.pas

use super::{jarr, jstr, Release, ReleaseDetail, Track};
use serde_json::Value;

pub(crate) const UNEXPECTED: &str = "Uventet svar fra Discogs";

fn arr_str(a: &[Value], i: usize) -> String {
    a.get(i).and_then(|v| v.as_str()).unwrap_or("").to_string()
}

/// 'Kim Larsen (2)' -> 'Kim Larsen'; 'Various' -> 'Various Artists'.
// from: CleanDiscogsName
pub fn clean_discogs_name(s: &str) -> String {
    let mut r = s.trim().to_string();
    // trailing ' (n)' added by Discogs to tell same-named artists apart
    let b = r.as_bytes();
    if b.len() > 3 && b[b.len() - 1] == b')' {
        let mut p = b.len() - 1; // index of ')'
        while p > 0 && b[p - 1].is_ascii_digit() {
            p -= 1;
        }
        // p - 1 is '(' and p - 2 a space, with at least one digit between
        if p >= 2 && p < b.len() - 1 && b[p - 1] == b'(' && b[p - 2] == b' ' {
            r.truncate(p - 2);
        }
    }
    if r.eq_ignore_ascii_case("Various") {
        r = "Various Artists".into();
    }
    r
}

/// 'Artist A & Artist B' from an artists array (anv = name variation used on the release).
// from: ArtistsText
fn artists_text(a: &[Value]) -> String {
    let mut r = String::new();
    for (i, o) in a.iter().enumerate() {
        let mut name = jstr(o, "anv");
        if name.is_empty() {
            name = jstr(o, "name");
        }
        r += &clean_discogs_name(&name);
        let join = jstr(o, "join").trim().to_string();
        if i + 1 < a.len() {
            if join.is_empty() || join == "," {
                r += &join;
                r.push(' ');
            } else {
                r += &format!(" {join} ");
            }
        }
    }
    r.trim().to_string()
}

/// '2-05' -> disc 2; 'CD2-3' -> disc 2; 'A1' -> disc 1.
// from: DiscogsDisc
pub fn discogs_disc(position: &str) -> i64 {
    let mut s = position.trim().to_uppercase();
    if s.starts_with("CD") {
        s.drain(..2);
    }
    if s.starts_with("DVD") {
        s.drain(..3);
    }
    let b = s.as_bytes();
    let digits = b.iter().take_while(|c| c.is_ascii_digit()).count();
    let mut r = 1;
    if digits > 0 && digits + 1 < b.len() && (b[digits] == b'-' || b[digits] == b'.') {
        r = s[..digits].parse().unwrap_or(1);
    }
    r.max(1)
}

/// Discogs durations are 'm:ss' or 'h:mm:ss'.
// from: DurationMs
pub fn duration_ms(s: &str) -> i64 {
    let s = s.trim();
    if s.is_empty() {
        return 0;
    }
    s.split(':').fold(0i64, |acc, p| acc * 60 + p.trim().parse::<i64>().unwrap_or(0)) * 1000
}

fn parse(json: &str) -> Option<Value> {
    serde_json::from_str::<Value>(json).ok().filter(|v| v.is_object())
}

// from: ParseDiscogsSearchJson
pub fn parse_discogs_search_json(json: &str) -> Vec<Release> {
    let Some(root) = parse(json) else { return Vec::new() };
    jarr(&root, "results")
        .iter()
        .map(|o| {
            // search titles are 'Artist - Album'
            let full = jstr(o, "title");
            let (artist, title) = match full.find(" - ") {
                Some(i) => (clean_discogs_name(&full[..i]), full[i + 3..].to_string()),
                None => (String::new(), full.clone()),
            };
            let fmt = jarr(o, "format");
            let formats = (0..fmt.len().min(3)).map(|j| arr_str(fmt, j)).collect::<Vec<_>>().join(", ");
            // the format list mixes media and descriptions: 'CD', 'Album', 'Compilation', ...
            let mut release_type = String::new();
            for j in 0..fmt.len() {
                let f = arr_str(fmt, j);
                if f == "Compilation" {
                    release_type = f;
                } else if release_type.is_empty() && (f == "Single" || f == "EP" || f == "Album") {
                    release_type = f;
                } else if release_type.is_empty() && f == "LP" {
                    release_type = "Album".into();
                }
            }
            Release {
                id: jstr(o, "id"),
                artist,
                title,
                date: jstr(o, "year"),
                country: jstr(o, "country"),
                release_group_id: jstr(o, "master_id"),
                formats,
                release_type,
                label_name: arr_str(jarr(o, "label"), 0),
                catalog_no: jstr(o, "catno"),
                ..Default::default()
            }
        })
        .collect()
}

// from: ParseDiscogsReleaseJson
pub fn parse_discogs_release_json(json: &str) -> Result<ReleaseDetail, String> {
    let o = parse(json).ok_or(UNEXPECTED)?;
    // 'released' may be '1975-10-14', '1975-00-00' or empty
    let mut released = jstr(&o, "released");
    if released.get(4..10) == Some("-00-00") {
        released.truncate(4);
    } else if released.get(7..10) == Some("-00") {
        released.truncate(7);
    }
    if released.is_empty() {
        released = jstr(&o, "year");
    }
    if released == "0" {
        released.clear();
    }
    let label = jarr(&o, "labels").first().cloned().unwrap_or(Value::Null);
    let formats = jarr(&o, "formats")
        .iter()
        .map(|f| {
            let qty = jstr(f, "qty");
            format!("{}{}", if qty != "1" { format!("{qty}×") } else { String::new() }, jstr(f, "name"))
        })
        .collect::<Vec<_>>()
        .join(" + ");
    let mut d = ReleaseDetail {
        release: Release {
            id: jstr(&o, "id"),
            title: jstr(&o, "title"),
            artist: artists_text(jarr(&o, "artists")),
            country: jstr(&o, "country"),
            release_group_id: jstr(&o, "master_id"),
            date: released,
            label_name: clean_discogs_name(&jstr(&label, "name")),
            catalog_no: jstr(&label, "catno"),
            formats,
            ..Default::default()
        },
        ..Default::default()
    };
    d.album_artist = d.release.artist.clone();
    d.compilation = d.album_artist.eq_ignore_ascii_case("Various Artists");
    // style is more specific than genre ('Hard Rock' vs 'Rock')
    d.genre = arr_str(jarr(&o, "styles"), 0);
    if d.genre.is_empty() {
        d.genre = arr_str(jarr(&o, "genres"), 0);
    }
    // primary image first, else the first one
    for img in jarr(&o, "images") {
        if d.cover_url.is_empty() || jstr(img, "type") == "primary" {
            d.cover_url = jstr(img, "uri");
            if jstr(img, "type") == "primary" {
                break;
            }
        }
    }
    let mut counts: Vec<i64> = Vec::new();
    for t in jarr(&o, "tracklist") {
        let kind = jstr(t, "type_");
        // 'heading' = section title, not a track; 'index' = a track made of sub-tracks
        if !kind.is_empty() && kind != "track" && kind != "index" {
            continue;
        }
        let disc = discogs_disc(&jstr(t, "position"));
        if disc as usize > counts.len() {
            counts.resize(disc as usize, 0);
        }
        counts[disc as usize - 1] += 1;
        let mut artist = artists_text(jarr(t, "artists"));
        if artist.is_empty() {
            artist = d.album_artist.clone();
        }
        d.tracks.push(Track {
            number: jstr(t, "position"),
            disc,
            position: counts[disc as usize - 1],
            title: jstr(t, "title"),
            artist,
            length_ms: duration_ms(&jstr(t, "duration")),
        });
    }
    d.disc_count = counts.len() as i64;
    d.disc_track_counts = counts;
    d.release.track_count = d.tracks.len() as i64;
    Ok(d)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SEARCH: &str = include_str!("testdata/discogs_search.json");
    const RELEASE: &str = include_str!("testdata/discogs_release.json");
    const MULTI: &str = include_str!("testdata/discogs_multi_disc.json");

    // from: webtest.lpr '-- Discogs'
    #[test]
    fn names_and_disc_positions() {
        assert_eq!(clean_discogs_name("Kim Larsen (2)"), "Kim Larsen");
        assert_eq!(clean_discogs_name("Blink-182"), "Blink-182");
        assert_eq!(clean_discogs_name("Various"), "Various Artists");
        assert_eq!((discogs_disc("A1"), discogs_disc("2-05"), discogs_disc("CD3-1"), discogs_disc("12")), (1, 2, 3, 1));
        assert_eq!(duration_ms("1:02:03"), 3723000);
    }

    #[test]
    fn search_results() {
        let r = parse_discogs_search_json(SEARCH);
        assert_eq!(r.len(), 2);
        assert_eq!(format!("{} / {}", r[0].artist, r[0].title), "Gasolin' / Gas 5");
        assert_eq!(r[0].formats, "Vinyl, LP, Album");
        assert_eq!(r[0].release_type, "Album");
        assert_eq!(format!("{} {}", r[0].label_name, r[0].catalog_no), "CBS CBS 80993");
        assert_eq!(r[0].id, "1234");
        assert_eq!(format!("{}|{}", r[1].artist, r[1].title), "|Gasolin'");
    }

    #[test]
    fn release_detail() {
        let d = parse_discogs_release_json(RELEASE).unwrap();
        assert_eq!(d.release.artist, "Gasolin'");
        assert_eq!(d.release.date, "1975");
        assert_eq!(d.release.label_name, "CBS");
        assert_eq!(d.genre, "Hard Rock");
        assert_eq!(d.cover_url, "https://i.discogs.com/front.jpg");
        assert_eq!(d.tracks.len(), 3);
        assert_eq!(d.tracks[0].title, "Rabalderstræde");
        assert_eq!(d.tracks[0].artist, "Gasolin'");
        assert_eq!(d.tracks[1].artist, "Kim & Franz Beckerlee");
        assert_eq!((d.tracks[2].position, d.tracks[2].number.as_str()), (3, "B1"));
        assert_eq!(d.tracks[2].length_ms, 3723000);
        assert_eq!((d.disc_count, d.disc_track_counts.clone()), (1, vec![3]));
    }

    #[test]
    fn multi_disc_release() {
        let d = parse_discogs_release_json(MULTI).unwrap();
        assert!(d.compilation);
        assert_eq!(d.release.date, "2001-05");
        assert_eq!(d.disc_count, 2);
        assert_eq!((d.tracks[3].disc, d.tracks[3].position), (2, 2));
    }

    #[test]
    fn unexpected_answer_is_an_error() {
        assert_eq!(parse_discogs_release_json("\"x\"").unwrap_err(), "Uventet svar fra Discogs");
    }
}
