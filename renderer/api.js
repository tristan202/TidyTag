// Thin wrappers over the Tauri commands (src-tauri/src/commands.rs).
(function () {
  'use strict';
  const { invoke } = window.__TAURI__.core;
  const { listen } = window.__TAURI__.event;
  window.API = {
    settingsGet: (section, key) => invoke('settings_get', { section, key }),
    settingsSet: (section, key, value) => invoke('settings_set', { section, key, value: String(value) }),
    settingsSection: (section) => invoke('settings_section', { section }),
    settingsWriteSection: (section, entries) => invoke('settings_write_section', { section, entries }),
    listDrives: () => invoke('list_drives'),
    listDirs: (path) => invoke('list_dirs', { path }),
    scanStart: (path, subfolders, scanId) => invoke('scan_start', { path, subfolders, scanId }),
    scanCancel: () => invoke('scan_cancel'),
    readCover: (path) => invoke('read_cover', { path }),
    folderCover: (dir) => invoke('folder_cover', { dir }),
    writeTagsBatch: (items, batchId) => invoke('write_tags_batch', { items, batchId }),
    writeCancel: () => invoke('write_cancel'),
    genreList: () => invoke('genre_list'),
    // phase 3 (src-tauri/src/edit.rs)
    readTag: (path) => invoke('read_tag', { path }),
    saveTag: (path, fields, pictures) => invoke('save_tag', { path, fields, pictures }),
    removeTagsBatch: (paths, batchId) => invoke('remove_tags_batch', { paths, batchId }),
    id3SyncBatch: (paths, direction, existing, batchId) => invoke('id3_sync_batch', { paths, direction, existing, batchId }),
    folderCovers: (dirs) => invoke('folder_covers', { dirs }),
    coverToTagsBatch: (paths, batchId) => invoke('cover_to_tags_batch', { paths, batchId }),
    coverFromTags: (paths) => invoke('cover_from_tags', { paths }),
    coverAsFolder: (path, replace) => invoke('cover_as_folder', { path, replace }),
    resizeFileCoversBatch: (paths, opt, batchId) => invoke('resize_file_covers_batch', { paths, opt, batchId }),
    resizeFolderCovers: (dirs, opt) => invoke('resize_folder_covers', { dirs, opt }),
    pathKind: (path) => invoke('path_kind', { path }),
    readImageFile: (path) => invoke('read_image_file', { path }),
    readTextFile: (path) => invoke('read_text_file', { path }),
    writeFile: (path, data) => invoke('write_file', { path, data }),
    on: (event, fn) => listen(event, (e) => fn(e.payload)),
    window: () => window.__TAURI__.window.getCurrentWindow(),
  };
})();
