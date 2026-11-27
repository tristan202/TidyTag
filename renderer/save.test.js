'use strict';
const test = require('node:test');
const assert = require('node:assert');
const SAVE = require('./save.js');
const I18N = require('./strings.js');

const tr = (o) => ({ path: 'C:/m/' + (o.name || 'a.mp3'), checked: false, ...o });

test('targets prefer checked files', () => {
  const a = tr({ name: 'a', checked: true }), b = tr({ name: 'b', checked: true }), c = tr({ name: 'c' });
  const r = SAVE.targets({ items: [a, b, c], sel: new Set([c]) });
  assert.deepStrictEqual(r.items, [a, b]);
});

test('targets fall back to selection', () => {
  const a = tr({ name: 'a' }), b = tr({ name: 'b' });
  assert.deepStrictEqual(SAVE.targets({ items: [a, b], sel: new Set([b]) }).items, [b]);
});

test('multiValues only ticked, trimmed', () => {
  const r = SAVE.multiValues({ artist: { on: true, value: ' A ' }, album: { on: false, value: 'X' } });
  assert.deepStrictEqual(r.fields, { artist: 'A' });
});

test('cleared fields are listed', () => {
  I18N.setLang('da');
  const r = SAVE.multiValues({ comment: { on: true, value: '  ' } });
  assert.deepStrictEqual(r.fields, { comment: '' });
  assert.deepStrictEqual(r.cleared, ['Kommentar']);
});

test('confirm text', () => {
  I18N.setLang('da');
  assert.strictEqual(SAVE.confirmText(3, ['Kommentar']), 'Gem i 3 filer?\nDisse felter bliver ryddet: Kommentar');
  assert.strictEqual(SAVE.confirmText(1, []), 'Gem i 1 filer?');
});

test('done text', () => {
  I18N.setLang('da');
  assert.strictEqual(SAVE.doneText('Multi-fil-tag-editor', 2, 1, 1),
    'Multi-fil-tag-editor: gemt i 2 filer, 1 fejl, 1 sprunget over (filtype)');
  assert.strictEqual(SAVE.doneText('Multi-fil-tag-editor', 2, 0, 0), 'Multi-fil-tag-editor: gemt i 2 filer, 0 fejl');
});

test('save is refused while scanning', () => {
  assert.strictEqual(SAVE.canStartBatch({ scanning: true, writing: false }), false);
  assert.strictEqual(SAVE.canStartBatch({ scanning: false, writing: true }), false);
  assert.strictEqual(SAVE.canStartBatch({ scanning: false, writing: false }), true);
});

test('a scan started while the confirm is open stops the save', async () => {
  const a = tr({ name: 'a', checked: true });
  const state = { items: [a], sel: new Set(), scanning: false, writing: false };
  const calls = [];
  const ui = {
    info: async (text) => calls.push(['info', text]),
    confirm: async () => { state.scanning = true; return true; }, // F5 pressed meanwhile
    write: async () => calls.push(['write']),
  };
  await SAVE.save(state, { artist: { on: true, value: 'X' } }, ui);
  assert.ok(!calls.some((c) => c[0] === 'write'), 'nothing may be written');
});

test('the save writes the targets after Ja', async () => {
  const a = tr({ name: 'a', checked: true }), b = tr({ name: 'b' });
  const state = { items: [a, b], sel: new Set(), scanning: false, writing: false };
  let written = null;
  await SAVE.save(state, { artist: { on: true, value: ' X ' } }, {
    info: async () => {}, confirm: async () => true, write: async (items) => { written = items; },
  });
  assert.deepStrictEqual(written, [{ path: a.path, values: { artist: 'X' }, cover: null }]);
});

test('Enter answers with the focused button', () => {
  const DIALOG_KEYS = require('./dialog.js');
  assert.strictEqual(DIALOG_KEYS.keyAnswer('Enter', 1, 2), 1); // "Nej" has focus
  assert.strictEqual(DIALOG_KEYS.keyAnswer('Enter', -1, 2), 0);
  assert.strictEqual(DIALOG_KEYS.keyAnswer('Escape', 0, 2), 1);
  assert.strictEqual(DIALOG_KEYS.keyAnswer('F5', 0, 2), null);
});

test('the window cannot close while saving', () => {
  assert.strictEqual(SAVE.canClose({ writing: true }), false);
  assert.strictEqual(SAVE.canClose({ writing: false }), true);
});
