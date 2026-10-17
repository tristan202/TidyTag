# Tag&Rename 3.9.15 – feature overview for TidyTag

This is the planning document written before TidyTag was built. It lists what the original program
can do, so that TidyTag could cover the same ground.

Source: the forms (DFM) and strings of `TagRename.exe` (Delphi, 32-bit, June 2018). The forms were
used only as a reference for *which* features and settings exist, never as code or design to copy,
and they are not part of this repository.

**Status column**
- ✅ Local feature – should still work in the original, just needs to be recreated
- ⚠️ Outdated or depends on something external – should be modernized
- ❌ Dead – external service shut down, must be replaced

**Priority**: P1 = core (MVP), P2 = important, P3 = can wait / may be dropped

The current state of TidyTag is described in the [README](../README.md); the remaining gaps are
listed in [missing-features.md](missing-features.md).

---

## 1. Main window and file list

| Feature | Status | Prio | Notes |
|---|---|---|---|
| Folder tree (Explorer-like) with favourites and history | ✅ | P1 | Original: `TVirtualExplorerTree`. Lazarus: `TShellTreeView` or a custom tree |
| Address bar | ✅ | P2 | |
| File list with columns (tag fields + file properties) | ✅ | P1 | Virtual list – must handle thousands of files. Column choice, order, width |
| Search subfolders / flat list / tree list | ✅ | P1 | "Search Subfolders", "Flat File List", expand/collapse all |
| View mode per tag type: All, ID3v2, WMA, Ogg/FLAC, MP4/M4A, APEv2 | ✅ | P2 | Filters which fields/columns are shown |
| Checking files (check box) vs. selecting | ✅ | P1 | Many features only work on *checked* files |
| Select all / none / invert / select highlighted | ✅ | P1 | |
| Sorting, secondary sort column, random order | ✅ | P2 | |
| Move file up/down (manual order) | ✅ | P2 | Used to control track numbering |
| Filter: by field/text, hide selected, show all | ✅ | P2 | |
| Colours: low bitrate, missing-ID3v1 indicator, hide file extension | ✅ | P3 | |
| Copy/move to folder, delete, properties, create folder/subfolder | ✅ | P2 | |
| Find (in chosen tag fields, whole word, match case, find all, count) | ✅ | P2 | |
| Copy tag / paste tag / paste into all selected (with "do not paste title/track/BPM/artist/lyrics") | ✅ | P1 | |
| Play file / selected files in the default player | ✅ | P3 | |
| Winamp control (play/pause/next, add to playlist) | ⚠️ | P3 | Winamp is outdated – drop or replace with "open in player" |
| Customize toolbars and shortcuts | ✅ | P3 | |
| Panel with the folder's cover (folder.jpg) and the file's cover | ✅ | P2 | Use tag picture as folder cover, delete folder cover |

## 2. The three main features (tabs in the main window)

### 2a. Rename files from tags (F4) – P1 ✅
- Mask with variables, e.g. `%1 - %3 (%2)`. `\` in the mask creates folders (`%1\%3\%6 - %2`).
- Preview, Rename, **Undo**.
- Case conversion (radio group), "replace spaces with underscores".
- Word replacements and "always keep the case of these words" (Options → File Rename Strings).
- "Do not rename if a file with the same name exists".
- Saved masks + **mask editor**.

**Mask variables** (from the mask editor):

| Var | Field | Var | Field | Var | Field |
|---|---|---|---|---|---|
| `%1` | Artist | `%b` | BPM | `%rb` | Remixed by |
| `%2` | Title | `%t` | Play time | `%key` | Initial key |
| `%3` | Album | `%#` | Disc # | `%swt` | Show title |
| `%4` | Year | `%aa` | Album artist | `%eid` | Episode ID |
| `%5` | Genre | `%co` | Conductor | `%snr` | Season number |
| `%6` | Track # | `%cp` | Composer | `%enr` | Episode number |
| `%7` | File name | `%lb` | Label | `%rnd` | Random number |
| `%8` | File number | `%md` | Mood | `%ext` | File extension |
| `%9` | Comment | `%rt` | Release time | `%khz` | Sample rate |
| `%0` | Bitrate | | | `%dbit` / `%enc` | Bit depth / Encoder |

### 2b. Multi-file tag editor (Ctrl+F4) – P1 ✅
- Set Artist/Album/Year/Comment/Genre on all checked files; only ticked fields are changed.
- Case conversion, Save tags, Remove tags, "Copy from focused file", "Edit all fields".

### 2c. Tags from file name (Shift+F4) – P1 ✅
- Mask such as `%6 %1 - %2`; `%d` skips a part; the file extension is removed automatically.
- Folder names (path parts) can be used in the mask.
- Preview/test, "replace underscores with spaces", case conversion.

## 3. Tag editor for a single file – P1 ✅

Tabs and fields:
- **General**: Title, Artist, Album, Year, Track #, Genre, Comment, Composer, Orig. Artist, Copyright, URL, Encoded by, BPM, Disc #, Rating, Mood, "Part of a compilation", file information, **cover art** (add/remove/save to file, several pictures).
- **Lyrics**: load/save from a text file, clear, remove leading spaces.
- **Additional**: Album Artist, Conductor, Lyricist, Original lyricist, Label, ISRC, Catalog #, Remixed by, Initial Key, web addresses (file info, artist, audio source, buy CD, radio station), radio station name.
- **More Additional** (MP4/iTunes): Grouping, Music/Video kind, Subtitle, Podcast (category, description, ID, URL), Release time, Show title, Episode ID, Season #, Episode #.
- **Sorting**: Sort Title/Artist/Album Artist/Album/Composer/Show.
- Buttons: Save, Save and previous/next, Remove tag, Copy from ID3v1, case conversion.

## 4. Tools (Tools menu)

| Feature | Status | Prio |
|---|---|---|
| Track number format: `x`, `0x`, `00x`, `xx/xx`, `xx` | ✅ | P1 |
| Auto-fill track # / episode # (in list order) | ✅ | P1 |
| Swap fields: Artist↔Album, Artist↔Title, Album↔Title, advanced | ✅ | P2 |
| Copy text from one field to another | ✅ | P2 |
| Remove trailing / leading and trailing spaces in all fields | ✅ | P2 |
| Artist tools: remove "The", "The Artist"↔"Artist, The", "First Last"↔"Last, First" | ✅ | P3 |
| Cover: add folder.jpg/png to tags, extract cover to folder.jpg, delete folder covers | ✅ | P2 |
| Resize covers in files/folders (max. size, JPEG quality, convert to JPEG) | ✅ | P2 |
| Change extension .mp4→.m4a, .mp4/.m4a/.m4p→.m4b | ✅ | P3 |
| MP3 tag sync: ID3v1↔ID3v2 (do not write / empty fields only / all fields) | ✅ | P2 |
| Rename folder from tags (folder mask, applied to all highlighted folders) | ✅ | P1 |
| Edit file/folder name manually (previous/next) | ✅ | P2 |
| **Rename Actions**: named combinations of file and folder mask | ✅ | P2 |
| Genre list editor (standard genres + your own) | ✅ | P2 |

## 5. Playlists – P2 ✅
- Save selected/all files as a playlist; "quick save" with a name mask (`%1 %2 %3 %4 %f %aa`, `\` for folders).
- Optional EXTINF lines (with a mask), full vs. relative paths, fixed playlist folder.
- Formats: m3u (and probably pls/wpl, judging from the program's MIME table).

## 6. Export/import – P2 ✅
- Export to CSV, HTML, XML and text (according to the Readme) with a choice of fields.
- Import **only from XLS/XLSX**: apply to all files listed in the spreadsheet, or only to selected files.
- The original uses TMS FlexCel for Excel. TidyTag reads XLSX itself and also imports CSV.

## 7. Web import – this is what is broken

Addresses found in the program file:

| Service in the original | Address(es) | Status today | Replacement in TidyTag |
|---|---|---|---|
| freedb (CDDB protocol over HTTP) | `freedb.freedb.org`, `freedb.musicbrainz.org`, `.../~cddb/cddb.cgi?cmd=cddb+read+...` | ❌ Shut down (2019–2020) | **MusicBrainz** web API (JSON). Possibly **gnudb.org** (still uses the CDDB protocol) |
| gnudb | `gnudb.gnudb.org` | ⚠️ Still running as far as known – needs testing | Could be kept as a secondary source |
| TrackType.org | `tracktype.org/~cddb/cddb.cgi?cmd=cddb+album+...` | ❌ Shut down | MusicBrainz |
| Amazon (com/co.uk/de/ca) | `ecs.amazonaws.*` (the old Product Advertising API, before v5) + the user's own AWS keys | ❌ Shut down – the API was replaced and needs a seller account | **Cover Art Archive** (MusicBrainz) for covers; possibly the iTunes Search API |
| Discogs | `api.discogs.com/database/search`, OAuth 1.0a (`request_token`, `authorize`, `access_token`) | ⚠️ The API still exists; failures are probably due to old OpenSSL/TLS or API changes | Discogs with a **personal token** (simpler than OAuth) |
| Update check, RSS, "Buy", home page | `softpointer.com/...` | ❌ Discontinued | Drop, or check GitHub releases |

Dialogs and features to recreate (P2):
- **Search**: artist/album/year, choose source, next result page, "master releases" only (Discogs).
- **Album information**: choose which fields to write (artist, album, year, genre, label, comment, titles, track numbers, compilation), match files ↔ tracks with drag and drop, save the cover in the tag and/or as jpg, save the review as a text file, save the catalog number, apply a Rename Action (normal CD / compilation CD), "Title - Orig. Artist" format.
- Settings: cover file name (`%1 %2 %3 %f`), cover search URL (`%1..%4`), tracks in `xx/xx` format, copy Artist to Album Artist, proxy.
- New option in TidyTag: lookup by **disc ID/TOC** or **AcoustID** (audio fingerprint) through MusicBrainz – the original could not do that.

## 8. Options

- **General**: Explorer integration, do not close the tag editor on errors, **keep the file timestamp when saving**, do not rename if the name exists, interface font, case settings, start folder (last/fixed).
- **File List**: after opening a folder (expand all; select root files/all/none), colours, grid lines, low bitrate, ID3v1 indicator, hide file extension, auto-select files when a folder is selected, use check boxes.
- **File List Columns**: visible columns.
- **Players**: music player, Winamp path.
- **Web Import**: freedb server + e-mail, cover/review file names, cover search URL, proxy.
- **Playlists**: see section 5.
- **File Rename Strings**: word replacements, words that always keep their case.
- **Tags**: max. padding (KB) and rewrite the file if larger, Artist→Album Artist rules, "Various Artists" for compilations, ID3v2 always Unicode / ASCII, automatic resizing and JPEG conversion of covers.
- **Advanced**: own Amazon AWS keys (drop), plus advanced choices (e.g. "save the ID3 chunk at the end of WAV files", according to WhatsNew).

## 9. File formats and tag types (requirements for the tag library)

From the Readme/WhatsNew: MP3 (ID3v1, ID3v2.2/2.3/2.4), MPC/MP+ (APEv1/v2, ID3v1), WMA/ASF/WMV, Ogg Vorbis, FLAC (Vorbis comments), MP4/M4A/M4B/M4P (iTunes atoms, incl. the Xtra atom), Monkey's Audio (APE), WavPack, OptimFROG, Apple Lossless, WMA Lossless, WAV (ID3 chunk), AIFF.

**Suggested MVP**: MP3 (ID3v2.3/2.4 + v1), FLAC, Ogg Vorbis, MP4/M4A. Then APE tags (APE/WavPack/MPC), WMA/ASF, WAV/AIFF.

## 10. Not included in TidyTag
- Registration, unlocking and the nag screen.
- Update check against softpointer.com, "Buy", RSS.
- Amazon AWS keys.
- Winamp control (maybe later).

---

## Suggested MVP (first version)
1. Folder tree + virtual file list with columns, subfolders, check boxes.
2. Read/write tags for MP3, FLAC, Ogg, M4A (title, artist, album, year, track, disc, genre, comment, album artist, cover).
3. Single-file tag editor (General tab + cover).
4. Multi-file tag editor.
5. Rename files and folders from a mask, with preview and undo.
6. Tags from file name.
7. Track number tools.

After that: MusicBrainz + Cover Art Archive, Discogs, export/import, playlists, the rest of the tools.
