# TidyTag 2 — Phase 6: Online Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1.2's *Web-opslag (MusicBrainz/Discogs)...* works in TidyTag 2:
- searching releases or a song on MusicBrainz or Discogs;
- pairing the files with the release's tracks, with Op/Ned;
- writing the chosen fields and the front cover (in the files and/or as folder.jpg);
- the batch lookup of several albums or loose songs, one dialog after the other;
- *Discogs-token...*.

**Architecture:**
- The web clients are ported to Rust in `tidytag-core/src/web/`:
  - `musicbrainz.rs` from `musicbrainz.pas`;
  - `discogs.rs` from `discogs.pas`;
  - `http.rs` with the rate limits and retries.
- The network sits behind a small `Fetch` trait, so every test runs offline on 1.2's own JSON
  from `tools/webtest.lpr`.
- Tauri commands in `src-tauri/src/web.rs` run one search, release or cover call at a time,
  off the window's thread.
- The pairing (`trackmatch.pas`) is ported to the renderer as `webmatch.js`. The dialog moves
  files Op/Ned there with no round trip, and the track numbers reuse `TOOLS.parseTrack` /
  `formatTrack`. Writing goes through the existing `write_tags_batch`.

**Tech Stack:** Rust (tidytag-core, Tauri 2), `reqwest` 0.12 (`blocking`, `default-tls`, which
is Schannel on Windows, so no OpenSSL), `serde_json`; plain JS renderer (UMD, `node --test`).

**Spec:** `docs/superpowers/specs/2026-11-26-tidytag-tauri-design.md` (phase 6 in *Order of
work*; the *Other areas* table: `web` with `reqwest`, 1 request/second to MusicBrainz). Phase 1–5
plans: `docs/superpowers/plans/2026-11-2[678]-tidytag2-*.md`.

## Global Constraints

**Same as 1.2**
- 1.2's units are the specification: `musicbrainz.pas`, `discogs.pas`, `trackmatch.pas`,
  `weblookupform.pas` + `.lfm`, `tooldialogs.pas` (`AskLookupMode`) and `mainform.pas`
  (`ActWebExecute`, `RunWebBatch`, `ActDiscogsTokenExecute`). Every port carries
  `// from: <Pascal name>` comments.
- `tools/webtest.lpr` holds 1.2's expected values. Its `Check`/`Eq` lines are ported as they are.
- All texts are 1.2's Danish source strings, looked up with `t()`.
  - The form's captions come from `weblookupform.lfm`.
  - The unit texts come through `MENUDATA.unitRs`. Add `weblookupform`, `musicbrainz` and
    `discogs` to `tools/mkmenu.py`'s unit list, then regenerate.
  - Rust returns its errors as 1.2's Danish source texts; a text with `%d`/`%s` comes as
    `"<text>|<arg>"`, as the player does since phase 5.
- Settings keep 1.2's keys and defaults:
  - `[Web]`: `Title` 1, `Artist` 1, `Album` 1, `AlbumArtist` 1, `Year` 1, `YearOnly` 1,
    `Track` 1, `TrackTotal` 0, `Disc` 1, `Genre` 0, `Label` 0, `CoverTags` 1, `CoverFolder` 0,
    `Source` 0 (0 MusicBrainz, 1 Discogs);
  - `[Discogs] Token`;
  - *Bevar filernes dato* is phase 3's `[Editor] KeepTimestamp`.
- Limits as 1.2:
  - MusicBrainz: requests at least 1100 ms apart, process-wide; 503 is retried after 1500, 3000
    and 5000 ms (4 tries); timeouts of 20 s.
  - Discogs: also at least 1100 ms apart; 429 is retried after 3000 × attempt ms (3 tries).
  - Cover Art Archive: no limit; front-500.
- User-Agent: `TidyTag/<crate version> ( https://github.com/tristan202/TidyTag )`.
  MusicBrainz asks for an identifying agent. 1.2's `TidyTag/0.1 ( personal music tag editor )`
  is replaced.

**Safety and privacy**
- The Discogs token is the owner's. It is never typed, printed or logged by an agent; tests use
  the fake value `test-token`.
- The `Authorization: Discogs token=…` header goes only to hosts that are `discogs.com` or end
  in `.discogs.com`. A cover URL from the JSON that points elsewhere is fetched without it.
- Tests never use the network. One `#[ignore]` live test may be run by hand. Live searches in
  the manual check need the owner's OK; they send only artist, album and title.
- Writing uses phase 2's batch writer on copies under `%TEMP%`, with `TIDYTAG_INI`. Folder
  covers are never overwritten.

**UI automation and commits**
- Phase 3's rules apply: clicks only when TidyTag is in front, and manual checks only with the
  owner's OK.
- Dialog buttons never use `data-act`. Add each new dialog file to the smoke test's list.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No push.

## Review Focus

1. **The Discogs token goes to Discogs only.** A release whose image `uri` is on another host
   gets no `Authorization` header, and an error or log line never contains the token. Pinned in
   Task 3 by `token_only_sent_to_discogs`.
2. **MusicBrainz' one request per second holds during a batch.** Searches, song searches (two
   requests) and release details across several dialogs never come closer than 1100 ms. Pinned
   in Task 3 by `mb_requests_are_spaced`, which uses a fake clock.
3. **More files than tracks, or a file the pairing leaves out.** The row shows `-` / *(intet
   spor - filen ændres ikke)* and that file is not written. Only the paired rows are counted in
   "Skriv oplysninger fra … i %d filer?". Pinned in Task 5 by `extra files get no track and are
   not written`.
4. **One song whose album tag is wrong.** The song search is retried without the album, the
   first result (the original album) is chosen, and the file pairs with the hit's disc/position.
   Pinned in Task 4 by `song_search_retries_without_album`, and in Task 5 by
   `single file pairs with the search hit`.
5. **folder.jpg already exists, or several files share a folder.** It is written once per
   folder, never over an existing file, and an existing one is reported as
   `<path> findes allerede - ikke overskrevet`. Pinned in Task 6 by
   `folder cover once per folder, never over an existing one`.

---

### Task 0: Branch

- [ ] `git checkout -b tidytag2-phase6` from main.

### Task 1: MusicBrainz parsers (Rust core)

**Files:** Create `src-tauri/core/src/web/mod.rs`, `src-tauri/core/src/web/musicbrainz.rs`;
modify `core/src/lib.rs` (`pub mod web;`), `core/Cargo.toml` if needed

**Interfaces:**
- `web::Release` (`TMBRelease`): `id, title, artist, date, country, formats, label_name,
  catalog_no, release_group_id, disambiguation, status, release_type: String; track_count,
  score: i64; hit_title: String; hit_disc, hit_position: i64`.
- `web::Track` (`TMBTrack`): `disc, position: i64; number, title, artist: String; length_ms: i64`.
- `web::ReleaseDetail` (`TMBReleaseDetail`): `release: Release; album_artist, genre: String;
  disc_count: i64; disc_track_counts: Vec<i64>; compilation: bool; cover_url: String;
  tracks: Vec<Track>`.
- All three use serde with camelCase, because the renderer receives them as they are.
- `musicbrainz` functions:
  - `url_encode(&str) -> String`;
  - `build_release_query(artist, album) -> String`;
  - `build_recording_query(artist, title, album) -> String`;
  - `parse_search_json(&str) -> Vec<Release>`;
  - `parse_release_json(&str) -> Result<ReleaseDetail, String>`;
  - `parse_recordings_raw(&str) -> (Vec<Release>, String /* earliest */)`;
  - `parse_recording_search_json(&str) -> Vec<Release>`;
  - `sort_song_releases(&mut Vec<Release>)`.

  Errors are 1.2's texts (`rsUventetSvarFraMusicbrainz`, …).

- [ ] **Step 1: Port `webtest.lpr`'s MusicBrainz checks.** Copy its `ReleaseJson`,
  `SearchJson` and `RecordingJson` constants verbatim as Rust raw strings, plus these checks, one
  `assert_eq!` each:
  - search: 2 releases; `Gasolin’`; `12" Vinyl`; `CBS / CBS 80993`; `2×CD`; empty date;
  - release: `Bedste ændringer`; compilation; genre `Hard Rock`; 2 discs; 3 tracks;
    `Kunstner A feat. Gæst`; disc 2 track 1; 99000 ms from the recording;
  - recordings: 4 releases in the order `alb single comp boot`; types `Album`/`Compilation`;
    hit disc 1 position 3; artist `Bandet` from the recording; track count 21;
  - `build_recording_query("Gasolin'", "Rabalderstræde", "")` = `recording:"Rabalderstræde" AND artist:"Gasolin'"`;
  - `url_encode("Æ ø/\"")` = `%C3%86%20%C3%B8%2F%22`;
  - `build_release_query("A \"B\"", "")` = `artist:"A \"B\""`.

  Run `cargo test -p tidytag-core --lib web::musicbrainz`. Expected: FAIL (module missing).
- [ ] **Step 2: Implement it with `serde_json::Value`.** Mind these:
  - `JStr` accepts strings and numbers;
  - `CapitalizeGenre` uppercases only ASCII a–z after `' -/&'`;
  - `DateKey` and the `SongRank`/`Better`/`Before` sort are stable (an insertion sort, as in
    1.2).

  Run it. Expected: PASS.
- [ ] **Step 3:** Commit `feat(core): MusicBrainz parsers`.

### Task 2: Discogs parsers (Rust core)

**Files:** Create `src-tauri/core/src/web/discogs.rs`

**Interfaces:**
- `clean_discogs_name(&str) -> String`, `discogs_disc(&str) -> i64` and `duration_ms(&str) -> i64`.
- `parse_discogs_search_json(&str) -> Vec<Release>` and
  `parse_discogs_release_json(&str) -> Result<ReleaseDetail, String>`. They return the Task 1
  types.

- [ ] **Step 1: Port `webtest.lpr`'s Discogs checks.** Copy its `DiscogsSearchJson`,
  `DiscogsReleaseJson` and `DiscogsMultiDiscJson` constants verbatim. Port every `Check`/`Eq`:
  - `Kim Larsen (2)` → `Kim Larsen`; `Blink-182` kept; `Various` → `Various Artists`;
  - the `DiscogsDisc` cases;
  - search: 2 results; `Gasolin' / Gas 5`; `Vinyl, LP, Album`; type `Album`; `CBS CBS 80993`;
    id `1234`; `|Gasolin'`;
  - release: artist cleaned; `1975-00-00` → `1975`; label cleaned; style before genre
    (`Hard Rock`); `https://i.discogs.com/front.jpg`; a heading is not a track; `Rabalderstræde`;
    `Kim & Franz Beckerlee`; position 3 / number `B1`; 3723000 ms; 1 disc of 3;
  - multi-disc: compilation; `2001-05`; `CD2-2` = disc 2 track 2.

  Run it. Expected: FAIL.
- [ ] **Step 2: Implement it.** Run it. Expected: PASS.
- [ ] **Step 3:** Commit `feat(core): Discogs parsers`.

### Task 3: HTTP, rate limits and the web calls (Rust core)

**Files:** Create `src-tauri/core/src/web/http.rs`; modify `web/mod.rs`, `web/musicbrainz.rs`,
`web/discogs.rs`, `core/Cargo.toml` (`reqwest = { version = "0.12", default-features = false,
features = ["blocking", "default-tls"] }`)

**Interfaces:**
- `trait Fetch: Send + Sync`:
  - `fn get(&self, url: &str, headers: &[(&str, String)]) -> Result<(u16, Vec<u8>), String>`;
  - `fn sleep(&self, ms: u64)`;
  - `fn now_ms(&self) -> u64`.
- `struct Http`, the real one:
  - a `reqwest::blocking::Client` with the User-Agent, 20 s connect/read timeouts and `Accept:
    application/json, image/*`;
  - a network error becomes `"Ingen forbindelse til %s (fejl %d). Tjek internetforbindelsen.|<host>|0"`
    (1.2's `rsIngenForbindelseTilSFejl`).
- `struct Limiter { last: Mutex<u64> }`: one for MusicBrainz and one for Discogs, as process-wide
  statics.
- Calls, each a port of the Pascal function of the same name:
  - `mb_get(f: &dyn Fetch, path_and_query) -> Result<String, String>`;
  - `search_releases(f, artist, album) -> Result<Vec<Release>, String>`;
  - `search_recordings(f, artist, title, album) -> Result<Vec<Release>, String>`, with the
    second query `firstreleasedate:[* TO <earliest>]` and limit 25;
  - `get_release_detail(f, id) -> Result<ReleaseDetail, String>`;
  - `get_front_cover(f, id, group_id) -> Option<Vec<u8>>`: release, then release group, front-500;
  - `discogs_get(f, path, token)`;
  - `discogs_search(f, artist, album, token, track) -> Result<Vec<Release>, String>`;
  - `discogs_release(f, id, token)`;
  - `discogs_cover(f, url, token) -> Option<Vec<u8>>`.
- `auth_header(url, token) -> Option<(&'static str, String)>`: only for discogs.com hosts and a
  non-empty token.

- [ ] **Step 1: Write the tests with a `FakeFetch`.** It records the URLs and headers, answers
  from a queue, and has a fake clock: `sleep` advances `now`.
  - `mb_requests_are_spaced`: three `mb_get` calls at fake time 0 → the request times are at
    least 1100 apart.
  - `mb_retries_503_then_gives_up`: four 503 answers → sleeps include 1500, 3000 and 5000, and
    the error is `rsMusicbrainzHarTravltLigeNu`'s text. A 404 gives
    `MusicBrainz kender ikke denne udgivelse`. A 500 gives `MusicBrainz svarede med fejl %d|500`.
  - `discogs_search_needs_token`: an empty token → 1.2's `rsSoegningPaaDiscogsKraeverEt` text,
    and no request is made.
  - `discogs_errors`: 401 → `rsDiscogsAfvisteDitTokenTjek`; 429 three times →
    `rsDiscogsForMangeForespoergslerVent`.
  - `token_only_sent_to_discogs`:
    - `discogs_search(…, "test-token", …)` sends `Authorization: Discogs token=test-token` to
      `api.discogs.com`;
    - `discogs_cover(f, "https://i.discogs.com/a.jpg", tok)` sends it;
    - `discogs_cover(f, "https://evil.example/a.jpg", tok)` does not;
    - no error string contains `test-token`.
  - `cover_falls_back_to_release_group`: 404 on `release/r/front-500`, then 200 on
    `release-group/g/front-500` → the bytes. Both 404 → `None`.
  - `search_urls_match_1_2`: the exact URLs of `search_releases` (`…&fmt=json&limit=40`),
    `get_release_detail` (`?inc=artist-credits+labels+recordings+release-groups+genres&fmt=json`)
    and `discogs_search` (`database/search?type=release&per_page=50&artist=…&release_title=…`).
  - `#[ignore] live_musicbrainz_search`: the real `Http`, `search_releases("Gasolin'", "Gas 5")`
    → at least one release. Run it only by hand.

  Run `cargo test -p tidytag-core --lib web`. Expected: FAIL.
- [ ] **Step 2: Implement it.** Run it. Expected: PASS, with the live test ignored.
- [ ] **Step 3:** Commit `feat(core): web client with rate limits`.

### Task 4: Lookup jobs and commands (Tauri)

**Files:** Modify `src-tauri/core/src/web/mod.rs`; create `src-tauri/src/web.rs`; modify
`src-tauri/src/main.rs`, `renderer/api.js`

**Interfaces:**
- `web::Source { MusicBrainz, Discogs }`; the ini value is its index.
- `web::search(f, source, artist, album, title, token) -> Result<Vec<Release>, String>`, from
  `TWebJob.Execute`'s search branch:
  - with a title, it is a song search, retried without the album when nothing is found;
    Discogs' song results go through `sort_song_releases`;
  - without a title, it is a release search.
- `web::detail(f, source, id, token)` and `web::cover(f, source, id, group_id, cover_url, token)`.
- Commands, all `async`. Each reads `[Discogs] Token` from the ini itself, so the renderer
  never passes the token around.
  - `web_search(source: usize, artist, album, title) -> Vec<Release>`;
  - `web_release(source, id) -> ReleaseDetail`;
  - `web_cover(source, id, groupId, coverUrl) -> Option<{ data /* base64 */, mime, width, height }>`
    (`detect_image_mime`, `image_dimensions`).

- [ ] **Step 1: Write `song_search_retries_without_album`.** It uses a FakeFetch. The first
  recording search, with `release:"Forkert"`, gives `{"recordings":[]}`; the second, without
  it, gives Task 1's `RecordingJson`. The result's first id is `alb`, and the second URL has no
  `release:`. Run it. Expected: FAIL.
- [ ] **Step 2:** Implement the jobs and the commands, and add the `API` wrappers `webSearch`,
  `webRelease` and `webCover`. Run `cargo test --workspace`. Expected: PASS.
- [ ] **Step 3:** Commit `feat: web lookup commands`.

### Task 5: Pairing files and tracks (renderer)

**Files:** Create `renderer/webmatch.js`, `renderer/webmatch.test.js`

**Interfaces:**
- `WEBMATCH`, which is pure:
  - `normTitle(s, strip)`, from `NormTitle`;
  - `matchFilesToTracks(files, detail, hitDisc = 0, hitPos = 0) -> { rows: [{ trackIdx, fileIdx }], method: 'title'|'hit'|'number'|'order' }`;
  - `moveFile(rows, row, delta)`;
  - `applyTrack(detail, trackIdx, opt) -> { field: value }`, from `ApplyTrack`:
    - only the chosen fields;
    - a year, genre or label that is empty on the release is left out;
    - `opt` is `{ fields: Set, yearOnly, trackWithTotal }`;
    - the track with its total uses `TOOLS.formatTrack(pos, total, 'twoDigitsTotal')`;
  - `options(webSection) -> opt`, from the `[Web]` keys;
  - `commonValue(items, key)`;
  - `pairs(rows) -> [{ trackIdx, fileIdx }]` (only rows with both);
  - `batchGroups(items) -> { groups, albumMode, files, folders, tagged, albums }`, from
    `RunWebBatch`'s grouping (folder + album, lower case).
- `files` are TrackDtos (`fields.title`, `fields.track`, `fields.disc`).

- [ ] **Step 1: Port `webtest.lpr`'s matching and ApplyTrack checks as tests:**
  - by number (rows 1, 2, 0); fallback to order; `moveFile` down; an extra file without a track;
  - by title (case, punctuation and brackets ignored); a title beats a wrong number;
  - `mmHit` disc 2 track 1; without a hit, by number;
  - `normTitle("Rock'n'Roll [Live] (1975)", true)` = `rocknroll`;
  - applyTrack: `Sang B`, `Various Artists`, `1999`, `02/02`, `1/2`; the comment is not in the
    result; only the chosen fields (`Sang C / Uændret`).

  Add the Review Focus tests:
  - `extra files get no track and are not written`: 3 files, a release of 2 tracks →
    `pairs(rows).length === 2`, and the third file's row has `trackIdx -1`.
  - `single file pairs with the search hit`: one file with a wrong track number, hit disc 2
    position 1 → method `hit`.
  - `batch groups by folder and album`: 4 files in 2 folders with 2 album names →
    2 groups, `albumMode` true; one file without an album → `albumMode` false.

  Run `npm test`. Expected: FAIL.
- [ ] **Step 2: Implement it.** Run `npm test`. Expected: PASS.
- [ ] **Step 3:** Commit `feat(ui): pairing files with release tracks`.

### Task 6: The lookup dialog (renderer)

**Files:** Create `renderer/weblookup.js`; modify `renderer/index.html`, `renderer/styles.css`,
`renderer/renderer.js` (host hooks), `renderer/smoke.test.js`, `tools/mkmenu.py` +
`renderer/menudata.js` (regenerated)

**Interfaces:**
- `WEBLOOKUP.open(items, { batch: { pos, count } | null, host }) -> Promise<'written'|'skipped'|'stopped'>`.
  - `host` is `{ get, save, settingsGet, settingsSet, write(items) -> Promise<writeDoneMsg>, keepDate, setKeepDate, pathKind, writeFile }`.
  - `host.write` is phase 2's `startWrite(t(RS.rsWebOpslag…), id => API.writeTagsBatch(items, id), { quiet: true })`.
- `WEBMATCH.folderCoverDirs(rows, files) -> [dir]`: the unique folders of the paired-or-listed
  files, in row order. Add it to Task 5's module and test.

The dialog follows `weblookupform.lfm` (1060×720, in the new look):
- **Search row:** the source combo (MusicBrainz/Discogs), *Discogs-token...* (Discogs only),
  *Kunstner:*, *Sang:*, *Album:* and *Søg*. Enter in a field searches.
- **Releases:** columns Kunstner, Album (+ ` (disambiguation)`), Dato, Land, Spor, Format,
  Pladeselskab, Katalognr. and Type.
- **Tracks:** Nr. (`d-dd` on multi-disc), Titel (fra kilden), Kunstner, Længde, Fil and Længde,
  with *Op* and *Ned*.
- **Right side:** the cover (180×180) with `Cover: %dx%d, %d KB`, and the *Skriv* group with
  1.2's 13 check boxes.
- **Bottom:** the status line, *Skriv tags* and *Luk*. In a batch, *Luk* is *Stop* and *Spring
  over* is added.
- **Prefill:** from `ExecuteBatch`. The artist is the common album artist, else the common
  artist; the album is the common album; the song title is set only for one file. The title
  bar is `rsWebOpslagDFiler` or `rsWebOpslagBatch`. A batch searches at once when the artist and
  the title or album are set.
- **Search** (`ButtonSearchClick`):
  - the status texts, then the list;
  - a song search selects row 0; otherwise the first release with as many tracks as files, else
    row 0;
  - selecting a release loads it (`LoadRelease`): status `rsHenterSporliste`, then the pairing
    with its method's status text, then the cover. *Skriv tags* is enabled only after that.
- **Busy:** while a call runs, Søg, the lists, Op/Ned and Skriv are disabled, and the dialog
  cannot close (`FormCloseQuery`).
- **Switching the source** clears everything and shows `rsDiscogsKraeverEtPersonligtToken` when
  there is no token (`ComboSourceChange`).
- **Skriv tags** (`ButtonWriteClick`):
  - nothing chosen → `rsVaelgHvadDerSkalSkrives`;
  - outside a batch, ask `rsSkrivOplysningerFraSI` with the paired count;
  - save the options;
  - one batch item per pair, `{ path, values: applyTrack(…), cover: CoverTags ? base64 : null }`;
  - then folder covers: `folder.png` or `folder.jpg` by MIME, once per folder; an existing one
    adds `<path> findes allerede - ikke overskrevet`;
  - the status `rsGemtIDFilerD` (+ `rsCoverGemtIDMapper`), and at most 20 error lines under
    `rsBemaerk`;
  - in a batch, close as `'written'` when anything was saved.
- **Options** are loaded and saved with 1.2's `[Web]` keys, when the dialog closes and before
  writing.

- [ ] **Step 1:** Add `folder cover once per folder, never over an existing one` to
  `webmatch.test.js`, for `folderCoverDirs` (two files in `C:\a`, one in `C:\b` → `['C:\a',
  'C:\b']`, case-insensitive). Add `weblookup.js` to the smoke list. Run them. Expected: FAIL.
- [ ] **Step 2: Implement the dialog.** Run `npm test` and `python tools\mkmenu.py` (the generated
  file changes only by the new units). Expected: PASS.
- [ ] **Step 3:** Commit `feat(ui): web lookup dialog`.

### Task 7: The action, the batch and the token

**Files:** Modify `renderer/renderer.js`, `renderer/forms.js` (`askLookupMode`)

- **`aWeb` (Ctrl+W)**, from `ActWebExecute`:
  - it needs `canStartBatch` and a non-empty list;
  - with more than one target it runs the batch;
  - with no target, the whole list if it is one folder, else `rsAfkrydsEllerMarkerFilerneFra`;
  - afterwards the file cover, the list and the selection are refreshed. The written tracks
    come back through `write-done` and phase 5's `replaceTrack`.
- **The batch**, from `RunWebBatch`:
  - `WEBMATCH.batchGroups`, then `FORMS.askLookupMode(summary, albumMode)`, from
    `AskLookupMode`: the summary `rsWebBatchOversigt`, the two radios and the help text;
  - per file when not in album mode;
  - one dialog per group; `'stopped'` ends it;
  - the message `rsWebBatchResultat` when there was more than one group.
- **`aToken`**, from `ActDiscogsTokenExecute`:
  - a one-field form (phase 5's `askText`) with 1.2's text `rsLavEtPersonligtTokenPaa`. The
    field is a password field with the current value, as 1.2's `InputQuery(..., True, ...)`;
  - it saves `[Discogs] Token` trimmed;
  - the message is `rsDiscogsTokenFjernet` or `rsDiscogsTokenGemt`.
- `ENABLED.aWeb`: the list is not empty.

- [ ] **Step 1: Write `batch summary counts files, folders, tagged files and albums`** for a pure
  `WEBMATCH.batchSummary(items) -> [files, folders, tagged, albums]`, which feeds
  `rsWebBatchOversigt`. Five files: three in `C:\a` with albums `X`, `x` and `Y`, and two in
  `C:\B` (one with album `Y`, one without) → `[5, 2, 4, 2]`. Album names compare
  case-insensitively, as 1.2's sorted `TStringList`. Also cover a group of 1 file making
  `albumMode` false. Run it. Expected: FAIL. Then implement and run. Expected: PASS.
- [ ] **Step 2:** Wire the actions. Run `npm test`. Expected: PASS.
- [ ] **Step 3:** Commit `feat(ui): web lookup action, batch and Discogs token`.

### Task 8: Manual check (with the owner's OK) and docs

- [ ] **Step 1:** Ask the owner for a hands-off session, and OK for live MusicBrainz searches.
  On copies in `%TEMP%\tidytag-web6`, check:
  1. A folder of one album, untagged or partly tagged: search MusicBrainz, choose a release,
     move a file with Op/Ned, then write titles, track numbers and the cover. Check with 1.2's
     tagdump.
  2. One song with a wrong album tag: the song search finds the original album and pairs the
     hit.
  3. A batch of two albums in two folders: *Spring over* on the first, write the second; the
     status shows `rsWebBatchResultat`.
  4. *Cover som folder.jpg i mappen* with an existing folder.jpg: not overwritten, and reported.
  5. Discogs without a token: 1.2's message. With the owner's own token, only if the owner sets
     it in the dialog themself: one search.
  6. Search with no network (the owner's choice: skip, or unplug): the dialog shows `Fejl: …`
     and stays usable.
- [ ] **Step 2:** Update the README's TidyTag 2 section with phase 6. Run `npm test`,
  `cargo test --workspace`, and `golden`, `golden_write` and `golden_rename` with the corpus.
  Expected: all green, 0 mismatches.
- [ ] **Step 3:** Commit `docs: TidyTag 2 phase 6 notes`.
