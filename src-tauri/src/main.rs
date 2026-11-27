// No console window in release builds
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;

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
            commands::genre_list,
        ])
        .run(tauri::generate_context!())
        .expect("TidyTag could not start");
}
