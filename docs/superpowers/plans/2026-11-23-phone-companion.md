# Phone Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tag, rename and add covers to music directly on an Android phone from TidyTag, through a small companion app on the phone that serves its files over Wi-Fi.

**Architecture:**
- **Companion app:** The server logic is a plain Kotlin/JVM module (`companion/core`). The Android app wraps it with real storage, MediaStore rescans and trash. The same core also runs on the PC as a jar, and TidyTag's tests use that.
- **TidyTag:** A new file layer (`filelayer.pas`) gives local and phone paths one way to open files and do file operations. Phone paths have the form `\\TidyTag-Phone\<phone>\...` and go to `phoneclient.pas`.
- **What changes:** Readers, writers, the scanner, file ops and the folder tree switch to the file layer.

**Tech Stack:**
- **TidyTag:** Lazarus 4.6 / FPC 3.2.2, WinInet (as `musicbrainz.pas`), fpjson.
- **Companion app:** Kotlin, JDK 17 (Temurin), Gradle wrapper, Android SDK (compileSdk 35, minSdk 30), NanoHTTPD 2.3.1 (BSD-3) for HTTP, JUnit 5.

**Spec:** `docs/superpowers/specs/2026-11-23-phone-companion-design.md`

## Global Constraints

- TidyTag: Lazarus 4.6 / FPC 3.2.2, Windows; GPL-3.0; tests only on copies (scratch folders), never the user's real music on the PC.
- Writing to the real phone only with the user's OK, in test folders.
- App: Kotlin, minimum Android 11 (API 30); "All files access" (MANAGE_EXTERNAL_STORAGE); file access is one replaceable part (interface `Storage`).
- Wi-Fi, local network only; plain HTTP with a pairing token on every request; requests without a valid token get 401.
- The app serves only `/storage/emulated/0` (shared storage); paths with `..`, absolute paths, or that resolve outside the root are refused (400).
- After any change the app rescans the file(s) in MediaStore; after rename/move both old and new paths.
- Writes are safe against a dropped connection: in-place range writes are applied whole and synced before the reply; rewrites go through `<name>.tidytag-tmp` + replace; stale `*.tidytag-tmp` are removed when their folder is listed.
- Delete in a phone folder = Android trash (MediaStore); non-media files are not deleted; internal deletes (temp files, replaced cover PNG) are real deletes.
- Copy/move between PC and phone is refused with a message in v1.
- BPM/key, ReplayGain and playback are disabled in phone folders, with a short explanation.
- The existing MTP feature (`phonesync.pas`) stays unchanged.
- Installing the JDK / Android SDK on the PC needs the user's OK first (downloads).
- UI strings Danish in code, translated through `languages/src/translations.json` like the rest of TidyTag; code comments English.

## Review Focus

1. **Wi-Fi drops in the middle of a batch save.** Each file must end up either old or new, never half-written, and the error list names the failed files. Task 6 test `TestDroppedConnection`.
2. **Phone file names with characters Windows does not allow** (`?`, `:`, `"`, `*`, `|`). They must list, play nicely with rename masks, and round-trip unchanged. Task 6 test `TestOddNames`, using `Hvad?.mp3` and `A:B.mp3` on the test root.
3. **The phone's IP address changes** (DHCP), or the app is switched off and on. The tree must find the phone again via discovery without re-pairing. Task 5 test `TestRediscover`, which restarts the server on another port.
4. **A big rewrite.** A 300 KB cover added to a file whose tag has no padding must not send the audio over the network. Task 6 test `TestServerSideCopy` asserts that the bytes uploaded are less than 400 KB for a 5 MB file.
5. **Two TidyTag windows, or a stale block cache.** A file written by one stream must read back fresh in a new stream. Task 6 test `TestCacheFresh`.

---

### Task 0: Toolchain on the PC (needs the user's OK)

**Files:** none in the repo.

- [ ] **Step 1:** Ask the user for OK to download and install, then install:
  - Eclipse Temurin JDK 17 (MSI, per user)
  - Android command-line tools in `%LOCALAPPDATA%\Android\Sdk`
  - `sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"`
- [ ] **Step 2:** Verify.
  - Run `java -version`. Expected: `17.`
  - Run `sdkmanager --list_installed`. Expected: it lists `platforms;android-35`.

### Task 1: Companion core — protocol, storage, safe writes

**Files:**
- Create: `companion/settings.gradle.kts`, `companion/gradlew*`, `companion/core/build.gradle.kts`
- Create: `companion/core/src/main/kotlin/dk/tidytag/companion/core/{Server.kt,Storage.kt,LocalStorage.kt,Protocol.kt}`
- Create: `docs/phone-protocol.md` (the wire format, written from this task's code)
- Test: `companion/core/src/test/kotlin/.../ServerTest.kt`

**Interfaces:**
- Produces `interface Storage`:
  - `list(rel): List<Entry>`
  - `read(rel, offset, len): ByteArray`
  - `write(rel, offset, data)`
  - `setLength(rel, len)`
  - `create(rel)`
  - `rename(from, to, replace: Boolean)`
  - `mkdir(rel)`
  - `exists(rel): Entry?`
  - `copyRange(src, srcOffset, len, dst, dstOffset)`
  - `trash(rels): List<String>` (returns the names it refused)
  - `setModified(rel, millis)`
- Produces `interface MediaHooks { fun changed(rels: List<String>) }`
- Produces `class CompanionServer(storage, hooks, port, tokens: TokenStore)`
- Produces the HTTP API. Every endpoint carries the header `X-TidyTag-Token`. Paths are UTF-8, relative to the root, with `/` as separator.

  | Method | Endpoint | Body | Answer |
  |---|---|---|---|
  | GET | `/v1/list?path=` | | JSON `[{name, dir, size, mtime}]` |
  | GET | `/v1/read?path=&offset=&len=` | | bytes |
  | POST | `/v1/peek` | JSON `{paths:[...], head, tail}` | JSON `[{path, size, mtime, head(base64), tail(base64)}]` |
  | POST | `/v1/write?path=&offset=` | bytes | |
  | POST | `/v1/truncate?path=&len=` | | |
  | POST | `/v1/create?path=` | | |
  | POST | `/v1/rename?from=&to=&replace=0\|1` | | |
  | POST | `/v1/mkdir?path=` | | |
  | GET | `/v1/stat?path=` | | JSON or 404 |
  | POST | `/v1/copy?src=&srcOffset=&len=&dst=&dstOffset=` | | |
  | POST | `/v1/trash` | JSON `{paths:[...]}` | JSON `{refused:[...]}` |
  | POST | `/v1/mtime?path=&ms=` | | |

  Errors are JSON `{error}` with status 400, 401, 404 or 409.

- [ ] **Step 1: Write the failing tests in `ServerTest.kt`.** Each runs against `LocalStorage` over a JUnit temp dir.
  - `listShowsFilesAndFolders`
  - `readRangeAcrossEnd` (a read past the end returns the bytes that exist)
  - `writeIsApplied`
  - `renameReplace`
  - `copyRangeOnPhone`
  - `refusesDotDotAndAbsolute` (`../x`, `/etc`, `a/../../x` → 400)
  - `refusesWithoutToken` (401)
  - `staleTmpRemovedOnList` (`a.mp3.tidytag-tmp` is gone after a list)
  - `hooksCalledOnChange` (write, rename and copy call `changed` with both names on rename)
- [ ] **Step 2:** Run `companion\gradlew -p companion :core:test`. Expected: FAIL (classes missing).
- [ ] **Step 3: Implement** `Storage`, `LocalStorage(root: File)`, `CompanionServer` (NanoHTTPD) and `TokenStore`.
  - `TokenStore` persists to a file and holds `pairingCode: String` (6 digits) and `tokens: Set<String>`.
  - `write` uses `RandomAccessFile` plus `fd.sync()`.
  - `rename(replace)` uses `Files.move(ATOMIC_MOVE, REPLACE_EXISTING)`.
  - `copyRange` uses `FileChannel.transferTo`.
  - `LocalStorage.trash` refuses everything (the PC has no MediaStore). Android overrides it.
- [ ] **Step 4: Add the desktop runner.** Add `main(args)` with `--root <dir> --port <n> --token <t>` and an `application` jar (`:core:shadowJar` or `jar` with a manifest).
  - Run `java -jar core.jar --root C:\tmp\x --port 47100 --token t`, then `curl -H "X-TidyTag-Token: t" localhost:47100/v1/list?path=`.
  - Expected: a JSON list.
- [ ] **Step 5:** Run `:core:test`. Expected: all pass.
- [ ] **Step 6:** Write `docs/phone-protocol.md` from the code. Commit `companion: core server, storage and protocol`.

### Task 2: Companion core — discovery and pairing

**Files:**
- Create: `companion/core/src/main/kotlin/.../{Discovery.kt,Pairing.kt}`
- Test: `DiscoveryTest.kt`, `PairingTest.kt`

**Interfaces:**
- **Discovery:** a UDP listener on port 47101.
  - Request datagram: `TIDYTAG?`
  - Reply datagram: JSON `{name, port, id}`, where `id` is a stable random device id.
- **Pairing endpoint:** `POST /v1/pair` with JSON `{code, pcName}`.
  - Answer: JSON `{token, id, name}`.
  - A wrong code gives 401.
  - The pairing code changes after each successful pairing.
  - This endpoint is the only one without a token.
- **Unpairing:** `TokenStore.remove(token)`.

- [ ] **Step 1: Write the failing tests.**
  - `answersBroadcast` (send `TIDYTAG?` to 127.0.0.1:47101 → JSON with the port)
  - `pairWithRightCode`
  - `pairWithWrongCodeRefused`
  - `codeRotatesAfterPair`
  - `removedTokenRefused`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement. The desktop runner gets `--code <6 digits>` for the tests.
- [ ] **Step 4:** Run the tests. Expected: PASS. Commit `companion: discovery and pairing`.

### Task 3: Android app

**Files:**
- Create: `companion/app/` (Android module)
  - `MainActivity.kt`: one screen with an on/off switch, status, address `ip:port`, pairing code, a list of paired PCs with remove, and a permission button.
  - `CompanionService.kt`: foreground service with a notification `TidyTag Companion kører`.
  - `AndroidStorage.kt`: `LocalStorage` on `Environment.getExternalStorageDirectory()`. Its `trash` uses `MediaStore.createTrashRequest` (with MANAGE_MEDIA: no dialog) or sets `IS_TRASHED` for files resolved to MediaStore ids. Non-media files are returned as refused.
  - `MediaScanHooks.kt`: `MediaScannerConnection.scanFile`.
- Strings: Danish default plus English `values-en`.

**Interfaces:**
- Consumes `CompanionServer`, `Storage`, `MediaHooks` and `TokenStore` from Tasks 1–2.

- [ ] **Step 1:** Run `companion\gradlew -p companion :app:assembleDebug`. Expected: `app-debug.apk` is built.
- [ ] **Step 2:** Unit test `AndroidStorageTrashTest` with Robolectric is optional. It is required only if it can be run headless. Otherwise trash is checked in Step 3.
- [ ] **Step 3: Check on the phone (with the user's OK).** The user installs the APK, grants "All files access" and "Media management" and switches the server on. Then, from the PC:
  - `curl` `/v1/list?path=Music` with the token from a pair call.
  - Expected: Allan's Music folders.
  - In the test folder `Music/TidyTag-test` only: trash `music-test.mp3`.
  - Expected: it is gone from the folder and is in Files → Trash.
- [ ] **Step 4:** Commit `companion: Android app`.

### Task 4: TidyTag phone client

**Files:**
- Create: `src/phoneclient.pas`
- Test: `tools/phoneclienttest.lpr` (it starts `companion\core\build\libs\core.jar` on a scratch folder of copies)

**Interfaces:**
- Produces:

  ```pascal
  type
    TPhoneEntry = record Name: string; IsDir: Boolean; Size: Int64; MTime: Int64; end;
    TPhoneEntries = array of TPhoneEntry;
    TPhoneInfo = record Id, Name, Host: string; Port: Integer; end;
    TPhonePeek = record Path: string; Size, MTime: Int64; Head, Tail: TBytes; end;
    EPhoneError = class(Exception);
    TPhone = class
      constructor Create(const Info: TPhoneInfo; const Token: string);
      function List(const Rel: string): TPhoneEntries;
      function Read(const Rel: string; Offset: Int64; Len: Integer): TBytes;
      function Peek(const Rels: TStringArray; Head, Tail: Integer): array of TPhonePeek;
      procedure Write(const Rel: string; Offset: Int64; const Data: TBytes);
      procedure Truncate(const Rel: string; Len: Int64);
      procedure CreateFile(const Rel: string);
      procedure Rename(const FromRel, ToRel: string; Replace: Boolean);
      procedure MakeDir(const Rel: string);
      function Stat(const Rel: string; out E: TPhoneEntry): Boolean;
      procedure CopyRange(const Src: string; SrcOffset, Len: Int64; const Dst: string; DstOffset: Int64);
      function Trash(const Rels: TStringArray): TStringArray; // refused
      procedure SetMTime(const Rel: string; Ms: Int64);
    end;
  function DiscoverPhones(TimeoutMs: Integer = 1500): array of TPhoneInfo;
  function PairPhone(const Info: TPhoneInfo; const Code: string; out Token: string): Boolean;
  function PhoneByName(const Name: string): TPhone; // paired phones from the settings, found again by Id
  procedure SavePairedPhone(const Info: TPhoneInfo; const Token: string); // [Phones] in tidytag.ini
  ```

- **Errors:** Network errors and statuses other than 200 raise `EPhoneError` with a Danish message. `PhoneByName` runs discovery when the stored host does not answer and updates the host and port (Review Focus 3).

- [ ] **Step 1: Write the failing tests in `phoneclienttest.lpr`.** Use `Check` as in the other tools.
  - `TestListReadWrite`
  - `TestPeekBatch` (300 files in one request)
  - `TestPairAndToken`
  - `TestRediscover` (restart the jar on another port; `PhoneByName` still works)
  - `TestErrorsRaise` (wrong token → `EPhoneError`)
- [ ] **Step 2:** Run `bin\phoneclienttest.exe <scratch> <core.jar>`. Expected: FAIL.
- [ ] **Step 3:** Implement with WinInet. Keep one connection handle per `TPhone` and use fpjson.
- [ ] **Step 4:** Run the tests. Expected: `ALLE TESTS OK`. Commit `TidyTag: phone client`.

### Task 5: TidyTag file layer

**Files:**
- Create: `src/filelayer.pas`
- Modify: `src/tagutils.pas` (`ReplaceFileWith`, `CopyStreamRange`, `GetFileStamp`/`SetFileStamp` delegate to the layer)
- Test: `tools/filelayertest.lpr`

**Interfaces:**
- Produces:

  ```pascal
  const PhonePrefix = '\\TidyTag-Phone\';
  function IsPhonePath(const Path: string): Boolean;
  function OpenFileStream(const FileName: string; Mode: Word): TStream; // fmOpenRead/ReadWrite/fmCreate as TFileStream
  function FileExistsL(const FileName: string): Boolean;
  function DirectoryExistsL(const Dir: string): Boolean;
  function RenameFileL(const OldName, NewName: string): Boolean;
  function DeleteFileL(const FileName: string): Boolean;        // real delete (temp files)
  function TrashFiles(const Files: TStringArray): TStringArray;  // phone: Android trash; local: Recycle Bin; returns refused
  function ForceDirectoriesL(const Dir: string): Boolean;
  function ListDirL(const Dir: string): TPhoneEntries;           // also local, same record
  procedure PrefetchTags(const Files: TStringArray);            // phone: one Peek; local: nothing
  ```

- **`TPhoneStream = class(TStream)`:**
  - Reads use 64 KB blocks, first from the Peek cache, then from `TPhone.Read`.
  - Writes are kept as ranges and sent in `Flush` and in `Destroy`.
  - `CopyRangeFrom(Src: TPhoneStream; From, Count: Int64)` flushes and then calls `TPhone.CopyRange`.
  - `Size` and `SetSize` go through Stat/Truncate.
- **`CopyStreamRange(Src, Dst, From, Count)`:** When both are `TPhoneStream` on the same phone, it calls `CopyRangeFrom`, so the audio never crosses the network. Otherwise it behaves as today.
- **The Peek cache** is keyed by path plus size plus mtime. Every write or rename of a path clears its entry (Review Focus 5).
- **Path mapping:** `\\TidyTag-Phone\<phone>\a\b.mp3` → phone `<phone>`, rel `a/b.mp3`.

- [ ] **Step 1: Write the failing tests in `filelayertest.lpr`.** They run against the core jar on a scratch copy of the test audio.
  - `TestReadAcrossBlocks` (read 100 bytes at 65500)
  - `TestInPlaceWrite`
  - `TestServerSideCopy` (5 MB file, 300 KB cover via `id3writer`; bytes uploaded counted by a counter in `TPhone` < 400 KB; Review Focus 4)
  - `TestReplace`
  - `TestCacheFresh`
  - `TestOddNames` (`Hvad?.mp3`, `A:B.mp3` round-trip; Review Focus 2)
  - `TestDroppedConnection` (kill the jar during a rewrite; after restart the file equals old or new by hash and no `.tidytag-tmp` is listed; Review Focus 1)
  - `TestLocalUnchanged` (local paths behave as `TFileStream`)
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `filelayer.pas` and the `tagutils` delegation.
- [ ] **Step 4:** Run `filelayertest`, then the existing `tagtest`, `renametest`, `tooltest` and `rgtest`. Expected: all `ALLE TESTS OK`. Commit `TidyTag: file layer`.

### Task 6: Readers and writers through the layer

**Files:**
- Modify (replace `TFileStream.Create(FileName…)` with `OpenFileStream`, and `DeleteFile(Temp)` with `DeleteFileL`):
  - `audiotags.pas:69`
  - `apetag.pas:251`
  - `asfwriter.pas:301,450,460,469`
  - `flacwriter.pas:263,332,344,355`
  - `id3sync.pas:36,50,63`
  - `id3writer.pas:419,472,489,502,515`
  - `mp4writer.pas:481,543,567,582`
  - `oggwriter.pas:206,299,317`
  - `wavwriter.pas:133,180,202,213`
  - `tagremove.pas:48,58,67,90,99,120`
- Not changed: picture dialogs in `tageditform`/`multieditform` (local files the user picks).
- Test: `tools/tagtest.lpr` gets an optional `-phone <core.jar>` flag. It serves the work folder through the jar and runs every existing check on `\\TidyTag-Phone\test\...` paths.

- [ ] **Step 1:** Add `-phone` to `tagtest`. Run it. Expected: FAIL, because the writers still use `TFileStream`.
- [ ] **Step 2:** Replace the sites above.
- [ ] **Step 3:** Run `tagtest` with and without `-phone`. Expected: `ALLE TESTS OK` both times. Commit `TidyTag: tag readers and writers through the file layer`.

### Task 7: Scanner, file operations, renames

**Files:**
- Modify `scanthread.pas`: for phone folders, use `ListDirL` with `PrefetchTags` on each folder's audio files before `ReadAudioInfo`.
- Modify `fileops.pas`:
  - delete → `TrashFiles` for phone paths, reporting refused files
  - copy/move → refuse across sides (`IsPhonePath(src) <> IsPhonePath(target)`) with `rsIkkeMellemPcOgTelefon`
  - same-side phone move → `RenameFileL`
- Modify `renamecore.pas:636,682`: use `RenameFileL` and `ForceDirectoriesL`. Refuse a plan whose target side differs from the source.
- Test: `tools/renametest.lpr` gets `-phone <core.jar>` like `tagtest`.

- [ ] **Step 1:** Add `-phone` to `renametest`, plus `TestCrossSideRefused` and `TestTrashRefusesNonMedia` (the core's `LocalStorage` refuses all, so expect the message path).
- [ ] **Step 2:** Run it. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `renametest` and `tooltest` with and without `-phone`. Expected: `ALLE TESTS OK`. Commit `TidyTag: scanning, renames and deletes on phone folders`.

### Task 8: Folder tree, phone UI and guards

**Files:**
- Modify `src/mainform.pas`:
  - **Tree:** Add an interposer `TShellTreeView = class(ShellCtrls.TShellTreeView)` before `TFormMain`, so the lfm uses it. It overrides `CanExpand` and node population for nodes whose path starts with `PhonePrefix`. Paired phones are added as top-level nodes beside the drives, with a phone icon from `res/icons`. An unreachable phone is greyed out (`Node.Enabled`/font).
  - **Navigate:** Selecting a phone node calls `Navigate(path)`.
  - **Window title:** `TidyTag - Telefon: <phone>\<rel>`.
  - **Guards:**
    - Actions disabled in phone folders, with hint `rsKunPaaPc`: BPM/key, ReplayGain, play, play folder, Play with, playlists, Show in Explorer, properties, Explorer-menu hand-over.
    - The cover drag source does not offer phone paths.
- Add the action "Tilføj telefon...":
  1. Run discovery.
  2. Show a list.
  3. Ask for the code.
  4. `PairPhone` and `SavePairedPhone`, then rebuild the tree.
- **Errors:**
  - An unreachable phone shows `rsStartCompanion`.
  - A lost connection during scan writes a status bar message and keeps the tracks read so far.
- Strings: added to `languages/src/translations.json` for all languages, then `tools/mkpot.py`.
- Modify `src/layoutcheck.pas`: add the "Tilføj telefon" dialog.

- [ ] **Step 1:** Build with `lazbuild TidyTag.lpi`. Expected: it links.
- [ ] **Step 2:** Run `--layoutcheck` in all 7 languages (scratchpad `layoutall.ps1`). Expected: 0 problems.
- [ ] **Step 3: GUI check against the core jar on a scratch copy.**
  - Pair via "Tilføj telefon" with code `123456` (jar flag `--code`).
  - Expand the phone and open a folder. Expected: the tracks are listed with tags.
  - Edit a title, rename a file and delete a file. Expected: the jar root shows the changes, and the delete is refused (LocalStorage), with the message shown.
- [ ] **Step 4:** Commit `TidyTag: phones in the folder tree`.

### Task 9: Release, docs, real phone

**Files:**
- Modify `tools/make-release.ps1`: build `companion\gradlew :app:assembleRelease` and copy the APK as `TidyTag-Companion-<version>.apk` into `release\`. Sign with a release key from `%USERPROFILE%\.tidytag\release.jks`, which must stay out of git. The first run asks the user before creating the key.
- Modify `README.md`: the phone companion section, the known v1 limit "plain HTTP on the local network, no encryption", how to install the APK, and the project structure.
- Modify `docs/missing-features.md`.

- [ ] **Step 1:** Run `tools\make-release.ps1`. Expected: `release\` contains the setup, the zip and the APK.
- [ ] **Step 2: Real phone (with the user's OK), in `Music/TidyTag-test` only.**
  - Pair, open the folder, edit a tag, add a cover, rename, delete one test file.
  - Expected:
    - The files changed on the phone.
    - A music app shows the new tags.
    - The deleted file is in Files → Trash.
- [ ] **Step 3:** Commit `Phone companion: release and docs`.
