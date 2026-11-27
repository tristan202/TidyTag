// The rename settings dialogs from tooldialogs.pas: EditRenameWords (word replacements and
// keep-case words), EditMask (the mask editor) and EditRenameActions (rename actions).
(function () {
  'use strict';
  const { t, label } = I18N;
  const RS = { ...MENUDATA.rs, ...MENUDATA.unitRs.tooldialogs };
  const esc = FORMS.esc;
  const okCancel = () => `<div class="modal-buttons"><button class="btn primary" data-ok>${esc(label(t('OK')))}</button>
    <button class="btn" data-cancel>${esc(label(t('Annuller')))}</button></div>`;

  /** A modal with OK/Annuller: collect(el) gives the answer (undefined keeps it open). */
  function dialog(title, body, collect, cls) {
    return new Promise((resolve) => {
      const done = (v) => { m.close(); resolve(v); };
      const ok = async () => { const v = await collect(m.el); if (v !== undefined) done(v); };
      const m = FORMS.modal(`<h2>${esc(title)}</h2>${body}${okCancel()}`, { cls, onEscape: () => done(null), onEnter: ok });
      m.el.querySelector('[data-ok]').addEventListener('click', ok);
      m.el.querySelector('[data-cancel]').addEventListener('click', () => done(null));
      m.el.querySelector('input, textarea')?.focus();
    });
  }

  // from: EditRenameWords — the grid gets 10 empty rows for new replacements
  function words(w) {
    const rows = w.from.map((f, i) => [f, w.to[i] ?? '']);
    for (let i = 0; i < 10; i++) rows.push(['', '']);
    return dialog(t(RS.rsOrdudskiftninger), `<p class="lbl">${esc(t(RS.rsErstatTekst))}</p>
      <div class="grid-box"><table class="edit-grid"><thead><tr><th>${esc(t(RS.rsErstat))}</th><th>${esc(t(RS.rsMed))}</th></tr></thead>
      <tbody>${rows.map(([f, to]) => `<tr><td><input class="input" data-from value="${esc(f)}" spellcheck="false"></td>
        <td><input class="input" data-to value="${esc(to)}" spellcheck="false"></td></tr>`).join('')}</tbody></table></div>
      <p class="lbl">${esc(t(RS.rsFasteOrd))}</p><textarea class="input words-memo" spellcheck="false">${esc(w.keep.join('\n'))}</textarea>
      <p class="notes">${esc(t(RS.rsOrdHjaelp))}</p>`,
    (el) => {
      const out = { from: [], to: [], keep: [] };
      el.querySelectorAll('tbody tr').forEach((tr) => {
        const f = tr.querySelector('[data-from]').value;
        if (f !== '') { out.from.push(f); out.to.push(tr.querySelector('[data-to]').value); }
      });
      out.keep = el.querySelector('textarea').value.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
      return out;
    }, 'form wide words-dialog');
  }

  // from: EditMask — preview(mask) gives the example; `saved` is [SavedRenameMasks], kept even on
  // Annuller. Resolves with { mask (null on Annuller), saved }.
  function mask(title, current, vars, preview, saved) {
    let list = saved.slice();
    const buttons = vars.map((v) => [v.slice(0, v.indexOf('|')), v.slice(v.indexOf('|') + 1)])
      .filter(([code]) => code && code !== '-' && !code.includes(' '))
      .map(([code, cap]) => `<button class="btn small" data-code="${esc(code)}">${esc(cap)} (${esc(code)})</button>`).join('');
    return new Promise((resolve) => {
      const done = (m2) => { m.close(); resolve({ mask: m2, saved: list }); };
      const m = FORMS.modal(`<h2>${esc(title)}</h2>
        <div class="form-grid"><span class="lbl">${esc(t(RS.rsMaske))}</span><input class="input grow" name="mask" spellcheck="false" value="${esc(current)}">
          <span class="lbl">${esc(t(RS.rsEksempelColon))}</span><b data-example></b></div>
        <fieldset class="radio-group"><legend>${esc(t(RS.rsVariabler))}</legend><div class="var-buttons">${buttons}</div></fieldset>
        <p class="lbl">${esc(t(RS.rsGemteMasker))}</p>
        <div class="saved-masks"><select size="6" name="saved"></select>
          <div class="btn-col"><button class="btn" data-save>${esc(label(t(RS.rsGemMasken)))}</button>
          <button class="btn" data-remove>${esc(label(t(RS.rsFjern)))}</button></div></div>${okCancel()}`,
      { cls: 'form wide mask-editor', onEscape: () => done(null), onEnter: () => done(input.value) });
      const q = (s) => m.el.querySelector(s);
      const input = q('[name="mask"]');
      const fill = () => { q('[name="saved"]').innerHTML = list.map((x) => `<option>${esc(x)}</option>`).join(''); };
      let seq = 0;
      const example = async () => { const n = ++seq; const s = await preview(input.value); if (n === seq) q('[data-example]').textContent = s; };
      input.addEventListener('input', example);
      m.el.addEventListener('click', (e) => {
        const b = e.target.closest('[data-code]');
        if (b) { input.setRangeText(b.dataset.code, input.selectionStart, input.selectionEnd, 'end'); input.focus(); example(); }
        if (e.target.closest('[data-save]') && input.value.trim() && !list.includes(input.value)) { list.push(input.value); fill(); }
        if (e.target.closest('[data-remove]')) { const i = q('[name="saved"]').selectedIndex; if (i >= 0) { list.splice(i, 1); fill(); } }
        if (e.target.closest('[data-ok]')) done(input.value);
        if (e.target.closest('[data-cancel]')) done(null);
      });
      q('[name="saved"]').addEventListener('dblclick', (e) => {
        const i = e.currentTarget.selectedIndex;
        if (i >= 0) { input.value = list[i]; example(); }
      });
      fill();
      example();
      input.focus();
    });
  }

  // from: EditRenameActions — Tilføj starts from the main window's current file mask
  function actions(list, currentFileMask) {
    const items = list.map((a) => ({ ...a }));
    let cur = items.length ? 0 : -1;
    return new Promise((resolve) => {
      const done = (v) => { m.close(); resolve(v); };
      const m = FORMS.modal(`<h2>${esc(t(RS.rsOmdoebningshandlinger))}</h2>
        <div class="actions-edit"><div class="actions-left"><span class="lbl">${esc(t(RS.rsHandlinger))}</span>
            <select size="10" name="list"></select>
            <div class="frow"><button class="btn" data-add>${esc(label(t(RS.rsTilfoej)))}</button>
              <button class="btn" data-remove>${esc(label(t(RS.rsFjern)))}</button></div></div>
          <div class="actions-right">
            <span class="lbl">${esc(t(RS.rsNavn))}</span><input class="input" name="name" spellcheck="false">
            <label class="chk-label"><input type="checkbox" name="useFile"> ${esc(t(RS.rsFilnavnsmaske))}</label>
            <input class="input" name="file" spellcheck="false">
            <label class="chk-label"><input type="checkbox" name="useFolder"> ${esc(t(RS.rsMappemaske))}</label>
            <input class="input" name="folder" spellcheck="false">
            <p class="notes">${esc(t(RS.rsHandlingHjaelp))}</p></div></div>${okCancel()}`,
      { cls: 'form wide actions-dialog', onEscape: () => done(null), onEnter: () => ok() });
      const q = (s) => m.el.querySelector(s);
      let loading = false;
      // from: TActionsEditor.Store / Load
      function store() {
        if (cur < 0 || cur >= items.length) return;
        const it = items[cur];
        it.name = q('[name="name"]').value.trim();
        it.fileMask = q('[name="useFile"]').checked ? q('[name="file"]').value.trim() : '';
        it.folderMask = q('[name="useFolder"]').checked ? q('[name="folder"]').value.trim() : '';
        if (it.name) q('[name="list"]').options[cur].textContent = it.name;
      }
      function load() {
        loading = true;
        const on = cur >= 0 && cur < items.length;
        for (const n of ['name', 'useFile', 'useFolder']) q(`[name="${n}"]`).disabled = !on;
        const it = on ? items[cur] : { name: '', fileMask: '', folderMask: '' };
        q('[name="name"]').value = it.name;
        q('[name="useFile"]').checked = !!it.fileMask;
        q('[name="file"]').value = it.fileMask;
        q('[name="useFolder"]').checked = !!it.folderMask;
        q('[name="folder"]').value = it.folderMask;
        q('[name="file"]').disabled = !on || !q('[name="useFile"]').checked;
        q('[name="folder"]').disabled = !on || !q('[name="useFolder"]').checked;
        q('[name="list"]').selectedIndex = cur;
        loading = false;
      }
      const fill = () => { q('[name="list"]').innerHTML = items.map((a) => `<option>${esc(a.name)}</option>`).join(''); };
      function ok() {
        store();
        // every action needs a name and at least one mask
        const bad = items.findIndex((a) => !a.name || (!a.fileMask && !a.folderMask));
        if (bad >= 0) {
          cur = bad;
          load();
          DIALOG.info(t(RS.rsGivHandlingenEtNavn));
          return;
        }
        done(items);
      }
      m.el.addEventListener('input', () => { if (!loading) store(); });
      m.el.addEventListener('change', (e) => {
        if (e.target.name === 'list') { store(); cur = e.target.selectedIndex; load(); return; }
        if (loading) return;
        store();
        q('[name="file"]').disabled = !q('[name="useFile"]').checked;
        q('[name="folder"]').disabled = !q('[name="useFolder"]').checked;
      });
      m.el.addEventListener('click', (e) => {
        if (e.target.closest('[data-add]')) {
          store();
          items.push({ name: t(RS.rsNyHandling), fileMask: currentFileMask, folderMask: '' });
          fill();
          cur = items.length - 1;
          load();
          q('[name="name"]').select();
        } else if (e.target.closest('[data-remove]') && cur >= 0) {
          items.splice(cur, 1);
          fill();
          cur = Math.min(cur, items.length - 1);
          load();
        } else if (e.target.closest('[data-ok]')) ok();
        else if (e.target.closest('[data-cancel]')) done(null);
      });
      fill();
      load();
    });
  }

  window.RENAMEEDIT = { words, mask, actions };
})();
