'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

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
