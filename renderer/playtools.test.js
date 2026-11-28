'use strict';
const test = require('node:test');
const assert = require('node:assert');
const P = require('./playtools.js');

const tr = (path, fields = {}) => ({ path, fileName: path.replace(/^.*\\/, ''), fields });

test('player stops after the last track and on errors', () => {
  const q = { files: ['a', 'b', 'c'], index: 2, sawPlaying: true };
  assert.strictEqual(P.queueAfterEnd(q).index, -1);
  assert.strictEqual(P.queueAfterEnd({ ...q, index: 0 }).index, 1);
  // Forrige: back to the start first, the previous track within the first 3 seconds
  assert.deepStrictEqual(P.queuePrev({ ...q, index: 1 }, 5), { q: { ...q, index: 1 }, seekZero: true });
  assert.deepStrictEqual(P.queuePrev({ ...q, index: 1 }, 1), { q: { ...q, index: 0, sawPlaying: false }, seekZero: false });
  assert.strictEqual(P.queuePrev({ ...q, index: 0 }, 1).q.index, 0);
  // Næste on the last track does nothing
  assert.strictEqual(P.queueNext(q), null);
  assert.strictEqual(P.queueNext({ ...q, index: 0 }).index, 1);
  // an error stops the queue
  assert.strictEqual(P.queueStopped(q).index, -1);
});

test('play targets: several selected, else the whole view from the focused file', () => {
  const xs = [tr('C:\\m\\1.mp3'), tr('C:\\m\\2.mp3'), tr('C:\\m\\3.mp3')];
  assert.deepStrictEqual(P.playTargets({ items: xs, sel: new Set([xs[0], xs[2]]), focus: 2 }),
    { files: ['C:\\m\\1.mp3', 'C:\\m\\3.mp3'], index: 0 });
  assert.deepStrictEqual(P.playTargets({ items: xs, sel: new Set([xs[1]]), focus: 1 }),
    { files: ['C:\\m\\1.mp3', 'C:\\m\\2.mp3', 'C:\\m\\3.mp3'], index: 1 });
  assert.deepStrictEqual(P.playTargets({ items: xs, sel: new Set(), focus: -1 }), { files: [], index: 0 });
});

test('player for an extension, with * as the fallback', () => {
  const players = ['.MP3=C:\\a.exe', '*=C:\\b.exe', 'flac= C:\\c.exe '];
  assert.strictEqual(P.playerFor('D:\\x.mp3', players), 'C:\\a.exe');
  assert.strictEqual(P.playerFor('D:\\x.flac', players), 'C:\\c.exe');
  assert.strictEqual(P.playerFor('D:\\x.ogg', players), 'C:\\b.exe');
  assert.strictEqual(P.playerFor('D:\\x.ogg', ['mp3=C:\\a.exe']), '');
});

test('title is artist - title when both are set', () => {
  const all = [tr('C:\\m\\1.mp3', { artist: 'A', title: 'T' }), tr('C:\\m\\2.mp3', { title: 'T' })];
  assert.strictEqual(P.titleFor('c:\\M\\1.mp3', all), 'A - T');
  assert.strictEqual(P.titleFor('C:\\m\\2.mp3', all), '2.mp3');
  assert.strictEqual(P.titleFor('C:\\o\\9.mp3', all), '9.mp3');
});

test('extra players are written as WriteList', () => {
  assert.deepStrictEqual(P.listToIni(['C:\\a b\\x.exe', 'C:\\y.exe']), [['Item0', '"C:\\a b\\x.exe"'], ['Item1', '"C:\\y.exe"']]);
  assert.deepStrictEqual(P.listFromIni([['Item0', '"C:\\a.exe"'], ['Foo', 'C:\\b.exe']]), ['C:\\a.exe', 'C:\\b.exe']);
});
