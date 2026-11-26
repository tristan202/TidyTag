//! The JSONL record shared with 1.2's `tagdump --json` (see the phase 1 plan).

use crate::model::AudioInfo;
use serde_json::{json, Map, Value};

pub fn json_record(info: &AudioInfo) -> Value {
    let mut fields = Map::new();
    for (f, v) in &info.fields {
        if !v.is_empty() {
            fields.insert(f.key().to_string(), Value::String(v.clone()));
        }
    }
    let pictures: Vec<Value> = info
        .pictures
        .iter()
        .map(|p| json!({"type": p.pic_type, "mime": p.mime, "description": p.description, "size": p.data.len()}))
        .collect();
    json!({
        "file": info.path.to_string_lossy(),
        "fileSize": info.file_size,
        "supported": info.supported,
        "error": info.error,
        "codec": info.codec,
        "tagTypes": info.tag_types_text(),
        "hasCover": info.has_cover,
        "durationMs": (info.duration * 1000.0).round() as i64,
        "bitrate": info.bitrate,
        "sampleRate": info.sample_rate,
        "channels": info.channels,
        "bitDepth": info.bit_depth,
        "fields": fields,
        "pictures": pictures,
    })
}
