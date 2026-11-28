'use strict';
const test = require('node:test');
const assert = require('node:assert');
const G = require('./genres.js');

test('genre lists round-trip quoted', () => {
  const ini = G.toIni(['Polka', 'Rock'], [' Rock ', 'Dansktop']);
  assert.deepStrictEqual(ini.HiddenGenres, [['Item0', '"Polka"'], ['Item1', '"Rock"']]);
  assert.deepStrictEqual(ini.CustomGenres, [['Item0', '" Rock "'], ['Item1', '"Dansktop"']]);
  assert.deepStrictEqual(G.fromIni(ini.HiddenGenres, ini.CustomGenres), { hidden: ['Polka', 'Rock'], custom: [' Rock ', 'Dansktop'] });
});

test('own genres come from the memo, one per line, trimmed and without empty lines', () => {
  assert.deepStrictEqual(G.customFromMemo(' Dansktop \r\n\r\nViser\n  '), ['Dansktop', 'Viser']);
});

test('standard genres are sorted and the hidden ones are unchecked', () => {
  const rows = G.checkRows(['Rock', 'blues', 'Pop'], ['pop']);
  assert.deepStrictEqual(rows, [{ name: 'blues', checked: true }, { name: 'Pop', checked: false }, { name: 'Rock', checked: true }]);
});
