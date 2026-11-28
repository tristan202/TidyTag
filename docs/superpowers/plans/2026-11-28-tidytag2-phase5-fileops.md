# TidyTag 2 — Phase 5: File Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything around the file list that 1.2 has and 2.0 does not yet have:
- the Recycle Bin, copy/move to a folder, new folder, deleting folder covers;
- changing extensions (`.mp4 → .m4a` and so on), with undo;
- the filter row and *Find / filtrér*, hiding files, manual order, random order, fitting the
  columns;
- playlists (save, quick save);
- the built-in player and *Afspil med*;
- *Vis i Stifinder*, *Egenskaber*, *Åbn mappe...*, *Seneste mapper*, expanding and collapsing the
  tree;
- the Explorer menu (*Åbn i TidyTag*), paths from Explorer and single instance;
- the small dialogs left in the menus: *Genreliste...*, *Tastaturgenveje* and *Om TidyTag...*.

**Architecture:**
- File work is ported to Rust in `tidytag-core`:
  - `fileops.rs` from `fileops.pas`;
  - `playlist.rs` from `WritePlaylist`/`MaskText` (mainform.pas).
- Windows-only work goes in the app crate:
  - `src-tauri/src/shell.rs` from `shellintegration.pas`, plus Explorer, properties and starting
    programs;
  - `src-tauri/src/player.rs` from `audioplayer.pas`. It uses Media Foundation's MFPlay on its own
    thread, which runs a message loop.
- The renderer gets a filtered view: `state.all` is 1.2's `FItems` and `state.items` is its
  `FView`. Everything that already uses `state.items` therefore keeps acting on the visible files,
  as 1.2's `AllItems`/`TargetItems` do.

**Tech Stack:** Rust (tidytag-core, Tauri 2, the `windows` crate for COM/MFPlay), plain JS
renderer (UMD, `node --test`).

**Spec:** `docs/superpowers/specs/2026-11-26-tidytag-tauri-design.md` (phase 5 in *Order of
work*). Phase 1–4 plans: `docs/superpowers/plans/2026-11-2[67]-tidytag2-*.md`.

## Global Constraints

**Same as 1.2**
- 1.2's units are the specification: `fileops.pas`, `shellintegration.pas`, `audioplayer.pas`,
  `progoptions.pas` (`PlayerFor`, `ReadList`/`WriteList`), `tooldialogs.pas` (`EditGenreList`) and
  the `mainform.pas` handlers named in each task. Every port carries `// from: <Pascal name>`
  comments.
- All texts are 1.2's Danish source strings, looked up with `t()`. A new text is allowed only
  where 1.2 has none, and then with all six translations.
- Settings keep 1.2's keys and defaults:
  - `[Player]`: `Internal` (1) and `Volume` (80);
  - `[Players]`: values `ext=program`;
  - `[ExtraPlayers]`, `[CustomGenres]` and `[HiddenGenres]`: `Item0`.. with quoted values
    (`WriteList`). They are read in file order, whatever the key (`ReadList`);
  - `[Playlist]`: `ExtInf` (1), `InfoMask` (`%1 - %2`), `FullPaths` (0), `Folder` ('') and
    `NameMask` (`%f`);
  - `[View] AutoFitColumns` (0).

  Add the sections the renderer reads to its `SECTIONS` list.
- Phone paths are phase 9. The `IsPhonePath`/`rsKunPaaPc` branches are left out and marked
  `// phase 9`.

**Safety**
- Tests and manual runs use copies under `%TEMP%`, and the app runs with `TIDYTAG_INI`. Never
  touch `C:\Users\allan\Music` or `D:\`.
- Copy and move never overwrite. The target is checked before each file, and `CopyFileW` is
  called with fail-if-exists.
- **The Explorer menu of the installed 1.2 must not change.**
  - Tests write only below `HKCU\Software\TidyTag2Test` and delete that key afterwards.
  - The start-up refresh (`RefreshExplorerMenu`) runs only in release builds, so a dev build never
    points the user's Explorer menu at `target\debug`.
- Deleting, copying, moving and changing extensions claim `WriteState`, like a write batch. The
  window cannot close while they run.
- Player tests play a generated WAV of silence at volume 0.

**UI automation and commits**
- Phase 3's rules apply: clicks only when TidyTag is in front, and manual checks only with the
  owner's OK.
- Dialog buttons never use `data-act`. Add each new dialog file to the smoke test's list.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.

## Review Focus

1. **Copy or move onto a name that already exists in the target.** Nothing is overwritten. The
   file is reported as `<name>: findes allerede i målmappen`, and the other files still go.
   Copying a file onto itself is skipped silently. Pinned in Task 1 by
   `copy_move_never_overwrites`.
2. **An action while a filter hides files.** Rename, delete and the tag tools act only on the
   visible files. A rename's log still moves hidden files' paths, and *Vis alle* brings them back
   with their checkmarks. Pinned in Task 5 by `hidden files follow renames and come back`.
3. **The Explorer menu of the installed 1.2.** Tests never write under `Software\Classes`, and a
   debug build never refreshes the menu at start. Pinned in Task 2 by
   `explorer_menu_round_trip_in_test_root` and `dev_build_never_refreshes_menu`.
4. **The player at the end of the list, or on a file it cannot play.** It stops cleanly. It
   neither loops nor plays the next file after an error. The error is shown once. Pinned in
   Task 7 by `player stops after the last track and on errors`, and in Task 3 by
   `play_unplayable_file_fails`.
5. **Playlist paths.** A file below the playlist's folder, written with different upper/lower case
   (`c:\Musik` and `C:\musik\a.mp3`), is written relative. Names outside Windows-1252 (`漢字`)
   survive as UTF-8 without a BOM. Lines end in CRLF. Pinned in Task 1 by
   `playlist_relative_paths_and_utf8`.

---

### Task 0: Branch

- [ ] `git checkout -b tidytag2-phase5` from main.

### Task 1: File operations and playlists (Rust core)

**Files:** Create `src-tauri/core/src/fileops.rs`, `src-tauri/core/src/playlist.rs`; modify
`core/src/lib.rs`

**Interfaces:**
- `fileops`:
  - `CopyMoveResult { done: Vec<bool>, new_names: Vec<PathBuf>, errors: Vec<String>, count: usize }`.
  - `copy_or_move_files(files: &[PathBuf], dir: &Path, do_move: bool) -> CopyMoveResult`, from
    `CopyOrMoveFiles`:
    - a move uses `MoveFileExW` with `MOVEFILE_COPY_ALLOWED`;
    - a copy uses `CopyFileW(.., TRUE)`;
    - an OS error is reported as `<name>: <text>`, with the ` (os error N)` suffix dropped.
  - `FOLDER_COVER_NAMES = ["folder.jpg", "folder.png", "cover.jpg", "cover.png", "front.jpg", "front.png"]`.
  - `folder_cover_files(dirs: &[PathBuf]) -> Vec<PathBuf>`: the existing ones, dirs in order.
  - `create_folder(parent: &Path, name: &str) -> Result<PathBuf, String>`, from
    `ActNewFolderExecute`. The name goes through `rename::sanitize_name_part`. An empty name gives
    `Err("")`. An existing folder or a failure gives `Err("rsMappenKunneIkkeOprettes")`.
  - `plan_ext_change(files: &[PathBuf], kind: usize) -> Vec<rename::PlanItem>`, from
    `ActChangeExtExecute`:
    - `FromExt = [".mp4", ".mp4.m4a.m4p", ".m4b"]` and `ToExt = [".m4a", ".m4b", ".m4a"]`;
    - an existing target gives `Exists`, with the detail 1.2's `rsFiltypeFindes` text;
    - files that do not apply are left out.
- `playlist`:
  - `PlaylistItem { path: PathBuf, duration: f64, info: AudioInfo }`.
  - `mask_text(mask, &AudioInfo) -> String`, from `MaskText`: `expand_rename_mask` with default
    options, file number 1 and width 2; the file name without its extension; `''` when a field is
    missing.
  - `playlist_text(target: &Path, items: &[PlaylistItem], full_paths: bool, ext_inf: bool, info_mask: &str) -> String`,
    from `WritePlaylist`:
    - the first line is `#EXTM3U`;
    - with `ext_inf`, each file gets `#EXTINF:<round(duration)>,<name>`, where the name falls
      back to the file name without its extension;
    - paths below the target's folder are relative unless `full_paths`;
    - every line ends in CRLF, including the last.

- [ ] **Step 1: Write the tests.**
  - `copy_move_never_overwrites`: in a temp folder, `a.mp3` and `b.mp3` go to `dst\`, which
    already has `b.mp3` with other bytes.
    - The copy gives `count 1` and `done [true, false]`, and one error ending in
      `: findes allerede i målmappen`.
    - `dst\b.mp3` keeps its old bytes.
    - A second call with `dir` = the source folder gives `count 0` and no errors.
  - `move_renames_across_folders`: a move gives `new_names[0] == dst\a.mp3`, and the source is
    gone.
  - `folder_covers_found_in_order`: a temp dir with `cover.png` and `folder.jpg` gives
    `[folder.jpg, cover.png]`.
  - `new_folder_sanitized`: `create_folder(tmp, "AC/DC: Live?")` creates a folder with no `/`,
    `:` or `?` in its name. A second call gives `Err("rsMappenKunneIkkeOprettes")`.
  - `ext_change_plans_only_matching`: `a.mp4`, `b.m4a`, `c.m4b` and `d.mp3` with kind 1 give 2
    rows (`a`→`.m4b`, `b`→`.m4b`). If `b.m4b` exists, b's row is `Exists`.
  - `playlist_relative_paths_and_utf8`: the target is `C:\Musik\x.m3u8`. Items
    `c:\musik\漢字.mp3` (183.4 s, artist `A`, title `T`) and `D:\o\b.flac` (no tags) give exactly
    `"#EXTM3U\r\n#EXTINF:183,A - T\r\n漢字.mp3\r\n#EXTINF:0,b\r\nD:\\o\\b.flac\r\n"`. With
    `full_paths` the first path stays whole.

  Run `cargo test -p tidytag-core --lib fileops playlist`. Expected: FAIL (modules missing).
- [ ] **Step 2: Implement both modules.** Run the tests. Expected: PASS.
- [ ] **Step 3:** Commit `feat(core): file operations and playlists`.

### Task 2: Shell integration (Rust, app crate)

**Files:** Create `src-tauri/src/shell.rs`; modify `src-tauri/Cargo.toml`, `src-tauri/src/main.rs`

**Interfaces:**
- `windows-sys` features for the app crate: `Win32_System_Registry`, `Win32_UI_Shell`,
  `Win32_Storage_FileSystem` (version info), `Win32_Foundation`.
- Functions:
  - `menu_keys(classes: &str, exts: &[&str]) -> Vec<(String, &'static str)>`, from `ListKeys`.
    `classes` is `Software\Classes` in the app and `Software\TidyTag2Test\Classes` in tests.
  - `explorer_menu_installed(classes) -> bool`.
  - `install_explorer_menu(classes, caption, exe, exts) -> Result<(), String>`. It writes the
    default value, `Icon` = `"<exe>",0`, `MultiSelectModel` = `Player` for
    `SystemFileAssociations`, and the command `"<exe>" "<arg>"`.
  - `remove_explorer_menu(classes, exts)`.
  - `refresh_explorer_menu(classes, caption, exe, exts)`: only when installed and stale.
  - `should_refresh_menu_at_start() -> bool { cfg!(not(debug_assertions)) }`.
  - `command_line_paths(args: &[OsString]) -> Vec<String>`, from `CommandLinePaths`. It skips the
    exe, returns nothing at all if any argument starts with `--`, keeps existing files and
    folders, and makes each path absolute.
  - `program_name(exe: &Path) -> String`, from `ProgramName`: the `ProductName` from the version
    info; a trailing ` Application` is cut off; the fallback is the file stem.
  - `known_players(players: &[String], extra: &[String]) -> Vec<PathBuf>`, from
    `RebuildPlayWith`: 1.2's ten known paths, with `%ProgramFiles%`/`%ProgramFiles(x86)%`
    expanded; only existing files; no duplicates (case-insensitive); quotes stripped.
- `main.rs`:
  - `menu_caption() -> String`: `Åbn i TidyTag` looked up in `languages/src/translations.json`
    (`include_str!`). The language is `[Main] Language`, or Windows' UI language when that is
    empty, by the same rule as `I18N.effectiveLanguage` (`nb` → `da`, unknown → `en`, `da` → the
    key itself).
  - `--explorer-menu=on|off` as the only argument installs or removes the menu with
    `menu_caption()`, then exits with code 0 or 1, before Tauri starts. The exts are core's
    `READABLE_EXTS` + `OTHER_EXTS`.
  - At start, `refresh_explorer_menu` runs only when `should_refresh_menu_at_start()`.

- [ ] **Step 1: Write the tests.**
  - `explorer_menu_round_trip_in_test_root`:
    1. install in the test root with exe `C:\x\TidyTag.exe` and exts `[".mp3"]`;
    2. `installed` is true, and `Directory\shell\TidyTag\command` holds
       `"C:\x\TidyTag.exe" "%1"`;
    3. the `.mp3` key has `MultiSelectModel = Player`;
    4. after `remove`, `installed` is false;
    5. finally delete `Software\TidyTag2Test`.
  - `refresh_rewrites_only_stale`: install with exe A, refresh with exe B → the command now
    names B. Refresh with no menu installed → nothing is created.
  - `dev_build_never_refreshes_menu`: `assert!(!should_refresh_menu_at_start())` (tests are
    debug builds).
  - `command_line_paths_skip_switches`:
    - `[exe, <tmp file>, "C:\\nope"]` → `[<tmp file>]`;
    - `[exe, "--selftest", <tmp>]` → `[]`.
  - `program_name_falls_back_to_stem`: for a temp `foo.exe` with no version info → `"foo"`.
  - `menu_caption_follows_language`: through `menu_caption_for(lang)`, `da` → `Åbn i TidyTag`,
    `en` → the json's `en` value, and `xx` → the `en` value.

  Run `cargo test -p tidytag shell`. Expected: FAIL.
- [ ] **Step 2: Implement it.** Use `RegCreateKeyExW`/`RegSetValueExW`/`RegDeleteTreeW` under
  `HKEY_CURRENT_USER`. Run the tests. Expected: PASS.
- [ ] **Step 3:** Commit `feat: Explorer menu and command-line paths`.

### Task 3: The built-in player (Rust, app crate)

**Files:** Create `src-tauri/src/player.rs`; modify `src-tauri/Cargo.toml`

**Interfaces:**
- Dependency: `windows = { version = "0.61", features = ["Win32_Foundation", "Win32_Media_MediaFoundation", "Win32_System_Com", "Win32_UI_WindowsAndMessaging"] }`.
- `PlayerState { Stopped, Playing, Paused }`, with serde as `"stopped" | "playing" | "paused"`.
- `PlayerStatus { state, position: f64, duration: f64, file: String }`.
- `Player`, a handle to one thread:
  - the thread calls `CoInitializeEx(COINIT_APARTMENTTHREADED)` and owns the `IMFPMediaPlayer`;
  - it runs `PeekMessageW`/`DispatchMessageW` while it waits on an `mpsc` channel, with a 20 ms
    timeout, because MFPlay posts its events to the thread that created it;
  - methods: `play(path, volume: f32) -> Result<(), String>`, `pause()`, `resume()`, `stop()`,
    `seek(seconds)`, `set_volume(f32)` and `status() -> PlayerStatus`;
  - each method is a message with a reply channel.
- `player_available() -> bool`, from `PlayerAvailable`: `MFStartup` succeeds and
  `MFPCreateMediaPlayer` can create a player.
- `play` follows `TAudioPlayer.Play`: create the player with the URL, wait up to 5 s for the item
  to be set (`MFP_EVENT_TYPE_MEDIAITEM_SET` or the media item's duration), then `Play`. An error
  is returned as 1.2's text or the HRESULT's message.

- [ ] **Step 1: Write the tests.** Each skips when `!player_available()`.
  - `plays_and_stops_silence`: write a 3 s 44.1 kHz 16-bit stereo WAV of zeros to temp. Then
    `play(path, 0.0)`; within 3 s `status().state == Playing`; `duration` is between 2.9 and 3.1;
    after `stop()`, the state is `Stopped`.
  - `play_unplayable_file_fails`: a temp `x.mp3` of 100 random bytes → `play` returns `Err`, and
    the status is `Stopped`.

  Run `cargo test -p tidytag player -- --test-threads=1`. Expected: FAIL.
- [ ] **Step 2: Implement it.** Run the tests. Expected: PASS.
- [ ] **Step 3:** Commit `feat: built-in player`.

### Task 4: Commands, single instance and paths from Explorer

**Files:** Create `src-tauri/src/files.rs`; modify `src-tauri/src/main.rs`, `renderer/api.js`

**Interfaces:**
- Commands (`files.rs`). The ones that change files claim `WriteState`:
  - `recycle_cmd(paths) -> {gone, errors, exists: [bool]}`;
  - `copy_move_cmd(paths, dir, doMove) -> {done, newNames, errors, count}`;
  - `folder_cover_files_cmd(dirs) -> [path]`;
  - `create_folder_cmd(parent, name) -> path`;
  - `plan_ext_change_cmd(paths, kind) -> [PlanRow]`. Running the plan goes through phase 4's
    `execute_rename_cmd`.
  - `save_playlist(target, tracks, fullPaths) -> ()`. It reads `[Playlist]` `ExtInf`/`InfoMask`
    from the ini and writes with `write_atomic`. `tracks` are `RenameTrack`s.
  - `quick_playlist_name(track, mask) -> String`: `mask_text`.
  - `temp_playlist(tracks) -> path`: writes `%TEMP%\TidyTag-afspil.m3u8` with full paths.
  - `show_in_explorer(path, select)`, `show_properties(path)` (`SHObjectProperties` with the main
    window's HWND), `open_default(path)` (`ShellExecuteW` "open") and `run_program(exe, arg)`
    (spawned, not waited for). Each returns `Err(text)` on failure.
  - `play_with_list() -> [{path, name}]`, from `known_players` + `program_name`, with `[Players]`
    and `[ExtraPlayers]` read from the ini.
  - `player_play(path, volume)`, `player_pause`, `player_resume`, `player_stop`,
    `player_seek(seconds)`, `player_volume(v)`, `player_status -> PlayerStatus`, and
    `player_available -> bool`. The `Player` is created lazily in managed state.
  - `app_info -> {version, settingsFile}`.
  - `start_paths -> [path]`: `command_line_paths(std::env::args_os())`, taken once.
- Single instance: the plugin's callback runs `command_line_paths(argv)`. Non-empty paths are
  emitted as the `paths-received` event, then the window is brought to the front, as now.
- In the renderer's `counted` list, add `recycle`, `copyMove` and the ext rename.

- [ ] **Step 1: Write `files_commands_round_trip`.** In a temp folder:
  - `copy_move_cmd` with `doMove=false` copies;
  - `recycle_cmd` on the copy gives `gone 1` and `exists [false]`;
  - `create_folder_cmd` returns the new path;
  - `save_playlist` writes a file whose first line is `#EXTM3U`.

  Run it. Expected: FAIL.
- [ ] **Step 2:** Implement and register the commands and the event, and add the `API` wrappers.
  Run `cargo test --workspace`. Expected: PASS.
- [ ] **Step 3:** Commit `feat: file, shell and player commands`.

### Task 5: The filtered list (renderer)

**Files:** Create `renderer/listview.js`, `renderer/listview.test.js`; modify
`renderer/renderer.js`, `renderer/list.js` (`applyBatch` fills `state.all`), `renderer/index.html`,
`renderer/tree.js`

**Interfaces:**
- `LISTVIEW` (pure):
  - `matchesFilter(tr, f) -> bool`, from `MatchesFilter`. `f` is `{ tagType, text, field, whole, matchCase }`:
    - field 0 is the file name, 1..n are `FIELD_KEYS`, and the last is all fields joined with
      `\u0001`;
    - a tag type of `-` means no tags and no error;
    - `whole` follows `ContainsText` (word boundaries are non-letters/digits).
  - `rebuildView(state)`: `state.items = state.all.filter((tr) => !tr.hidden && matchesFilter(tr, state.filter))`.
    It keeps the selection's objects and drops hidden ones from `state.sel`.
  - `moveSelected(state, delta) -> bool`, from `MoveSelected`. It swaps in both lists and sets
    `state.sort.col = state.sort.col2 = -1`.
  - `shuffle(state, rnd = Math.random)`, from `ActRandomOrderExecute`: Fisher–Yates on
    `state.all`, manual order, then `rebuildView`.
  - `prepareOpen(paths, isDir) -> {dir, select: [path]}`, from `PrepareOpen`.
  - `autoFitWidths(rows, cols, measure) -> [px]`, from `AutoFitColumns`:
    - at most 1000 rows;
    - the header text + 24, cells + 16, at most 450;
    - column 0 is unchanged.
- Wiring in `renderer.js`:
  - the filter row is enabled: *Filtrer!*, Enter in the text field, *Skjul valgte filer*, *Vis
    alle*, and Esc in a non-empty filter text (`FormKeyDown`);
  - the checkboxes and *Tagtype* rebuild at once (`FilterOptionChange`);
  - the status bar shows `rsFilerDDSkjult` when files are hidden;
  - the sort works on `state.all`, then rebuilds;
  - `applyRenameLog` maps `state.all`: `RENAMETOOLS.applyLog` walks `state.all` instead of
    `state.items`, and `mapped` is in `state.all`'s order;
  - `aFind` shows the row and focuses the text;
  - `aMoveUp`/`aMoveDown` and `aRandom` set the message `rsManuelRaekkefoelgeKlikPaaEn`;
  - `aAutoFit` measures with a canvas in the list's font, and `FActAutoFitAfterScan` toggles
    `[View] AutoFitColumns`. When on, it fits after each scan;
  - the paths from Explorer (`start_paths` at start, the `paths-received` event) are handled as
    in `OpenPaths`/`ApplyPendingSelect`:
    - paths wait 400 ms for more and wait while a dialog is open;
    - files already in the list are just selected;
    - otherwise the folder opens and the files are selected after the scan.
  - *Seneste mapper* is a dynamic submenu: the first 15 of the address history. It is disabled
    when empty.
  - `aExpandFolders`: `TREE.expand(path)` loads and opens every subfolder of the selected node.
  - `aCollapseFolders`: `TREE.collapseAll()`, then `TREE.reveal(state.folder)`.
  - `aNewFolder`: a one-field `FORMS.modal` (`InputQuery`), titled `rsNyMappe3`, with the label
    `rsNavnPaaDenNyeMappe + folder + ':'`, then
    `create_folder_cmd`, then `TREE.refresh(state.folder)` (it re-reads that node's children) and
    the message `rsMappeOprettet + name`.

- [ ] **Step 1: Write the tests.**
  - `filter matches file name, one field and all fields`, including `matchCase` and `whole`
    (`'love'` does not match `'Lovely'` with `whole`).
  - `tag type filter: '-' keeps only files without tags or errors`.
  - `hidden files follow renames and come back`: `state.all` holds 3 tracks, one is hidden. A
    phase 4 `applyLog` over `state.all` changes all 3 paths. `rebuildView` shows 2. After *Vis
    alle* (clear hidden and text, then rebuild) it shows 3, and the checked track is still
    checked.
  - `move selected swaps in view and master and keeps selection`.
  - `prepare open picks the first folder, else the first file's folder with its files`.
  - `auto fit caps at 450 and reads at most 1000 rows`.

  Run `npm test`. Expected: FAIL.
- [ ] **Step 2:** Implement and wire it. Run `npm test`. Expected: PASS.
- [ ] **Step 3:** Commit `feat(ui): filter, manual order and paths from Explorer`.

### Task 6: File actions (renderer)

**Files:** Modify `renderer/renderer.js`, `renderer/listview.js`, `renderer/listview.test.js`

**Interfaces:**
- `LISTVIEW.afterMove(state, items, result, inScope) -> void`, from `CopyOrMoveTo`'s move branch.
  A moved item gets its new path when `inScope(newPath)`; otherwise it leaves `state.all`.
- `LISTVIEW.inScanScope(path, folder, subfolders) -> bool`, from `InScanScope`.
- Actions:
  - `FActDeleteFiles`: `requireTargets`, ask `rsLaegDFilerIPapirkurven`, run `recycle_cmd`, drop
    the items whose file no longer exists, set the message `rsDFilerLagtIPapirkurven`, and show
    the errors under `rsSletFiler`.
  - `aCopyTo` and `aMoveTo`:
    - a folder dialog (`tauri-plugin-dialog`, `directory: true`, title
      `rsKopierTilMappe`/`rsFlytTilMappe`, default the open folder);
    - ask `rsKopierDFilerTilS`/`rsFlytDFilerTilS`;
    - `copy_move_cmd`;
    - a move updates the list (`afterMove`). A copy into the scan scope scans again;
    - the message and the errors as 1.2.
  - `aDelFolderCover`: `folder_cover_files_cmd` on the targets' folders. If none, inform
    `rsIngenAfMapperneHarEtCover`. Otherwise ask `rsLaegDMappeCoverIPapirkurven`, recycle, and
    refresh the covers.
  - `aExtM4A`, `aExtM4B` and `aExtM4BBack` (kinds 0, 1, 2):
    - `plan_ext_change_cmd`; with no rows, inform `rsIngenFilerMedFiltypen`;
    - `execute_rename_cmd` on the `Ok` rows;
    - `setUndoLog(log, rsSkiftFiltype)` and `applyRenameLog`;
    - the message `rsFiltypeSkiftet`, and the `Exists`/`Failed` texts under `rsSkiftFiltype`.
  - `aOpen`: the folder dialog with `rsVaelgMappe`, then `navigate`.
  - `aExplorer`: `show_in_explorer(focused path, true)`, or the folder when nothing is focused.
  - `aProperties` (Alt+Enter): `show_properties` on the focused file or the folder.

- [ ] **Step 1: Write the tests.**
  - `moved files outside the scan scope leave the list`: folder `C:\m` with subfolders off. A
    move to `C:\m\sub` drops the item; with subfolders on it keeps it with the new path; a failed
    item stays as it was.
  - `scan scope compares case-insensitively`.

  Run them. Expected: FAIL. Then implement, and run. Expected: PASS.
- [ ] **Step 2:** Commit `feat(ui): recycle bin, copy/move, extensions and Explorer`.

### Task 7: Player bar, *Afspil med* and playlists (renderer)

**Files:** Create `renderer/player.js`, `renderer/playtools.js`, `renderer/playtools.test.js`;
modify `renderer/index.html` (the player bar above the status bar), `renderer/styles.css`,
`renderer/icons.js` (prev, play, pause, stop, next, volume, close), `renderer/renderer.js`

**Interfaces:**
- `PLAYTOOLS` (pure):
  - `playTargets(state) -> {files, index}`, from `PlayTargets`: the selected files when there are
    more than one, otherwise the whole view from the focused file.
  - `playerFor(path, players) -> string`, from `PlayerFor`: the extension with or without a dot,
    case-insensitive, with `*` as the fallback.
  - `titleFor(path, all) -> string`, from `PlayQueueItem`: `Artist - Title` when both are set,
    otherwise the file name.
  - `queueAfterEnd(q) -> q'`, `queuePrev(q, position) -> {q', seekZero}` and `queueNext(q)`, from
    `PlayerTimer`/`PlayerPrevClick`/`PlayerNextClick`:
    - `q` is `{ files, index, sawPlaying }`;
    - past the end, the index is -1 (stop);
    - *Forrige* within the first 3 s goes to the previous track, otherwise back to 0.
- `player.js`, the bar from `BuildPlayerBar`:
  - the buttons ⏮ ⏯ ⏹ ⏭ with 1.2's hints;
  - the title (with the path as its tooltip), a seek bar (0..1000, a click jumps there), the time
    `0:00 / 0:00`, the volume (0..100, saved to `[Player] Volume`) and ✕ (stop and hide);
  - hidden until something plays;
  - polls `player_status` every 250 ms while visible;
  - an error from `player_play` stops the queue and is shown once as `<name>: <error>` under
    `rsAfspilFil`.
- Actions:
  - `aPlay` (Ctrl+P): with `[Player] Internal` and `player_available`, it plays `playTargets`;
    otherwise *Afspil med* on the focused file (`PlayWith`).
  - `aPlayFolder` (Ctrl+Shift+P): the whole view, or with an external player, `temp_playlist` +
    `PlayWith`.
  - *Afspil med* is a dynamic submenu in the *Filer* menu and in the list's popup
    (`RebuildPlayWith`/`PlayWithClick`):
    - *TidyTag (indbygget afspiller)* when available;
    - the programs from `play_with_list`;
    - *Windows-standardprogram*;
    - a separator, then *Vælg program...*, which opens a file dialog for `*.exe` and appends to
      `[ExtraPlayers]` with `WriteList`'s format.

    More than one file goes as `temp_playlist`.
  - `aPlChecked` and `aPlAll` (`SavePlaylistDialog`): a save dialog with 1.2's filter
    (`rsPlaylisteUtfMUM`) and default name `<folder name>.m3u8`, in `[Playlist] Folder` when it
    exists. Then `save_playlist` with `[Playlist] FullPaths`, and the message
    `rsPlaylisteMedDFilerGemt`. An empty list informs `rsDerErIngenFilerAt`.
  - `aQuickPlaylist` (Ctrl+Alt+P), from `ActQuickPlaylistExecute`:
    - the name is `quick_playlist_name(first, NameMask)`, falling back to the folder name;
    - it asks `rsPlaylisteFindesOverskriv` if the file exists.
- Closing the window stops the player.

- [ ] **Step 1: Write `player stops after the last track and on errors`.**
  - `queueAfterEnd` on the last index gives -1.
  - `queuePrev` at 5 s gives `seekZero`, and at 1 s gives index - 1.
  - `queueNext` on the last track keeps the index.
  - Also test `playTargets`, `playerFor` (`.mp3=C:\a.exe`, `*=C:\b.exe`) and `titleFor`.

  Run them. Expected: FAIL.
- [ ] **Step 2:** Implement and wire it. Run `npm test`. Expected: PASS.
- [ ] **Step 3:** Commit `feat(ui): player, play with and playlists`.

### Task 8: Genre list, keyboard shortcuts and About

**Files:** Create `renderer/genres.js`; modify `renderer/renderer.js`, `renderer/smoke.test.js`,
`tools/mkmenu.py` (only if `tooldialogs`' texts are missing from `unitRs`)

- **`aGenres`** (`EditGenreList`):
  - the standard genres, sorted, as a check list. An unchecked genre is hidden;
  - *Alle* and *Ingen*;
  - a memo with *Egne genrer*;
  - OK saves `[HiddenGenres]`/`[CustomGenres]` in `WriteList`'s format and refreshes the multi
    tab's genre list (`RefreshGenreCombos`).
- **`aKeys`** (F1): `DIALOG.info(t(rsEnterDobbeltklikRedigerTagFor), t(rsTastaturgenveje))`,
  with the tabs kept (`white-space: pre`, `tab-size: 16`).
- **`aAbout`**: 1.2's text, with `app_info`'s version and settings path.
- [ ] **Step 1:** Add `genres.js` to the smoke test's dialog list, and add
  `genre lists round-trip quoted` for a pure `GENRES.toIni(hidden, custom)` / `fromIni(entries)`,
  where `Item0`.. are quoted and `' Rock '` keeps its spaces. Run it. Expected: FAIL. Then
  implement, and run. Expected: PASS.
- [ ] **Step 2:** Commit `feat(ui): genre list, shortcuts and about`.

### Task 9: Manual check (with the owner's OK) and docs

- [ ] **Step 1:** Ask the owner for a hands-off session. On copies in `%TEMP%\tidytag-ops5`,
  check:
  1. Filter by artist, *Skjul valgte filer*, *Vis alle*, Esc.
  2. Move up/down, random order, fitting the columns.
  3. Copy 2 files to a subfolder where one name exists: one error, nothing overwritten. Then move
     them back.
  4. Delete 1 file to the Recycle Bin and check that it is in the Recycle Bin.
  5. `.mp4 → .m4a` on a copy, then Ctrl+Z.
  6. Play 3 files: pause, seek, next and previous; the list ends and the player stops.
  7. Save a playlist and a quick playlist, and open the playlist in Notepad (relative paths,
     `#EXTINF`).
  8. *Vis i Stifinder*, *Egenskaber* and *Afspil med → Windows-standardprogram*.
  9. Start a second `tidytag.exe <copy file>` from a terminal: the running window selects the
     file.
  10. New folder, expand and collapse the tree, *Seneste mapper*.
  11. Run the Explorer-menu switch only against the test root (Task 2's test). The real
      `Software\Classes\Directory\shell\TidyTag` is unchanged before and after the session:
      compare `reg query` output.
- [ ] **Step 2:** Update the README's TidyTag 2 section with phase 5. Run `npm test`,
  `cargo test --workspace`, and `golden`, `golden_write` and `golden_rename` with the corpus.
  Expected: all green, 0 mismatches.
- [ ] **Step 3:** Commit `docs: TidyTag 2 phase 5 notes`.
