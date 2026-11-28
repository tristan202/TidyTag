'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

test('the tool tabs never give two elements the same id', () => {
  // the preview line was ${prefix}-preview and the button 'ft-preview': the click went to the line
  const src = fs.readFileSync(path.join(__dirname, 'panel.js'), 'utf8');
  const templated = [...src.matchAll(/id="\$\{prefix\}-([\w-]+)"/g)].flatMap((m) => ['rn-' + m[1], 'ft-' + m[1]]);
  const literal = [...src.matchAll(/id="((?:rn|ft)-[\w-]+)"/g)].map((m) => m[1]);
  const all = [...templated, ...literal];
  assert.deepStrictEqual(all.filter((id, i) => all.indexOf(id) !== i), []);
});

test('index.html has the app root', () => {
  const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  assert.match(html, /<div id="app">/);
});

test('dialogs never use the menu bar\'s data-act attribute', () => {
  // menu.js refreshes every [data-act] in the page as a menu action; a dialog button with it broke saving
  const fs = require('node:fs');
  for (const f of ['tageditor.js', 'multieditor.js', 'tracktools.js', 'forms.js', 'covers.js', 'dialog.js']) {
    assert.ok(!/data-act\b/.test(fs.readFileSync(require('node:path').join(__dirname, f), 'utf8')), f);
  }
});
