'use strict';
const test = require('node:test');
const assert = require('node:assert');
const LISTVIEW = require('./listview.js');
const RENAMETOOLS = require('./renametools.js');

const KEYS = ['title', 'artist', 'album'];
const tr = (path, fields = {}, extra = {}) => ({ path, fileName: path.replace(/^.*\\/, ''), folder: path.replace(/\\[^\\]*$/, ''),
  fields, tagTypes: '', error: '', checked: false, ...extra });
const F = (o = {}) => ({ tagType: '', text: '', field: 0, whole: false, matchCase: false, ...o });

test('filter matches file name, one field and all fields', () => {
  const a = tr('C:\\m\\Lovely Day.mp3', { artist: 'Bill Withers', title: 'Lovely Day' });
  assert.ok(LISTVIEW.matchesFilter(a, F({ text: 'lovely' }), KEYS));
  assert.ok(!LISTVIEW.matchesFilter(a, F({ text: 'lovely', matchCase: true }), KEYS));
  assert.ok(LISTVIEW.matchesFilter(a, F({ text: 'Lovely', matchCase: true }), KEYS));
  assert.ok(!LISTVIEW.matchesFilter(a, F({ text: 'love', whole: true }), KEYS));
  assert.ok(LISTVIEW.matchesFilter(a, F({ text: 'day', whole: true }), KEYS));
  assert.ok(LISTVIEW.matchesFilter(a, F({ text: 'withers', field: 2 }), KEYS)); // field 2 = artist
  assert.ok(!LISTVIEW.matchesFilter(a, F({ text: 'withers', field: 1 }), KEYS)); // title
  assert.ok(LISTVIEW.matchesFilter(a, F({ text: 'withers', field: KEYS.length + 1 }), KEYS)); // all fields
  assert.ok(!LISTVIEW.matchesFilter(a, F({ text: 'withers' }), KEYS)); // file name only
});

test("tag type filter: '-' keeps only files without tags or errors", () => {
  const none = tr('C:\\m\\a.mp3');
  const v2 = tr('C:\\m\\b.mp3', {}, { tagTypes: 'ID3v2 ID3v1' });
  const bad = tr('C:\\m\\c.mp3', {}, { error: 'Filen er for kort' });
  const pick = (tagType) => [none, v2, bad].filter((x) => LISTVIEW.matchesFilter(x, F({ tagType }), KEYS));
  assert.deepStrictEqual(pick('-'), [none]);
  assert.deepStrictEqual(pick('ID3v1'), [v2]);
  assert.deepStrictEqual(pick(''), [none, v2, bad]);
});

test('hidden files follow renames and come back', () => {
  const a = tr('C:\\m\\a\\1.mp3'), b = tr('C:\\m\\a\\2.mp3'), c = tr('C:\\m\\a\\3.mp3');
  b.hidden = true;
  c.checked = true;
  const state = { all: [a, b, c], items: [], sel: new Set([a]), focus: -1, anchor: -1, filter: F(), folder: 'C:\\m\\a' };
  LISTVIEW.rebuildView(state, KEYS);
  assert.deepStrictEqual(state.items, [a, c]);
  // phase 4's log mapping walks every file, the hidden ones too
  RENAMETOOLS.applyLog(state, ['C:\\m\\b\\1.mp3', 'C:\\m\\b\\2.mp3', 'C:\\m\\b\\3.mp3'], 'C:\\m\\b');
  assert.deepStrictEqual(state.all.map((x) => x.path), ['C:\\m\\b\\1.mp3', 'C:\\m\\b\\2.mp3', 'C:\\m\\b\\3.mp3']);
  LISTVIEW.showAll(state, KEYS);
  assert.deepStrictEqual(state.items, [a, b, c]);
  assert.ok(c.checked && state.sel.has(a));
});

test('hiding drops hidden files from the selection and keeps focus on its object', () => {
  const a = tr('C:\\m\\1.mp3'), b = tr('C:\\m\\2.mp3'), c = tr('C:\\m\\3.mp3');
  const state = { all: [a, b, c], items: [a, b, c], sel: new Set([a, c]), focus: 2, anchor: 2, filter: F() };
  LISTVIEW.hideSelected(state, KEYS);
  assert.deepStrictEqual(state.items, [b]);
  assert.strictEqual(state.sel.size, 0);
  assert.strictEqual(state.focus, -1);
  const x = tr('C:\\m\\1.mp3'), y = tr('C:\\m\\2.mp3'), z = tr('C:\\m\\3.mp3');
  const s2 = { all: [x, y, z], items: [x, y, z], sel: new Set(), focus: 2, anchor: 2, filter: F({ text: '3.' }) };
  LISTVIEW.rebuildView(s2, KEYS);
  assert.deepStrictEqual(s2.items, [z]);
  assert.strictEqual(s2.focus, 0);
});

test('move selected swaps in view and master and keeps selection', () => {
  const a = tr('C:\\m\\1.mp3'), b = tr('C:\\m\\2.mp3'), c = tr('C:\\m\\3.mp3'), h = tr('C:\\m\\h.mp3', {}, { hidden: true });
  const state = { all: [a, h, b, c], items: [a, b, c], sel: new Set([b, c]), focus: 1, anchor: 1, filter: F(),
    sort: { col: 1, desc: false, col2: 3, desc2: false } };
  assert.ok(LISTVIEW.moveSelected(state, -1));
  assert.deepStrictEqual(state.items, [b, c, a]);
  assert.deepStrictEqual(state.all, [b, h, c, a]);
  assert.ok(state.sel.has(b) && state.sel.has(c));
  assert.strictEqual(state.focus, 0);
  assert.deepStrictEqual([state.sort.col, state.sort.col2], [-1, -1]);
  assert.ok(!LISTVIEW.moveSelected(state, -1)); // already at the top
});

test('random order shuffles the master list and sorts manually', () => {
  const xs = [1, 2, 3, 4].map((n) => tr(`C:\\m\\${n}.mp3`));
  const state = { all: xs.slice(), items: xs.slice(), sel: new Set(), focus: -1, anchor: -1, filter: F(), sort: { col: 1, col2: 2 } };
  LISTVIEW.shuffle(state, KEYS, () => 0); // j = 0 every time
  assert.deepStrictEqual(state.all.map((x) => x.fileName), ['2.mp3', '3.mp3', '4.mp3', '1.mp3']);
  assert.deepStrictEqual(state.items, state.all);
  assert.strictEqual(state.sort.col, -1);
});

test('prepare open picks the first folder, else the first file\'s folder with its files', () => {
  const isDir = (p) => !/\.\w+$/.test(p);
  assert.deepStrictEqual(LISTVIEW.prepareOpen(['C:\\m\\a.mp3', 'C:\\x'], isDir), { dir: 'C:\\x', select: [] });
  assert.deepStrictEqual(LISTVIEW.prepareOpen(['C:\\m\\a.mp3', 'C:\\o\\b.mp3', 'c:\\M\\c.mp3'], isDir),
    { dir: 'C:\\m', select: ['C:\\m\\a.mp3', 'c:\\M\\c.mp3'] });
  assert.deepStrictEqual(LISTVIEW.prepareOpen([], isDir), { dir: '', select: [] });
});

test('auto fit caps at 450 and reads at most 1000 rows', () => {
  const rows = Array.from({ length: 2000 }, (_, i) => ({ text: i === 1500 ? 'x'.repeat(999) : 'ab' }));
  const cols = [{ caption: '' }, { caption: 'Filnavn' }, { caption: 'Titel' }];
  const measured = [];
  const widths = LISTVIEW.autoFitWidths(rows, cols, [30, 100, 100], (s) => { measured.push(s); return s.length * 10; },
    (row, c) => (c === 1 ? row.text : 'y'.repeat(60)));
  assert.strictEqual(widths[0], 30); // the check column keeps its width
  assert.strictEqual(widths[1], Math.max(7 * 10 + 24, 2 * 10 + 16)); // row 1500 is not read
  assert.strictEqual(widths[2], 450);
  assert.ok(measured.length <= 2 * (1000 + 1));
});

test('moved files outside the scan scope leave the list', () => {
  const mk = () => [tr('C:\\m\\a.mp3'), tr('C:\\m\\b.mp3'), tr('C:\\m\\c.mp3')];
  const result = { done: [true, false, true], newNames: ['C:\\m\\sub\\a.mp3', 'C:\\m\\b.mp3', 'C:\\x\\c.mp3'] };
  for (const subfolders of [false, true]) {
    const xs = mk();
    const state = { all: xs.slice(), items: xs.slice(), sel: new Set([xs[0]]), focus: 0, anchor: 0, filter: F(), folder: 'C:\\m' };
    LISTVIEW.afterMove(state, xs, result, (p) => LISTVIEW.inScanScope(p, state.folder, subfolders), KEYS);
    if (subfolders) {
      assert.deepStrictEqual(state.all.map((x) => x.path), ['C:\\m\\sub\\a.mp3', 'C:\\m\\b.mp3']);
      assert.strictEqual(xs[0].folder, 'C:\\m\\sub');
      assert.strictEqual(xs[0].fileName, 'a.mp3');
    } else {
      assert.deepStrictEqual(state.all.map((x) => x.path), ['C:\\m\\b.mp3']); // the failed one stays
    }
    assert.strictEqual(state.sel.size, 0);
  }
});

test('scan scope compares case-insensitively', () => {
  assert.ok(LISTVIEW.inScanScope('c:\\M\\a.mp3', 'C:\\m', false));
  assert.ok(LISTVIEW.inScanScope('C:\\m\\a.mp3', 'C:\\m\\', false));
  assert.ok(!LISTVIEW.inScanScope('C:\\m\\sub\\a.mp3', 'C:\\m', false));
  assert.ok(LISTVIEW.inScanScope('C:\\M\\Sub\\a.mp3', 'C:\\m', true));
  assert.ok(!LISTVIEW.inScanScope('C:\\mm\\a.mp3', 'C:\\m', true));
});

test('a saved track replaces its old object in both lists and keeps focus, selection and ticks', () => {
  const a = tr('C:\\m\\a.mp3', { title: 'Old' }), b = tr('C:\\m\\b.mp3'), h = tr('C:\\m\\h.mp3', {}, { hidden: true });
  a.checked = true;
  const state = { all: [a, h, b], items: [a, b], sel: new Set([a]), focus: 0, anchor: 0, filter: F() };
  const a2 = tr('C:\\m\\a.mp3', { title: 'New' });
  LISTVIEW.replaceTrack(state, a, a2);
  assert.ok(state.all[0] === a2 && state.items[0] === a2);
  assert.ok(a2.checked && state.sel.has(a2) && !state.sel.has(a));
  LISTVIEW.rebuildView(state, KEYS); // a column click, a filter, a rename ...
  assert.strictEqual(state.items[0].fields.title, 'New');
  assert.deepStrictEqual([state.focus, state.anchor], [0, 0]);
  assert.ok(state.sel.has(a2));
  // a hidden file read again stays hidden
  const h2 = tr('C:\\m\\h.mp3');
  LISTVIEW.replaceTrack(state, h, h2);
  assert.ok(h2.hidden && state.all[1] === h2);
});
