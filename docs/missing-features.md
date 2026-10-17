# Tag&Rename features and their state in TidyTag

This list compares the original's features with TidyTag. It was compiled from the original's forms
and menu actions, used only as a reference for *what* the features do – no code was used.

Priority: **A** = high value in daily use, **B** = useful, **C** = rare / niche, **–** = dropped.
**Done** means TidyTag has the feature.

## Tag tools (Tools menu)
| Feature | Priority | Notes |
|---|---|---|
| Swap fields: Artist ↔ Title, Artist ↔ Album, Album ↔ Title, advanced (any two fields) | **Done** | The classic fix after a wrong "tags from file name" |
| Copy text from one tag field to another | **Done** | E.g. Artist → Album Artist |
| Remove spaces (trailing / leading and trailing) in all fields | **Done** | |
| Artist tools: remove leading "The", "The Artist" ↔ "Artist, The", "First Last" ↔ "Last, First" | **Done** | |
| Remove tags completely (Ctrl+Del) | **Done** | |
| MP3 tag sync: ID3v1 → ID3v2 or back (skip / empty fields only / all fields) | **Done** | |
| ReplayGain (track and album gain) | **Done** | Not in the original; added in TidyTag |
| Track number: "x/xx" format, automatic episode number | C | Formatting already exists |
| Change extension .mp4 → .m4a and .mp4/.m4a → .m4b | C | |

## Cover tools
| Feature | Priority | Notes |
|---|---|---|
| Put the folder's cover (folder.jpg) into all files' tags | **Done** | |
| Extract the cover from the files' tags to folder.jpg | **Done** | |
| Delete the folder cover in all selected folders | **Done** | |
| Resize covers in files/folders (max. size, JPEG quality, convert to JPEG) | **Done** | Also as a setting: resize large pictures automatically when added |
| Use a tag picture as folder cover | **Done** | Pictures can also be dragged onto the cover panels |

## Renaming
| Feature | Priority | Notes |
|---|---|---|
| "Rename Actions": named presets (file mask + folder mask) in a menu | **Done** | One click for fixed patterns |
| Mask editor with variable buttons, example and saved masks | **Done** | |
| Word replacements (e.g. "&" → "and") and words that always keep their case (e.g. "AC/DC", "ABBA") | **Done** | |
| More mask variables: %rt release time, %rnd random number, %dbit bit depth, %enc encoder, TV series (%swt %eid %snr %enr) | **Done** (except TV series) | |
| "Do not rename if the file exists" as a setting | C | TidyTag already skips on conflicts |
| Edit a file/folder name in a dialog with "and previous/next" (F6) | C | Names can be edited directly in the list |

## File list and view
| Feature | Priority | Notes |
|---|---|---|
| View mode: show only files with ID3v2 / WMA / Ogg-FLAC / MP4 / APE | **Done** | Filter on tag type |
| Flat file list (all subfolders) | – | Exists: "Search subfolders" |
| Search: in chosen fields, whole word, match case, find all, count | **Done** | |
| Columns: auto-fit width (also after changing folder), secondary sort, random order | **Done** | |
| Colours: mark low bitrate, show "missing ID3v1", hide file extensions, grid lines | C | |
| Expand/collapse all folders, "play files in folder" from the folder menu | C | |
| History menu for folders | C | The address bar has a history |

## File actions
| Feature | Priority | Notes |
|---|---|---|
| Delete files (Recycle Bin) | **Done** | |
| Copy/move to folder | **Done** | |
| Properties (Windows dialog) | C | |

## Tag editor
| Feature | Priority | Notes |
|---|---|---|
| "Part of a compilation" (TCMP/cpil) and "Podcast" flags | **Done** | |
| Edit the tag in all selected files (Ctrl+F5) | – | Exists: the multi-file editor |

## Paste tag
| Feature | Priority | Notes |
|---|---|---|
| Choose which fields are *not* pasted (title, track, BPM, artist, lyrics) | **Done** | |

## Options (dialog)
| Feature | Priority | Notes |
|---|---|---|
| One settings dialog | **Done** | |
| ID3v2: always save as Unicode / ASCII when possible | C | TidyTag uses UTF-16 when needed |
| Copy Artist → Album Artist (if empty / always) | **Done** | |
| Player per file type | C | TidyTag uses the Windows default program |
| Playlist: EXTINF, full paths, quick save without a dialog | C | |
| Start folder, font size | C | |
| Genre list editor (choose standard genres, own genres) | C | |

## Dropped
| Feature | Reason |
|---|---|
| Winamp control | Winamp is rarely used; TidyTag has "Play file" |
| freedb, Amazon/TrackType.org | The services have shut down – replaced by MusicBrainz/Discogs |
| Update check, RSS, Buy, Unlock, nag screen | Not relevant |
| Proxy and Amazon AWS settings | Belonged to the closed services (WinInet uses the Windows proxy) |
| Shell integration (right-click in Explorer) | Possible later; needs registry changes |
| Customize toolbars and shortcuts | Large task, small gain |
