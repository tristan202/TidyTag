'use strict';
const test = require('node:test');
const assert = require('node:assert');
const R = require('./renametools.js');
const D = require('./menudata.js');

test('mask template shows field names', () => {
  assert.strictEqual(R.maskTemplate('%1 - %2', '.mp3', D.renameVars, '_'), '<Kunstner>_-_<Titel>.mp3');
  assert.strictEqual(R.maskTemplate('%aa\\%6 %x', '.flac', D.renameVars, ' '), '<Albumkunstner>\\<Spor> %x.flac');
  assert.strictEqual(R.maskTemplate('', '.mp3', D.renameVars, ' '), '');
});

test('history keeps 15 newest', () => {
  let h = Array.from({ length: 15 }, (_, i) => 'm' + i);
  h = R.addMaskToHistory(h, 'm3');
  assert.deepStrictEqual(h.slice(0, 2), ['m3', 'm0']);
  assert.strictEqual(h.length, 15);
  h = R.addMaskToHistory(h, 'ny');
  assert.deepStrictEqual([h[0], h.length, h.includes('m14')], ['ny', 15, false]);
  assert.deepStrictEqual(R.addMaskToHistory(['a'], '  '), ['a']);
});

const tr = (path, fields) => ({ path, fields });

test('f2t writes only changed files', () => {
  const ts = [tr('C:/a/1.mp3', { title: 'X' }), tr('C:/a/2.mp3', { title: 'Same', track: '2' }), tr('C:/a/3.mp3', { title: 'Old' })];
  const ms = [
    { ok: false, values: {}, used: [] },
    { ok: true, values: { title: 'Same', track: '2' }, used: ['title', 'track'] },
    { ok: true, values: { title: 'New', track: '3', artist: '' }, used: ['title', 'track'] },
  ];
  const r = R.f2tItems(ts, ms);
  assert.deepStrictEqual([r.ready, r.noMatch], [1, 1]);
  assert.deepStrictEqual(r.items, [{ path: 'C:/a/3.mp3', values: { title: 'New', track: '3' }, cover: null }]);
});

test('rename confirmation like 1.2', () => {
  const rows = [
    { oldName: 'C:\\a\\1.mp3', newName: 'C:\\a\\One.mp3', status: 'Ok', detail: '' },
    { oldName: 'C:\\a\\2.mp3', newName: 'C:\\a\\2.mp3', status: 'Unchanged', detail: '' },
    { oldName: 'C:\\a\\3.mp3', newName: '', status: 'Missing', detail: 'Kunstner' },
  ];
  const c = R.renameConfirm(rows, (s) => s);
  assert.deepStrictEqual([c.okCount, c.skipped], [1, 1]);
  assert.strictEqual(c.examples, '1.mp3  →  One.mp3\n');
  assert.strictEqual(c.problems, '3.mp3: Mangler felt (Kunstner)\n');
});

test('rename log moves the open folder and its files', () => {
  const a = { path: 'C:/m/a/1.mp3', folder: 'C:/m/a', fileName: '1.mp3', checked: true };
  const b = { path: 'C:/m/x.mp3', folder: 'C:/m', fileName: 'x.mp3' };
  const state = { folder: 'C:/m/a', items: [a, b], sel: new Set([a]) };
  const changed = R.applyLog(state, ['C:/m/b/1.mp3', 'C:/m/x.mp3'], 'C:/m/b');
  assert.strictEqual(changed, true);
  assert.strictEqual(state.folder, 'C:/m/b');
  assert.deepStrictEqual([a.path, a.folder, a.fileName], ['C:/m/b/1.mp3', 'C:/m/b', '1.mp3']);
  assert.ok(state.items[0] === a && a.checked && state.sel.has(a));
  assert.strictEqual(R.applyLog(state, ['C:/m/b/1.mp3', 'C:/m/x.mp3'], 'C:/m/b'), false);
});

test('renamedialog state', () => {
  const row = (status) => ({ oldName: 'C:\\a\\x.mp3', newName: '', status, detail: '' });
  const before = [row('Ok'), row('Ok'), row('Unchanged'), row('Missing'), row('Exists')];
  assert.deepStrictEqual(R.summary(before), ['rsDOmdoebesDUaendretD', 2, 1, 2]);
  const after = [row('Done'), row('Failed'), row('Unchanged'), row('Missing')];
  assert.deepStrictEqual(R.summary(after), ['rsDOmdoebtDFejlKan', 1, 1]);
  assert.strictEqual(R.displayName('C:\\a\\x.mp3', 'C:\\A\\b\\y.mp3'), 'b\\y.mp3');
  assert.strictEqual(R.displayName('C:\\a\\x.mp3', 'D:\\y.mp3'), 'D:\\y.mp3');
});
