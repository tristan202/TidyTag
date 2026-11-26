# TidyTag 2.0: rewrite in Tauri — design

Status: draft for approval · 2026-11-26

## Intent

TidyTag 1.2 (Lazarus/Free Pascal, Windows) is moved to the same technology and look as the owner's
other apps: Skal, PadReady, AI Copilot Mapper and Torrentry. These are Tauri 2 apps with a plain
JavaScript renderer and a dark theme. The reason is **the look**. Version 2.0 is the same program in
new clothes:

- every feature from 1.2 is kept;
- the window is laid out like 1.2;
- the user should feel at home at once.

## Goals

1. **Full parity with 1.2.0.** Everything in the README's *Features* section, and every
   menu item, dialog, setting and keyboard shortcut in 1.2, works in 2.0. That README section is
   the checklist.
2. **The look of the other apps:**
   - Skal/Torrentry colour tokens (`--bg #171a26`, `--sidebar #10121b`, `--panel #1d2131`,
     `--raised #242940`, `--border #2a2f45`, `--text #e4e7f0`, `--muted #8a90a8`,
     `--accent #5b8def`, `--danger #e5534b`, `--ok #3fb950`, `--warn #d29922`);
   - Segoe UI Variable and Cascadia Mono;
   - rounded corners (6/10 px) and the same buttons, fields, check boxes and scrollbars;
   - simple **line icons** drawn as inline SVG, the same way as Torrentry: 24×24 viewBox,
     `stroke: currentColor`, `stroke-width: 1.8`, round caps and joins.
3. **1.2's layout, unchanged.** The approved mockup is
   [2026-11-26-tidytag-tauri-mockup.html](2026-11-26-tidytag-tauri-mockup.html). From top to bottom:
   - the menu bar (Filer, Rediger, Vis, Playliste, Værktøjer, Indstillinger, Hjælp), with the
     language picker on the right;
   - the tool panel with the tabs *Omdøb filer (F4)*, *Multi-fil-tag-editor (Ctrl+F4)* and
     *Tags fra filnavn (Shift+F4)*, with the same fields as in 1.2, and the folder and file cover
     on the right;
   - the icon bar, in 1.2's order;
   - the *Adresse* row with *Tagtype*;
   - the *Filtrer efter* row;
   - *Mapper* (the tree, including drives and paired phones) on the left and the file list on
     the right;
   - the player;
   - the status bar.

   Dialogs (the tag editor, settings, online lookup, ReplayGain, BPM/key, export/import, rename
   preview, the mask editor and so on) keep 1.2's content and arrangement, in the new look.
4. **Safe for music files.** Audio data is never changed (checked with a hash). Tags written by 2.0
   read the same in 2.0, in 1.2's `tagdump` and in ordinary players. Fields TidyTag does not edit
   stay as they are. All testing is done on copies.
5. **Seamless switch from 1.2:** 2.0 uses the same settings file,
   `%LOCALAPPDATA%\TidyTag\tidytag.ini`, with the same sections and keys. Settings, masks, rename
   actions, word replacements, the Discogs token and paired phones therefore carry over without
   being typed again. (1.2 keeps undo in memory only, so there is nothing else to carry over.)
6. **Same seven languages:** da, en, de, es, fr, it, sv. Danish is the source text, as in 1.2.

## Non-goals

- macOS and Linux. Windows only, as today. Platform-specific code goes behind small Rust modules,
  so a port later is possible, but nothing is built for it now.
- New features. Ideas that come up along the way go on a list for after 2.0.
- Changes to TidyTag Companion (the Android app) or its protocol (`docs/phone-protocol.md`). 2.0
  talks to the same app, in the same way.
- `--layoutcheck`. The HTML layout adapts to text length by itself. Long translations are checked
  by eye in each language instead.

## Anti-goals (this would be a failure even if it works)

- A version that writes differently to the user's music than 1.2 does, without anyone having
  decided so. Examples: converting ID3v2.3 to v2.4, rewriting frames TidyTag does not edit, or
  dropping unknown MP4 atoms.
- A window that feels like a different program.
- A file list that is slow with thousands of files. 1.2 uses a virtual list, and 2.0 must too.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| **A (chosen)** | Rewrite everything in Tauri 2 + Rust | One language and the same structure as the other apps. The most work; the engine is re-tested from scratch. |
| B | New Tauri UI with 1.2's Pascal engine as a helper program (JSON over stdin/stdout) | About half the work, and the file-handling code is unchanged. Two languages and two toolchains. |
| C | Pascal engine as a DLL called from Rust | Rejected: the same two languages as B, and harder to make stable (memory and threads across languages). |

The owner chose A.

## Decided in the conversation

- **Approach A:** everything in Rust and JS.
- **Platform:** Windows only, as today.
- **Scope:** full parity before 2.0 replaces 1.x.
- **Layout:** 1.2's, with the colours and line icons of the other apps (mockup v3).
- **Repo and version:** the same repo (`tristan202/TidyTag`), the same name, version **2.0.0**.
  The Pascal code stays until 2.0 has parity. Release 1.2.0 stays on GitHub.
- **Android:** TidyTag Companion and the protocol are unchanged.
- **Data safety:** audio is never changed, and tags read the same (goal 4). It does not have to be
  byte-for-byte identical to 1.2.

## Technical design (my calls, open to correction)

### Structure (as in Torrentry)

```
TidyTag/
  package.json            "start": "tauri dev", "dist": "tauri build"; devDependency @tauri-apps/cli 2
  renderer/               index.html, renderer.js (+ modules per area), strings.js, styles.css, icons.js
  src-tauri/              Cargo.toml, tauri.conf.json, src/ (Rust)
  src/ ... (Pascal)       stays until parity, then removed
  tools/                  Pascal test tools stay as a cross-check until parity
```

- **Renderer:** plain JS without a framework or bundler, like the other apps.
  - The DOM is split by area: menu, tool panel, list, tree, dialogs.
  - Dialogs are modal overlays in the window, like `#modal` in Torrentry. All of 1.2's dialogs are
    modal, so 2.0 has a single OS window.
  - Drag and drop works as in 1.2: files and pictures can be dragged onto the cover panels and
    the list. Torrentry turns this off (`dragDropEnabled: false`); 2.0 turns it on.
  - The file list is a **virtual list**: only visible rows are drawn. It has 23 columns with
    sorting, secondary sort, check boxes and column widths/order, as in 1.2.
- **Rust:** all file and network work happens in Rust. The renderer only talks to Rust through
  Tauri commands and events; it has no direct file access. Long tasks (scanning, ReplayGain, BPM,
  batch writes, phone) run on worker threads and send progress as events, so the window never
  freezes.
- **Plugins:** `tauri-plugin-single-instance` and `tauri-plugin-window-state`, as in Torrentry.
  Single instance is needed for "Open in TidyTag": files go to the running window.

### Tag engine: a port of 1.2's own readers and writers

1.2's readers and writers are ported to Rust module by module, with the same rules. A generic
library like `lofty` is **not** used. The reasons:

- 1.2 keeps a tag's existing ID3v2 version (v2.3 stays v2.3; files without a tag get v2.3);
- 1.2 keeps frames and atoms it does not edit byte-for-byte;
- 1.2 chooses the text encoding by the setting;
- 1.2 writes WMA/ASF, which `lofty` cannot.

Using `lofty` would break the anti-goals above. The Pascal units are the specification:

| Pascal | Rust module |
|---|---|
| mp3reader, id3writer, id3sync, apereader, apetag | `tags::mp3`, `tags::id3`, `tags::ape` |
| flacwriter, vorbisreader, oggwriter | `tags::flac`, `tags::vorbis`, `tags::ogg` |
| mp4reader, mp4writer | `tags::mp4` (incl. chunk offsets) |
| wavreader, wavwriter | `tags::riff` (WAV, AIFF/AIFC) |
| asfreader, asfwriter | `tags::asf` |
| tagwriter, tagremove, tagutils, audiotags, audiotypes | `tags` (shared model, in-place write with padding/free, otherwise temp file + replace) |
| filelayer | `fs::layer` (local disk and phone path behind the same interface) |

### Other areas

| Area | Pascal | Rust / JS |
|---|---|---|
| Scan, list | scanthread, trackcore | `scan` (background thread, subfolders), list in the renderer |
| Rename, tags from file name, rename folders, undo | renamecore, filenametags, renameform, filetotagform | `rename` + tool panel tabs |
| Multi-edit, tag editor | multieditform, tageditform | dialogs; `tags` |
| Field tools, track numbers, covers | fieldtools, trackmatch, coverimage, tracktoolsform | `tools`, `cover` (the `image` crate for resizing/JPEG) |
| MusicBrainz, Discogs, batch lookup | musicbrainz, discogs, weblookupform | `web` (`reqwest`, 1 request/second to MusicBrainz) |
| ReplayGain 2.0, BPM/key | replaygain, loudness, musicanalysis | `analysis` |
| Decoding | audiodecode, mfdecode | `decode`: **Windows Media Foundation** through the `windows` crate, plus WAV/AIFF read directly, exactly as in 1.2. That way the same formats can be decoded (incl. WMA, and codecs installed in Windows). |
| Playback | audioplayer | `player`, built on Media Foundation |
| Export/import (CSV, text, HTML, XML; CSV/XLSX import) | exportimport, exportimportform | `export` (`calamine` for XLSX reading) |
| Playlists | (mainform) | `playlist` |
| Phone via the app | phoneclient, phonetree, phonesync | `phone` (HTTP to port 47100, UDP discovery 47101, same pairing token) |
| Phone over USB (copy method) | phonesync, shell code | `phone::usb` (Windows Shell/MTP through the `windows` crate, sent back automatically, as in 1.2) |
| Recycle Bin, Explorer menu, properties | fileops, shellintegration | `shell` (SHFileOperation/IFileOperation, registry under HKCU) |
| Settings | appsettings, settingsfile, progoptions | `settings`: reads and writes the same ini file, **round-trip safe** (see below) |
| Languages | language, translations.json | `strings.js` generated from `languages/src/translations.json` by a script. The keys are the Danish source text, as in 1.2. |

### Shared settings file while 1.2 and 2.0 both exist

- During development 1.2 and 2.0 run one after the other against the same ini.
- 2.0 rewrites the file round-trip safe. It keeps sections, key order, keys it does not know, and
  the file encoding, and changes only the values that changed.
- 2.0 adds no keys of its own unless a 2.0-only setting is unavoidable. Such a key goes in its own
  section, `[TidyTag2]`, so 1.2 ignores it.

### Installer and release

- Tauri's NSIS bundle, per user, as in Torrentry. It has the same options as 1.2's Inno installer,
  among them "Open in TidyTag" in Explorer.
- **2.0 replaces 1.2:**
  - the 2.0 setup finds an installed 1.2 (Inno AppId `{6F1E9C2A…}`) and uninstalls it silently
    first;
  - it installs to the same per-user place, `%LOCALAPPDATA%\Programs\TidyTag`;
  - it rewrites the Explorer menu keys to point at 2.0.
- Neither uninstaller ever deletes `%LOCALAPPDATA%\TidyTag` (settings). The NSIS "delete app data"
  option is turned off.
- **Interim builds:** until phase 10, 2.0 runs only as a development build (`npm start`) and is
  not published. Phase 1 is read-only. Writing is used only on copies until phase 2's cross-check
  is green. The owner decides when 2.0 may touch the real music library.
- Release files: `TidyTag-2.0.0-setup.exe` and a portable zip, plus the unchanged Companion APK.
- `tools/make-release.ps1` is updated for this.

### Tests

- **Rust unit tests** for every module, ported from 1.2's test tools: `tagtest`, `renametest`,
  `tooltest`, `bpmtest`, `rgtest`, `exporttest`, `webtest`, `phoneclienttest`, `filelayertest`,
  `phonetest`. They use the same checks and the same test folders under the user's Temp, always on
  **copies**.
- **Cross-check against 1.2** while both exist. For a set of copied test files:
  1. 2.0 writes the fields;
  2. 1.2's `tagdump` reads them back and must show the same thing;
  3. the reverse: what 1.2's `tagset` writes, 2.0 reads the same;
  4. the audio data's hash is unchanged.
- The phone tests run against `companion-desktop.jar`, as today. Testing on the real phone only
  happens with the owner's OK.
- `--selftest` is carried over to 2.0 in the same form.

### Order of work (each phase is its own plan and ends in something that runs)

1. **Skeleton:**
   - the Tauri app with the approved layout and theme, menus, tree, the virtual file list
     (read-only, all formats), the status bar and the language picker;
   - the same ini file.
2. **The tag engine (writing)** for all formats, with the cross-check against 1.2, and saving from
   the multi-edit tab.
3. **The tag editor dialog**, covers, copy/paste of tags, field tools, track numbers and cover
   tools.
4. **Renaming:** files, tags from file name, folders, by hand, actions, word replacements, undo.
5. **File operations**: Recycle Bin, copy/move, extensions, filter/find, playlists, the player,
   Explorer integration, single instance.
6. **Online lookup:** MusicBrainz, Discogs, batch.
7. **ReplayGain and BPM/key**, through Media Foundation.
8. **Export/import.**
9. **Phone:** the Companion app and the USB copy method.
10. **Settings dialog** (complete), installer, release 2.0.0, README; then remove the Pascal code.

## Left to the builder

- The split of renderer JS into files, and the Rust module names below the level given above.
- Exact SVG icons for each command, following the rules in goal 2.
- How Tauri commands and events are named and shaped.
- The choice of Rust crates for INI, CSV/XML and images, as long as the ini file stays
  readable by 1.2.
