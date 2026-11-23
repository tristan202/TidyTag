# TidyTag Companion protocol (v1)

## Connection

- HTTP/1.1 on the local network. The default port is 47100.
- Every request except `/v1/pair` carries the header `X-TidyTag-Token: <token>`. A missing or unknown token gives `401`.
- Paths are relative to the phone's shared storage (`/storage/emulated/0`), are UTF-8 and use `/` as separator. The following are refused with `400`:
  - `..` that leaves the root
  - absolute paths
  - `\`
- Errors are JSON `{"error": "..."}` with one of these statuses:

  | Status | Meaning |
  |---|---|
  | 400 | bad request or path |
  | 401 | not paired |
  | 404 | not found |
  | 405 | wrong method |
  | 409 | conflict (exists) |
  | 500 | other |

## Requests

Unless stated otherwise, a successful POST answers `{}`.

| Request | What it does |
|---|---|
| `GET /v1/list?path=` | Answers `[{"name","dir","size","mtime"}]`. `mtime` is in ms since 1970, and the list is sorted by name. Stale `*.tidytag-tmp` files in the folder are deleted first. |
| `GET /v1/read?path=&offset=&len=` | Answers the bytes. Fewer bytes come back at the end of the file. |
| `GET /v1/stat?path=` | Answers one entry object, or `404`. |
| `POST /v1/peek` | Body `{"paths":[...],"head":N,"tail":M}`. Answers `[{"path","size","mtime","head","tail"}]`, where `head` and `tail` are base64. `head` holds the first N bytes; `tail` holds the last M bytes after `head`, which may be shorter or empty. Missing files and folders are left out. |
| `POST /v1/write?path=&offset=` | The body bytes are written at the offset. The file must exist; the write is applied and synced before the answer. |
| `POST /v1/truncate?path=&len=` | Sets the file's length. |
| `POST /v1/create?path=` | Creates an empty file, or empties an existing one. |
| `POST /v1/rename?from=&to=&replace=0\|1` | Renames or moves. Parent folders are created. `replace=1` atomically replaces an existing target; without it an existing target gives `409`. |
| `POST /v1/mkdir?path=` | Creates the folder, including its parents. |
| `POST /v1/copy?src=&srcOffset=&len=&dst=&dstOffset=` | The phone copies a range of `src` into `dst` at `dstOffset`, so a rewrite never sends the audio over the network. |
| `POST /v1/trash` | Body `{"paths":[...]}`. Moves the files to Android's trash. Answers `{"refused":[...]}` with the files that could not be moved, such as non-media files. |
| `POST /v1/mtime?path=&ms=` | Sets the modified time. |
| `POST /v1/pair` | Body `{"code":"123456","pcName":"..."}`. Answers `{"token","id","name"}`; a wrong code gives `401`. The code changes after every successful pairing. |

After `write`, `truncate`, `rename` (both paths), `copy` (target), `trash` and `mtime`, the app asks MediaStore to rescan the files. It does not do this for `*.tidytag-tmp` files.

## Discovery

- TidyTag sends the UDP datagram `TIDYTAG?` as a broadcast to port 47101.
- An app that is switched on answers with JSON `{"name","port","id"}`. `id` is a stable random device id.

## Safe saving (how TidyTag uses it)

- **In place:** When the tag fits, TidyTag sends `write` ranges.
- **Rewrite:** Otherwise TidyTag does this:
  1. `create` `<file>.tidytag-tmp`.
  2. `write` the new tag.
  3. `copy` the audio from the original.
  4. `rename` with `replace=1` over the original.

  If the connection is lost before the rename, the original is untouched, and the temporary file is deleted at the next `list` of the folder.
