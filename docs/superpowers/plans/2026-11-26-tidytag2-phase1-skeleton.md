# TidyTag 2.0 — Phase 1: Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Tauri 2 app, launched with `npm start`, that:
- shows 1.2's window in the approved look (menus, tool panel, icon bar, address row, filter row,
  folder tree, file list, player bar, status bar);
- reads the tags of every format 1.2 reads, read-only, with results identical to 1.2's `tagdump`;
- shares 1.2's settings file.

**Architecture:**
- **Cargo workspace in `src-tauri/`:**
  - `tidytag-core` (pure Rust, no Tauri) holds the tag readers ported from 1.2's Pascal units,
    the folder scan, directory listing and a round-trip-safe ini file.
  - The `tidytag` app crate exposes these as Tauri commands and events.
- **Renderer:** plain JavaScript in `renderer/` (no framework, no bundler), the same as Torrentry.
  Testable logic lives in UMD-wrapped files that run under `node --test`.
- **Phase boundary:** nothing writes to audio files in this phase.

**Tech Stack:**
- Tauri 2, `tauri-plugin-single-instance` 2 and `tauri-plugin-window-state` 2;
- Rust 1.99 (edition 2021), `serde`, `serde_json`, `base64` 0.22,
  `windows-sys` 0.59 (drive list);
- Node 24 with `node --test`, `@tauri-apps/cli` ^2.12;
- Free Pascal 3.2.2 for the one change to 1.2's `tagdump` tool.

**Spec:** `docs/superpowers/specs/2026-11-26-tidytag-tauri-design.md`. The approved mockup is
`docs/superpowers/specs/2026-11-26-tidytag-tauri-mockup.html`.

## Global Constraints

**Platform and product**
- Windows only. Product name `TidyTag`, identifier `dk.tidytag.app`, version `2.0.0` in
  `package.json`, which `tauri.conf.json` reads through `"version": "../package.json"`.

**Look**
- Colours, set as CSS variables on `:root`: `--bg #171a26`, `--sidebar #10121b`,
  `--panel #1d2131`, `--raised #242940`, `--border #2a2f45`, `--text #e4e7f0`,
  `--muted #8a90a8`, `--accent #5b8def`, `--accent-hover #4a7de0`, `--danger #e5534b`,
  `--ok #3fb950`, `--warn #d29922`.
- Radius: `--radius-sm: 6px; --radius: 10px`.
- Fonts: `"Segoe UI Variable", "Segoe UI", system-ui, sans-serif` at 13.5px/1.45, and
  `"Cascadia Mono", Consolas, monospace`.
- Icons are inline SVG with a 24×24 viewBox, `fill:none; stroke:currentColor; stroke-width:1.8;
  stroke-linecap:round; stroke-linejoin:round`. No emoji and no icon fonts.
- The layout follows mockup v3, from top to bottom: menu bar; tool panel (tabs *Omdøb filer (F4)*,
  *Multi-fil-tag-editor (Ctrl+F4)*, *Tags fra filnavn (Shift+F4)*, plus the folder and file
  cover); icon bar; *Adresse* + *Tagtype*; *Filtrer efter*; *Mapper* tree | file list; player
  bar; status bar.

**Data**
- Never write to an audio file in this phase. Readers open files read-only and allow other
  programs to keep reading and writing them, as 1.2's `fmShareDenyNone` does.
- The settings file is `%LOCALAPPDATA%\TidyTag\tidytag.ini`. Every save keeps:
  - the UTF-8 BOM, if there is one;
  - CRLF line endings;
  - section order, key order, comments, blank lines and unknown keys, byte for byte;
  - only the changed value is new.

  Section and key names are case-insensitive, as in TIniFile.

**Text**
- UI texts are Danish source strings that are looked up in `languages/src/translations.json`.
  The languages are `da, en, de, fr, it, sv, es`, with the display names `Dansk, English,
  Deutsch, Français, Italiano, Svenska, Español`.
- The effective language is the `[Main] Language` setting. If that is empty, it is the system
  language (`nb` → `da`), and English when that language is not supported.

**Tests**
- Tests touch only copies, in folders under `%TEMP%`. The user's music (`C:\Users\allan\Music`,
  `D:\`) is never a test folder.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.

## Review Focus

1. **A damaged or truncated file:** reading never panics or hangs. The file is listed with
   `error` set, as in 1.2. Pinned by `truncated_files_never_panic` (Task 2).
2. **A folder with 10,000+ files:**
   - the window stays responsive;
   - the list draws only the visible rows;
   - results stream in batches.

   Pinned by `virtual window renders only visible rows` (Task 11) and `scan_streams_batches`
   (Task 9).
3. **Unicode names and paths over 260 characters:** they are listed and read. Pinned by
   `scan_reads_unicode_and_long_paths` (Task 9).
4. **An ini file written by 1.2** (BOM, CRLF, comments, unknown sections, key case different from
   ours): a save changes exactly one value and nothing else. Pinned by `roundtrip_keeps_bytes`
   (Task 8).
5. **Changing folder while a scan runs:** no file from the old folder appears in the new list.
   Pinned by `stale scan batches are ignored` (Task 11) and `cancel_stops_scan` (Task 9).

---

## File Structure

```
package.json                          scripts: start, dist, test
src-tauri/
  Cargo.toml                          workspace [".", "core"] + app crate "tidytag"
  tauri.conf.json, build.rs, capabilities/default.json, icons/icon.ico
  src/main.rs                         builder, plugins, invoke_handler
  src/commands.rs                     Tauri commands + scan event bridge
  core/Cargo.toml                     crate tidytag-core (lib tidytag_core)
  core/src/lib.rs
  core/src/model.rs                   TagField, AudioInfo, Picture, helpers (port of audiotypes.pas)
  core/src/read.rs                    extension tables + read_audio_info (port of audiotags.pas)
  core/src/text.rs                    shared text helpers (port of tagutils.pas reading parts)
  core/src/tags/{mod,id3,mp3,ape,vorbis,mp4,riff,asf}.rs
  core/src/settings.rs                round-trip ini
  core/src/scan.rs                    folder scan with batches and cancel
  core/src/dirs.rs                    drives and subfolders
  core/src/bin/tagdump.rs             JSONL dump, same schema as Pascal tagdump --json
  core/tests/golden.rs                cross-check against 1.2 (needs TIDYTAG_CORPUS)
renderer/
  index.html, styles.css
  strings.js                          GENERATED by tools/mkstrings.py
  icons.js, menu.js, tree.js, list.js, panel.js, api.js, renderer.js
  *.test.js                           node --test
tools/
  tagdump.lpr                         + --json option (Pascal)
  make-corpus.ps1                     builds %TEMP%\tidytag-corpus with expected JSON
  mkstrings.py                        translations.json -> renderer/strings.js
```

**Shared field keys.** The Rust serde names, the JSON from both tagdumps, and the JS use the same
keys, in 1.2's `TTagField` order (37 keys):

`title artist album year track disc genre comment albumArtist composer bpm lyrics conductor
lyricist origArtist remixer publisher catalogNo isrc copyright encodedBy url grouping subtitle
mood initialKey sortTitle sortArtist sortAlbumArtist sortAlbum sortComposer compilation podcast
rgTrackGain rgTrackPeak rgAlbumGain rgAlbumPeak`

**Shared JSONL record.** Both tagdumps write one record per file:
- `file` (the full path) and `fileSize`;
- `supported`, `error` and `codec`;
- `tagTypes` (for example `"ID3v2.3, ID3v1"`) and `hasCover`;
- `durationMs` = round(seconds × 1000);
- `bitrate` (kbit/s), `sampleRate`, `channels` and `bitDepth`;
- `fields`: only the non-empty keys;
- `pictures`: a list of `{type, mime, description, size}`.

---

### Task 0: Branch

- [ ] **Step 1:** `git checkout -b tidytag2-phase1` in the repo root. Expected: `Switched to a new
  branch`.

### Task 1: Scaffold the Tauri app and test runners

**Files:**
- Create: `package.json`, `src-tauri/Cargo.toml`, `src-tauri/build.rs`,
  `src-tauri/tauri.conf.json`, `src-tauri/capabilities/default.json`, `src-tauri/icons/icon.ico`,
  `src-tauri/src/main.rs`
- Create: `src-tauri/core/Cargo.toml`, `src-tauri/core/src/lib.rs`
- Create: `renderer/index.html`, `renderer/smoke.test.js`
- Modify: `.gitignore`

**Interfaces:**
- Produces:
  - `npm start` (= `tauri dev`) opens one window;
  - `npm test` (= `node --test renderer/`);
  - `cargo test --workspace` in `src-tauri/`.

- [ ] **Step 1: Write `renderer/smoke.test.js`.** It asserts that `index.html` contains
  `<div id="app">`. Run `npm test`. Expected: FAIL (the file is missing).
- [ ] **Step 2: Create the scaffold, modelled on Torrentry's files.**
  - `tauri.conf.json`:
    - `frontendDist: "../renderer"`, `withGlobalTauri: true`, and Torrentry's CSP line;
    - one window `main`: title `TidyTag`, 1400×900, min 900×560, `center`,
      `backgroundColor "#171a26"`, **`dragDropEnabled: true`**;
    - bundle `nsis`, `installMode: "currentUser"`, icon `icons/icon.ico`.
  - `icon.ico` is a copy of the repo's `TidyTag.ico`.
  - The app crate has the two plugins. Single instance only focuses the existing window in this
    phase.
  - Add `node_modules/`, `src-tauri/target/` and `src-tauri/gen/` to `.gitignore`.
- [ ] **Step 3:** Run `npm install`, then `npm test`. Expected: PASS. Then run
  `cargo test --workspace` in `src-tauri`. Expected: `test result: ok` (0 tests).
- [ ] **Step 4:** Run `npm start`. Expected: an empty dark window titled TidyTag. Close it.
- [ ] **Step 5:** Commit: `chore: scaffold TidyTag 2 Tauri app`.

### Task 2: Data model, dispatcher, Rust tagdump and the golden harness

**Files:**
- Create: `core/src/model.rs`, `core/src/read.rs`, `core/src/text.rs`, `core/src/tags/mod.rs`,
  `core/src/bin/tagdump.rs`, `core/tests/golden.rs`
- Modify: `tools/tagdump.lpr`
- Create: `tools/make-corpus.ps1`

**Interfaces:**
- Produces, in `tidytag_core::model`:
  - `enum TagField`: 37 variants in the order above, `#[serde(rename_all = "camelCase")]` giving
    exactly the keys above. Also `TagField::ALL: [TagField; 37]` and `fn key(self) -> &'static str`.
  - `struct Picture { pic_type: u8, mime: String, description: String, data: Vec<u8> }`
  - `struct AudioInfo`: `path: PathBuf`, `file_size: u64`, `fields: BTreeMap<TagField, String>`,
    `tag_types: Vec<String>`, `codec: String`, `has_cover: bool`, `duration: f64` (seconds),
    `bitrate: u32`, `sample_rate: u32`, `channels: u32`, `bit_depth: u32`, `supported: bool`,
    `error: String`, `pictures: Vec<Picture>`.
  - Methods `set_field(f, v, overwrite)`, `append_field(f, v)` (joins with `"; "`),
    `add_tag_type(t)` and `add_picture(..)`, with 1.2's semantics: an empty value never erases.
  - Free functions ported 1:1 from `audiotypes.pas`: `is_true_flag`, `flag_value`,
    `rg_gain_text`, `rg_peak_text`, `parse_rg_gain`, `r128_to_rg`, `rg_to_r128`,
    `detect_image_mime`, `image_dimensions`, `picture_type_name`.
- Produces, in `tidytag_core::read`:
  - `READABLE_EXTS` (the 18 entries of `ReadableExts`, in the same order) and `OTHER_EXTS`
    (`[".dsf"]`);
  - `fn is_audio_file(&Path) -> bool`;
  - `fn read_audio_info(path: &Path, want_pictures: bool) -> AudioInfo`. It never panics; errors
    go to `.error`. It dispatches by extension exactly as `ReadAudioInfo` does. The readers in
    Tasks 3–7 plug in as `tags::<fmt>::read(&mut impl Read+Seek, &mut AudioInfo) -> Result<(), String>`.
- Produces `tagdump --json <file|dir> [-r]` (Rust and Pascal) and `tools/make-corpus.ps1`.

- [ ] **Step 1: Write the unit tests in `model.rs`, then run them and watch them fail.**

```rust
assert_eq!(rg_gain_text(-6.524), "-6.52 dB");
assert_eq!(rg_peak_text(0.9885531), "0.988553");
assert_eq!(parse_rg_gain("+1,2 dB"), Some(1.2));
assert_eq!(r128_to_rg("-512"), "3.00 dB");
assert_eq!(rg_to_r128("3.00 dB"), "-512");
assert!(is_true_flag("yes") && is_true_flag("1") && !is_true_flag("0") && !is_true_flag(""));
assert_eq!(detect_image_mime(&[0x89, b'P', b'N', b'G'], "image/jpeg"), "image/png");
assert_eq!(TagField::ALL.len(), 37);
assert_eq!(TagField::RgAlbumPeak.key(), "rgAlbumPeak");
```

  Run `cargo test -p tidytag-core`. Expected: FAIL (the items are missing).
- [ ] **Step 2: Implement `model.rs` and `read.rs`.** All readers return `Err("not implemented")`
  for now. Run the tests. Expected: PASS.
- [ ] **Step 3: Write the test `truncated_files_never_panic` in `read.rs`.**
  - For each of the 18 extensions, write files of 0, 1, 10 and 200 bytes into a temp folder.
    The content is the first bytes of a valid header (`ID3`, `fLaC`, `OggS`, `....ftyp`,
    `RIFF`, `FORM`, `MAC `, `wvpk`, `MPCK`, `OFR `, the ASF GUID) followed by zeros.
  - Assert that `read_audio_info` returns, and that `error` is non-empty or `supported` is false.
  - Keep this test; it must stay green after every reader task.
- [ ] **Step 4: Add `--json` to `tools/tagdump.lpr`.**
  - Use `fpjson`. The record is the shared JSONL record above, with `WantPictures := True`.
  - The field keys come from a 37-entry const array in `TTagField` order.
  - Build with `fpc -Mobjfpc -Sh -Fusrc -FUlib\tools -FEbin tools\tagdump.lpr`. Expected:
    `bin\tagdump.exe --json <file>` prints one JSON line.
- [ ] **Step 5: Write `core/src/bin/tagdump.rs`.** It prints the same record. Folders are walked
  in name order, recursively with `-r`.
- [ ] **Step 6: Write `tools/make-corpus.ps1 -Source <folders/files...>`.**
  1. It copies the source files into `%TEMP%\tidytag-corpus\files`, at most 3 per extension.
     It refuses a target inside `C:\Users\allan\Music` or on `D:\`.
  2. It makes a second copy of one file per format and writes rich tags into it with
     `bin\tagset.exe`:
     - every field, with Unicode (`Ægir — 東京`), a 5 KB lyrics text and `compilation=1`;
     - ReplayGain values;
     - a cover, if `tagset` supports one.
  3. It writes `expected.jsonl` with `bin\tagdump.exe --json files -r`.
- [ ] **Step 7: Write `core/tests/golden.rs`.**
  - If `TIDYTAG_CORPUS` is unset, print `skipped: TIDYTAG_CORPUS not set` and pass.
  - Otherwise, read `expected.jsonl` and compare each record with `read_audio_info(path, true)`.
    Every key must be equal, `durationMs` may differ by ±1, and pictures are compared by type,
    mime, description and size.
  - Every mismatch is printed as `file: key: expected X, got Y`, and the test fails after
    listing all of them.
- [ ] **Step 8: Build the corpus.** Run `make-corpus.ps1`, with the source folders the owner
  names when this task is executed. Ask the owner for them; never pick music folders yourself.
  Then run `cargo test -p tidytag-core --test golden`. Expected: FAIL, listing every file as
  `not implemented` (this proves the harness works).
- [ ] **Step 9:** Commit: `feat(core): data model, dispatcher and tagdump golden harness`
  (the corpus stays in %TEMP%, not in git).

### Tasks 3–7: The readers (one task per Pascal unit)

Every reader task has the same steps. Only the table differs.

- [ ] **Step 1: Write the unit tests listed for the reader.** Run them. Expected: FAIL.
- [ ] **Step 2: Port the Pascal unit to the Rust module, function by function.**
  - Keep 1.2's names in a `// from: <Pascal function>` comment.
  - Keep the same field mapping, tag-type strings, codec strings, duration/bitrate maths, and the
    order and priority between tag types.
  - Use only the reading parts. Writers come in phase 2.
- [ ] **Step 3: Run the tests.**
  - `cargo test -p tidytag-core`: the unit tests and `truncated_files_never_panic` must PASS.
  - `TIDYTAG_CORPUS=%TEMP%\tidytag-corpus cargo test -p tidytag-core --test golden`: no
    mismatches may remain for this reader's extensions.
- [ ] **Step 4:** Commit `feat(core): <format> reader`.

| Task | Pascal source | Rust module | Extensions | Unit tests (beyond golden) |
|---|---|---|---|---|
| 3 | `mp3reader.pas`, reading parts of `tagutils.pas` | `tags::id3`, `tags::mp3`, `text.rs` | .mp3 | `syncsafe(&[0,0,2,1]) == 257`; `id3v1_genre(17) == "Rock"`; `decode_text(1, b"\xFF\xFEA\x00") == "A"` (UTF-16 BOM); `decode_text(0, b"\xC6")` == `"Æ"` (Latin-1); `xing_duration` of 1000 frames at 44100 Hz MPEG1 L3 ≈ 26.12 s |
| 4 | `apereader.pas`, reading parts of `apetag.pas` (APE item parsing, `Cover Art (...)` pictures) | `tags::ape` | .ape .wv .mpc .ofr | APEv2 footer at file end found, both with and without a trailing ID3v1; a `Cover Art (Front)` binary item becomes a picture with type 3 |
| 5 | `vorbisreader.pas` | `tags::vorbis` | .flac .ogg .oga .opus | `TITLE=a`, `title=b` → title `"a; b"`; `R128_TRACK_GAIN=-512` in Opus → rgTrackGain `"3.00 dB"`; a `METADATA_BLOCK_PICTURE` base64 value becomes a picture |
| 6 | `mp4reader.pas` | `tags::mp4` | .m4a .m4b .mp4 | `trkn` data `[0,0,0,2,0,12,0,0]` → track `"2/12"`; a freeform `----:com.apple.iTunes:ISRC` → isrc; `covr` with flag 14 → mime image/png |
| 7a | `wavreader.pas` | `tags::riff` | .wav .aif .aiff .aifc | RIFF `LIST/INFO` `INAM` → title; an `id3 ` chunk wins over INFO for fields both have, as in 1.2; AIFF `NAME` → title |
| 7b | `asfreader.pas` | `tags::asf` | .wma .asf | Content Description title/author → title/artist; `WM/TrackNumber` as DWORD 5 → track `"5"`; `WM/Picture` → picture |

*7a and 7b are two tasks with the same steps.*

### Task 8: Round-trip ini

**Files:** Create `core/src/settings.rs`

**Interfaces:**
- Produces `struct Ini` with:
  - `Ini::load(path: &Path) -> io::Result<Ini>` (a missing file gives an empty Ini; the
    `TagKlon\tagklon.ini` migration copy from `settingsfile.pas` is done by `settings_path()`);
  - `get(&self, section, key) -> Option<&str>`;
  - `set(&mut self, section, key, value)`;
  - `section(&self, section) -> Vec<(String, String)>`;
  - `erase_section(&mut self, section)`;
  - `save(&self) -> io::Result<()>`.
- Also `fn settings_path() -> PathBuf` → `%LOCALAPPDATA%\TidyTag\tidytag.ini`.

- [ ] **Step 1: Write the tests.**
  - `roundtrip_keeps_bytes`: the input is
    `"\u{FEFF}[Main]\r\nLastFolder=C:\\x\r\n; note\r\n\r\n[Odd]\r\nZ=1\r\n[View]\r\nFolders=1\r\n"`.
    After `set("main","lastfolder","D:\\y")` and `save()`, the file equals the input with
    only `C:\\x` replaced by `D:\\y`.
  - `set_new_key_appends_to_section`: `set("View","Address","0")` inserts `Address=0\r\n`
    right after `Folders=1`.
  - `set_new_section_appends_at_end`: a new section is written as `\r\n[TidyTag2]\r\nK=V\r\n`
    at the end.
  - `erase_then_write_section` reproduces 1.2's Favorites rewrite: the section stays in place and
    its keys are replaced.
  - `get_is_case_insensitive`.

  Run them. Expected: FAIL.
- [ ] **Step 2: Implement.** Keep the file as a list of raw lines; edits replace whole lines.
  Run the tests. Expected: PASS.
- [ ] **Step 3: Check against the real file.** Copy the real `tidytag.ini` to %TEMP%, load it,
  set one value, save, then run `fc /b` against a copy that has the same single edit made by
  hand. Expected: only that value differs.
- [ ] **Step 4:** Commit `feat(core): round-trip ini settings`.

### Task 9: Scan, directories and the Tauri command layer

**Files:** Create `core/src/scan.rs`, `core/src/dirs.rs`, `src-tauri/src/commands.rs`; modify
`src-tauri/src/main.rs`

**Interfaces:**
- Produces in core:
  - `fn scan(dir: &Path, subfolders: bool, cancel: &AtomicBool, on_batch: impl FnMut(Vec<AudioInfo>), on_progress: impl FnMut(usize, usize)) -> usize`.
    It lists files with `is_audio_file` (in name order, folders depth-first as in
    `scanthread.pas`), then reads them with `want_pictures = false`, in batches of 200. It
    checks `cancel` between files.
  - `fn list_drives() -> Vec<DirEntry>` (letter, plus the volume label in `name`).
  - `fn list_dirs(path: &Path) -> Vec<DirEntry>`. Hidden and system folders are excluded, as in
    1.2's tree.
  - `struct DirEntry { name: String, path: String, has_children: bool }`.
- Produces these Tauri commands (JS `invoke` names), all camelCase over the wire:
  - `settings_get(section, key) -> Option<String>`
  - `settings_set(section, key, value)` (saves at once)
  - `settings_section(section) -> Vec<[String;2]>`
  - `settings_erase_section(section)`
  - `list_drives()`
  - `list_dirs(path)`
  - `scan_start(path, subfolders, scanId: u32)`: runs on its own thread and cancels any
    running scan.
  - `scan_cancel()`
  - `read_cover(path) -> Option<{mime, data}>`: base64. It returns the first type-3 picture,
    otherwise the first picture.
  - `folder_cover(dir) -> Option<{mime, data}>`: names in 1.2's order: `folder.jpg, folder.png,
    cover.jpg, cover.png, front.jpg, front.png`.
- Produces these events:
  - `scan-batch` `{scanId, tracks: TrackDto[]}`
  - `scan-progress` `{scanId, done, total}`
  - `scan-done` `{scanId, count}`
- `TrackDto` is `AudioInfo` without pictures: `{path, folder, fileName, fileSize, fields,
  tagTypes (joined with ", "), codec, hasCover, duration, bitrate, sampleRate, channels,
  bitDepth, supported, error}`.

- [ ] **Step 1: Write the core tests.**
  - `scan_streams_batches`: 450 empty `.mp3` files arrive in batches of 200, 200 and 50.
  - `cancel_stops_scan`: setting cancel after the first batch gives fewer than 450 files.
  - `scan_reads_unicode_and_long_paths`: `Ægir — 東京.mp3`, and a file in a nested path over
    300 characters (using the `\\?\` prefix), are both listed.
  - `subfolders_flag`: a file in a subfolder is listed only with `subfolders = true`.

  Run them. Expected: FAIL.
- [ ] **Step 2: Implement core, then the commands.** The app crate holds one `Mutex<Ini>` and
  one cancel `Arc<AtomicBool>` in Tauri state. Run the tests. Expected: PASS.
- [ ] **Step 3:** Commit `feat: scan, directory listing and Tauri commands`.

### Task 10: Theme, strings, icons and the static layout

**Files:** Create `renderer/styles.css`, `renderer/icons.js`, `renderer/api.js`,
`renderer/panel.js`, `tools/mkstrings.py`, `renderer/strings.js` (generated),
`renderer/strings.test.js`; modify `renderer/index.html`

**Interfaces:**
- Produces:
  - `I18N.t(dk: string, ...args) -> string`: a lookup in the current language. It replaces `%d`
    and `%s` in order and falls back to the Danish text.
  - `I18N.setLang(code)`, `I18N.LANGS` (the codes and names from Global Constraints) and
    `I18N.effectiveLanguage(setting, navigatorLanguage)`.
  - `ICONS[name]` holds inner SVG markup and `icon(name) -> string` the full `<svg>`. The names
    are: `open refresh search subfolders pencil tags rename renameFolder f2t copy paste play
    pause up down tracks cloud export check x undo keyboard info plus star folderUp newFolder
    folder pc drive phone globe`.
  - `api.js` holds thin wrappers over `invoke` for every Task 9 command.
- `mkstrings.py` reads `languages/src/translations.json` (`{dk: {lang: text}}`) and writes
  `strings.js` in Torrentry's UMD style. Run it after any text is added.

- [ ] **Step 1: Write `strings.test.js`.**
  - `t('Filer')` is `'File'` in `en` and `'Filer'` in `da`.
  - `t('%d markeret', 3)` keeps the placeholder order.
  - `effectiveLanguage('', 'nb-NO') === 'da'`.
  - `effectiveLanguage('', 'pt-BR') === 'en'`.
  - `effectiveLanguage('sv', 'da-DK') === 'sv'`.

  Run `npm test`. Expected: FAIL.
- [ ] **Step 2: Implement `mkstrings.py`, generate `strings.js`, and add any Danish texts this
  phase needs** that are missing from `translations.json`, with all six translations, using
  `python tools\addtranslations.py`. Run the test. Expected: PASS.
- [ ] **Step 3: Build `index.html` and `styles.css` as mockup v3,** using real `data-i18n`
  texts and `icon()` icons.
  - The tool panel (`panel.js`) has the three tabs and 1.2's fields for each tab:
    - *Omdøb filer*: mask with Variabler, example, check boxes, the case radios, the variable
      list, and Forhåndsvis/Omdøb/Fortryd;
    - *Multi-fil-tag-editor*: 1.2's fields;
    - *Tags fra filnavn*: 1.2's fields.
  - The mask fields and check boxes are filled from `[Rename]` and `[FileToTag]` in the ini.
    All action buttons are **disabled**, with the tooltip `Kommer i en senere version`.
  - The tab is remembered in `[View] ToolTab`. F4, Ctrl+F4 and Shift+F4 switch tabs.
  - The cover boxes are on the right.
- [ ] **Step 4:** Run `npm start`. Expected: the window matches the mockup. Check it by eye
  against `2026-11-26-tidytag-tauri-mockup.html` in Danish and English.
- [ ] **Step 5:** Commit `feat(ui): theme, strings, icons and layout`.

### Task 11: Menus, icon bar, tree, address row and the virtual file list

**Files:** Create `renderer/menu.js`, `renderer/tree.js`, `renderer/list.js`,
`renderer/renderer.js`, `renderer/list.test.js`, `renderer/menu.test.js`

**Interfaces:**
- Consumes `api.js`, `I18N` and `icon()` (Task 10).
- Produces:
  - `MENU`: the data for 1.2's seven menus, the file-list popup menu and the icon bar, in the
    exact item order of `mainform.pas` (from `TopMenu := Menu(rsFiler)` to the end of the
    `Btn(ToolBarFolders, ...)` lines). Each item is `{id, text (Danish), shortcut, icon, phase}`.
    Items whose `phase > 1` are drawn disabled.
  - In `list.js`:
    - `COLUMNS`: 1.2's 27 columns from `AddColumn(...)`, with caption, width, kind, field and
      numeric flag;
    - `cellText(track, col)`, ported from `TFormMain.CellText`;
    - `compareTracks(a, b, sortCol, sortDesc, secondCol)`, ported from `TFormMain.SortItems`;
    - `visibleWindow(scrollTop, viewportH, rowH, count, overscan=10) -> {first, last}`;
    - `statusTexts(view, selection, checked)` → the 5 texts of 1.2's `UpdateStatus`, with
      `formatDuration` from `tagutils.pas`.
- Phase 1 behaviour:
  - **Menu bar:** keyboard and mouse.
  - **Tree:** "Denne pc" → drives → lazy subfolders. The *Mapper* buttons Op/Favorit/Ny mappe/
    Opdater/Luk.
  - **Address combo:** history from `[AddressHistory] DirN` and favourites from
    `[Favorites] DirN`, written back with erase + rewrite as 1.2 does.
  - **Folders:** open the last folder from `[Main] LastFolder`; `[Main] Subfolders` and the
    subfolders toggle on the icon bar work.
  - **Scan:** `scan_start`, with a new `scanId` per folder change. Batches for an old id are
    ignored.
  - **List:** a virtual list with a sticky header, sorting by header click (Ctrl+click =
    secondary), row selection (click, Shift, Ctrl, Ctrl+A) and the ☑ column (Space toggles).
  - **Edit menu:** check/uncheck all, selected and invert work.
  - **Cover boxes:** the file cover of the focused row and the folder cover.
  - **Status bar:** `[View] Folders/Address/Filter/ToolsPanel` show and hide areas.
  - **Language:** the picker at the right of the menu bar sets `[Main] Language` and re-renders
    all texts without a restart.
  - Everything else is disabled.

- [ ] **Step 1: Write `list.test.js` and `menu.test.js`.**
  - `visible window renders only visible rows`: `visibleWindow(0, 600, 24, 50000)` returns
    `{first: 0, last: 34}`, and `(240000, 600, 24, 50000)` returns `{first: 9990, last: 10034}`.
  - `compareTracks sorts track numerically`: "2" < "10".
  - Text comparison is case-insensitive: "abc" == "ABC" → secondary column decides.
  - `formatDuration(3725) === '1:02:05'` and `formatDuration(65) === '1:05'`.
  - `stale scan batches are ignored`: `applyBatch(state, {scanId: 1, ...})` after
    `state.scanId = 2` leaves the rows unchanged.
  - `MENU has 1.2's top menus`:
    `['Filer','Rediger','Vis','Playliste','Værktøjer','Indstillinger','Hjælp']`.
  - The icon bar has 1.2's order: 22 buttons and 8 separators, 30 entries in all, as in the
    `Btn(ToolBarMain, ...)` lines.

  Run them. Expected: FAIL.
- [ ] **Step 2: Implement the pure functions.** Run the tests. Expected: PASS.
- [ ] **Step 3: Wire the DOM in `renderer.js`, `menu.js` and `tree.js`.**
- [ ] **Step 4: Manual check with `npm start`** on a copy folder (`%TEMP%\tidytag-corpus\files`):
  - the list fills progressively;
  - sorting and checking update the status bar;
  - switching folders mid-scan shows only the new folder;
  - a generated folder of 20,000 empty `.mp3` files scrolls smoothly;
  - the language switch works;
  - closing and reopening restores the folder and the window size.
- [ ] **Step 5:** Commit `feat(ui): menus, tree and virtual file list`.

### Task 12: Docs and phase wrap-up

- [ ] **Step 1: Add a "TidyTag 2 (in progress)" section to `README.md` under *Building*.**
  It covers `npm install`, `npm start`, `npm test`, `cargo test --workspace`, and the corpus
  script with `TIDYTAG_CORPUS`.
- [ ] **Step 2: Run everything.** Run `npm test`, `cargo test --workspace`, and the golden test
  with the corpus. Expected: all green, golden with 0 mismatches.
- [ ] **Step 3:** Commit `docs: TidyTag 2 phase 1 build notes`.
