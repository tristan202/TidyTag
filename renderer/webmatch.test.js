'use strict';
const test = require('node:test');
const assert = require('node:assert');
global.TOOLS = require('./tools.js');
const W = require('./webmatch.js');

// webtest.lpr's ReleaseJson, as web_release sends it
const D = {
  release: { title: 'Bedste ændringer', date: '1999-05-01', labelName: 'Pladeselskab', catalogNo: 'CAT 1' },
  albumArtist: 'Various Artists', genre: 'Hard Rock', discCount: 2, discTrackCounts: [2, 1], compilation: true, coverUrl: '',
  tracks: [
    { disc: 1, position: 1, number: '1', title: 'Sang A', artist: 'Kunstner A feat. Gæst', lengthMs: 180000 },
    { disc: 1, position: 2, number: '2', title: 'Sang B', artist: 'Kunstner B', lengthMs: 200500 },
    { disc: 2, position: 1, number: '1', title: 'Sang C', artist: 'Kunstner C', lengthMs: 99000 },
  ],
};
// from: MakeFile
const file = (name, track, disc, title = '') => ({ path: 'C:\\x\\' + name, folder: 'C:\\x', fields: { track, disc, title, comment: 'bevares' } });
const files = (rows) => rows.map((r) => r.fileIdx);

test('pairs by disc/track numbers, else in list order; move a file', () => {
  const f = [file('c.mp3', '1', '2'), file('a.mp3', '1/2', '1/2'), file('b.mp3', '02', '')];
  let m = W.matchFilesToTracks(f, D);
  assert.strictEqual(m.method, 'number');
  assert.deepStrictEqual(files(m.rows), [1, 2, 0]);
  f[2].fields.track = '';
  m = W.matchFilesToTracks(f, D);
  assert.strictEqual(m.method, 'order');
  assert.deepStrictEqual(files(m.rows), [0, 1, 2]);
  W.moveFile(m.rows, 0, 1);
  assert.deepStrictEqual(files(m.rows).slice(0, 2), [1, 0]);
  f.push(file('ekstra.mp3', '', ''));
  m = W.matchFilesToTracks(f, D);
  assert.strictEqual(m.rows.length, 4);
  assert.deepStrictEqual([m.rows[3].trackIdx, m.rows[3].fileIdx], [-1, 3]);
});

test('pairs by title first; a single file goes to the search hit', () => {
  const f = [file('c.mp3', '1', '2', 'SANG b!'), file('a.mp3', '1/2', '1/2', 'Sang C (Remastered 2011)')];
  let m = W.matchFilesToTracks(f, D);
  assert.strictEqual(m.method, 'title');
  assert.deepStrictEqual([m.rows[1].fileIdx, m.rows[2].fileIdx], [0, 1]);
  f[1].fields.title = 'Sang A';
  f[1].fields.track = '7';
  m = W.matchFilesToTracks(f, D);
  assert.strictEqual(m.method, 'title');
  assert.strictEqual(m.rows[0].fileIdx, 1);
  const one = [file('c.mp3', '1', '2', 'Ukendt titel')];
  m = W.matchFilesToTracks(one, D, 2, 1);
  assert.strictEqual(m.method, 'hit');
  assert.strictEqual(m.rows[2].fileIdx, 0);
  m = W.matchFilesToTracks(one, D);
  assert.strictEqual(m.method, 'number');
  assert.strictEqual(m.rows[2].fileIdx, 0);
  assert.strictEqual(W.normTitle("Rock'n'Roll [Live] (1975)", true), 'rocknroll');
});

test('single file pairs with the search hit', () => {
  const m = W.matchFilesToTracks([file('x.mp3', '9', '', 'Noget andet')], D, 2, 1);
  assert.strictEqual(m.method, 'hit');
  assert.deepStrictEqual(W.pairs(m.rows), [{ trackIdx: 2, fileIdx: 0 }]);
});

test('apply track writes only the chosen fields', () => {
  const opt = { fields: new Set(['title', 'artist', 'album', 'albumArtist', 'year', 'track', 'disc', 'genre']), yearOnly: true, trackWithTotal: true };
  const v = W.applyTrack(D, 1, opt);
  assert.strictEqual(v.title, 'Sang B');
  assert.strictEqual(v.albumArtist, 'Various Artists');
  assert.strictEqual(v.year, '1999');
  assert.strictEqual(v.track, '02/02');
  assert.strictEqual(v.disc, '1/2');
  assert.ok(!('comment' in v));
  assert.deepStrictEqual(W.applyTrack(D, 2, { fields: new Set(['title']), yearOnly: false, trackWithTotal: false }), { title: 'Sang C' });
  // an empty genre/label on the release is not written; a single disc gets no disc number
  const single = { ...D, genre: '', discCount: 1, release: { ...D.release, labelName: '' } };
  const v2 = W.applyTrack(single, 0, { fields: new Set(['genre', 'disc', 'publisher', 'catalogNo', 'track']), yearOnly: false, trackWithTotal: false });
  assert.deepStrictEqual(v2, { track: '1', catalogNo: 'CAT 1' });
});

test('extra files get no track and are not written', () => {
  const f = [file('1.mp3', '', ''), file('2.mp3', '', ''), file('3.mp3', '', ''), file('4.mp3', '', '')];
  const m = W.matchFilesToTracks(f, D);
  assert.strictEqual(m.rows.length, 4);
  assert.strictEqual(m.rows[3].trackIdx, -1);
  assert.strictEqual(W.pairs(m.rows).length, 3);
});

test('options come from the [Web] keys with 1.2 defaults', () => {
  const o = W.options({});
  assert.deepStrictEqual([...o.fields].sort(), ['album', 'albumArtist', 'artist', 'disc', 'title', 'track', 'year']);
  assert.ok(o.yearOnly && !o.trackWithTotal && o.coverTags && !o.coverFolder);
  const o2 = W.options({ genre: '1', label: '1', title: '0', tracktotal: '1' });
  assert.ok(o2.fields.has('genre') && o2.fields.has('publisher') && o2.fields.has('catalogNo') && !o2.fields.has('title'));
  assert.ok(o2.trackWithTotal);
});

test('batch groups by folder and album', () => {
  const t = (folder, album) => ({ path: folder + '\\x.mp3', folder, fields: { album } });
  let g = W.batchGroups([t('C:\\a', 'X'), t('C:\\a', 'x'), t('C:\\b', 'Y'), t('C:\\B', 'Y')]);
  assert.strictEqual(g.groups.length, 2);
  assert.ok(g.albumMode);
  g = W.batchGroups([t('C:\\a', 'X'), t('C:\\a', 'X'), t('C:\\b', '')]);
  assert.ok(!g.albumMode);
  assert.strictEqual(W.commonValue([t('C:\\a', 'X'), t('C:\\b', 'X')], 'album'), 'X');
  assert.strictEqual(W.commonValue([t('C:\\a', 'X'), t('C:\\b', 'Y')], 'album'), '');
});

test('batch summary counts files, folders, tagged files and albums', () => {
  const t = (folder, album) => ({ path: folder + '\\x.mp3', folder, fields: { album } });
  const items = [t('C:\\a', 'X'), t('C:\\a', 'x'), t('C:\\a', 'Y'), t('C:\\B', 'Y'), t('C:\\B', '')];
  assert.deepStrictEqual(W.batchSummary(items), [5, 2, 4, 2]);
  // one album of a single file: not the album guess
  assert.ok(!W.batchGroups([t('C:\\a', 'X'), t('C:\\a', 'X'), t('C:\\b', 'Z')]).albumMode);
});

test('folder cover once per folder, never over an existing one', () => {
  // every listed file's folder counts (1.2 walks the rows with a file), once, case-insensitive
  const f = [{ folder: 'C:\\a' }, { folder: 'C:\\b' }, { folder: 'c:\\A' }];
  const rows = [{ trackIdx: 0, fileIdx: 0 }, { trackIdx: -1, fileIdx: 1 }, { trackIdx: 1, fileIdx: 2 }, { trackIdx: 2, fileIdx: -1 }];
  assert.deepStrictEqual(W.folderCoverDirs(rows, f), ['C:\\a', 'C:\\b']);
});
