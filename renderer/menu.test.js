'use strict';
const test = require('node:test');
const assert = require('node:assert');
const D = require('./menudata.js');
const ICONS = require('./icons.js');

test("MENU has 1.2's top menus", () => {
  assert.deepStrictEqual(D.menus.map((m) => m.text.replace('&', '')),
    ['Filer', 'Rediger', 'Vis', 'Playliste', 'Værktøjer', 'Indstillinger', 'Hjælp']);
});

test("the icon bar has 1.2's order: 22 buttons and 8 separators", () => {
  assert.strictEqual(D.toolbar.length, 30);
  assert.strictEqual(D.toolbar.filter((i) => i === '-').length, 8);
  assert.deepStrictEqual(D.toolbar.slice(0, 4).map((i) => i.ref || i), ['aOpen', 'aRefresh', 'aFind', '-']);
});

test('every toolbar and folder button has an icon', () => {
  for (const i of [...D.toolbar, ...D.folderbar]) {
    if (i === '-') continue;
    const name = D.actions[i.ref].icon;
    assert.ok(ICONS.ICONS[name], `${i.ref}: no icon "${name}"`);
  }
});

test("1.2's 27 columns", () => {
  assert.strictEqual(D.columns.length, 27);
  assert.strictEqual(D.columns[1].caption, 'Filnavn');
});
