# TidyTag

A tag editor and music organizer for Windows, written in Lazarus / Free Pascal. It is inspired by
the feature set of Tag&Rename 3.9.15, which is no longer maintained. TidyTag is an independent
clean-room implementation that contains no code or artwork from Tag&Rename, and it is not affiliated
with Softpointer.

The user interface is available in English, Danish, German, French, Italian, Swedish and Spanish.
The source code comments are in English; the source language of the UI texts is Danish (see
[Translations](#translations)).

## Features

### File list and browsing
- Folder tree and a fast virtual file list with 23 columns; click a column header to sort, with
  secondary sort, random order and "fit column widths".
- Tags are read in a background thread (optionally including subfolders), so the window never freezes.
- Address bar with history, favourites, new folder, tag-type filter, and a search filter on one field
  or all fields ("whole words", "match case"). The status bar shows count and playing time for all,
  selected and checked files.
- Check boxes (☑ column): most tools work on the checked files, otherwise on the selected ones.
- Copy/paste tags (Ctrl+Shift+C/V, choose which fields to paste), playlists (.m3u8/.m3u), play file,
  show in Explorer, move files up/down for a manual order, delete to the Recycle Bin, copy/move to a folder.

### Editing tags
- **Tag editor** for one file: all common fields plus lyrics, conductor, lyricist, original
  artist, remixer, label, catalog number, ISRC, copyright, encoded by, URL, grouping, subtitle, mood,
  key, five sort fields, "part of a compilation", "podcast" and ReplayGain; cover pictures
  (add/remove/save), "Save and previous/next", "Keep file date".
- **Multi-file tag editor**: common values are shown, differing values appear as hints; only ticked
  fields are saved. Replace or remove the cover in all files.
- **Tag tools**: swap artist/title/album or any two fields, copy one field to another, clean up spaces,
  artist name tools ("The Beatles" ↔ "Beatles, The", "Carl Nielsen" ↔ "Nielsen, Carl"),
  ID3v1 ↔ ID3v2 sync for MP3, automatic album artist on save, and **remove tags**.
- **Track numbers**: format existing numbers (`7`, `07`, `007`, `7/12`, `07/12`) or number files in
  list order (start number, restart per folder).
- **Cover tools**: embed the folder's folder.jpg/cover.jpg, save embedded covers as folder.jpg,
  delete folder covers, resize covers in files and folders (largest side, JPEG quality, PNG → JPEG),
  optional automatic resizing on save.

### Renaming
- **Rename files** from tags with a mask (`%1 - %2`; `%1\%3\%6 - %2` creates folders), case
  conversion, spaces → `_`, two-digit track numbers, live preview (unchanged / missing field / already
  exists / duplicate), and **undo** (also removes folders that became empty).
- **Tags from file name** with a mask (`%6 - %1 - %2`, `%d` skips a part, `\` uses folder names).
- **Rename folders** from tags (`%1 - %4 - %3`, `%f` = current name), with undo.
- Mask editor with saved masks; around 30 variables, including release date, bit depth, encoder,
  sample rate and a random number.
- **Rename actions**: named presets with a file mask and/or a folder mask, run from the Tools menu.
- **Word replacements**: text to replace and words with a fixed spelling (AC/DC, ABBA) for every rename.

### Online lookup
- **MusicBrainz**: search by artist and album, pick a release (date, country, format, label, catalog
  number). Files are matched by disc/track number or by order, and the chosen fields plus the front
  cover from the Cover Art Archive are written. The 1-request-per-second limit is respected.
- **Discogs** as a second source in the same dialog. Searching needs a personal token
  (discogs.com > Settings > Developers), which is stored only in the local settings file.
- Networking uses Windows' WinInet, so no OpenSSL DLLs are needed.

### ReplayGain 2.0
- Tools > ReplayGain measures loudness according to EBU R128 / ITU-R BS.1770-4 (-18 LUFS reference,
  sample peak) and writes track and album gain. An album is the files in one folder with the same
  album name. Several files are measured at once on worker threads.
- No external programs: WAV/AIFF are read directly, everything else is decoded by Windows Media
  Foundation (MP3, AAC/ALAC, WMA, FLAC). Ogg, Opus, APE, WavPack, Musepack and OptimFROG need a
  codec installed in Windows.
- Opus files get `R128_TRACK_GAIN`/`R128_ALBUM_GAIN` (RFC 7845). "Remove tags" keeps ReplayGain values.

### Export and import
- Export to CSV (Excel: semicolon + BOM), CSV (comma), text, HTML and XML with selectable columns.
- Import from CSV/XLSX with a preview, matched on path or file name.

### Supported formats
| Format | Read | Write | Tags |
|---|---|---|---|
| MP3 | ✓ | ✓ | ID3v2.2/2.3/2.4, ID3v1, APEv2; duration/bitrate incl. VBR (Xing/Info/VBRI) |
| FLAC | ✓ | ✓ | Vorbis comments, pictures |
| Ogg Vorbis, Opus | ✓ | ✓ | Vorbis comments (new pages, sequence numbers and CRCs on write) |
| Ogg FLAC | ✓ | – | Vorbis comments |
| MP4 / M4A / M4B (AAC, ALAC) | ✓ | ✓ | iTunes atoms, incl. freeform `----` items; chunk offsets are fixed when audio moves |
| WAV, AIFF/AIFC | ✓ | ✓ | ID3 chunk, RIFF LIST/INFO, AIFF text chunks |
| Monkey's Audio, WavPack, Musepack (SV7/SV8), OptimFROG | ✓ | ✓ | APEv2 (+ ID3v1) |
| WMA / ASF | ✓ | ✓ | Content Description, WM/* attributes, Metadata Library (large pictures) |

When writing, fields TidyTag does not edit (MusicBrainz IDs, iTunes data, and so on) are kept
unchanged. Tags are rewritten in place when there is room (padding / `free` atoms); otherwise a
temporary file replaces the original.

### Other
- Settings dialog (Ctrl+Alt+O) for language, album artist rule, keeping file dates, cover resizing,
  the file list, word replacements, rename actions and the Discogs token.
- Settings are stored in `%LOCALAPPDATA%\TidyTag\tidytag.ini`. Settings from the program's former
  working name, TagKlon, are copied over automatically on first start.
- Windows adapt to longer translated texts (wider buttons, fields that move).

## Requirements
- Windows 10 or 11, 64-bit. Windows "N" editions need the Media Feature Pack for ReplayGain
  measurement of compressed formats.
- To build: [Lazarus](https://www.lazarus-ide.org/) 4.x with Free Pascal 3.2.2 (64-bit).

## Building
```
C:\lazarus\lazbuild.exe TidyTag.lpi
```
The result is `bin\TidyTag.exe`. The project can also be opened in the Lazarus IDE (`TidyTag.lpi`).
The program finds its `languages\` folder next to the exe or in `..\languages`.

Note: `lazbuild` does not rebuild a form when only its `.lfm` file has changed. Save the matching
`.pas` file as well.

## Development and test tools
The console tools in `tools\` are built with the Free Pascal compiler directly:
```
C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe -Mobjfpc -Sh -Fusrc -FUlib\tools -FEbin tools\tagtest.lpr
```

| Tool | Purpose |
|---|---|
| `tagdump` | Prints the tags of files or folders: `bin\tagdump.exe "D:\Music\Album" -r` |
| `tagtest` | Write test. It works on **copies** in a test folder and checks fields, pictures, tag removal and that the audio data is unchanged: `bin\tagtest.exe C:\Temp\tagtest song.mp3 song.flac` |
| `renametest` | Renaming of files and folders, tags from file names, track numbers (creates empty test files): `bin\renametest.exe C:\Temp\renametest` |
| `tooltest` | Field tools, ID3 sync, Recycle Bin (puts one tiny test file in the Recycle Bin): `bin\tooltest.exe C:\Temp\tt song.mp3` |
| `rgtest` | ReplayGain: EBU Tech 3341 test signals written as WAV/AIFF and measured directly and through Media Foundation, plus measurement of given files: `bin\rgtest.exe C:\Temp\rg song.flac` |
| `exporttest` | Export and import |
| `webtest` | Offline test of MusicBrainz responses and track matching |
| `mbtest`, `dgtest` | Live MusicBrainz search (`bin\mbtest.exe "Gasolin'" "Gas 5"`) and Discogs release (`bin\dgtest.exe 249504`) |
| `tagset` | Set fields from the command line: `bin\tagset.exe song.mp3 artist=X album=Y track=1` |
| `icon_cut.py` | Rebuilds `TidyTag.ico` from the logo artwork (needs Pillow and numpy) |

The program itself has two developer switches:
```
bin\TidyTag.exe --layoutcheck C:\Temp\layout.txt
bin\TidyTag.exe --selftest C:\Temp\copies\album C:\Temp\selftest.txt
```
- `--layoutcheck` creates every window and dialog in the current language and reports texts that do
  not fit, overlap or stick out. To check a language, set `Language=xx` under `[Main]` in the
  settings file first.
- `--selftest` runs the main window's tools (field tools, covers, a rename action with undo,
  ReplayGain, remove tags, copy/move) without dialogs and writes the fields after each step to the
  report. Use a folder with **copies** of music files.

## Translations
The UI texts in the source are Danish. Texts in code are `resourcestring`s; form texts come from the
`.lfm` files. `languages\src\translations.json` is the source of the translations
(`{Danish text: {language: text}}`). After changing texts or translations:
```
C:\lazarus\lazbuild.exe TidyTag.lpi
python tools\mkpot.py
```
`mkpot.py` builds `languages\TidyTag.pot` from the compiler's `.rsj` files and the forms, and writes
`languages\TidyTag.<lang>.po` (format codes such as `%d`/`%s` are checked).
`python tools\addtranslations.py new.json` merges new translations and lists missing ones.

To add a language, add its code in `src\language.pas`, add translations to the JSON file, and copy
`lclstrconsts.<lang>.po` from `C:\lazarus\lcl\languages` (the LCL's dialog buttons).

## Project structure
| File | Contents |
|---|---|
| `src/audiotypes.pas` | `TAudioInfo`, the format-independent result; field list and helpers |
| `src/audiotags.pas` | Picks the reader by file extension |
| `src/mp3reader.pas` | ID3v2/ID3v1 and MPEG audio info |
| `src/vorbisreader.pas` | FLAC and Ogg (Vorbis/Opus/FLAC) |
| `src/mp4reader.pas` | MP4/M4A atoms |
| `src/wavreader.pas`, `src/wavwriter.pas` | WAV/AIFF chunks: audio info, ID3 chunk, LIST/INFO |
| `src/apetag.pas`, `src/apereader.pas` | APEv2 tags; audio info for APE/WavPack/Musepack/OptimFROG |
| `src/asfreader.pas`, `src/asfwriter.pas` | WMA/ASF header objects |
| `src/tagutils.pas` | Byte helpers, text decoding, ID3 genre list |
| `src/scanthread.pas` | Background thread: find files and read tags |
| `src/tagwriter.pas` | Picks the writer by file extension, optionally keeps the timestamp |
| `src/id3writer.pas` | ID3v2 (+ ID3v1) for MP3 |
| `src/flacwriter.pas` | FLAC metadata blocks and Vorbis comments |
| `src/mp4writer.pas` | MP4 atom tree, `ilst`, chunk offsets |
| `src/oggwriter.pas` | Ogg Vorbis/Opus: comment packet, new paging, CRC |
| `src/batchwrite.pas` | Saves selected fields/cover in one file (tabs, paste tag, drag and drop) |
| `src/tagremove.pas` | Remove tags |
| `src/id3sync.pas` | ID3v1 ↔ ID3v2 sync |
| `src/fieldtools.pas` | Swap/copy fields, clean spaces, name tools (planned per file) |
| `src/fileops.pas` | Recycle Bin, copy/move files |
| `src/coverimage.pas` | Cover resizing |
| `src/loudness.pas` | Loudness meter for ReplayGain 2.0 (BS.1770-4 K-weighting, gating) |
| `src/audiodecode.pas`, `src/mfdecode.pas` | Decoding to PCM: WAV/AIFF directly, everything else through Windows Media Foundation |
| `src/replaygain.pas` | Measures many files on threads; track and album values |
| `src/renamecore.pas` | Mask → file/folder name, sanitizing, plan/execute/undo |
| `src/filenametags.pas` | File name → tags (mask matching) |
| `src/trackcore.pas` | Track numbers: format and number |
| `src/trackmatch.pas` | Matching files to release tracks, filling fields |
| `src/musicbrainz.pas` | HTTP (WinInet), MusicBrainz search/release, Cover Art Archive |
| `src/discogs.pas` | Discogs search/release/picture (same data structures as MusicBrainz) |
| `src/exportimport.pas` | Export (CSV/TXT/HTML/XML), CSV/XLSX reading, import plan |
| `src/appsettings.pas` | Settings file, mask history, word replacements, rename actions |
| `src/language.pas` | Language choice and loading of `.po` files (LCLTranslator) |
| `src/layoutfit.pas` | Makes room for longer translated texts when a window is shown |
| `src/layoutcheck.pas` | The `--layoutcheck` developer check |
| `src/mainform.pas/.lfm` | Main window (menu and toolbar are built in code from one action table) |
| `src/tageditform.pas/.lfm` | Tag editor for one file |
| `src/multieditform.pas/.lfm` | Multi-file editor dialog |
| `src/renameform.pas/.lfm` | Rename files / rename folders dialog |
| `src/filetotagform.pas/.lfm` | Tags from file name dialog |
| `src/tracktoolsform.pas/.lfm` | Track numbers dialog |
| `src/weblookupform.pas/.lfm` | Web lookup dialog (MusicBrainz/Discogs) |
| `src/exportimportform.pas/.lfm` | Export/import dialog |
| `src/tooldialogs.pas` | Dialogs built in code: field choice, word replacements, rename actions, mask editor, ReplayGain |
| `languages/` | `TidyTag.pot`, `TidyTag.<lang>.po`, `lclstrconsts.<lang>.po`, `src/translations.json` |
| `tools/` | Test and helper tools (see above) |
| `res/icons/`, `res/icons.rc` | Toolbar icons (Lazarus general_purpose set by Roland Hahn, CC0) |
| `TidyTag.ico`, `res/logo/tidytag.png` | Program icon |
| `docs/` | Feature overview and gap list compared with Tag&Rename (in Danish) |

## Roadmap
1. Rating (POPM) and more picture types in the editor
2. ReplayGain for Ogg Vorbis and Opus without a Windows codec
3. Ogg FLAC writing and DSF (ID3 in DSD files)
4. A setting for contact info in the MusicBrainz User-Agent (recommended by MusicBrainz)
