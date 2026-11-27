'use strict';
const test = require('node:test');
const assert = require('node:assert');
const T = require('./tools.js');

const tr = (fields, folder = 'C:/a', name = 'x.mp3') => ({ path: `${folder}/${name}`, folder, fileName: name, fields });

test('swap', () => {
  assert.deepStrictEqual(T.planSwap(tr({ artist: 'A', title: 'B' }), 'artist', 'title'),
    { values: { artist: 'B', title: 'A' }, fields: ['artist', 'title'] });
  assert.strictEqual(T.planSwap(tr({ artist: 'A', title: 'A' }), 'artist', 'title'), null);
});

test('copy', () => {
  assert.strictEqual(T.planCopy(tr({ albumArtist: 'X' }), 'artist', 'albumArtist', false), null); // empty source
  assert.strictEqual(T.planCopy(tr({ artist: 'A', albumArtist: 'X' }), 'artist', 'albumArtist', true), null);
  assert.deepStrictEqual(T.planCopy(tr({ artist: 'A' }), 'artist', 'albumArtist', true),
    { values: { albumArtist: 'A' }, fields: ['albumArtist'] });
});

test('cleanSpaces', () => {
  assert.strictEqual(T.cleanSpaces('  a   b\tc ', true), 'a b c');
  assert.strictEqual(T.cleanSpaces('  a  b ', false), 'a  b');
  const p = T.planCleanSpaces(tr({ title: ' a  b ', lyrics: ' x  y ', comment: 'c  d' }));
  assert.deepStrictEqual(p.values, { title: 'a b', lyrics: 'x  y', comment: 'c  d' });
});

test('name tools', () => {
  assert.strictEqual(T.applyNameTool('The Beatles', 'removeThe'), 'Beatles');
  assert.strictEqual(T.applyNameTool('The Beatles', 'theToEnd'), 'Beatles, The');
  assert.strictEqual(T.applyNameTool('Beatles, The', 'theToFront'), 'The Beatles');
  assert.strictEqual(T.applyNameTool('Carl Nielsen', 'nameToSurnameFirst'), 'Nielsen, Carl');
  assert.strictEqual(T.applyNameTool('Nielsen, Carl', 'surnameFirstToName'), 'Carl Nielsen');
  assert.strictEqual(T.applyNameTool('The A; The B', 'removeThe'), 'A; B');
  assert.strictEqual(T.planNameTool(tr({ artist: 'ABBA' }), 'artist', 'removeThe'), null);
});

test('formatTrack', () => {
  assert.strictEqual(T.formatTrack(7, 12, '07/12'), '07/12');
  assert.strictEqual(T.formatTrack(7, 0, '7/12'), '7');
  assert.strictEqual(T.formatTrack(7, 9, '007'), '007');
  assert.deepStrictEqual(T.parseTrack(' 5/9'), { num: 5, total: 9 });
  assert.strictEqual(T.parseTrack('abc'), null);
});

test('numbering across folders', () => {
  const ts = [tr({}, 'C:/a', '1'), tr({}, 'C:/a', '2'), tr({}, 'C:/b', '3')];
  assert.deepStrictEqual(T.planTrackNumbers(ts, 'number', '07/12', 1, false), ['01/03', '02/03', '03/03']);
  assert.deepStrictEqual(T.planTrackNumbers(ts, 'number', '07/12', 1, true), ['01/02', '02/02', '01/01']);
});

test('format mode', () => {
  const ts = [tr({ track: '7' }, 'C:/a', '1'), tr({ track: 'abc' }, 'C:/a', '2'), tr({}, 'C:/a', '3')];
  assert.deepStrictEqual(T.planTrackNumbers(ts, 'format', '07/12', 1, false), ['07/03', 'abc', '']);
});

test('paste keeps only chosen fields', () => {
  assert.deepStrictEqual(T.pasteValues({ artist: 'A', album: 'B', title: '' }, ['album', 'title']), { album: 'B' });
});

test('swap plans for a selection skip unchanged files', () => {
  const ts = [tr({ artist: 'A', title: 'B' }), tr({ artist: 'C', title: 'C' }), tr({ artist: 'D' })];
  const items = T.writeItems(ts, (t) => T.planSwap(t, 'artist', 'title'));
  assert.strictEqual(items.length, 2);
  assert.deepStrictEqual(items[0], { path: ts[0].path, values: { artist: 'B', title: 'A' }, cover: null });
});

test('track dialog statuses', () => {
  const RS = require('./menudata.js').rs;
  assert.strictEqual(RS[T.trackStatus(tr({ track: '01' }), '01')], 'Uændret');
  assert.strictEqual(RS[T.trackStatus(tr({ track: '1' }, 'C:/a', 'x.dsf'), '01')], 'Filtypen kan ikke gemmes endnu');
  assert.strictEqual(RS[T.trackStatus(tr({ track: '1' }), '01')], 'Ændres');
  assert.ok(T.canWriteTags('C:/a/b.FLAC') && !T.canWriteTags('C:/a/b.dsf'));
});

test('drop targets follow 1.2', () => {
  const C = require('./covers.js');
  const a = tr({}, 'C:/m/a', '1.mp3'), b = tr({}, 'C:/m/b', '2.mp3');
  const st = { items: [a, b], sel: new Set([a]), focus: 1, folder: 'C:/m' };
  assert.deepStrictEqual(C.dropPlan('file', st), { kind: 'file', items: [a] }); // nothing checked: the selection
  b.checked = true;
  assert.deepStrictEqual(C.dropPlan('file', st), { kind: 'file', items: [b] }); // checked files win
  assert.deepStrictEqual(C.dropPlan('folder', st), { kind: 'folder', dir: 'C:/m/b' }); // the focused file's folder
  assert.deepStrictEqual(C.dropPlan('folder', { ...st, focus: -1 }), { kind: 'folder', dir: 'C:/m' });
  assert.strictEqual(C.dropPlan('list', st), null);
  assert.ok(C.isImageFile('x.JPEG') && !C.isImageFile('x.gif'));
});
