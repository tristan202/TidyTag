// The genre list dialog (EditGenreList, tooldialogs.pas): which standard ID3 genres the lists
// show, and the user's own genres. The pure parts run under node --test.
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.GENRES = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  const unquote = (s) => (s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"' ? s.slice(1, -1) : s);
  // WriteList: Item<n>, quoted so leading/trailing spaces survive
  const rows = (list) => list.map((v, i) => ['Item' + i, `"${v}"`]);
  const toIni = (hidden, custom) => ({ HiddenGenres: rows(hidden), CustomGenres: rows(custom) });
  // ReadList: the values in file order, whatever the key
  const fromIni = (hiddenRows, customRows) => ({ hidden: hiddenRows.map(([, v]) => unquote(v)), custom: customRows.map(([, v]) => unquote(v)) });
  const customFromMemo = (text) => text.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  // the standard genres sorted (case-insensitive), unchecked when hidden
  const checkRows = (standard, hidden) => standard.slice()
    .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }))
    .map((name) => ({ name, checked: !hidden.some((h) => h.toLowerCase() === name.toLowerCase()) }));

  /** The dialog; resolves to { hidden, custom } for OK, null for Annuller. */
  function open(standard, hidden, custom) {
    const { t, label } = I18N;
    const U = MENUDATA.unitRs.tooldialogs;
    const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
    const list = checkRows(standard, hidden);
    return new Promise((resolve) => {
      const m = FORMS.modal(`<h2>${esc(t(U.rsGenrelisteTitel))}</h2>
        <div class="genres">
          <div><div class="lbl">${esc(t(U.rsStandardgenrer))}</div>
            <div class="genre-list">${list.map((g, i) => `<label class="chk-label"><input type="checkbox" data-g="${i}"${g.checked ? ' checked' : ''}><span>${esc(g.name)}</span></label>`).join('')}</div>
            <div class="frow"><button class="btn" data-all>${esc(label(t(U.rsAlle)))}</button><button class="btn" data-none>${esc(label(t(U.rsIngen)))}</button></div></div>
          <div><div class="lbl">${esc(t(U.rsEgneGenrer))}</div><textarea class="input genre-memo" spellcheck="false">${esc(custom.join('\n'))}</textarea></div>
        </div>
        <div class="modal-buttons"><span class="grow"></span><button class="btn primary" data-ok>${esc(label(t('OK')))}</button>
          <button class="btn" data-cancel>${esc(label(t('Annuller')))}</button></div>`,
      { cls: 'form genre-form', onEscape: () => done(null), onEnter: () => ok() });
      const boxes = () => [...m.el.querySelectorAll('[data-g]')];
      const done = (v) => { m.close(); resolve(v); };
      const ok = () => done({
        hidden: boxes().filter((b) => !b.checked).map((b) => list[Number(b.dataset.g)].name),
        custom: customFromMemo(m.el.querySelector('.genre-memo').value),
      });
      m.el.addEventListener('click', (e) => {
        if (e.target.closest('[data-all]')) boxes().forEach((b) => { b.checked = true; });
        else if (e.target.closest('[data-none]')) boxes().forEach((b) => { b.checked = false; });
        else if (e.target.closest('[data-ok]')) ok();
        else if (e.target.closest('[data-cancel]')) done(null);
      });
    });
  }

  return { toIni, fromIni, customFromMemo, checkRows, open };
});
