// No console window in release builds
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod edit;
mod rename;
mod player;
mod shell;

use tauri::Manager;

/// `--explorer-menu=on|off` (the installer's switch): set up or remove the menu, then exit.
// from: HandleExplorerMenuSwitch
fn handle_explorer_menu_switch() -> Option<i32> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [arg] = args.as_slice() else { return None };
    let on = match arg.as_str() {
        "--explorer-menu=on" => true,
        "--explorer-menu=off" => false,
        _ => return None,
    };
    let exts = shell::menu_exts();
    if on {
        let exe = std::env::current_exe().ok()?.to_string_lossy().into_owned();
        return Some(if shell::install_explorer_menu(shell::CLASSES, &shell::menu_caption(), &exe, &exts).is_ok() { 0 } else { 1 });
    }
    shell::remove_explorer_menu(shell::CLASSES, &exts);
    Some(0)
}

fn main() {
    if let Some(code) = handle_explorer_menu_switch() {
        std::process::exit(code);
    }
    if shell::should_refresh_menu_at_start() {
        // the exe moved or the language changed; only a convenience
        if let Ok(exe) = std::env::current_exe() {
            shell::refresh_explorer_menu(shell::CLASSES, &shell::menu_caption(), &exe.to_string_lossy(), &shell::menu_exts());
        }
    }
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
            edit::path_kind,
            edit::read_image_file,
            edit::read_text_file,
            edit::write_file,
            rename::plan_rename_cmd,
            rename::execute_rename_cmd,
            rename::undo_rename_cmd,
            rename::map_paths,
            rename::rename_one,
            rename::match_file_names,
            rename::mask_fields_cmd,
        ])
        .run(tauri::generate_context!())
        .expect("TidyTag could not start");
}
