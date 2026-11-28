//! MusicBrainz web service: query texts and the JSON parsers.
// from: musicbrainz.pas

use super::{jarr, jint, jobj, jstr, Release, ReleaseDetail, Track};
use serde_json::Value;

const MIXED: &str = "Blandet";
pub(crate) const UNEXPECTED: &str = "Uventet svar fra MusicBrainz";

// from: UrlEncode
pub fn url_encode(s: &str) -> String {
    let mut r = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
            r.push(b as char);
        } else {
            r += &format!("%{b:02X}");
        }
    }
    r
}

// from: QuoteTerm — inside quotes only the quote and the backslash need escaping
fn quote_term(s: &str) -> String {
    format!("\"{}\"", s.trim().replace('\\', "\\\\").replace('"', "\\\""))
}

fn and_terms(terms: &[(&str, &str)]) -> String {
    terms
        .iter()
        .filter(|(_, v)| !v.trim().is_empty())
        .map(|(k, v)| format!("{k}:{}", quote_term(v)))
        .collect::<Vec<_>>()
        .join(" AND ")
}

// from: BuildReleaseQuery
pub fn build_release_query(artist: &str, album: &str) -> String {
    and_terms(&[("release", album), ("artist", artist)])
}

// from: BuildRecordingQuery
pub fn build_recording_query(artist: &str, title: &str, album: &str) -> String {
    and_terms(&[("recording", title), ("artist", artist), ("release", album)])
}

/// 'Artist A feat. Artist B' from an artist-credit array.
// from: CreditText
fn credit_text(o: &Value) -> String {
    jarr(o, "artist-credit")
        .iter()
        .filter(|c| c.is_object())
        .map(|c| {
            let mut name = jstr(c, "name");
            if name.is_empty() {
                name = jstr(jobj(c, "artist"), "name");
            }
            name + &jstr(c, "joinphrase")
        })
        .collect()
}

/// 'Compilation', 'Live, Compilation', 'Single' ... from a release group.
// from: ReleaseTypeText
fn release_type_text(g: &Value) -> String {
    let sec: Vec<&str> = jarr(g, "secondary-types").iter().filter_map(|v| v.as_str()).collect();
    if sec.is_empty() { jstr(g, "primary-type") } else { sec.join(", ") }
}

// from: FillRelease
fn fill_release(o: &Value) -> Release {
    let rg = jobj(o, "release-group");
    let mut r = Release {
        id: jstr(o, "id"),
        title: jstr(o, "title"),
        artist: credit_text(o),
        date: jstr(o, "date"),
        country: jstr(o, "country"),
        status: jstr(o, "status"),
        disambiguation: jstr(o, "disambiguation"),
        score: jint(o, "score"),
        track_count: jint(o, "track-count"),
        release_group_id: jstr(rg, "id"),
        release_type: release_type_text(rg),
        ..Default::default()
    };
    let media = jarr(o, "media");
    if !media.is_empty() {
        if r.track_count == 0 {
            r.track_count = media.iter().map(|m| jint(m, "track-count")).sum();
        }
        for m in media {
            let mut fmt = jstr(m, "format");
            if fmt.is_empty() {
                fmt = "?".into();
            }
            if r.formats.is_empty() {
                r.formats = fmt;
            } else if r.formats != fmt {
                r.formats = MIXED.into(); // e.g. CD + DVD
            }
        }
        if media.len() > 1 {
            r.formats = format!("{}×{}", media.len(), r.formats);
        }
    }
    if let Some(l) = jarr(o, "label-info").first() {
        r.label_name = jstr(jobj(l, "label"), "name");
        r.catalog_no = jstr(l, "catalog-number");
    }
    r
}

fn parse(json: &str) -> Option<Value> {
    serde_json::from_str::<Value>(json).ok().filter(|v| v.is_object())
}

// from: ParseSearchJson
pub fn parse_search_json(json: &str) -> Vec<Release> {
    parse(json).map(|root| jarr(&root, "releases").iter().map(fill_release).collect()).unwrap_or_default()
}

// from: CapitalizeGenre
fn capitalize_genre(s: &str) -> String {
    let mut up = true;
    s.chars()
        .map(|c| {
            let c2 = if up && c.is_ascii_lowercase() { c.to_ascii_uppercase() } else { c };
            up = " -/&".contains(c2);
            c2
        })
        .collect()
}

// from: TopGenre — the genre with the highest count
fn top_genre(o: &Value) -> String {
    let mut best = -1;
    let mut r = String::new();
    for g in jarr(o, "genres") {
        if jint(g, "count") > best {
            best = jint(g, "count");
            r = capitalize_genre(&jstr(g, "name"));
        }
    }
    r
}

// from: ParseReleaseJson
pub fn parse_release_json(json: &str) -> Result<ReleaseDetail, String> {
    let o = parse(json).ok_or(UNEXPECTED)?;
    let mut d = ReleaseDetail { release: fill_release(&o), ..Default::default() };
    d.album_artist = d.release.artist.clone();
    d.genre = top_genre(&o);
    let rg = jobj(&o, "release-group");
    if d.genre.is_empty() {
        d.genre = top_genre(rg);
    }
    if jarr(rg, "secondary-types").iter().any(|s| s.as_str().is_some_and(|s| s.eq_ignore_ascii_case("Compilation")))
        || d.album_artist.eq_ignore_ascii_case("Various Artists")
    {
        d.compilation = true;
    }
    let media = jarr(&o, "media");
    d.disc_count = media.len() as i64;
    d.disc_track_counts = vec![0; media.len()];
    for (i, m) in media.iter().enumerate() {
        let tracks = jarr(m, "tracks");
        if m.get("tracks").is_none_or(|t| !t.is_array()) {
            continue;
        }
        d.disc_track_counts[i] = tracks.len() as i64;
        for (j, t) in tracks.iter().enumerate() {
            let rec = jobj(t, "recording");
            let mut tr = Track {
                disc: jint(m, "position"),
                position: jint(t, "position"),
                number: jstr(t, "number"),
                title: jstr(t, "title"),
                artist: credit_text(t),
                length_ms: jint(t, "length"),
            };
            if tr.disc == 0 {
                tr.disc = i as i64 + 1;
            }
            if tr.position == 0 {
                tr.position = j as i64 + 1;
            }
            if tr.title.is_empty() {
                tr.title = jstr(rec, "title");
            }
            if tr.artist.is_empty() {
                tr.artist = credit_text(rec);
            }
            if tr.artist.is_empty() {
                tr.artist = d.album_artist.clone();
            }
            if tr.length_ms == 0 {
                tr.length_ms = jint(rec, "length");
            }
            d.tracks.push(tr);
        }
    }
    Ok(d)
}

// from: SongRank
fn song_rank(r: &Release) -> i32 {
    if !r.status.is_empty() && r.status != "Official" {
        return 3;
    }
    match r.release_type.as_str() {
        "Album" => 0,
        "Single" | "EP" => 1,
        _ => 2, // compilations, live, soundtracks, ...
    }
}

/// '1975' sorts after '1975-11-21': a full date is the better known release.
fn date_key(d: &str) -> String {
    let r = if d.is_empty() { "9999".to_string() } else { d.to_string() };
    match r.len() {
        4 => r + "-99-99",
        7 => r + "-99",
        _ => r,
    }
}

/// One release per release group (official, then the earliest), the original studio album
/// first, then singles/EPs, compilations/live, unofficial; earliest first.
// from: SortSongReleases
pub fn sort_song_releases(r: &mut Vec<Release>) {
    let better = |a: &Release, b: &Release| {
        if (a.status == "Official") != (b.status == "Official") {
            return a.status == "Official";
        }
        date_key(&a.date) < date_key(&b.date)
    };
    let mut kept: Vec<Release> = Vec::new();
    for t in r.drain(..) {
        let found = kept.iter().position(|k| (!t.release_group_id.is_empty() && k.release_group_id == t.release_group_id) || k.id == t.id);
        match found {
            None => kept.push(t),
            Some(f) => {
                if better(&t, &kept[f]) {
                    kept[f] = t;
                }
            }
        }
    }
    let before = |a: &Release, b: &Release| {
        if song_rank(a) != song_rank(b) {
            return song_rank(a) < song_rank(b);
        }
        date_key(&a.date) < date_key(&b.date)
    };
    // insertion sort: stable, and the lists are short
    for i in 1..kept.len() {
        let mut j = i;
        while j > 0 && before(&kept[j], &kept[j - 1]) {
            kept.swap(j, j - 1);
            j -= 1;
        }
    }
    *r = kept;
}

/// The releases of the recordings found, and the earliest first-release date among them.
// from: ParseRecordingsRaw
pub fn parse_recordings_raw(json: &str) -> (Vec<Release>, String) {
    let mut out = Vec::new();
    let mut earliest = String::new();
    let Some(root) = parse(json) else { return (out, earliest) };
    let recs = jarr(&root, "recordings");
    let best = recs.iter().map(|r| jint(r, "score")).max().unwrap_or(0).max(0);
    let mut seen = std::collections::HashSet::new();
    for rec in recs {
        let score = jint(rec, "score");
        // weaker hits are other songs with similar words
        if score < best - 10 || score < 60 {
            continue;
        }
        let first = jstr(rec, "first-release-date");
        if !first.is_empty() && (earliest.is_empty() || first < earliest) {
            earliest = first;
        }
        for rel in jarr(rec, "releases") {
            if !rel.is_object() || !seen.insert(jstr(rel, "id")) {
                continue;
            }
            let mut r = fill_release(rel);
            r.score = score;
            if r.artist.is_empty() {
                r.artist = credit_text(rec);
            }
            let media = jarr(rel, "media");
            if let Some(medium) = media.first() {
                if let Some(t) = jarr(medium, "track").first() {
                    r.hit_disc = jint(medium, "position");
                    r.hit_position = jint(medium, "track-offset") + 1;
                    r.hit_title = jstr(t, "title");
                }
                // the media of a song hit only list that one disc; the release's count is the total
                r.track_count = jint(rel, "track-count");
                r.formats = jstr(medium, "format");
                if media.len() > 1 {
                    r.formats += "…";
                }
            }
            if r.hit_title.is_empty() {
                r.hit_title = jstr(rec, "title");
            }
            out.push(r);
        }
    }
    (out, earliest)
}

// from: ParseRecordingSearchJson
pub fn parse_recording_search_json(json: &str) -> Vec<Release> {
    let (mut r, _) = parse_recordings_raw(json);
    sort_song_releases(&mut r);
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    const RELEASE: &str = include_str!("testdata/release.json");
    const SEARCH: &str = include_str!("testdata/search.json");
    const RECORDING: &str = include_str!("testdata/recording.json");

    // from: webtest.lpr '-- søgesvar'
    #[test]
    fn search_answer() {
        let r = parse_search_json(SEARCH);
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].artist, "Gasolin’");
        assert_eq!(r[0].formats, "12\" Vinyl");
        assert_eq!(format!("{} / {}", r[0].label_name, r[0].catalog_no), "CBS / CBS 80993");
        assert_eq!(r[1].formats, "2×CD");
        assert_eq!(r[1].date, "");
    }

    // from: webtest.lpr '-- udgivelse'
    #[test]
    fn release_detail() {
        let d = parse_release_json(RELEASE).unwrap();
        assert_eq!(d.release.title, "Bedste ændringer");
        assert!(d.compilation);
        assert_eq!(d.genre, "Hard Rock");
        assert_eq!(d.disc_count, 2);
        assert_eq!(d.tracks.len(), 3);
        assert_eq!(d.tracks[0].artist, "Kunstner A feat. Gæst");
        assert_eq!((d.tracks[2].disc, d.tracks[2].position), (2, 1));
        assert_eq!(d.tracks[2].length_ms, 99000);
    }

    // from: webtest.lpr '-- sangsøgning'
    #[test]
    fn recording_search() {
        let r = parse_recording_search_json(RECORDING);
        assert_eq!(r.len(), 4, "{r:?}");
        let ids: Vec<&str> = r.iter().map(|x| x.id.as_str()).collect();
        assert_eq!(ids.join(" "), "alb single comp boot");
        assert_eq!(r[0].release_type, "Album");
        assert_eq!(r[2].release_type, "Compilation");
        assert_eq!((r[0].hit_disc, r[0].hit_position), (1, 3));
        assert_eq!(r[2].artist, "Bandet");
        assert_eq!(r[2].track_count, 21);
    }

    #[test]
    fn queries_and_url_encoding() {
        assert_eq!(
            build_recording_query("Gasolin'", "Rabalderstræde", ""),
            "recording:\"Rabalderstræde\" AND artist:\"Gasolin'\""
        );
        assert_eq!(url_encode("Æ ø/\""), "%C3%86%20%C3%B8%2F%22");
        assert_eq!(build_release_query("A \"B\"", ""), "artist:\"A \\\"B\\\"\"");
    }

    #[test]
    fn unexpected_answer_is_an_error() {
        assert_eq!(parse_release_json("[1]").unwrap_err(), "Uventet svar fra MusicBrainz");
    }
}
