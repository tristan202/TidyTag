'use strict';
const test = require('node:test');
const assert = require('node:assert');
const M = require('./multieditor.js');

const tr = (path, fields) => ({ path, fields });

test('multi editor writes only ticked fields', () => {
  const ts = [tr('C:/a/1.mp3', { artist: 'A', album: 'X' }), tr('C:/a/2.mp3', { artist: 'B', album: 'Y' })];
  const rows = [{ key: 'artist', on: true, value: ' Ny ' }, { key: 'album', on: false, value: '' }];
  const items = M.buildItems(ts, rows, null);
  assert.deepStrictEqual(items, [
    { path: 'C:/a/1.mp3', values: { artist: 'Ny' }, cover: null, pictures: null, removeCovers: false },
    { path: 'C:/a/2.mp3', values: { artist: 'Ny' }, cover: null, pictures: null, removeCovers: false },
  ]);
});

test('multi editor replaces or removes covers', () => {
  const ts = [tr('C:/a/1.mp3', {})];
  const rep = M.buildItems(ts, [], { mode: 'replace', mime: 'image/png', data: 'QUJD' })[0];
  assert.deepStrictEqual(rep.pictures, [{ picType: 3, mime: 'image/png', description: '', data: 'QUJD' }]);
  assert.strictEqual(M.buildItems(ts, [], { mode: 'remove' })[0].removeCovers, true);
});

test('common values and the fields that would be cleared', () => {
  const ts = [tr('1', { artist: 'A', album: 'X' }), tr('2', { artist: 'A', album: 'Y' })];
  assert.deepStrictEqual(M.commonValue(ts, 'artist'), { value: 'A', same: true });
  assert.deepStrictEqual(M.commonValue(ts, 'album'), { value: '', same: false });
  assert.deepStrictEqual(M.clearedKeys([{ key: 'artist', on: true, value: ' ' }, { key: 'album', on: false, value: '' }]), ['artist']);
});
