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
| Track number: "x/xx" format | **Done** | Part of the track number tools; episode numbers are left out with the TV fields |
| Change extension .mp4 → .m4a, .mp4/.m4a/.m4p → .m4b and back | **Done** | Tools > Change file extension, with undo |

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
| More mask variables: %rt release time, %rnd random number, %dbit bit depth, %enc encoder | **Done** | |
| TV series fields and variables (%swt %eid %snr %enr) | – | Video files are outside TidyTag's scope |
| "Do not rename if the file exists" | **Done** | Always: existing files are never overwritten |
| Edit a file/folder name in a dialog with "and previous/next" (F6) | **Done** | F6 renames the folder when the folder tree has focus; with undo |

## File list and view
| Feature | Priority | Notes |
|---|---|---|
| View mode: show only files with ID3v2 / WMA / Ogg-FLAC / MP4 / APE | **Done** | Filter on tag type |
| Flat file list (all subfolders) | – | Exists: "Search subfolders" |
| Search: in chosen fields, whole word, match case, find all, count | **Done** | |
| Columns: auto-fit width (also after changing folder), secondary sort, random order | **Done** | |
| Colours: mark low bitrate, show "missing ID3v1", hide file extensions, grid lines | **Done** | Options > File list |
| Expand/collapse all folders, "play files in folder" | **Done** | View menu and File > Play folder |
| History menu for folders | **Done** | File > Recent folders |

## File actions
| Feature | Priority | Notes |
|---|---|---|
| Delete files (Recycle Bin) | **Done** | |
| Copy/move to folder | **Done** | |
| Properties (Windows dialog) | **Done** | Alt+Enter |

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
| ID3v2: always save as Unicode / ASCII when possible | **Done** | Default: Latin-1 when possible; option: always UTF-16 |
| Copy Artist → Album Artist (if empty / always) | **Done** | |
| Player per file type | **Done** | Options > Players |
| Playlist: EXTINF, full paths, playlist folder, quick save without a dialog | **Done** | Options > Playlists |
| Start folder, font size | **Done** | Font size applies to the file list and folder tree |
| Genre list editor (choose standard genres, own genres) | **Done** | Options > Genre list |

## Dropped
| Feature | Reason |
|---|---|
| Winamp control | Winamp is rarely used; TidyTag has "Play file" |
| freedb, Amazon/TrackType.org | The services have shut down – replaced by MusicBrainz/Discogs |
| Update check, RSS, Buy, Unlock, nag screen | Not relevant |
| Proxy and Amazon AWS settings | Belonged to the closed services (WinInet uses the Windows proxy) |
| Shell integration (right-click in Explorer) | Possible later; needs registry changes |
| Customize toolbars and shortcuts | Large task, small gain |
