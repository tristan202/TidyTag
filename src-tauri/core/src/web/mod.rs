//! Online lookup: MusicBrainz, Discogs and the Cover Art Archive.
// from: musicbrainz.pas (the records are shared by both sources, as in 1.2)

pub mod discogs;
pub mod http;
pub mod musicbrainz;

use serde::Serialize;

// from: TMBRelease
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Release {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub date: String,
    pub country: String,
    pub formats: String,
    pub label_name: String,
    pub catalog_no: String,
    pub release_group_id: String,
    pub disambiguation: String,
    pub status: String,
    /// 'Album', 'Single', 'Compilation', 'Live', ...
    pub release_type: String,
    pub track_count: i64,
    pub score: i64,
    /// song search: where the song is on this release (0 = unknown)
    pub hit_title: String,
    pub hit_disc: i64,
    pub hit_position: i64,
}

// from: TMBTrack
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Track {
    /// disc (medium) number and position on it, 1-based
    pub disc: i64,
    pub position: i64,
    pub number: String,
    pub title: String,
    pub artist: String,
    pub length_ms: i64,
}

// from: TMBReleaseDetail
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReleaseDetail {
    pub release: Release,
    pub album_artist: String,
    pub genre: String,
    pub disc_count: i64,
    /// tracks per disc, index 0 = disc 1
    pub disc_track_counts: Vec<i64>,
    pub compilation: bool,
    /// Discogs: image URL; MusicBrainz uses the Cover Art Archive
    pub cover_url: String,
    pub tracks: Vec<Track>,
}

// ---------- JSON helpers (JStr, JInt, JObj, JArr) ----------
use serde_json::Value;

pub(crate) fn jstr(o: &Value, key: &str) -> String {
    match o.get(key) {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}

pub(crate) fn jint(o: &Value, key: &str) -> i64 {
    match o.get(key) {
        Some(Value::Number(n)) => n.as_i64().unwrap_or_else(|| n.as_f64().map(|f| f as i64).unwrap_or(0)),
        Some(Value::String(s)) => s.trim().parse().unwrap_or(0),
        _ => 0,
    }
}

static NULL: Value = Value::Null;

pub(crate) fn jobj<'a>(o: &'a Value, key: &str) -> &'a Value {
    match o.get(key) {
        Some(v @ Value::Object(_)) => v,
        _ => &NULL,
    }
}

pub(crate) fn jarr<'a>(o: &'a Value, key: &str) -> &'a [Value] {
    match o.get(key) {
        Some(Value::Array(a)) => a,
        _ => &[],
    }
}
