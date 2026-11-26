'use strict';
const test = require('node:test');
const assert = require('node:assert');
const I18N = require('./strings.js');

test('t translates Danish source texts', () => {
  I18N.setLang('en');
  assert.strictEqual(I18N.t('&Filer'), '&File');
  assert.strictEqual(I18N.t('Mapper:'), 'Folders:');
  I18N.setLang('da');
  assert.strictEqual(I18N.t('&Filer'), '&Filer');
});

test('unknown texts fall back to the Danish source', () => {
  I18N.setLang('de');
  assert.strictEqual(I18N.t('Findes ikke i tabellen'), 'Findes ikke i tabellen');
});

test('t fills %d and %s in order', () => {
  I18N.setLang('da');
  assert.strictEqual(I18N.t('%d markeret, %s', 3, 'x'), '3 markeret, x');
  assert.strictEqual(I18N.t('%.2d:%.2d', 5, 7), '05:07');
});

test('label strips the accelerator', () => {
  assert.strictEqual(I18N.label('Vær&ktøjer'), 'Værktøjer');
  assert.strictEqual(I18N.label('A && B'), 'A & B');
  assert.strictEqual(I18N.mnemonic('Vær&ktøjer'), 'k');
});

test('effectiveLanguage follows 1.2', () => {
  assert.strictEqual(I18N.effectiveLanguage('', 'nb-NO'), 'da');
  assert.strictEqual(I18N.effectiveLanguage('', 'pt-BR'), 'en');
  assert.strictEqual(I18N.effectiveLanguage('sv', 'da-DK'), 'sv');
  assert.strictEqual(I18N.effectiveLanguage('', 'de-AT'), 'de');
});
