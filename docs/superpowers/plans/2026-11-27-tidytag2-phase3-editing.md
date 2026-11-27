# TidyTag 2 — Phase 3: Editing Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything in 1.2's *Editing tags* section works in TidyTag 2:
- the tag editor dialog for one file;
- the multi-file editor dialog;
- copying and pasting tags;
- the tag tools: swap, copy field, clean spaces, artist name tools, ID3v1↔v2 sync and remove tags;
- track numbers;
- cover tools, including dragging a picture onto the cover panels and resizing on save.

**Architecture:**
- **Pure field logic in JS.** `fieldtools.pas` and `trackcore.pas` work only on field values the
  renderer already has, so they are ported to `renderer/tools.js` and tested with `node --test`.
- **File work in Rust.** Everything that touches files lives in `tidytag-core`:
  - reading and saving one whole tag, with pictures;
  - ID3 sync;
  - removing tags;
  - cover resize and the folder-cover operations.
- **Writing.** Tag changes are saved through phase 2's `write_tags_batch`, extended with per-item
  pictures. Removing tags and ID3 sync are cross-checked byte for byte against 1.2, like phase 2.
- **UI.** The dialogs are modal overlays built on phase 2's `dialog.js` pattern. OS file pickers
  come from `tauri-plugin-dialog`.

**Tech Stack:** as phase 2, plus:
- `tauri-plugin-dialog` 2 (Rust and the JS global API);
- the `image` crate 0.25 with features `jpeg` and `png` only (`default-features = false`).

**Spec:** `docs/superpowers/specs/2026-11-26-tidytag-tauri-design.md` (phase 3, goal 4, anti-goals).
Earlier plans: `docs/superpowers/plans/2026-11-26-tidytag2-phase1-skeleton.md` and
`docs/superpowers/plans/2026-11-26-tidytag2-phase2-writing.md`.

## Global Constraints

**Same as 1.2**
- 1.2's units are the specification. Every port carries `// from: <Pascal name>` comments.
- All texts are 1.2's Danish source strings, from `.lfm` captions or resourcestrings, looked up
  with `t()`. A new text is allowed only where 1.2 has none, and then with all six translations.
- Only files 1.2 can write are written. Everything else is skipped with 1.2's text.
- Settings keep 1.2's keys:
  - `[Main] PasteFields` (the fields last chosen to paste);
  - `[Cover] MaxSide` (600), `Quality` (90), `ToJpeg` and `AutoResize`;
  - `[Editor] KeepTimestamp`;
  - the track tools' keys from `TFormTrackTools.SaveOptions`;
  - the ID3 sync choice.

**Safety**
- Tests and manual runs use copies under `%TEMP%`, and the app runs with `TIDYTAG_INI` (a
  settings copy). Never touch `C:\Users\allan\Music` or `D:\`.
- Phase 2's safe-write rules apply unchanged: temp file + replace, the original intact on error.
- Removing tags asks first, with 1.2's text, and the files read again afterwards.
- Cover resizing changes picture bytes. That is the one place where byte identity with 1.2 is not
  required. Width, height, MIME and the JPEG quality setting must still match what 1.2 would
  produce.

**UI automation and commits**
- UI automation clicks only when the TidyTag window is in front. The scratchpad `click.ps1` check
  stays. Manual UI checks need the owner's OK to run while they keep their hands off.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.

## Review Focus

1. **Remove tags** on a file whose format keeps only part of its tags: 1.2's `RemovesWholeTag`
   difference (pictures and fields cleared versus the whole tag removed) is kept. The audio is
   untouched. Pinned by golden_write's new step `s3`, and by
   `remove_tags_keeps_audio_fingerprint` (Task 2).
2. **A picture file that is not an image** (a renamed .txt, a 0-byte file, a huge 30 MB JPEG) added
   in the tag editor or dropped on a cover panel: it is refused with a readable text, and nothing
   is written. Pinned by `read_image_file_rejects_non_images` (Task 3).
3. **Tag editor "Gem og næste" on the last file, or closing with unsaved changes:** 1.2's
   `FormCloseQuery` question is asked, and nothing is lost silently. Pinned by
   `editor asks before discarding changes` (Task 6).
4. **Multi editor with differing values:** a field left untouched (showing the "different"
   hint) is never written, even though it is shown. Only ticked fields are written. Pinned by
   `multi editor writes only ticked fields` (Task 7).
5. **Track numbers on files from several folders with "Start forfra i hver mappe" off:** one
   running number across the selection in list order, and the total is the selection size.
   Pinned by `numbering across folders` (Task 1).

---

## File Structure

```
renderer/tools.js (+ tools.test.js)   fieldtools.pas + trackcore.pas + paste rules (pure)
renderer/forms.js                     small form dialogs: field pair, field set, sync, cover resize
renderer/tageditor.js                 TFormTagEdit
renderer/multieditor.js               TFormMultiEdit
renderer/tracktools.js                TFormTrackTools
renderer/covers.js                    cover panels, drag and drop, cover menu actions
renderer/renderer.js, menu.js, api.js, index.html, styles.css   wiring
src-tauri/core/src/tagremove.rs       tagremove.pas
src-tauri/core/src/id3sync.rs         id3sync.pas
src-tauri/core/src/cover.rs           coverimage.pas + folder-cover helpers from mainform.pas
src-tauri/core/src/write.rs           + WriteOptions.cover_resize (1.2's PictureFilter)
src-tauri/src/commands.rs             + read_tag, save_tag, remove_tags_batch, id3_sync_batch,
                                        cover commands, read_image_file, read_text_file, write_file
tools/tagset.lpr, core/src/bin/tagset.rs   + --remove
tools/mkmenu.py                       phases: the Task 8 cover actions -> 3, aDelFolderCover -> 5 (Recycle Bin)
```

---

### Task 0: Branch

- [ ] `git checkout -b tidytag2-phase3` from main.

### Task 1: Field tools and track numbers (pure JS)

**Files:** Create `renderer/tools.js`, `renderer/tools.test.js`

**Interfaces:**
- Produces `TOOLS`. A plan is `{values: {key: value}, fields: [key]}`, or `null` when there is
  nothing to do.
  - `planSwap(track, a, b)` — from `PlanSwap`;
  - `planCopy(track, src, dst, onlyIfEmpty)` — from `PlanCopy`;
  - `cleanSpaces(s, collapse)` — from `CleanSpaces`;
  - `planCleanSpaces(track)`;
  - `applyNameTool(s, tool)` and `planNameTool(track, field, tool)`. `tool` is one of
    `'removeThe' | 'theToEnd' | 'theToFront' | 'nameToSurnameFirst' | 'surnameFirstToName'`.
  - `parseTrack(s) -> {num, total} | null`, `formatTrack(num, total, fmt)` and
    `planTrackNumbers(tracks, mode, fmt, startAt, perFolder) -> [string]`. `fmt` is one of
    `'7' | '07' | '007' | '7/12' | '07/12'` (1.2's `TrackFormatNames`), and `mode` is
    `'format' | 'number'`.
  - `pasteValues(copied, fields)`: the copied values restricted to the chosen fields, as in
    `ActPasteTagExecute`.

- [ ] **Step 1: Write `tools.test.js`.** Run it. Expected: FAIL.
  - `swap`:
    - artist 'A' and title 'B' → `{values: {artist: 'B', title: 'A'}, fields: ['artist', 'title']}`;
    - equal values → `null`.
  - `copy`:
    - an empty source → `null`;
    - `onlyIfEmpty` with the target set → `null`.
  - `cleanSpaces`:
    - `('  a   b\tc ', true)` → `'a b c'`;
    - `('  a  b ', false)` → `'a  b'`;
    - `planCleanSpaces` leaves lyrics and comment uncollapsed.
  - Name tools:
    - `'The Beatles'`: `removeThe` → `'Beatles'`, `theToEnd` → `'Beatles, The'`;
    - `'Beatles, The'`: `theToFront` → `'The Beatles'`;
    - `'Carl Nielsen'`: `nameToSurnameFirst` → `'Nielsen, Carl'`;
    - `'Nielsen, Carl'`: `surnameFirstToName` → `'Carl Nielsen'`;
    - `'The A; The B'`: `removeThe` → `'A; B'`.
  - `formatTrack`:
    - `(7, 12, '07/12')` → `'07/12'`;
    - `(7, 0, '7/12')` → `'7'`;
    - `(7, 9, '007')` → `'007'`.
  - `numbering across folders`: 3 tracks in 2 folders, mode `'number'`, start 1, `perFolder` false,
    fmt `'07/12'` → `['01/03', '02/03', '03/03']`. With `perFolder` true and 2+1 tracks →
    `['01/02', '02/02', '01/01']`.
  - Format mode: track `'7'` with no total, in a folder holding 3 selected tracks, fmt `'07/12'` →
    `'07/03'`. Track `'abc'` → unchanged.
- [ ] **Step 2: Port the two units function by function.** Run `npm test`. Expected: PASS.
- [ ] **Step 3:** Commit `feat(ui): field tools and track numbering logic`.

### Task 2: Remove tags and ID3 sync (Rust, cross-checked)

**Files:** Create `core/src/tagremove.rs` and `core/src/id3sync.rs`; modify `bin/tagset.rs`,
`tools/tagset.lpr`, `tools/make-write-corpus.ps1`, `tests/golden_write.rs`

**Interfaces:**
- Produces:
  - `tagremove::removes_whole_tag(&Path) -> bool` and
    `tagremove::remove_all_tags(&Path, keep_timestamp: bool) -> Result<(), String>`;
  - `id3sync::sync_id3(&Path, dir: SyncDirection, existing: SyncExisting, keep_timestamp: bool) -> Result<bool, String>`,
    with the enums `SyncDirection {V1ToV2, V2ToV1}` and `SyncExisting {Skip, BlankOnly, Overwrite}`.
- `tagset --remove <file>` (Pascal and Rust) calls `RemoveAllTags(file, False)`.
- `make-write-corpus.ps1` adds a step `s3` = `--remove`, run after `s2` on the same copy.
  `golden_write` compares `s3` the same way.

- [ ] **Step 1: Write the tests.**
  - `remove_tags_keeps_audio_fingerprint`: a corpus-free MP3 built as in phase 2's tests gives
    the same audio bytes after removing, and `read_audio_info` shows no tag types.
  - `sync_v1_to_v2_blank_only`: ID3v1 title 'V1', ID3v2 artist 'A' and no v2 title → after
    syncing, title 'V1' and artist 'A'.
  - `sync_v2_to_v1_overwrite`: the v2 title replaces the v1 title.

  Run them. Expected: FAIL.
- [ ] **Step 2: Port both units.** Extend tagset, the corpus script and golden_write. Rebuild
  1.2's tagset, run `make-write-corpus.ps1`, then `golden_write` with the corpus. Expected: 216
  steps (54 × 4), 0 mismatches.
- [ ] **Step 3:** Commit `feat(core): remove tags and ID3 sync`.

### Task 3: Covers and whole-tag commands (Rust)

**Files:** Create `core/src/cover.rs`; modify `core/src/write.rs`, `core/Cargo.toml`,
`src-tauri/Cargo.toml`, `src-tauri/src/commands.rs`, `src-tauri/src/main.rs`,
`capabilities/default.json`

**Interfaces:**
- Produces in core:
  - `cover::CoverResize { max_side: u32, quality: u8, to_jpeg: bool }`;
  - `cover::resize_cover(data: &[u8], opt: &CoverResize) -> Option<(Vec<u8>, &'static str)>`,
    from `ResizeCover`: `None` when nothing has to change. The new size is
    `round(other * max / longer)`, and JPEG is written at `quality`.
  - `cover::find_folder_cover(dir) -> Option<PathBuf>`, with phase 1's name order;
  - `cover::save_folder_cover(dir, data) -> Result<PathBuf, String>`, which writes `folder.jpg` or
    `folder.png` as in `ActCoverFromTagsExecute`;
  - `WriteOptions.cover_resize: Option<CoverResize>`. When it is set (`[Cover] AutoResize`),
    `write_audio_tags` resizes every picture first, as 1.2's `PictureFilter` does.
- Produces these commands:
  - `read_tag(path) -> {track: TrackDto, pictures: [{picType, mime, description, data}]}`;
  - `save_tag(path, fields: {key: value}, pictures: [...]) -> TrackDto`, which writes all 37
    fields and exactly the given pictures, with `write_options()`;
  - `remove_tags_batch(paths, batchId)` and `id3_sync_batch(paths, direction, existing, batchId)`,
    which use phase 2's `write-progress`/`write-done` events;
  - `cover_to_tags_batch(paths, batchId)`, `cover_from_tags(dirs) -> {saved, skipped}`,
    `cover_as_folder(path)`, `resize_file_covers_batch(paths, opt, batchId)` and
    `resize_folder_covers(dirs, opt)`, each from the `mainform.pas` handler of the same name;
  - `read_image_file(path) -> {mime, data}`: images only (`detect_image_mime` with no fallback),
    at most 16 MB, otherwise 1.2's text;
  - `read_text_file(path)` and `write_file(path, base64)`, for lyrics and "Gem som...".
  - `WriteItem` gains `pictures: Option<[...]>`, which replaces all pictures, and
    `removeCovers: bool`, for the multi editor.
- Adds `tauri-plugin-dialog` with `dialog:default`.

- [ ] **Step 1: Write the tests.**
  - `resize_large_jpeg`: 2000×1000 → 600×300, JPEG.
  - `png_to_jpeg`: 100×100 PNG with `to_jpeg` → JPEG 100×100.
  - `small_jpeg_unchanged` → `None`.
  - `auto_resize_on_save`: a 2000×1000 cover saved with `cover_resize` reads back 600×300.
  - `read_image_file_rejects_non_images`: a .txt, a 0-byte file and a 17 MB file all give `Err`.

  Run them. Expected: FAIL.
- [ ] **Step 2: Implement.** Run `cargo test --workspace`. Expected: PASS. Run `golden_write`.
  Expected: still 0 mismatches, because `cover_resize` is `None` there.
- [ ] **Step 3:** Commit `feat(core): covers, resize and whole-tag commands`.

### Task 4: Small form dialogs and the tag-tool menus

**Files:** Create `renderer/forms.js`; modify `renderer/renderer.js`, `renderer/menu.js`,
`tools/mkmenu.py`

**Interfaces:**
- Produces in `FORMS`:
  - `fieldPair(title, fromCaption, toCaption, checkCaption, a, b, check) -> Promise<{a, b, check} | null>`
    — from `AskFieldPair`;
  - `fieldSet(title, prompt, values, fields) -> Promise<[key] | null>` — from `AskFieldSet`;
  - `id3Sync(direction, existing) -> Promise<{direction, existing} | null>` — from `AskID3Sync`;
  - `coverResize(title, opt) -> Promise<opt | null>` — from `AskCoverResize`.

  Captions and layout follow the dialogs in `tooldialogs.pas`.
- Live actions, with 1.2's targets, confirms and status texts:
  - `aSwapAT`, `aSwapAA`, `aSwapLT` and `aSwap`;
  - `aCopyField` (its "only if empty" check is remembered as 1.2 does), `aClean`, the five
    `NameTools`;
  - `aCopy` and `FActPaste`. Paste is enabled after a copy, and `[Main] PasteFields` is
    remembered.
  - `aSync` and `aRemoveTags`, through the Task 2/3 commands.

  Each plan action writes only files whose plan is not `null`, through `write_tags_batch`.

- [ ] **Step 1: Write the tests** in `tools.test.js`:
  - `paste keeps only chosen fields`;
  - `swap plans for a selection skip unchanged files` (2 of 3 files change → 2 write items).

  Run them. Expected: FAIL.
- [ ] **Step 2: Implement.** Run `npm test`. Expected: PASS.
- [ ] **Step 3: Manual check** (with the owner's OK) on copies in `%TEMP%\tidytag-save3`:
  - swap artist/title on 2 files;
  - paste only the album;
  - remove tags on 1 file.

  Then `bin\tagdump.exe` (1.2) reads the results.
- [ ] **Step 4:** Commit `feat(ui): tag tools, copy/paste, ID3 sync and remove tags`.

### Task 5: Track numbers dialog

**Files:** Create `renderer/tracktools.js`; modify `renderer.js`, `index.html`

- It is `TFormTrackTools`:
  - mode radios;
  - the format combo with `TrackFormatNames`;
  - start spin and "Start forfra i hver mappe";
  - scope radios;
  - a live preview list with the columns Fil / Spor nu / Nyt spor / Status / Mappe;
  - "Bevar filernes dato", "Gem spornumre" and "Luk".
- It uses `TOOLS.planTrackNumbers`, writes through `write_tags_batch`, and saves the options with
  1.2's keys.
- [ ] **Step 1: Write the test** `track dialog statuses` in `tools.test.js`: unchanged → Uændret,
  and an unwritable extension → its 1.2 status text. Run it. Expected: FAIL. Then implement and
  run. Expected: PASS.
- [ ] **Step 2: Manual check.** Number 5 copies, then check with 1.2's tagdump.
- [ ] **Step 3:** Commit `feat(ui): track numbers`.

### Task 6: Tag editor dialog

**Files:** Create `renderer/tageditor.js`; modify `renderer.js`, `index.html`, `styles.css`

- It is `TFormTagEdit`:
  - **Generelt:** the fields as in the `.lfm`, the cover with < / >, *Tilføj...*, *Fjern* and
    *Gem som...*;
  - **Flere felter:** built as `BuildExtraFields`;
  - **Sortering**;
  - **Sangtekst:** *Indlæs fra tekstfil...*, *Gem som tekstfil...* and *Ryd*;
  - the file info line and "Bevar filens dato";
  - *Gem og forrige*, *Gem*, *Gem og næste* and *Luk*.
- It loads with `read_tag` and saves with `save_tag`.
- `FormCloseQuery`: if something was changed and not saved, it asks before closing or moving on.
- It is opened by `aEdit` (and Enter / double-click on a row, as 1.2).
- [ ] **Step 1: Write `editor asks before discarding changes`.** Move the editor's state logic
  into a pure `EDITOR_STATE` (`modified`, `next(index, count)`, `needsQuestion(action)`) and test
  it with node. Run it. Expected: FAIL. Then implement and run. Expected: PASS.
- [ ] **Step 2: Manual check** on a copy:
  1. Edit the title.
  2. Add a picture from a copied image.
  3. *Gem og næste*.
  4. `tagdump` (1.2) shows the title and the picture.
- [ ] **Step 3:** Commit `feat(ui): tag editor`.

### Task 7: Multi-file editor dialog

**Files:** Create `renderer/multieditor.js`; modify `renderer.js`, `panel.js` (*Alle felter...*),
`tools/mkmenu.py` (`aMulti` → 3 live)

- It is `TFormMultiEdit`:
  - one row per field (`BuildRows`);
  - common values filled in, and differing values shown as a hint (`FillCommonValues`);
  - typing ticks the field;
  - "Erstat alle covers med:" + *Vælg billede...*;
  - "Fjern alle cover-billeder";
  - "Bevar filernes dato";
  - *Gem* with progress, and *Luk*.
- It writes through `write_tags_batch` (values, `pictures`/`removeCovers`).
- [ ] **Step 1: Write `multi editor writes only ticked fields`** for a pure
  `MULTI.buildItems(tracks, rows, cover)`. With 2 tracks where only artist is ticked, the items
  have only `artist` in `values`, and the untouched "different" album is absent. Run it.
  Expected: FAIL. Then implement and run. Expected: PASS.
- [ ] **Step 2: Manual check:** on 3 copies, set the album and replace the cover, then read with
  1.2's tagdump.
- [ ] **Step 3:** Commit `feat(ui): multi-file editor`.

### Task 8: Cover tools and the cover panels

**Files:** Create `renderer/covers.js`; modify `renderer.js`, `tools/mkmenu.py`, `index.html`

- **Cover-værktøjer menu:**
  - `aCoverIn`, `aCoverOut`, `aCoverAsFolder` (also on right-click of the file cover);
  - `aResizeFiles` and `aResizeFolders` (with `FORMS.coverResize`);
  - `FActAutoResize` (`[Cover] AutoResize`, a check item).
- **Dragging a picture onto the cover panels** (Tauri `dragDropEnabled` events):
  - the file panel sets the front cover of the targets;
  - the folder panel saves folder.jpg/png.

  Both ask as 1.2 does.
- `aDelFolderCover` moves to phase 5 (Recycle Bin) in `mkmenu.py`.
- [ ] **Step 1: Write `drop targets follow 1.2`** in `tools.test.js` for a pure
  `COVERS.dropPlan(panel, state)`: the file panel → the checked/selected tracks, and the folder
  panel → the current folder. Run it. Expected: FAIL. Then implement and run. Expected: PASS.
- [ ] **Step 2: Manual check:**
  - drop a copied JPEG on the file cover of 2 selected copies;
  - run cover → folder.jpg;
  - resize the folder covers to 600.

  Check the results with tagdump and the image size.
- [ ] **Step 3:** Commit `feat(ui): cover tools and drag-and-drop covers`.

### Task 9: Docs and wrap-up

- [ ] **Step 1:** Update the README's TidyTag 2 section: phase 3 is done, and `tagset --remove`
  plus the golden step `s3` are described.
- [ ] **Step 2:** Run `npm test`, `cargo test --workspace`, and `golden` + `golden_write` with the
  corpus. Expected: all green, 0 mismatches.
- [ ] **Step 3:** Commit `docs: TidyTag 2 phase 3 notes`.
