# Phone companion: tagging directly on an Android phone

## Intent

Allan keeps much of his music on an Android phone (a Pixel 9 Pro XL) and wants to tag,
rename and add covers to it from TidyTag **directly on the phone's files**, the way TidyTag
works on a local disk: no working copy copied over and sent back (that is what the current
MTP feature in `src/phonesync.pas` does, and it is slow: 23 files took 2 minutes to fetch).

It is primarily for Allan himself, published on GitHub with TidyTag; if there is interest it
may later go to Google Play.

## Goals

- The phone shows up in TidyTag's folder tree **like a drive** (beside the local drives), with
  its folders below it. Opening a phone folder lists its tracks with tags, like a local folder.
- Tags, file and folder renames, and covers work on the phone's files.
- Only the bytes that are needed travel: listing reads the tag parts of files, a save that fits
  in the existing tag space sends only the changed bytes, a rename is a rename on the phone.
- After every change the phone's media library (MediaStore) is told, so music apps on the phone
  show the new tags at once.
- A folder of about 300 tracks should list within a few seconds over Wi-Fi.

## Non-goals

- BPM/key analysis, ReplayGain and playback on phone files. They need the whole audio and are
  only used on the PC. In a phone folder these actions are disabled with a short explanation.
- Editing tags on the phone itself. The app has no tag editor.
- Connections over the internet. Local network only.
- iPhone.

## Anti-goals (a failure even if it works)

- Files damaged or lost on the phone (a half-written file after a dropped connection, a rewrite
  that loses audio).
- Anyone on the network being able to read or change files on the phone.
- Needing developer mode, USB debugging, ADB or extra Windows drivers.

## Constraints

- TidyTag: Lazarus 4.6 / FPC 3.2.2, Windows; GPL-3.0. Tests only on copies; never write to the
  user's real music on the PC. Writing to the real phone only with the user's OK (test folders).
- Android app: Kotlin, minimum Android 11 (API 30) unless something forces otherwise; the user's
  phone runs current Android. No JDK or Android SDK is installed on the development PC yet;
  installing them needs the user's OK.
- Connection over Wi-Fi on the local network (a normal app cannot talk to the PC over the USB
  cable without ADB/developer mode).
- The app needs "All files access" (MANAGE_EXTERNAL_STORAGE) to change any music file. Google
  Play allows that only for some app types, so a Play version would likely need Android's
  MediaStore write requests instead. The app's file access is therefore one replaceable part.
- Distribution: the APK is published on GitHub next to the TidyTag release.

## Approaches considered

- **A. Phone files inside TidyTag's file layer (chosen).** One shared way to open files and do
  file operations in TidyTag; paths on the phone are served by the app: reads fetch blocks on
  demand, writes send byte ranges. Reading tags already goes through one place
  (`AudioTags.ReadAudioInfo`); the writers open files in about 25 places, which change to the
  shared layer. Most work, but the only one that edits phone files directly even when many files
  are saved at once.
- **B. Read directly, fetch the whole file on save.** Listing as in A, but saving downloads the
  whole file, writes it with the unchanged writers and sends back the changed bytes. Less work,
  but a tag change in 300 files means 300 full downloads (minutes over Wi-Fi). Rejected.
- **C. The phone as a Windows drive (WinFsp + the app).** Needs an extra driver install, and the
  phone would be a separate drive rather than part of TidyTag's tree. Rejected by the user.

The user picked A.

## Design

### Parts

1. **Android app "TidyTag Companion".** A small server on the phone.
   - Screen: on/off switch, status (connected PC, or waiting), the phone's address and a pairing
     code.
   - While on, it runs as a foreground service with a notification (Android stops background
     servers otherwise).
   - It serves the phone's shared storage (the root the user sees in a file manager,
     `/storage/emulated/0`).
   - After any change to a file it asks MediaStore to rescan that file. After a rename or move,
     it rescans both the old and the new path.
2. **TidyTag: phone connection** (a new unit). Finds and pairs phones, and remembers paired
   phones in the settings.
3. **TidyTag: file layer** (a new unit). One place that opens files and does file operations
   for local paths and phone paths alike.
4. **TidyTag: the phone in the folder tree.** It appears like a drive and can be expanded.

### Phone paths in TidyTag

A file on the phone gets a path shaped like a network path:
`\\TidyTag-Phone\<phone name>\Music\Rock\song.mp3`.

That shape keeps TidyTag's existing path handling working: folder, file name and extension
functions, rename masks that create folders, and the undo log. The file layer recognises the
prefix and sends those paths to the phone. Code that hands paths to Windows itself must refuse
or skip phone paths: Show in Explorer, Windows properties, Play/Play with, the Explorer context
menu, the folder cover drag source, and the playlist writers. Covers *read* from phone files
are fine.

### Protocol (app ↔ TidyTag)

- HTTP/1.1 on the local network, one port. JSON for listings and errors, raw bytes for file
  data. Every request carries the pairing token.
- **Operations:**
  - list a folder: names, folder/file, size, modified time
  - read a byte range of a file
  - read the head and tail of many files in one request (used when listing a folder)
  - write a byte range
  - set a file's length
  - create a file
  - rename or move a file or folder
  - create a folder
  - whether a path exists
  - copy a byte range from one file on the phone into another (done by the phone itself)
  - move files to Android's trash

  The last one exists for rewrites. When a tag outgrows its space, the writers build the new
  file by copying the audio from the original (`CopyStreamRange` in id3writer, and the same in
  the flac, mp4, ogg, asf and wav writers and tagremove). For phone files, the file layer turns
  that copy into this operation, so the audio never crosses Wi-Fi. Without it, adding a cover to
  300 files would send every file down and up again. *(Builder's call, from the goal that only
  the needed bytes travel.)*
- The app makes a write **safe against a dropped connection**:
  - **In-place write** (the tag fits in its space): the app applies a write request as one
    operation and syncs the file before answering.
  - **Rewrite** (the tag no longer fits): TidyTag writes the new file as a temporary file on the
    phone, in the same folder. The app then replaces the original with it and rescans. If the
    connection drops before the replace, the original is untouched and the temporary file is
    removed the next time that folder is listed.

### Discovery and pairing

- **Finding the phone:** TidyTag sends a UDP broadcast on the local network. Apps that are
  switched on answer with their name, address and port. This also finds a phone again after
  its address has changed.
- **Pairing:** The first time, TidyTag asks for the pairing code shown in the app. The app
  then issues a token that TidyTag stores and sends with every request. The app has a list of
  paired PCs, each of which can be removed. Requests without a valid token are refused.
- **No encryption in v1:** The connection is plain HTTP, limited to the local network. A user
  on a hostile network could listen in. TLS can come later. This is a known v1 limit and is
  written in the README.

### TidyTag's file layer

- **Shared functions:**
  - open a stream (read / read-write / create)
  - file exists, folder exists
  - rename, delete, create folder, list folder
  - replace a file with a temporary file (`ReplaceFileWith` today)
  - get and set the file time

  Local paths do exactly what the code does today.
- **Opening a phone file** gives a stream that fetches 64 KB blocks when they are read and
  keeps them in memory for that stream. Writes are collected as byte ranges and sent when the
  stream is freed or flushed. Errors raise exceptions, like a failing local file, so the
  existing error handling and messages keep working.
- **Where it plugs in:**
  - `ReadAudioInfo` opens files through the layer.
  - The writers, the tag remover and the cover tools go through the layer instead of
    `TFileStream.Create`, `RenameFile`, `DeleteFile` and `ReplaceFileWith`. That is about 25
    `TFileStream` sites plus the file operations in `fileops`, `renamecore`, `tagutils` and the
    writers.
  - `ScanThread` lists phone folders through the layer, using the batch head/tail read so that
    a folder costs only a few requests.
- **"Keep file date":** works on the phone too. The app sets the modified time.

### The folder tree

- **Placement:** Paired phones appear in the folder panel as their own entries beside the
  local drives, with a phone icon. A phone that is not reachable is shown greyed out.
- **Behaviour:** Expanding a phone lists its folders through the app. Selecting a folder opens
  it in the file list, like a local folder. The address bar shows the phone path, and the
  window title shows `TidyTag - Phone: Pixel 9 Pro XL\Music\Rock`.
- **Adding a phone:** "Add phone..." searches the network and pairs.
- **Implementation:** The current tree is a Lazarus `TShellTreeView`, which only knows real
  folders. How the phone entries are added is left to the builder. They must look and behave
  as part of the same tree.

### Deleting

"Delete files" in a phone folder moves the files to Android's own trash, where they can be
restored for about 30 days (the user's choice). This is what Google Photos and Files use: the
MediaStore trash. It is the phone's equivalent of the Recycle Bin that TidyTag uses on the PC.

- **Asking on the phone:** The app asks for the "media management" permission (Android 12+), so
  trashing needs no confirmation on the phone each time. Without that permission, or on Android
  11, the phone shows its own confirmation dialog.
- **Files the trash cannot take:** MediaStore only handles media files. Other files, such as
  `.lrc` or `.cue`, are not deleted; TidyTag says so.
- **Deleting inside TidyTag:** Internal deletes, like the cover PNG that is replaced by a JPEG
  and temporary files from a rewrite, are real deletes. They only remove what TidyTag itself has
  just created or replaced.

### Copying and moving between the PC and the phone

This is not in v1. "Copy/move to folder" and rename masks whose target lies on the other side
(PC ↔ phone) are refused with a message. Moves and renames within the phone work. *(Builder's
call: it was not asked for. If it is wanted later, it needs a safe "copy, then delete the
source" order.)*

### Relation to the existing MTP feature

"Open folder on phone" (copy, edit, send back) stays as the fallback for phones without the
app. Nothing in it changes.

### Error handling

- **Connection lost while listing:** The listing stops, already read tracks stay, and the status
  bar says the phone is not reachable.
- **Connection lost during a save:** Because of the safe write rules above, the file is either
  the old version or the new one. The save reports the files that failed, like a failed local
  save.
- **Phone locked or app off:** Its tree entry is greyed out. Opening it says "Start TidyTag
  Companion on the phone".

### Testing

- **TidyTag file layer:** Console tests against a local test server that speaks the same
  protocol over a folder of copies. They cover reads across block borders, in-place writes,
  rewrites through a temporary file, rename/move, a dropped connection mid-write (the file must
  stay old or new) and the existing tag tests run through phone paths.
- **App:** Unit tests for path safety. The app must never touch anything outside shared
  storage; `..` and absolute paths are refused. Further tests cover the write/replace logic and
  token checks.
- **On the real phone:** Only in test folders, with the user's OK.

## Left to the builder

- How the phone entries are put into the folder tree (they must look like part of it).
- Port number, JSON field names, block size tuning, and the exact batch format for head/tail
  reads.
- Kotlin libraries for the HTTP server and the app's look, kept small.
- How the UDP discovery messages look.
- Build setup for the Android app and how the APK gets into the release (`tools\make-release.ps1`).
