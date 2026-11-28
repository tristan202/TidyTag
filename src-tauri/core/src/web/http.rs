//! HTTP for the web lookup: the real client, the rate limits and the calls to MusicBrainz,
//! the Cover Art Archive and Discogs. The network sits behind `Fetch`, so tests run offline.
// from: musicbrainz.pas (HttpGet, MBGet, Search*, GetReleaseDetail, GetFrontCover),
//       discogs.pas (DiscogsGet, DiscogsSearch, DiscogsRelease, DiscogsCover)

use super::discogs::{parse_discogs_release_json, parse_discogs_search_json};
use super::musicbrainz::{
    build_recording_query, build_release_query, parse_recordings_raw, parse_release_json, parse_search_json, sort_song_releases, url_encode,
};
use super::{Release, ReleaseDetail};
use std::sync::Mutex;

const MB_BUSY: &str = "MusicBrainz har travlt lige nu (503). Prøv igen om et øjeblik.";
const MB_UNKNOWN: &str = "MusicBrainz kender ikke denne udgivelse";
const MB_ERROR: &str = "MusicBrainz svarede med fejl %d";
const NEED_ARTIST_OR_ALBUM: &str = "Skriv kunstner og/eller album";
const NEED_TITLE: &str = "Skriv sangens titel";
const DG_TOO_MANY: &str = "Discogs: for mange forespørgsler - vent et minut og prøv igen.";
const DG_TOKEN_REFUSED: &str = "Discogs afviste dit token. Tjek det under \"Discogs-token...\".";
const DG_UNKNOWN: &str = "Discogs kender ikke denne udgivelse";
const DG_ERROR: &str = "Discogs svarede med fejl %d";
const DG_NEED_TOKEN: &str = "Søgning på Discogs kræver et personligt token. Tryk \"Discogs-token...\" og indsæt det token, du kan lave på discogs.com under Settings > Developers.";
const NO_CONNECTION: &str = "Ingen forbindelse til %s (fejl %d). Tjek internetforbindelsen.";
const CUT_OFF: &str = "Forbindelsen blev afbrudt (fejl %d)";

/// The network and a clock. Errors are 1.2's texts as "<text>|<arg>|...".
pub trait Fetch: Send + Sync {
    /// The status code and the body; Err only when there is no answer at all.
    fn get(&self, url: &str, headers: &[(&str, String)]) -> Result<(u16, Vec<u8>), String>;
    fn sleep(&self, ms: u64);
    fn now_ms(&self) -> u64;
}

/// Keeps requests to one service at least 1.1 s apart (process-wide in the app: one `Web`).
#[derive(Default)]
struct Limiter {
    last: Mutex<Option<u64>>,
}

impl Limiter {
    fn wait(&self, f: &dyn Fetch) {
        let mut last = self.last.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(l) = *last {
            let since = f.now_ms().saturating_sub(l);
            if since < 1100 {
                f.sleep(1100 - since);
            }
        }
        *last = Some(f.now_ms());
    }
}

/// The real network: Windows' TLS (Schannel), 20 s timeouts, an identifying User-Agent.
// from: HttpGet
pub struct Http {
    client: Option<reqwest::blocking::Client>,
    start: std::time::Instant,
}

impl Http {
    pub fn new() -> Http {
        let client = reqwest::blocking::Client::builder()
            .user_agent(format!("TidyTag/{} ( https://github.com/tristan202/TidyTag )", env!("CARGO_PKG_VERSION")))
            .connect_timeout(std::time::Duration::from_secs(20))
            .timeout(std::time::Duration::from_secs(60))
            .build()
            .ok();
        Http { client, start: std::time::Instant::now() }
    }
}

impl Default for Http {
    fn default() -> Self {
        Http::new()
    }
}

fn host_of(url: &str) -> &str {
    let rest = url.split_once("://").map(|(_, r)| r).unwrap_or(url);
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    host.rsplit('@').next().unwrap_or(host).split(':').next().unwrap_or("")
}

impl Fetch for Http {
    fn get(&self, url: &str, headers: &[(&str, String)]) -> Result<(u16, Vec<u8>), String> {
        let no_connection = || format!("{NO_CONNECTION}|{}|0", host_of(url));
        let client = self.client.as_ref().ok_or_else(no_connection)?;
        let mut req = client.get(url).header("Accept", "application/json, image/*");
        for (k, v) in headers {
            req = req.header(*k, v);
        }
        let resp = req.send().map_err(|_| no_connection())?;
        let status = resp.status().as_u16();
        let body = resp.bytes().map_err(|_| format!("{CUT_OFF}|0"))?;
        Ok((status, body.to_vec()))
    }
    fn sleep(&self, ms: u64) {
        std::thread::sleep(std::time::Duration::from_millis(ms));
    }
    fn now_ms(&self) -> u64 {
        self.start.elapsed().as_millis() as u64
    }
}

/// `Authorization: Discogs token=…` — only for discogs.com hosts and a token that is set.
// from: AuthHeader (1.2 sent it to every cover URL; 2.0 keeps the token on Discogs)
pub fn auth_header(url: &str, token: &str) -> Option<(&'static str, String)> {
    let host = host_of(url).to_ascii_lowercase();
    let token = token.trim();
    if token.is_empty() || !(host == "discogs.com" || host.ends_with(".discogs.com")) {
        return None;
    }
    Some(("Authorization", format!("Discogs token={token}")))
}

/// [Web] Source: 0 MusicBrainz, 1 Discogs.
// from: TWebSource
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    MusicBrainz,
    Discogs,
}

impl Source {
    pub fn from_index(i: usize) -> Source {
        if i == 1 { Source::Discogs } else { Source::MusicBrainz }
    }
}

/// The web calls, with one rate limiter per service.
pub struct Web<F: Fetch> {
    pub fetch: F,
    mb: Limiter,
    discogs: Limiter,
}

impl<F: Fetch> Web<F> {
    pub fn new(fetch: F) -> Self {
        Web { fetch, mb: Limiter::default(), discogs: Limiter::default() }
    }

    fn get_ok(&self, url: &str, headers: &[(&str, String)]) -> Option<Vec<u8>> {
        match self.fetch.get(url, headers) {
            Ok((200, b)) => Some(b),
            _ => None,
        }
    }

    /// MusicBrainz request with the 1-per-second limit. 503 means MusicBrainz is shedding
    /// load (it happens even within the limit), so retry with growing pauses.
    // from: MBGet
    pub fn mb_get(&self, path_and_query: &str) -> Result<String, String> {
        const PAUSE: [u64; 3] = [1500, 3000, 5000];
        for attempt in 1..=4 {
            self.mb.wait(&self.fetch);
            let (status, data) = self.fetch.get(&format!("https://musicbrainz.org/ws/2/{path_and_query}"), &[])?;
            match status {
                200 => return Ok(String::from_utf8_lossy(&data).into_owned()),
                503 if attempt < 4 => self.fetch.sleep(PAUSE[attempt - 1]),
                503 => return Err(MB_BUSY.into()),
                404 => return Err(MB_UNKNOWN.into()),
                s => return Err(format!("{MB_ERROR}|{s}")),
            }
        }
        Err(MB_BUSY.into())
    }

    // from: SearchReleases
    pub fn search_releases(&self, artist: &str, album: &str) -> Result<Vec<Release>, String> {
        let q = build_release_query(artist, album);
        if q.is_empty() {
            return Err(NEED_ARTIST_OR_ALBUM.into());
        }
        Ok(parse_search_json(&self.mb_get(&format!("release/?query={}&fmt=json&limit=40", url_encode(&q)))?))
    }

    /// Releases that contain a song. Famous songs have hundreds of recordings with the same
    /// score, and the original need not be among the first 100: ask once more for recordings
    /// released no later than the earliest one found.
    // from: SearchRecordings
    pub fn search_recordings(&self, artist: &str, title: &str, album: &str) -> Result<Vec<Release>, String> {
        if title.trim().is_empty() {
            return Err(NEED_TITLE.into());
        }
        let q = build_recording_query(artist, title, album);
        let (mut r, earliest) = parse_recordings_raw(&self.mb_get(&format!("recording/?query={}&fmt=json&limit=100", url_encode(&q)))?);
        if !earliest.is_empty() {
            let q2 = format!("{q} AND firstreleasedate:[* TO {earliest}]");
            let (more, _) = parse_recordings_raw(&self.mb_get(&format!("recording/?query={}&fmt=json&limit=25", url_encode(&q2)))?);
            r.extend(more);
        }
        sort_song_releases(&mut r);
        Ok(r)
    }

    // from: GetReleaseDetail
    pub fn get_release_detail(&self, id: &str) -> Result<ReleaseDetail, String> {
        parse_release_json(&self.mb_get(&format!("release/{id}?inc=artist-credits+labels+recordings+release-groups+genres&fmt=json"))?)
    }

    /// Front cover (500 px) from the release, else its release group; None if there is none.
    // from: GetFrontCover
    pub fn get_front_cover(&self, id: &str, group_id: &str) -> Option<Vec<u8>> {
        self.get_ok(&format!("https://coverartarchive.org/release/{id}/front-500"), &[]).or_else(|| {
            if group_id.is_empty() {
                None
            } else {
                self.get_ok(&format!("https://coverartarchive.org/release-group/{group_id}/front-500"), &[])
            }
        })
    }

    // from: DiscogsGet
    pub fn discogs_get(&self, path_and_query: &str, token: &str) -> Result<String, String> {
        let url = format!("https://api.discogs.com/{path_and_query}");
        let headers: Vec<(&str, String)> = auth_header(&url, token).into_iter().collect();
        for attempt in 1..=3u64 {
            self.discogs.wait(&self.fetch);
            let (status, data) = self.fetch.get(&url, &headers)?;
            match status {
                200 => return Ok(String::from_utf8_lossy(&data).into_owned()),
                429 if attempt < 3 => self.fetch.sleep(3000 * attempt),
                429 => return Err(DG_TOO_MANY.into()),
                401 => return Err(DG_TOKEN_REFUSED.into()),
                404 => return Err(DG_UNKNOWN.into()),
                s => return Err(format!("{DG_ERROR}|{s}")),
            }
        }
        Err(DG_TOO_MANY.into())
    }

    /// `track`: a song title; the search then finds releases with that track.
    // from: DiscogsSearch
    pub fn discogs_search(&self, artist: &str, album: &str, token: &str, track: &str) -> Result<Vec<Release>, String> {
        if token.trim().is_empty() {
            return Err(DG_NEED_TOKEN.into());
        }
        let mut q = "type=release&per_page=50".to_string();
        for (k, v) in [("artist", artist), ("release_title", album), ("track", track)] {
            if !v.trim().is_empty() {
                q += &format!("&{k}={}", url_encode(v.trim()));
            }
        }
        Ok(parse_discogs_search_json(&self.discogs_get(&format!("database/search?{q}"), token)?))
    }

    // from: DiscogsRelease
    pub fn discogs_release(&self, id: &str, token: &str) -> Result<ReleaseDetail, String> {
        parse_discogs_release_json(&self.discogs_get(&format!("releases/{id}"), token)?)
    }

    // ---------- the dialog's three jobs ----------

    /// With a title: a song search (which finds the album it is on), retried without the album,
    /// since a wrong album tag should not hide the song. Otherwise a release search.
    // from: TWebJob.Execute (wjSearch)
    pub fn search(&self, source: Source, artist: &str, album: &str, title: &str, token: &str) -> Result<Vec<Release>, String> {
        if title.trim().is_empty() {
            return match source {
                Source::Discogs => self.discogs_search(artist, album, token, ""),
                Source::MusicBrainz => self.search_releases(artist, album),
            };
        }
        let song = |album: &str| match source {
            Source::Discogs => self.discogs_search(artist, album, token, title),
            Source::MusicBrainz => self.search_recordings(artist, title, album),
        };
        let mut r = song(album)?;
        if r.is_empty() && !album.trim().is_empty() {
            r = song("")?;
        }
        if source == Source::Discogs {
            sort_song_releases(&mut r); // one row per master release, the original album first
        }
        Ok(r)
    }

    // from: TWebJob.Execute (wjDetail)
    pub fn detail(&self, source: Source, id: &str, token: &str) -> Result<ReleaseDetail, String> {
        match source {
            Source::Discogs => self.discogs_release(id, token),
            Source::MusicBrainz => self.get_release_detail(id),
        }
    }

    // from: TWebJob.Execute (wjCover)
    pub fn cover(&self, source: Source, id: &str, group_id: &str, cover_url: &str, token: &str) -> Option<Vec<u8>> {
        match source {
            Source::Discogs => self.discogs_cover(cover_url, token),
            Source::MusicBrainz => self.get_front_cover(id, group_id),
        }
    }

    /// The release's primary image (ReleaseDetail::cover_url); None if there is none.
    // from: DiscogsCover
    pub fn discogs_cover(&self, url: &str, token: &str) -> Option<Vec<u8>> {
        if url.is_empty() {
            return None;
        }
        let headers: Vec<(&str, String)> = auth_header(url, token).into_iter().collect();
        self.get_ok(url, &headers)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::sync::Mutex;

    /// Answers from a queue, records every request, and has a clock that `sleep` advances.
    #[derive(Default)]
    struct FakeFetch {
        answers: Mutex<VecDeque<(u16, Vec<u8>)>>,
        calls: Mutex<Vec<(String, Vec<(String, String)>, u64)>>,
        now: Mutex<u64>,
        sleeps: Mutex<Vec<u64>>,
    }

    impl FakeFetch {
        fn with(answers: &[(u16, &str)]) -> Self {
            let f = FakeFetch::default();
            *f.answers.lock().unwrap() = answers.iter().map(|(s, b)| (*s, b.as_bytes().to_vec())).collect();
            f
        }
        fn urls(&self) -> Vec<String> {
            self.calls.lock().unwrap().iter().map(|c| c.0.clone()).collect()
        }
    }

    impl Fetch for FakeFetch {
        fn get(&self, url: &str, headers: &[(&str, String)]) -> Result<(u16, Vec<u8>), String> {
            let now = *self.now.lock().unwrap();
            self.calls.lock().unwrap().push((url.into(), headers.iter().map(|(k, v)| (k.to_string(), v.clone())).collect(), now));
            Ok(self.answers.lock().unwrap().pop_front().unwrap_or((404, Vec::new())))
        }
        fn sleep(&self, ms: u64) {
            self.sleeps.lock().unwrap().push(ms);
            *self.now.lock().unwrap() += ms;
        }
        fn now_ms(&self) -> u64 {
            *self.now.lock().unwrap()
        }
    }

    #[test]
    fn mb_requests_are_spaced() {
        let w = Web::new(FakeFetch::with(&[(200, "{}"), (200, "{}"), (200, "{}")]));
        for _ in 0..3 {
            w.mb_get("release/x").unwrap();
        }
        let times: Vec<u64> = w.fetch.calls.lock().unwrap().iter().map(|c| c.2).collect();
        assert!(times.windows(2).all(|t| t[1] - t[0] >= 1100), "{times:?}");
    }

    #[test]
    fn mb_retries_503_then_gives_up() {
        let w = Web::new(FakeFetch::with(&[(503, ""), (503, ""), (503, ""), (503, "")]));
        assert_eq!(w.mb_get("release/x").unwrap_err(), "MusicBrainz har travlt lige nu (503). Prøv igen om et øjeblik.");
        let sleeps = w.fetch.sleeps.lock().unwrap().clone();
        for p in [1500, 3000, 5000] {
            assert!(sleeps.contains(&p), "{sleeps:?}");
        }
        let w = Web::new(FakeFetch::with(&[(404, "")]));
        assert_eq!(w.mb_get("release/x").unwrap_err(), "MusicBrainz kender ikke denne udgivelse");
        let w = Web::new(FakeFetch::with(&[(500, "")]));
        assert_eq!(w.mb_get("release/x").unwrap_err(), "MusicBrainz svarede med fejl %d|500");
    }

    #[test]
    fn discogs_search_needs_token() {
        let w = Web::new(FakeFetch::default());
        let e = w.discogs_search("Gasolin'", "Gas 5", "  ", "").unwrap_err();
        assert!(e.starts_with("Søgning på Discogs kræver et personligt token."), "{e}");
        assert!(w.fetch.urls().is_empty());
    }

    #[test]
    fn discogs_errors() {
        let w = Web::new(FakeFetch::with(&[(401, "")]));
        assert_eq!(w.discogs_release("1", "test-token").unwrap_err(), "Discogs afviste dit token. Tjek det under \"Discogs-token...\".");
        let w = Web::new(FakeFetch::with(&[(429, ""), (429, ""), (429, "")]));
        assert_eq!(w.discogs_release("1", "").unwrap_err(), "Discogs: for mange forespørgsler - vent et minut og prøv igen.");
    }

    #[test]
    fn token_only_sent_to_discogs() {
        let auth = |c: &(String, Vec<(String, String)>, u64)| c.1.iter().find(|h| h.0 == "Authorization").map(|h| h.1.clone());
        let w = Web::new(FakeFetch::with(&[(200, "{\"results\":[]}"), (200, "img"), (200, "img"), (401, "")]));
        w.discogs_search("A", "B", "test-token", "").unwrap();
        assert_eq!(w.discogs_cover("https://i.discogs.com/a.jpg", "test-token"), Some(b"img".to_vec()));
        assert_eq!(w.discogs_cover("https://evil.example/a.jpg", "test-token"), Some(b"img".to_vec()));
        let e = w.discogs_release("1", "test-token").unwrap_err();
        let calls = w.fetch.calls.lock().unwrap().clone();
        assert!(calls[0].0.starts_with("https://api.discogs.com/"));
        assert_eq!(auth(&calls[0]).as_deref(), Some("Discogs token=test-token"));
        assert_eq!(auth(&calls[1]).as_deref(), Some("Discogs token=test-token"));
        assert_eq!(auth(&calls[2]), None);
        assert!(!e.contains("test-token"));
        assert_eq!(auth_header("https://discogs.com.evil.example/x", "t"), None);
        assert_eq!(auth_header("https://api.discogs.com/x", " "), None);
    }

    #[test]
    fn cover_falls_back_to_release_group() {
        let w = Web::new(FakeFetch::with(&[(404, ""), (200, "jpg")]));
        assert_eq!(w.get_front_cover("r", "g"), Some(b"jpg".to_vec()));
        assert_eq!(
            w.fetch.urls(),
            ["https://coverartarchive.org/release/r/front-500", "https://coverartarchive.org/release-group/g/front-500"]
        );
        let w = Web::new(FakeFetch::with(&[(404, ""), (404, "")]));
        assert_eq!(w.get_front_cover("r", "g"), None);
        let w = Web::new(FakeFetch::with(&[(404, "")]));
        assert_eq!(w.get_front_cover("r", ""), None);
        assert_eq!(w.fetch.urls().len(), 1);
    }

    #[test]
    fn search_urls_match_1_2() {
        let w = Web::new(FakeFetch::with(&[(200, "{}"), (200, "{\"id\":\"r\"}"), (200, "{}")]));
        w.search_releases("Gasolin'", "Gas 5").unwrap();
        w.get_release_detail("r").unwrap();
        w.discogs_search("Gasolin'", "Gas 5", "test-token", "").unwrap();
        assert_eq!(
            w.fetch.urls(),
            [
                "https://musicbrainz.org/ws/2/release/?query=release%3A%22Gas%205%22%20AND%20artist%3A%22Gasolin%27%22&fmt=json&limit=40",
                "https://musicbrainz.org/ws/2/release/r?inc=artist-credits+labels+recordings+release-groups+genres&fmt=json",
                "https://api.discogs.com/database/search?type=release&per_page=50&artist=Gasolin%27&release_title=Gas%205",
            ]
        );
        assert_eq!(w.search_releases(" ", "").unwrap_err(), "Skriv kunstner og/eller album");
    }

    #[test]
    fn song_search_asks_again_for_the_earliest() {
        let first = include_str!("testdata/recording.json").replace("\"rec1\",", "\"rec1\",\"first-release-date\":\"1975-09-01\",");
        let w = Web::new(FakeFetch::with(&[(200, &first), (200, "{\"recordings\":[]}")]));
        let r = w.search_recordings("Bandet", "Sangen", "").unwrap();
        assert_eq!(r[0].id, "alb");
        let urls = w.fetch.urls();
        assert!(urls[0].ends_with("&fmt=json&limit=100"));
        assert!(urls[1].contains(&url_encode(" AND firstreleasedate:[* TO 1975-09-01]")) && urls[1].ends_with("&limit=25"), "{}", urls[1]);
        assert_eq!(w.search_recordings("Bandet", " ", "").unwrap_err(), "Skriv sangens titel");
    }

    #[test]
    fn song_search_retries_without_album() {
        let w = Web::new(FakeFetch::with(&[(200, "{\"recordings\":[]}"), (200, include_str!("testdata/recording.json"))]));
        let r = w.search(Source::MusicBrainz, "Bandet", "Forkert", "Sangen", "").unwrap();
        assert_eq!(r[0].id, "alb");
        let urls = w.fetch.urls();
        assert_eq!(urls.len(), 2);
        assert!(urls[0].contains(&url_encode("release:\"Forkert\"")));
        assert!(!urls[1].contains("release%3A"), "{}", urls[1]);
    }

    #[test]
    fn jobs_pick_the_source() {
        let w = Web::new(FakeFetch::with(&[(200, include_str!("testdata/discogs_release.json")), (200, "img")]));
        let d = w.detail(Source::Discogs, "1234", "").unwrap();
        assert_eq!(d.release.title, "Gas 5");
        assert_eq!(w.cover(Source::Discogs, "1234", "99", &d.cover_url, ""), Some(b"img".to_vec()));
        assert_eq!(w.fetch.urls(), ["https://api.discogs.com/releases/1234", "https://i.discogs.com/front.jpg"]);
        assert_eq!(Source::from_index(1), Source::Discogs);
        assert_eq!(Source::from_index(7), Source::MusicBrainz);
    }

    #[test]
    #[ignore] // the real network: run by hand with --ignored
    fn live_musicbrainz_search() {
        let w = Web::new(Http::new());
        assert!(!w.search_releases("Gasolin'", "Gas 5").unwrap().is_empty());
    }
}
