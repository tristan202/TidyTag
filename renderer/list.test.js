'use strict';
const test = require('node:test');
const assert = require('node:assert');
const L = require('./list.js');

const tr = (o) => ({ path: 'C:/m/' + (o.fileName || 'a.mp3'), folder: 'C:/m', fileName: 'a.mp3', fileSize: 0,
  fields: {}, tagTypes: '', codec: '', hasCover: false, duration: 0, bitrate: 0, sampleRate: 0, channels: 0,
  bitDepth: 0, supported: true, error: '', checked: false, ...o });
const col = (caption) => L.COLUMNS.findIndex((c) => c.caption === caption);

test('visible window renders only visible rows', () => {
  assert.deepStrictEqual(L.visibleWindow(0, 600, 24, 50000), { first: 0, last: 34 });
  assert.deepStrictEqual(L.visibleWindow(240000, 600, 24, 50000), { first: 9990, last: 10034 });
  assert.deepStrictEqual(L.visibleWindow(0, 600, 24, 3), { first: 0, last: 2 });
  assert.deepStrictEqual(L.visibleWindow(0, 600, 24, 0), { first: 0, last: -1 });
});

test('compareTracks sorts track numerically', () => {
  const a = tr({ fields: { track: '2' }, fileName: 'x.mp3' }), b = tr({ fields: { track: '10' }, fileName: 'y.mp3' });
  assert.ok(L.compareTracks(a, b, { col: col('Spor'), desc: false, col2: -1 }) < 0);
  assert.ok(L.compareTracks(a, b, { col: col('Spor'), desc: true, col2: -1 }) > 0);
});

test('text comparison is case-insensitive; the second column decides ties', () => {
  const a = tr({ fields: { artist: 'abc', title: 'B' }, fileName: '1.mp3' });
  const b = tr({ fields: { artist: 'ABC', title: 'A' }, fileName: '2.mp3' });
  const order = { col: col('Kunstner'), desc: false, col2: col('Titel'), desc2: false };
  assert.ok(L.compareTracks(a, b, order) > 0);
  assert.ok(L.compareTracks(a, b, { ...order, col2: -1 }) < 0); // then the file name
});

test('formatDuration and formatSize follow 1.2', () => {
  assert.strictEqual(L.formatDuration(3725), '1:02:05');
  assert.strictEqual(L.formatDuration(65), '1:05');
  assert.strictEqual(L.formatDuration(0), '');
  assert.strictEqual(L.formatSize(1500, 'da'), '2 KB');
  assert.strictEqual(L.formatSize(5 * 1024 * 1024 + 100000, 'da'), '5,1 MB');
});

test('cellText follows 1.2', () => {
  const t = tr({ error: 'Ukendt lydformat', bitrate: 320, hasCover: true });
  assert.strictEqual(L.cellText(t, col('Tag-typer')), 'Fejl: Ukendt lydformat');
  assert.strictEqual(L.cellText(t, col('Bitrate')), '320');
  assert.strictEqual(L.cellText(t, col('Cover')), 'Ja');
  assert.strictEqual(L.cellText(tr({ supported: false }), col('Tag-typer')), '(ikke understøttet endnu)');
});

test('stale scan batches are ignored', () => {
  const state = { scanId: 2, items: [] };
  L.applyBatch(state, { scanId: 1, tracks: [tr({})] });
  assert.strictEqual(state.items.length, 0);
  L.applyBatch(state, { scanId: 2, tracks: [tr({}), tr({})] });
  assert.strictEqual(state.items.length, 2);
});

test('statusTexts are 1.2s five panels', () => {
  const items = [tr({ duration: 60, checked: true }), tr({ duration: 125 })];
  const s = L.statusTexts(items, [items[1]], 0);
  assert.deepStrictEqual(s, ['Filer i alt: 2', 'Markerede: 1', 'Samlet tid: 3:05', 'Markeret tid: 2:05', 'Afkrydset: 1']);
});
