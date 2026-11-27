# TidyTag 2 — Phase 4: Renaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything in 1.2's renaming works in TidyTag 2:
- renaming files from tags with a mask (the *Omdøb filer* tab and the preview dialog);
- tags from the file name (the *Tags fra filnavn* tab and the preview dialog);
- renaming folders from tags;
- renaming one file or folder by hand;
- rename actions, word replacements and the mask editor;
- undo.

**Architecture:**
- The rename engine is ported to Rust in `tidytag-core`:
  - `rename.rs` from `renamecore.pas`;
  - `filename_tags.rs` from `filenametags.pas`.
- It is cross-checked against 1.2 on the corpus with a new Pascal tool, `renamedump`.
- Tauri commands in `src-tauri/src/rename.rs` plan, run and undo renames for the renderer's
  tracks.
- The renderer brings the two tool tabs to life and adds the dialogs. The undo log lives in the
  renderer, in memory, as 1.2 kept it in `FUndoLog`.

**Tech Stack:** Rust (tidytag-core, Tauri 2), plain JS renderer (UMD, `node --test`), FPC 3.2.2
for the Pascal tool.

**Spec:** `docs/superpowers/specs/2026-11-26-tidytag-tauri-design.md` (phase 4 in *Order of
work*). Phase 1–3 plans: `docs/superpowers/plans/2026-11-26-*.md`, `2026-11-27-*phase3*.md`.

## Global Constraints

**Same as 1.2**
- 1.2's units are the specification: `renamecore.pas`, `filenametags.pas`, `renameform.pas`,
  `filetotagform.pas`, `tooldialogs.pas` (`EditRenameWords`, `EditRenameActions`, `EditMask`),
  `appsettings.pas` and the `mainform.pas` handlers named in each task. Every port carries
  `// from: <Pascal name>` comments.
- `tools/renametest.lpr` holds 1.2's own expected values. Its cases are ported as they are.
- All texts are 1.2's Danish source strings, looked up with `t()`. Dialog units use their own
  texts through `MENUDATA.unitRs`. mkmenu.py gains `renameform`, `filetotagform` and `renamecore`.
  A new text is allowed only where 1.2 has none, and then with all six translations.
- Settings keep 1.2's keys:
  - `[Rename]` (`Mask`, `Case`, `Underscores`, `PadTrack`), and `[RenameFolder]` with the same
    keys for the folder dialog;
  - `[FileToTag]` (`Mask`, `Case`, `Underscores`);
  - the mask histories `[RenameMasks]`, `[FolderMasks]` and `[FileToTagMasks]`, as `Mask0`..`Mask14`,
    newest first, at most 15;
  - `[SavedRenameMasks]`, as `Count` and `Mask1`..;
  - `[RenameReplace]` (`Count`, `From<n>`, `To<n>`) and `[RenameKeepCase]` (`Count`, `Word<n>`);
  - `[RenameActions]` (`Count`, `Name<n>`, `FileMask<n>`, `FolderMask<n>`).

  Values in the last three are written in double quotes (`Quote`/`Unquote`).

**Safety**
- Tests and manual runs use copies under `%TEMP%`, and the app runs with `TIDYTAG_INI`. Never
  touch `C:\Users\allan\Music` or `D:\`.
- A rename never overwrites. The target is checked again just before each move (`ExecuteRename`).
- Renames and undo claim `WriteState` like a write batch. The window cannot close while they run.
- Phone paths are phase 9. 2.0 cannot open a phone folder yet, so the phone branches of
  `RenamePaths`/`PhoneRenamed` are left out and marked `// phase 9`.

**UI automation and commits**
- Phase 3's rules apply: clicks only when TidyTag is in front, and manual checks only with the
  owner's OK.
- Dialog buttons never use `data-act`. The smoke test already guards this.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.

## Review Focus

1. **A rename that changes only upper/lower case** ("abc.mp3" → "Abc.mp3"). It is planned
   `Omdøbes`, not `Findes allerede`, and it really changes the name on disk. Pinned in Task 1 by
   `rename_case_only_changes_name`.
2. **Tag values with characters Windows forbids** (`AC/DC`, `What?`, `a:b`, a trailing dot or
   space). They are cleaned as `SanitizeNamePart` does, and never create a folder by accident.
   Pinned in Task 1 by `mask_values_are_sanitized`.
3. **Two files that would get the same new name.** The first is renamed, and every later one is
   `Samme navn som en anden fil`. Nothing is overwritten. Pinned in Task 1 by
   `duplicate_targets_rename_only_the_first`.
4. **Undo after the files were changed outside TidyTag** (one renamed file deleted, one old name
   taken again). The rest is restored, each problem is reported with 1.2's text, and empty
   folders the rename created are removed. Pinned in Task 1 by `undo_reports_missing_and_taken`.
5. **Renaming the folder that is open, or a parent of it** (folder dialog, a hand rename in the
   tree, undo of either). The list, the address bar and the tree follow the new name, and the
   files keep their checkmarks. Pinned in Task 7 by `rename log moves the open folder and its
   files`.

---

### Task 0: Branch

- [ ] `git checkout -b tidytag2-phase4` from main.

### Task 1: The rename engine (Rust)

**Files:** Create `src-tauri/core/src/rename.rs`; modify `core/src/lib.rs`

**Interfaces:**
- Produces in `tidytag_core::rename`:
  - `CaseMode { None, Title, Sentence, Lower, Upper }`, with serde in this order; the ini
    `Case` value is its index.
  - `RenameOptions { case_mode, spaces_to_underscores, pad_track, keep_case_words: Vec<String>,
    replace_from: Vec<String>, replace_to: Vec<String> }`.
  - `RenameStatus { Ok, Unchanged, Missing, Exists, Duplicate, Invalid, Done, Failed }`.
  - `PlanItem { old_name: PathBuf, new_name: PathBuf /* empty when not built */, status, detail: String }`.
  - `LogItem { old_name, new_name }`.
  - Functions, each a port of the Pascal function of the same name:
    - `apply_case(&str, CaseMode) -> String`;
    - `sanitize_name_part(&str) -> String`;
    - `adjust_words(&str, &RenameOptions) -> String`;
    - `expand_rename_mask(mask, &AudioInfo, file_number, number_width, &RenameOptions) -> Result<PathBuf, String /* missing captions */>`;
    - `plan_rename(&[&AudioInfo], mask, &RenameOptions) -> Vec<PlanItem>`;
    - `common_folder_values(&[&AudioInfo], dir) -> MaskValues`;
    - `plan_folder_rename(&[&AudioInfo], mask, &RenameOptions) -> Vec<PlanItem>`;
    - `map_renamed_path(&Path, &[LogItem], reverse) -> PathBuf`;
    - `execute_rename(&mut [PlanItem]) -> Vec<LogItem>`;
    - `undo_rename(&[LogItem], errors: &mut Vec<String>) -> usize`.
- Status and detail texts stay Danish source strings (`rsOmdoebes`, …, `rsStienErForLang`). The
  renderer translates them with `t()`.

- [ ] **Step 1: Port `renametest.lpr`'s pure cases as Rust tests.** The procedures are
  `TestCase`, `TestExpand`, `TestWords`, `TestTracks` and `TestFolderPlan`. Each `Eq`/`Check` line
  becomes one `assert_eq!` with the same values. Also port `TestRenameAndUndo` as
  `rename_and_undo_on_disk`, in a temp folder. Add the Review Focus tests:
  - `rename_case_only_changes_name`: `abc.mp3`, mask `%2` with title `Abc` →
    status `Ok`; after `execute_rename` the folder listing shows `Abc.mp3`.
  - `mask_values_are_sanitized`: artist `AC/DC`, title `What?: a.` → no `/`, `?`, `:` and no
    trailing dot or space in the new name, which stays in the same folder.
  - `duplicate_targets_rename_only_the_first`: two files with the same title, mask `%2` →
    `[Ok, Duplicate]`; after execute, the second still has its old name.
  - `undo_reports_missing_and_taken`: rename 3 files into `%1\%2` subfolders. Delete renamed
    file 1, and create a file at old name 2. Undo → returns 1. The errors end with
    `: findes ikke længere` and `: der ligger allerede en fil med det navn`, and the emptied
    subfolder of file 3 is gone.

  Run `cargo test -p tidytag-core --lib rename`. Expected: FAIL (module missing).
- [ ] **Step 2: Implement `rename.rs`.**
  - Case changes follow `ApplyCase` (word separators `' ([{-._"/&+'`).
  - Windows' own upper/lower mapping is what Task 3 checks. Use `CharUpperBuffW`/`CharLowerBuffW`
    through windows-sys, as Lazarus's `WideUpperCase` does, not Rust's `to_uppercase` (it turns
    `ß` into `SS`).
  - Paths are compared case-insensitively, as `SameFileName` does.
  - The 260-character check counts UTF-16 units.

  Run the tests. Expected: PASS.
- [ ] **Step 3:** Commit `feat(core): rename engine`.

### Task 2: Tags from file name (Rust)

**Files:** Create `src-tauri/core/src/filename_tags.rs`; modify `core/src/lib.rs`

**Interfaces:**
- Produces:
  - `FileNameMatch { ok: bool, values: BTreeMap<TagField, String>, used: Vec<TagField> }`;
  - `mask_fields(mask) -> Vec<TagField>`;
  - `match_file_name(mask, path, underscores_to_spaces, CaseMode) -> FileNameMatch`, from
    `MatchFileName`.

- [ ] **Step 1:** Port `renametest.lpr`'s `TestMatch` cases as tests. Run them. Expected: FAIL.
- [ ] **Step 2:** Implement it, with `Tokenize`, `MatchFrom` (backtracking), `ValidNumeric` and
  `apply_case` from Task 1. Run it. Expected: PASS.
- [ ] **Step 3:** Commit `feat(core): tags from file name`.

### Task 3: Cross-check against 1.2 on the corpus

**Files:** Create `tools/renamedump.lpr`, `tools/make-rename-corpus.ps1`,
`src-tauri/core/tests/golden_rename.rs`

**Interfaces:**
- `renamedump <file>` (1.2) prints one JSON line per case for that file:
  `{"mask", "case", "us", "words", "result", "missing"}`.
  - The masks are a fixed list in both tools: 1.2's six default rename masks, plus
    `%7 (%0 kbit, %t)`, `%cat %key %khz %ext %grp`, `%aa\%4 - %3\%6 - %2`, and two folder masks.
  - Each mask is printed for all five case modes, with underscores off and on.
  - `words` uses a fixed set: keep-case words `AC/DC` and `ABBA`, and the replacement `' & '` →
    `' and '`.
  - The tool also prints one F2T line per default F2T mask, matched against the file's own path.
- `make-rename-corpus.ps1` writes `%TEMP%\tidytag-corpus\rename.jsonl` from `files\`.

- [ ] **Step 1:** Write `golden_rename.rs`. It runs the same cases through Tasks 1–2 and
  compares each line, and it skips when `TIDYTAG_CORPUS` is not set (like `golden.rs`).
- [ ] **Step 2:** Build `renamedump` with the fpc command in the README, run the script, then run
  the test. Expected: 0 mismatches. Fix the port, not the expectations, until it is so. Note the
  line count in the ledger.
- [ ] **Step 3:** Commit `test: rename cross-check against 1.2`.

### Task 4: Rename commands (Tauri)

**Files:** Create `src-tauri/src/rename.rs`; modify `src-tauri/src/main.rs`, `renderer/api.js`

**Interfaces:**
- Renderer tracks go in as `RenameTrack { path, fields, bitrate, duration, sampleRate,
  bitDepth }`, which is a subset of `TrackDto` and is turned into `AudioInfo`.
- Commands:
  - `plan_rename(tracks, mask, opt) -> [PlanRow]` and `plan_folder_rename(tracks, mask, opt) -> [PlanRow]`.
    A row is `{oldName, newName, status, detail}`.
  - `execute_rename(rows) -> {rows, log}`. It claims `WriteState`, runs only the `Ok` rows, and
    reports `Done`/`Failed` per row.
  - `undo_rename(log) -> {restored, errors}`. It claims `WriteState`.
  - `map_paths(paths, log, reverse) -> [path]`.
  - `rename_one(oldPath, newName) -> LogItem`. It renames inside the same folder. An invalid name
    gives `rsUgyldigtNavn`, and an existing target gives 1.2's `rsFiltypeFindes` text.
  - `match_file_names(paths, mask, underscores, caseMode) -> [FileNameMatch]`.
- `opt` is `{caseMode, underscores, padTrack}`. The commands add the word lists from the ini
  (`ApplyRenameWords`) themselves.

- [ ] **Step 1:** Write `plan_and_execute_from_dto`. In a temp folder, two `RenameTrack`s and mask
  `%6 - %2` → `plan_rename` gives `Ok` rows; `execute_rename` renames both and returns a log of
  two; `undo_rename` restores both. Also write `rename_one_refuses_invalid_and_existing`. Run them.
  Expected: FAIL.
- [ ] **Step 2:** Implement and register the commands, and add the `API` wrappers. In the
  renderer's `counted` list (closing waits), add `executeRename`, `undoRename` and `renameOne`.
  Run `cargo test --workspace`. Expected: PASS.
- [ ] **Step 3:** Commit `feat: rename commands`.

### Task 5: The two tool tabs come alive

**Files:** Create `renderer/renametools.js`, `renderer/renametools.test.js`; modify
`renderer/panel.js`, `renderer/renderer.js`

**Interfaces:**
- Produces `RENAMETOOLS` (pure):
  - `maskTemplate(mask, ext, vars, spacesTo)`, from `MaskTemplate`;
  - `addMaskToHistory(list, mask)`: newest first, no duplicates, at most 15;
  - `renameConfirm(rows) -> {okCount, skipped, examples, problems}`, from `ButtonRenameDoClick`;
    `examples` is at most 400 characters and `problems` at most 600;
  - `f2tItems(tracks, matches) -> {items, ready, noMatch}`, from `ButtonF2TWriteClick`. A file is
    written only when a used field changes, and only its used fields are written.
- The tabs, as `mainform.pas` builds them:
  - **Omdøb filer:** the live preview (`UpdateInlinePreviews`, with the focused file's result as
    the tooltip); *Variabler ▾* (`ButtonVarsClick`: *Maske-editor...* for rename only, then the
    codes); *Forhåndsvis...*, *Omdøb* and *Fortryd*.
  - **Tags fra filnavn:** the live preview; *Variabler ▾*; *Forhåndsvis...* and *Skriv tags*.
    Writing goes through `write_tags_batch` as `rsTagsFraFilnavn`.
  - The options are saved with `SaveInlineOptions`' keys before each action.
  - The mask joins its history after a successful run.

- [ ] **Step 1:** Write the tests:
  - `mask template shows field names`: `'%1 - %2'`, `.mp3`, `'_'` → `'<Kunstner>_-_<Titel>.mp3'`,
    with 1.2's spaces rule.
  - `history keeps 15 newest`.
  - `f2t writes only changed files`: 3 tracks, one no-match, one unchanged and one changed →
    `ready 1`, `noMatch 1`, and the item holds only the used fields.

  Run them. Expected: FAIL.
- [ ] **Step 2:** Implement and wire it. Run `npm test`. Expected: PASS.
- [ ] **Step 3:** Commit `feat(ui): rename and tags-from-filename tabs`.

### Task 6: The two preview dialogs

**Files:** Create `renderer/renamedialog.js`, `renderer/f2tdialog.js`; modify `renderer.js`,
`index.html`, `styles.css`, `tools/mkmenu.py`

- **Rename dialog** (`TFormRename`), for both files and folders (`FolderMode`):
  - the mask combo with history (`RenameMasks` or `FolderMasks`);
  - the variables help (`RenameVariablesHelp` or `FolderVariablesHelp`);
  - the scope radios: subset or all, with folder counts in folder mode;
  - case, underscores and pad track;
  - a live preview list with *Nuværende navn* / *Nyt navn* / *Status*, refreshed after 300 ms
    (`TimerPreview`);
  - the summary texts;
  - *Omdøb* asks, then runs. The log goes back to the caller for undo. Folder mode then applies it
    to the list (Task 7).
- **F2T dialog** (`TFormFileToTag`): the mask, scope, case, underscores and keep date. The preview
  has one column per field used by the mask, plus the status. *Skriv tags* writes through the
  batch and shows each file's result.
- Actions `aRenameDlg`, `aRenameFolder` and `aF2TDlg` are live, as are the tabs'
  *Forhåndsvis...* buttons. The tabs reload their options after a dialog closes.
- [ ] **Step 1:** Add `renamedialog state` tests in `renametools.test.js` for a pure
  `RENAMETOOLS.summary(rows, folderMode)`:
  - before a run: `'%d omdøbes   ·   %d uændret   ·   %d springes over'`;
  - after a run: `rsDOmdoebtDFejlKan`.

  Run them. Expected: FAIL. Then implement, and run. Expected: PASS.
- [ ] **Step 2:** Commit `feat(ui): rename and tags-from-filename dialogs`.

### Task 7: Hand renames, the rename log and undo

**Files:** Modify `renderer/renderer.js`, `renderer/tree.js`, `renderer/renametools.js`,
`renametools.test.js`

- **`aRenameManual` (F6).** When the tree has focus, it renames the tree's folder
  (`RenameFolderManual`). Otherwise it opens the file dialog (`RenameFileDialog`):
  - the folder line;
  - *Nyt navn:* with the extension beside it;
  - *Forrige*, *Næste*, OK and Annuller;
  - each change goes through `rename_one` and is added to one log.
- **`applyRenameLog(log, reverse)`**, from `ApplyRenameLog`. It runs `map_paths` on every list
  path, the open folder and the address bar. The tree shows the new folder names and keeps the
  open folder selected. Checkmarks and selection stay.
- **Undo** (`FActUndo`, Ctrl+Z, and the tab's *Fortryd*):
  - the hint text comes from `SetUndoLog` (`rsFortrydOmdoebningAfDS`);
  - it asks `rsGivDFilerMapperDeres`;
  - then `undo_rename`, then `applyRenameLog(..., true)`;
  - the status and error texts are 1.2's;
  - it is enabled only while a log exists.
- [ ] **Step 1:** Write `rename log moves the open folder and its files` for a pure
  `RENAMETOOLS.applyLog(state, mapped)`. The folder `C:/m/a` is renamed to `C:/m/b`, and the
  mapped paths come back from the command. Afterwards `state.folder` is `C:/m/b`, the tracks have
  the new paths, and checked and selected tracks are the same objects. Run it. Expected: FAIL.
  Then implement and run. Expected: PASS.
- [ ] **Step 2:** Commit `feat(ui): rename by hand and undo`.

### Task 8: Word replacements, the mask editor and rename actions

**Files:** Create `renderer/renameedit.js`; modify `renderer/renderer.js`, `renderer/menu.js`
(only if the dynamic submenu needs it)

- **`aWords`** opens `EditRenameWords`:
  - a two-column replace grid, plus 10 empty rows;
  - the keep-case memo;
  - the help text.

  It saves `[RenameReplace]`/`[RenameKeepCase]` quoted, then refreshes the live previews.
- **The mask editor** (`EditMask`, from the rename tab's *Variabler ▾*):
  - the mask, a live example and variable buttons that insert at the cursor;
  - the saved masks (`[SavedRenameMasks]`), with *Gem masken* and *Fjern*;
  - a double-click on a saved mask uses it.
- **`FActManageActions`** opens `EditRenameActions`:
  - a list, plus name, file-mask and folder-mask edits, each with its check box;
  - *Tilføj* (prefilled with the current file mask) and *Fjern*;
  - the help text.

  It saves `[RenameActions]` quoted.
- **The *Omdøbningshandlinger* submenu** is dynamic (`RebuildActionsMenu`): the actions, a
  separator, then *Administrer handlinger...*. Running an action follows `RunRenameAction`:
  - it plans the file mask first, then asks `rsKoerHandlingenS`;
  - files first, then folders of the renamed files;
  - one combined log for undo.
- [ ] **Step 1:** Write `ini lists round-trip quoted`. Pure `RENAMETOOLS.wordsToIni(words)` /
  `wordsFromIni(entries)` and `actionsToIni` / `actionsFromIni` keep `' & '` (leading and trailing
  spaces) through `Quote`/`Unquote`, and `Count` matches. Run it. Expected: FAIL. Then implement
  and run. Expected: PASS.
- [ ] **Step 2:** Commit `feat(ui): word replacements, mask editor and rename actions`.

### Task 9: Manual check (with the owner's OK) and docs

- [ ] **Step 1:** Ask the owner for a hands-off session. On copies in `%TEMP%\tidytag-ren4`, check:
  1. Rename 5 files with `%6 - %2`, then undo.
  2. Rename with `%1\%3\%6 - %2`, so subfolders are created; undo removes them again.
  3. Tags from file name with `%6 - %2` on renamed copies, checked with 1.2's tagdump.
  4. Rename the open folder in the folder dialog: the list and the tree follow.
  5. F6 on one file, Forrige/Næste, then Ctrl+Z.
  6. A word replacement (`' & '` → `' and '`) shows in the live preview.
  7. A rename action with a file mask and a folder mask, then one undo.
- [ ] **Step 2:** Update the README's TidyTag 2 section with phase 4 and the rename cross-check.
  Run `npm test`, `cargo test --workspace`, and `golden`, `golden_write` and `golden_rename` with
  the corpus. Expected: all green, 0 mismatches.
- [ ] **Step 3:** Commit `docs: TidyTag 2 phase 4 notes`.
