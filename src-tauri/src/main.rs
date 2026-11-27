// No console window in release builds
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod edit;

use tauri::Manager;

fn main() {
    tauri::Builder::default()
        // one instance: a second start brings the running window to the front
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.unminimize();
                let _ = w.show();
                let _ = w.set_focus();
            }
        }))
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .manage(commands::ScanState::default())
        .manage(commands::WriteState::default())
        .invoke_handler(tauri::generate_handler![
            commands::settings_get,
            commands::settings_set,
            commands::settings_section,
            commands::settings_write_section,
            commands::settings_erase_section,
            commands::list_drives,
            commands::list_dirs,
            commands::scan_start,
            commands::scan_cancel,
            commands::read_cover,
            commands::folder_cover,
            commands::write_tags_batch,
            commands::write_cancel,
            commands::genre_list,
            edit::read_tag,
            edit::save_tag,
            edit::remove_tags_batch,
            edit::id3_sync_batch,
            edit::folder_covers,
            edit::cover_to_tags_batch,
            edit::cover_from_tags,
            edit::cover_as_folder,
            edit::resize_file_covers_batch,
            edit::resize_folder_covers,
            edit::read_image_file,
            edit::read_text_file,
            edit::write_file,
        ])
        .run(tauri::generate_context!())
        .expect("TidyTag could not start");
}
