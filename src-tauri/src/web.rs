//! Commands for the web lookup (phase 6). Each runs one blocking call on a worker thread;
//! the Discogs token is read from the settings here, so the window never passes it around.

use base64::Engine;
use serde::Serialize;
use std::sync::OnceLock;
use tidytag_core::model::{detect_image_mime, image_dimensions};
use tidytag_core::settings::{settings_path, Ini};
use tidytag_core::web::http::{Http, Source, Web};
use tidytag_core::web::{Release, ReleaseDetail};

/// One client for the whole process, so the 1-per-second limits hold across dialogs.
fn web() -> &'static Web<Http> {
    static WEB: OnceLock<Web<Http>> = OnceLock::new();
    WEB.get_or_init(|| Web::new(Http::new()))
}

fn token() -> String {
    Ini::load(&settings_path()).ok().and_then(|i| i.get("Discogs", "Token").map(|t| t.trim().to_string())).unwrap_or_default()
}

/// reqwest's blocking client must not run on the async runtime's own threads.
async fn blocking<T: Send + 'static>(f: impl FnOnce(&Web<Http>, String) -> T + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(move || f(web(), token())).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn web_search(source: usize, artist: String, album: String, title: String) -> Result<Vec<Release>, String> {
    blocking(move |w, tok| w.search(Source::from_index(source), artist.trim(), album.trim(), title.trim(), &tok)).await?
}

#[tauri::command]
pub async fn web_release(source: usize, id: String) -> Result<ReleaseDetail, String> {
    blocking(move |w, tok| w.detail(Source::from_index(source), &id, &tok)).await?
}

#[derive(Serialize)]
pub struct WebCover {
    data: String,
    mime: String,
    width: u32,
    height: u32,
}

#[tauri::command]
pub async fn web_cover(source: usize, id: String, group_id: String, cover_url: String) -> Result<Option<WebCover>, String> {
    let data = blocking(move |w, tok| w.cover(Source::from_index(source), &id, &group_id, &cover_url, &tok)).await?;
    Ok(data.map(|d| {
        let (width, height) = image_dimensions(&d).unwrap_or((0, 0));
        WebCover {
            mime: detect_image_mime(&d, "image/jpeg").to_string(),
            width,
            height,
            data: base64::engine::general_purpose::STANDARD.encode(&d),
        }
    }))
}
