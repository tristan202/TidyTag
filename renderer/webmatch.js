// Pairing the files with a release's tracks, and a track's tag values (trackmatch.pas), plus
// the web lookup's option keys and the batch grouping (RunWebBatch). Pure: node --test runs it.
// Uses TOOLS.parseTrack / formatTrack (tools.js).
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.WEBMATCH = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  /* global TOOLS */

  /** Title for comparing: lower case, letters and digits only; strip also drops (...) and [...]. */
  // from: NormTitle
  function normTitle(s, strip) {
    let r = '', depth = 0;
    for (const c of String(s || '').toLowerCase()) {
      if (strip && (c === '(' || c === '[')) depth += 1;
      else if (strip && (c === ')' || c === ']')) { if (depth > 0) depth -= 1; }
      else if (depth === 0 && (c.toUpperCase() !== c.toLowerCase() || (c >= '0' && c <= '9'))) r += c;
    }
    return r;
  }

  /** The only unused track whose title matches (full, else without brackets); -1 if none or several. */
  // from: FindTitle
  function findTitle(detail, t, used) {
    for (const strip of [false, true]) {
      const want = normTitle(t, strip);
      if (!want) return -1;
      const hits = detail.tracks.map((tr, j) => (!used[j] && normTitle(tr.title, strip) === want ? j : -1)).filter((j) => j >= 0);
      if (hits.length === 1) return hits[0];
      if (hits.length > 1) return -1;
    }
    return -1;
  }

  /** Rows = max(tracks, files). By title when every file's title matches exactly one track; a
   *  single file goes to the song search's hit; then by disc/track numbers when every file has
   *  one on the release; else in list order. */
  // from: MatchFilesToTracks
  function matchFilesToTracks(files, detail, hitDisc = 0, hitPos = 0) {
    const nt = detail.tracks.length, nf = files.length;
    const rows = Array.from({ length: Math.max(nt, nf) }, (_, i) => ({ trackIdx: i < nt ? i : -1, fileIdx: -1 }));
    const done = (method, pick) => { pick.forEach((t, i) => { rows[t].fileIdx = i; }); return { rows, method }; };
    // titles first: also right for single songs whose track number is from another release
    if (nf > 0 && nf <= nt) {
      const used = new Array(nt).fill(false), pick = [];
      for (const f of files) {
        const j = findTitle(detail, f.fields.title, used);
        if (j < 0) break;
        used[j] = true;
        pick.push(j);
      }
      if (pick.length === nf) return done('title', pick);
    }
    // one file and a song search: the track the search found
    if (nf === 1 && hitPos > 0) {
      const j = detail.tracks.findIndex((t) => t.position === hitPos && (hitDisc === 0 || t.disc === hitDisc));
      if (j >= 0) return done('hit', [j]);
    }
    // disc/track numbers: all or nothing, so a half-tagged album is not mixed up
    if (nf > 0 && nf <= nt) {
      const used = new Array(nt).fill(false), pick = [];
      for (const f of files) {
        const num = TOOLS.parseTrack(f.fields.track);
        if (!num) break;
        const disc = TOOLS.parseTrack(f.fields.disc)?.num ?? 1;
        const j = detail.tracks.findIndex((t) => t.disc === disc && t.position === num.num);
        if (j < 0 || used[j]) break;
        used[j] = true;
        pick.push(j);
      }
      if (pick.length === nf) return done('number', pick);
    }
    return done('order', files.map((_, i) => i));
  }

  // from: MoveFile
  function moveFile(rows, row, delta) {
    const other = row + delta;
    if (row < 0 || row >= rows.length || other < 0 || other >= rows.length) return;
    [rows[row].fileIdx, rows[other].fileIdx] = [rows[other].fileIdx, rows[row].fileIdx];
  }

  const pairs = (rows) => rows.filter((r) => r.trackIdx >= 0 && r.fileIdx >= 0).map((r) => ({ trackIdx: r.trackIdx, fileIdx: r.fileIdx }));

  /** The chosen fields of a release track as tag values. */
  // from: ApplyTrack
  function applyTrack(detail, trackIdx, opt) {
    const t = detail.tracks[trackIdx], f = opt.fields, rel = detail.release, v = {};
    if (f.has('title')) v.title = t.title;
    if (f.has('artist')) v.artist = t.artist;
    if (f.has('album')) v.album = rel.title;
    if (f.has('albumArtist')) v.albumArtist = detail.albumArtist;
    if (f.has('year') && rel.date) v.year = opt.yearOnly ? rel.date.slice(0, 4) : rel.date;
    if (f.has('track')) {
      const total = t.disc >= 1 && t.disc <= detail.discTrackCounts.length ? detail.discTrackCounts[t.disc - 1] : 0;
      v.track = opt.trackWithTotal ? TOOLS.formatTrack(t.position, total, '07/12') : String(t.position);
    }
    // disc numbers only for real multi-disc releases
    if (f.has('disc') && detail.discCount > 1) v.disc = `${t.disc}/${detail.discCount}`;
    if (f.has('genre') && detail.genre) v.genre = detail.genre;
    if (f.has('publisher') && rel.labelName) v.publisher = rel.labelName;
    if (f.has('catalogNo') && rel.catalogNo) v.catalogNo = rel.catalogNo;
    return v;
  }

  // from: LoadOptions / Options — `sec` is the settings snapshot of [Web] (lower-case keys)
  function options(sec) {
    const b = (k, def) => { const x = sec?.[k]; return x === undefined || x === '' ? def : !['0', 'false'].includes(String(x).toLowerCase()); };
    const fields = new Set();
    for (const [key, field, def] of [['title', 'title', true], ['artist', 'artist', true], ['album', 'album', true],
      ['albumartist', 'albumArtist', true], ['year', 'year', true], ['track', 'track', true], ['disc', 'disc', true], ['genre', 'genre', false]]) {
      if (b(key, def)) fields.add(field);
    }
    if (b('label', false)) { fields.add('publisher'); fields.add('catalogNo'); }
    return { fields, yearOnly: b('yearonly', true), trackWithTotal: b('tracktotal', false), coverTags: b('covertags', true),
      coverFolder: b('coverfolder', false), source: Number(sec?.source) === 1 ? 1 : 0 };
  }

  // from: CommonValue
  function commonValue(items, key) {
    if (!items.length) return '';
    const v = items[0].fields[key] || '';
    return items.every((tr) => (tr.fields[key] || '') === v) ? v : '';
  }

  /** One group per folder + album name; album mode is the guess when every file has an album
   *  name and no group has just one file. */
  // from: RunWebBatch
  function batchGroups(items) {
    const byKey = new Map();
    let allTagged = true;
    for (const tr of items) {
      const album = (tr.fields.album || '').trim();
      if (!album) allTagged = false;
      const key = tr.folder.toLowerCase() + '|' + album.toLowerCase();
      if (!byKey.has(key)) byKey.set(key, []);
      byKey.get(key).push(tr);
    }
    const groups = [...byKey.values()];
    return { groups, albumMode: allTagged && groups.every((g) => g.length >= 2) };
  }

  /** [files, folders, files with an album name, different album names] for rsWebBatchOversigt;
   *  folders and albums compare case-insensitively, as 1.2's sorted TStringLists. */
  // from: RunWebBatch
  function batchSummary(items) {
    const folders = new Set(items.map((tr) => tr.folder.toLowerCase()));
    const albums = items.map((tr) => (tr.fields.album || '').trim()).filter(Boolean);
    return [items.length, folders.size, albums.length, new Set(albums.map((a) => a.toLowerCase())).size];
  }

  /** The folders that get folder.jpg: every row with a file, once per folder (case-insensitive). */
  // from: ButtonWriteClick (DoneDirs)
  function folderCoverDirs(rows, files) {
    const seen = new Set(), out = [];
    for (const r of rows) {
      if (r.fileIdx < 0) continue;
      const d = files[r.fileIdx].folder;
      if (seen.has(d.toLowerCase())) continue;
      seen.add(d.toLowerCase());
      out.push(d);
    }
    return out;
  }

  return { normTitle, matchFilesToTracks, moveFile, pairs, applyTrack, options, commonValue, batchGroups, batchSummary, folderCoverDirs };
});
