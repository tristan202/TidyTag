# TidyTag 2 — Phase 2: Writing Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** TidyTag 2 saves tags in every format 1.2 writes. The files are byte for byte the same as
1.2's for the same edit. Saving is used from the *Multi-fil-tag-editor* tab.

**Architecture:**
- 1.2's writer units are ported 1:1 into `tidytag-core`, next to the phase 1 readers, with the
  same rules:
  - keep the ID3 version;
  - keep frames/atoms/items TidyTag does not edit byte for byte;
  - use padding and in-place writes where 1.2 does;
  - otherwise write a temporary file and replace the original.
- A write cross-check runs tagtest's three scenarios with 1.2 (`tagset --scenario`) and with 2.0 on
  copies, and compares the resulting files byte for byte after every step.
- The UI gets a batch-write command with progress events and a small modal dialog, and the
  multi tab's *Gem tags* / *Kopiér fra fil* become live.

**Tech Stack:** as phase 1 (Rust 1.99, Tauri 2, plain JS, `node --test`, FPC 3.2.2 for the two
Pascal tool changes). No new crates; file times use `std::fs::File::set_times` and
`std::os::windows::fs::FileTimesExt`.

**Spec:** `docs/superpowers/specs/2026-11-26-tidytag-tauri-design.md` (phase 2 in *Order of work*;
goal 4 *Safe for music files*; anti-goals). Phase 1 plan:
`docs/superpowers/plans/2026-11-26-tidytag2-phase1-skeleton.md`.

## Global Constraints

**Safety**
- Audio data is never changed.
- A file is never left half-written. Rewrites go to `<file>.tidytag-tmp` (1.2's
  `TempFileFor`) and replace the original with `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`.
  On any error the temp file is deleted and the original is untouched.
- Writing needs a file that was read with pictures (`want_pictures = true`); otherwise the error is
  `Intern fejl: filen er læst uden billeder`. Unwritable types give
  `Skrivning af denne filtype understøttes ikke endnu`.
- Tests write only to copies in folders under `%TEMP%`. Never to `C:\Users\allan\Music` or `D:\`.
  Manual app runs use `TIDYTAG_INI` (a copy of the settings).

**Same as 1.2**
- Writable extensions (`CanWriteTags`): `.mp3 .flac .m4a .m4b .mp4 .ogg .oga .opus .wav .aif .aiff
  .aifc .ape .wv .mpc .ofr .wma .asf`.
- Settings that change a write, read from the ini for every batch:
  - `[Tags] ID3Unicode` (bool): ID3v2.3 text is always UTF-16, otherwise Latin-1 when every text
    fits.
  - `[Main] AlbumArtistRule`: 0 = none, 1 = copy Artist if Album artist is empty, 2 = always.
  - `[Editor] KeepTimestamp` (bool): restore creation, access and write time after saving.
- Error and status texts are 1.2's Danish resourcestrings, translated in the renderer with `t()`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.

## Review Focus

1. **A file that is read-only or locked** by another program (a player): the save fails for that
   file with a readable error, the original is unchanged, and no `.tidytag-tmp` is left. Pinned by
   `readonly_file_fails_cleanly` (Task 1).
2. **A rewrite that fails after the temp file was written** (the replace fails): the temp file is
   removed and the original is intact. Pinned by `failed_replace_removes_temp` (Task 1).
3. **Characters outside Latin-1** (CJK, `–`) in an ID3v2.3 tag with `ID3Unicode` off: those
   frames are written as UTF-16, and pure Latin-1 text stays Latin-1. Pinned by
   `v23_picks_encoding_per_frame` (Task 2).
4. **Saving while a folder is still being read:** refused with 1.2's
   `Vent venligst, til alle tags er læst.`, and nothing is written. Pinned by
   `save is refused while scanning` (Task 10).
5. **A file whose read gave an error** (damaged): it is skipped with that error and never
   written. Pinned by `damaged_file_is_not_written` (Task 9).

---

## File Structure

```
src-tauri/core/src/
  fileio.rs              temp_file_for, replace_file_with, copy_range, file stamps (tagutils.pas write parts)
  write.rs               can_write_tags, WriteOptions, apply_album_artist_rule, write_audio_tags (tagwriter.pas)
  batch.rs               update_file_tags, set_front_cover (batchwrite.pas)
  scenario.rs            tagtest's three edits, shared by the Rust tagset and the tests
  tags/id3_write.rs      id3writer.pas
  tags/flac_write.rs     flacwriter.pas (incl. build_vorbis_comment, build_flac_picture)
  tags/ogg_write.rs      oggwriter.pas
  tags/mp4_write.rs      mp4writer.pas
  tags/riff_write.rs     wavwriter.pas
  tags/ape_write.rs      apetag.pas (write parts)
  tags/asf_write.rs      asfwriter.pas
  bin/tagset.rs          tagset <file> field=value ... | --scenario N <file>
  tests/golden_write.rs  byte-for-byte cross-check against 1.2 (needs TIDYTAG_CORPUS)
src-tauri/src/commands.rs   + write_tags_batch, write events, write options from the ini
renderer/dialog.js          modal message / confirm (1.2's MessageDlg)
renderer/panel.js           multi tab live
renderer/renderer.js        targets, batch save, keep-date + album-artist menus
renderer/save.js            pure logic: targets, values, messages (+ save.test.js)
tools/tagset.lpr            + --scenario N
tools/make-write-corpus.ps1 1.2's results per scenario -> %TEMP%\tidytag-corpus\written
tools/mkmenu.py             phases: aMulti -> 3, FActKeepDate -> 2
```

**The scenarios** are tagtest's (`tools/tagtest.lpr`, `Scenario`). They run in order 0 → 1 → 2 on
the same copy:
- **0:** all 37 fields with tagtest's values, plus one front cover = `test_png(0)`.
- **1:** one front cover = `test_png(400 * 1024)`.
- **2:** comment, composer, lyrics, mood, catalogNo and url are cleared, and the pictures are
  removed.

`test_png(size)` is tagtest's 67-byte 1×1 PNG, padded to `size` with byte `i` = `(i * 31 + 7)
mod 256`. This replaces tagtest's `Random(256)`, so 1.2 and 2.0 get identical input.

---

### Task 0: Branch

- [ ] `git checkout -b tidytag2-phase2` from main. Expected: `Switched to a new branch`.

### Task 1: Write path, tagset, scenarios and the write cross-check harness

**Files:** Create `fileio.rs`, `write.rs`, `batch.rs`, `scenario.rs`, `bin/tagset.rs`,
`tests/golden_write.rs`, `tools/make-write-corpus.ps1`; modify `tools/tagset.lpr`, `lib.rs`

**Interfaces:**
- Produces, in `tidytag_core::fileio`:
  - `temp_file_for(&Path) -> PathBuf` (`<path>.tidytag-tmp`);
  - `replace_file_with(temp: &Path, target: &Path) -> Result<(), String>` (MoveFileExW as in
    Global Constraints; on failure it deletes `temp` and returns 1.2's text
    `Kunne ikke erstatte filen (Windows-fejl %d): %s`);
  - `copy_range(src: &mut File, dst: &mut impl Write, from: u64, count: u64) -> Result<(), String>`
    (a short copy gives `Kunne ikke kopiere lyddata`);
  - `struct FileStamp`, `get_file_stamp(&Path) -> Option<FileStamp>` and
    `set_file_stamp(&Path, &FileStamp)`.
- Produces, in `tidytag_core::write`:
  - `can_write_tags(&Path) -> bool`;
  - `struct WriteOptions { id3_always_unicode: bool, album_artist_rule: u8, keep_timestamp: bool }`
    with `Default`;
  - `apply_album_artist_rule(&mut AudioInfo, rule: u8)`;
  - `write_audio_tags(info: &mut AudioInfo, opt: &WriteOptions) -> Result<(), String>`. It
    dispatches by extension exactly as `WriteAudioTags` does. The writers in Tasks 2–8 plug in as
    `tags::<fmt>_write::write(path: &Path, info: &AudioInfo, opt: &WriteOptions) -> Result<(), String>`.
- Produces, in `tidytag_core::batch` (port of `UpdateFileTags`):
  - `update_file_tags(path: &Path, values: &BTreeMap<TagField, String>, cover: Option<Vec<u8>>, opt: &WriteOptions) -> Result<AudioInfo, (String, bool)>`.
    `Ok` holds the file read again; `Err` holds the error text and `skipped`.
  - `set_front_cover(&mut AudioInfo, Vec<u8>)`.
- Produces, in `tidytag_core::scenario`:
  - `test_png(size: usize) -> Vec<u8>`;
  - `apply(info: &mut AudioInfo, n: u8)`.
- Produces `tagset` (Rust and Pascal):
  - `tagset <file> key=value ...` with 1.2's `Names` keys;
  - `tagset --scenario N <file>`;
  - exit code 0 prints `ok`, 1 prints `FEJL: <text>`.

- [ ] **Step 1: Write the tests.**
  - In `fileio.rs`:
    - `readonly_file_fails_cleanly`: a read-only copy of a corpus MP3, then
      `write_audio_tags` → `Err`, the file bytes unchanged, and no `.tidytag-tmp` next to it.
    - `failed_replace_removes_temp`: `replace_file_with` onto a read-only target → `Err`, and the
      temp file no longer exists.
    - `stamp_roundtrip`: set the times, write, restore, and they are equal to the 100 ns.
  - In `write.rs`:
    - `refuses_unread_pictures` (`want_pictures = false` → 1.2's text);
    - `refuses_unknown_type` (`.dsf` → 1.2's text);
    - `album_artist_rule` for 0/1/2 with an empty and a set album artist.
  - In `scenario.rs`:
    - `test_png(0).len() == 67`;
    - `test_png(400 * 1024)[67] == ((67 * 31 + 7) % 256) as u8`.

  Run `cargo test -p tidytag-core`. Expected: FAIL (items missing).
- [ ] **Step 2: Implement the four modules.** All writers return `Err("not implemented")` for now.
  `update_file_tags`:
  1. Read with pictures.
  2. If the read gave an error, return `Err((error, false))` without writing.
  3. Set the values and the cover.
  4. Write.
  5. Read again.

  Run the tests. Expected: PASS.
- [ ] **Step 3: Add `--scenario N` to `tools/tagset.lpr`.** It applies the edits above to a file
  read with pictures, then calls `WriteAudioTags(Info, False)`, so it matches the Rust
  `scenario::apply`. Build it with fpc, as in phase 1.
- [ ] **Step 4: Write `tools/make-write-corpus.ps1`.** For every file in
  `%TEMP%\tidytag-corpus\files` it copies the file to `written\<name>`, then runs scenarios 0, 1
  and 2 in order with `bin\tagset.exe --scenario`. After each step it keeps a copy
  `written\<name>.s<N>`, or `written\<name>.s<N>.err` with tagset's error text. It refuses any
  target in Music or on `D:`.
- [ ] **Step 5: Write `tests/golden_write.rs`.**
  - If `TIDYTAG_CORPUS` is unset, print `skipped` and pass.
  - For each file, run the same three steps on a fresh copy with `scenario::apply` +
    `write_audio_tags`.
  - After each step, compare with `written\<name>.s<N>`: bytes must be identical. Where 1.2 gave
    `.err`, 2.0 must return the same error text.
  - Mismatches are printed as `<name> s<N>: first difference at byte <offset> (1.2 <len>, 2.0 <len>)`.
  - Also read the 2.0 result with `read_audio_info`; every field set in the scenario must read
    back.
- [ ] **Step 6:** Run the corpus script, then the golden test with the corpus. Expected: FAIL,
  with every file `not implemented`.
- [ ] **Step 7:** Commit `feat(core): write path, tagset and write cross-check harness`.

### Tasks 2–8: The writers (one task per Pascal unit)

Every writer task has the same steps:
1. Write the listed unit tests and see them fail.
2. Port the unit function by function, with `// from:` comments. Use the same padding sizes,
   frame/atom order, encodings, in-place versus rewrite decisions, and error texts.
3. Run `cargo test -p tidytag-core` (all green), then `golden_write` with the corpus: 0
   mismatches for this task's extensions, and the reader `golden` test still 0.
4. Commit `feat(core): <format> writer`.

| Task | Pascal source | Rust module | Extensions | Unit tests (beyond golden_write) |
|---|---|---|---|---|
| 2 | `id3writer.pas` | `tags::id3_write` (incl. `build_id3_tag_bytes(old: Option<&[u8]>, info, padding) -> Vec<u8>`, `write_id3v1(path, info, create_if_missing)`) | .mp3 | `v23_picks_encoding_per_frame`: TIT2 "æøå" → encoding 0, TPE1 "漢字" → encoding 1 with BOM, and with `id3_always_unicode` both → 1. `keeps_v24`: a v2.4 tag stays v2.4 with UTF-8 (encoding 3). `unknown_frames_kept`: a PRIV frame survives byte for byte. `id3v1_updated_not_created`. |
| 3 | `flacwriter.pas` | `tags::flac_write` (incl. `build_vorbis_comment`, `build_flac_picture`) | .flac | `in_place_when_padding_fits`: the audio offset is unchanged after a small edit. `unmanaged_comments_kept` (MUSICBRAINZ_TRACKID). `rewrite_when_growing` (400 KB picture). |
| 4 | `oggwriter.pas` | `tags::ogg_write` (incl. `ogg_crc`) | .ogg .oga .opus | `ogg_crc` of a page from a corpus copy (CRC field zeroed) equals the CRC stored in it. `opus_writes_r128`: rgTrackGain "3.00 dB" → `R128_TRACK_GAIN=-512`. `ogg_flac_refused` with 1.2's text. |
| 5 | `mp4writer.pas` | `tags::mp4_write` | .m4a .m4b .mp4 | `stco_shifted_when_moov_first`: every chunk offset moves by the size change. `free_atom_used_as_slack`. `freeform_kept` (an unknown `----` item). |
| 6 | `wavwriter.pas` | `tags::riff_write` | .wav .aif .aiff .aifc | `tags_after_audio`: the `id3 `/`LIST` chunks are last and the `data` chunk is unchanged. `riff_size_updated`. `aiff_has_no_info_chunk`. |
| 7 | `apetag.pas` (write parts: `AddItem`, `WriteHeaderFooter`, `WriteApeTags`) | `tags::ape_write` | .ape .wv .mpc .ofr | `replaces_in_place_before_id3v1`. `unknown_items_kept`. `picture_as_cover_art_front`. |
| 8 | `asfwriter.pas` | `tags::asf_write` | .wma .asf | `big_value_goes_to_metadata_library` (a 70 KB lyrics value). `unknown_attributes_kept`. `file_size_updated_on_rewrite`. |

*Before Task 2:* if the Pascal unit uses a helper from `tagutils.pas` that `fileio.rs`/`text.rs`
lack (`PutBE32`, `WriteZeros`, `UTF8Bytes`...), add it to `text.rs` in the task that first needs
it.

### Task 9: Batch command

**Files:** Modify `src-tauri/src/commands.rs`, `src-tauri/src/main.rs`, `core/src/batch.rs`

**Interfaces:**
- Consumes: `batch::update_file_tags` and `WriteOptions` (Task 1).
- Produces:
  - `write_tags_batch(items: Vec<WriteItem>, what: String, batch_id: u32)`, where
    `WriteItem = { path, values: {fieldKey: value}, cover: Option<base64> }`. It runs on its own
    thread and reads `WriteOptions` from the ini first.
  - Events:
    - `write-progress` `{batchId, done, total}`;
    - `write-done` `{batchId, saved, failed, skipped, errors: [{file, error}] (at most 20), tracks: TrackDto[]}`,
      where `tracks` are the files read again (so the list updates).

- [ ] **Step 1: Write `damaged_file_is_not_written`** in `batch.rs`: a truncated `.flac` copy gives
  `Err((_, false))` and is byte-identical afterwards. Also `skipped_type`: `.dsf` →
  `Err((_, true))`. Run them. Expected: FAIL (if the Task 1 code already passes, note it and keep
  the tests).
- [ ] **Step 2: Implement the command.** Tauri keeps one batch at a time. A second call while one
  runs returns `Err("busy")`. Run `cargo test --workspace`. Expected: PASS.
- [ ] **Step 3:** Commit `feat: batch write command`.

### Task 10: Saving from the multi tab, keep-date and album-artist settings

**Files:** Create `renderer/dialog.js`, `renderer/save.js`, `renderer/save.test.js`; modify
`renderer/panel.js`, `renderer/renderer.js`, `renderer/index.html`, `renderer/styles.css`,
`renderer/api.js`, `tools/mkmenu.py` (+ regenerate), `languages/src/translations.json` (+
regenerate strings)

**Interfaces:**
- Consumes `write_tags_batch` and its events (Task 9).
- Produces:
  - `DIALOG.info(text, kind)` and `DIALOG.confirm(title, text) -> Promise<boolean>`. They are
    modal overlays with LCL's buttons `Ja`, `Nej` and `OK`; add any missing translation.
  - In `save.js`:
    - `targets(state) -> {items, scope}`: the checked items, otherwise the selected ones (1.2's
      `TargetItems`);
    - `multiValues(form) -> {fields: {key: value}, cleared: [caption]}`: values are trimmed, and
      only ticked fields are included;
    - `confirmText(n, clearedCaptions)`;
    - `doneText(what, saved, failed, skipped)`, built from `rsGemIDFiler`,
      `rsDisseFelterBliverRyddet`, `rsSGemtIDFiler` and `rsDSprungetOverFiltype`.
- Behaviour, as `ButtonMultiSaveClick`, `ButtonMultiCopyClick` and `MultiValueChange` in 1.2:
  - The six fields (Kunstner, Album, Albumkunstner, År, Genre, Kommentar) are editable. Typing
    ticks the field. The genre field offers 1.2's `GenreList`: the ID3 genres plus `[Genres]`
    custom ones, minus hidden ones, sorted case-insensitively.
  - *Kopiér fra fil* fills the fields from the focused file.
  - *Gem tags*:
    1. With no field ticked, show `rsSaetFluebenVedDeFelter`.
    2. If a scan is running, refuse with `rsVentVenligstTilAlleTags`.
    3. With no targets, show `rsAfkrydsEllerMarkerDeFiler`.
    4. Ask `Gem i %d filer?`, adding the cleared fields if any.
    5. Run the batch. The status bar shows `%s: %d af %d...` and then `rsSGemtIDFiler`. Errors are
       shown in a `rsNogleFilerBlevIkkeGemt` dialog. The list rows update from `tracks`.
  - *Alle felter...* stays disabled until phase 3.
  - Menu *Indstillinger*:
    - *Bevar filernes dato ved gem* (`FActKeepDate`, `[Editor] KeepTimestamp`) becomes a check
      item;
    - *Albumkunstner ved gem* becomes a submenu with 1.2's three radio items
      (`rsAlbumkunstnerIngen`, `rsAlbumkunstnerHvisTom`, `rsAlbumkunstnerAltid`) and
      `[Main] AlbumArtistRule`.
  - `mkmenu.py` phases: `FActKeepDate` → 1 (live now), `aMulti` → 3.

- [ ] **Step 1: Write `save.test.js`:**
  - `targets prefer checked files`: 2 checked + 1 selected → the 2 checked.
  - `targets fall back to selection`.
  - `multiValues only ticked, trimmed`: `{artist: ' A '}` ticked + album unticked →
    `{artist: 'A'}`.
  - `cleared fields are listed`: a ticked empty comment → `['Kommentar']`.
  - `confirm text`: `confirmText(3, ['Kommentar'])` →
    `'Gem i 3 filer?\nDisse felter bliver ryddet: Kommentar'`.
  - `done text`: `doneText('Multi-fil-tag-editor', 2, 1, 1)` →
    `'Multi-fil-tag-editor: gemt i 2 filer, 1 fejl, 1 sprunget over (filtype)'`.
  - `save is refused while scanning`: `canStartBatch({scanning: true})` → `false`.

  Run `npm test`. Expected: FAIL.
- [ ] **Step 2: Implement `save.js`, `dialog.js` and the wiring.** Run `npm test`. Expected:
  PASS.
- [ ] **Step 3: Manual check.** Use `npm start` with `TIDYTAG_INI` on a fresh copy of the corpus
  in `%TEMP%\tidytag-save`.
  1. Tick 3 files, set Kunstner, then Gem tags → the confirm dialog, then the status text. The
     rows show the new artist.
  2. `bin\tagdump.exe` (1.2) reads the new artist.
  3. With *Bevar filernes dato*, the write time is unchanged.
  4. With Albumkunstner = "always", the album artist equals the artist.
  5. Saving during a scan is refused.
- [ ] **Step 4:** Commit `feat(ui): save from the multi tab; keep-date and album-artist settings`.

### Task 11: Docs and wrap-up

- [ ] **Step 1:** In the README's *TidyTag 2* section, note that phase 2 is done, and describe
  `make-write-corpus.ps1`, `golden_write` and `tagset --scenario`.
- [ ] **Step 2:** Run `npm test`, `cargo test --workspace`, and `golden` + `golden_write` with
  the corpus. Expected: all green, 0 mismatches.
- [ ] **Step 3:** Commit `docs: TidyTag 2 phase 2 notes`.
