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
    on: (event, fn) => listen(event, (e) => fn(e.payload)),
    window: () => window.__TAURI__.window.getCurrentWindow(),
  };
})();
