'use strict';
const test = require('node:test');
const assert = require('node:assert');
const E = require('./tageditor.js');

test('editor asks before discarding changes', () => {
  const st = E.create(0, 3);
  assert.strictEqual(E.needsQuestion(st, 'close'), false);
  E.setModified(st, true);
  assert.strictEqual(E.needsQuestion(st, 'close'), true);
  assert.strictEqual(E.needsQuestion(st, 'saveNext'), false); // saving first never asks
  E.setModified(st, false);
  assert.strictEqual(E.needsQuestion(st, 'close'), false);
});

test('editor moves within the list', () => {
  assert.deepStrictEqual(E.next(0, 3), { prev: false, next: true });
  assert.deepStrictEqual(E.next(2, 3), { prev: true, next: false });
  assert.deepStrictEqual(E.next(0, 1), { prev: false, next: false });
});

test('editor saves trimmed fields and 1/empty flags', () => {
  const f = E.collectFields({ title: '  A ', genre: ' Rock ', compilation: true, podcast: false, lyrics: 'x\n' });
  assert.deepStrictEqual(f, { title: 'A', genre: 'Rock', compilation: '1', podcast: '', lyrics: 'x' });
  assert.strictEqual(E.isTrueFlag(' Yes '), true);
  assert.strictEqual(E.isTrueFlag('0'), false);
  assert.strictEqual(E.isTrueFlag('2'), true);
});

test('comment and lyrics keep Windows line breaks, as 1.2\'s memo', () => {
  const f = E.collectFields({ comment: 'a\nb', lyrics: 'x\r\ny\nz', title: 't' });
  assert.deepStrictEqual(f, { comment: 'a\r\nb', lyrics: 'x\r\ny\r\nz', title: 't' });
});
