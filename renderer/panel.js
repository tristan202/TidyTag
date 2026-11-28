// The tool panel's three tabs, laid out like 1.2's PageTools: the masks and options are shown
// and saved with 1.2's keys, with a live preview of the focused file; the actions are the
// renderer's (hooks).
(function () {
  'use strict';
  const { t } = I18N;
  const RS = MENUDATA.rs;
  // from: mainform.pas
  const DEFAULT_RENAME_MASKS = ['%1 - %2', '%6 - %2', '%6 - %1 - %2', '%1 - %3 - %6 - %2', '%1\\%3\\%6 - %2', '%aa\\%4 - %3\\%6 - %2'];
  const DEFAULT_F2T_MASKS = ['%1 - %2', '%6 - %2', '%6 - %1 - %2', '%6. %2', '%6 %1 - %2', '%1\\%3\\%6 - %2', '%1\\%4 - %3\\%6 - %2'];
  const RENAME_CODES = ['%1', '%2', '%3', '%4', '%5', '%6', '%7', '%8', '%9', '%0', '%t', '%b', '%#', '%aa', '%co'];
  const F2T_CODES = ['%1', '%2', '%3', '%4', '%5', '%6', '%#', '%9', '%b', '%aa', '%cp', '%co', '%lb', '%d'];
  // TCaseMode = (cmNone, cmTitle, cmSentence, cmLower, cmUpper); radios in 1.2's order
  const RADIOS = [['små bogstaver', 3], ['STORE BOGSTAVER', 4], ['Hvert Ord Med Stort', 1], ['Første bogstav stort', 2]];

  let S = null; // settings snapshot: { section: { key: value } } (lower-case names)
  let body = null;
  let tab = 0;

  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const get = (sec, key, def = '') => S[sec.toLowerCase()]?.[key.toLowerCase()] ?? def;
  const bool = (sec, key, def) => { const v = get(sec, key, null); return v === null ? def : !['0', 'false', ''].includes(String(v).toLowerCase()); };
  function save(sec, key, value) {
    (S[sec.toLowerCase()] ||= {})[key.toLowerCase()] = String(value);
    API.settingsSet(sec, key, value);
  }

  // from: MaskVarCaption — 'code|caption' entries
  function varCaption(code) {
    for (const v of [...MENUDATA.renameVars, ...MENUDATA.f2tVars]) {
      const s = t(v);
      if (v.startsWith(code + '|')) return s.slice(s.indexOf('|') + 1);
    }
    return '';
  }

  function masks(section, defaults) {
    const list = [];
    for (let i = 0; i < 15; i++) { const m = get(section, 'Mask' + i); if (m) list.push(m); }
    return list.length ? list : defaults;
  }

  function varsTable(codes) {
    const cells = [];
    for (let c = 0; c < Math.ceil(codes.length / 5); c++) {
      const col = codes.slice(c * 5, c * 5 + 5);
      while (col.length < 5) col.push('');
      for (const code of col) cells.push(`<span class="code">${esc(code)}</span>`);
      for (const code of col) cells.push(`<span class="cap">${esc(code ? varCaption(code) : '')}</span>`);
    }
    return `<div class="vars">${cells.join('')}</div>`;
  }

  const check = (id, text, on, disabled = false) =>
    `<label class="chk-label"><input type="checkbox" id="${id}"${on ? ' checked' : ''}${disabled ? ' disabled' : ''} /><span>${esc(t(text))}</span></label>`;

  function caseBlock(prefix, mode) {
    return `${check(prefix + '-case', 'Skift versaler:', mode !== 0)}
      <div class="case-radios${mode === 0 ? ' off' : ''}" id="${prefix}-radios">${RADIOS.map(([text, m]) =>
        `<label class="chk-label"><input type="radio" name="${prefix}-mode" value="${m}"${(mode || 1) === m ? ' checked' : ''} /><span>${esc(t(text))}</span></label>`).join('')}</div>`;
  }

  function maskRow(prefix, section, defaults, resultLabel) {
    return `<div class="frow"><span class="lbl">${esc(t('Filnavnsmaske:'))}</span>
        <input class="input grow" id="${prefix}-mask" list="${prefix}-masks" spellcheck="false" value="${esc(get(section, 'Mask', defaults[0]) || defaults[0])}" />
        <datalist id="${prefix}-masks">${masks(prefix === 'rn' ? 'RenameMasks' : 'FileToTagMasks', defaults).map((m) => `<option value="${esc(m)}"></option>`).join('')}</datalist>
        <button class="btn" id="${prefix}-vars">${esc(t('Variabler ▾'))}</button></div>
      <div class="frow"><span class="lbl">${esc(t(resultLabel))}</span><div class="preview" id="${prefix}-preview"></div></div>`;
  }

  function renameTab() {
    const mode = Number(get('Rename', 'Case', 0)) || 0;
    return `<div class="tool-grid"><div class="tool-left">
        ${maskRow('rn', 'Rename', DEFAULT_RENAME_MASKS, 'Eksempel på resultat:')}
        <div class="chk-row">${check('rn-us', 'Erstat mellemrum med _', bool('Rename', 'Underscores', false))}
          ${check('rn-pad', 'Spornummer med 2 cifre (%6)', bool('Rename', 'PadTrack', true))}</div>
        ${caseBlock('rn', mode)}
      </div><div class="tool-right">${varsTable(RENAME_CODES)}<div class="notes">${esc(t(RS.rsRenameNoter))}</div>
        <div class="btn-row"><button class="btn" id="rn-show">${esc(t('Forhåndsvis...'))}</button>
          <button class="btn primary" id="rn-do">${esc(t('Omdøb'))}</button>
          <button class="btn" id="rn-undo"${hooks.canUndo?.() ? '' : ' disabled'}>${esc(t('Fortryd'))}</button></div></div></div>`;
  }

  // 1.2's six inline fields (lfm captions); the values stay while other tabs are shown
  const MULTI = [['artist', 'Kunstner'], ['album', 'Album'], ['albumArtist', 'Albumkunstner'], ['year', 'År'],
    ['genre', 'Genre'], ['comment', 'Kommentar']];
  const multi = Object.fromEntries(MULTI.map(([k]) => [k, { on: false, value: '' }]));
  let genres = [];
  let hooks = {};

  function multiTab() {
    return `<div class="tool-grid"><div class="tool-left"><div class="multi-grid">${MULTI.map(([k, caption]) =>
        `<label class="chk-label"><input type="checkbox" data-mk="${k}"${multi[k].on ? ' checked' : ''} /><span>${esc(t(caption))}</span></label>
         <input class="input" data-mv="${k}" spellcheck="false" value="${esc(multi[k].value)}"${k === 'genre' ? ' list="genre-list"' : ''} />`).join('')}</div>
        <datalist id="genre-list">${genres.map((g) => `<option value="${esc(g)}"></option>`).join('')}</datalist></div>
      <div class="tool-right"><div class="notes">${esc(t(RS.rsKunFelterMedFluebenBliver))}</div>
        <div class="btn-row"><button class="btn primary" id="multi-save">${esc(t('Gem tags'))}</button>
          <button class="btn" id="multi-copy" title="${esc(t('Udfyld felterne med værdierne fra den fokuserede fil'))}">${esc(t('Kopiér fra fil'))}</button>
          <button class="btn" id="multi-all">${esc(t('Alle felter...'))}</button></div></div></div>`;
  }

  // from: MultiValueChange, ButtonMultiCopyClick, ButtonMultiSaveClick
  function wireMulti() {
    body.querySelectorAll('[data-mk]').forEach((c) => c.addEventListener('change', () => { multi[c.dataset.mk].on = c.checked; }));
    body.querySelectorAll('[data-mv]').forEach((i) => i.addEventListener('input', () => {
      const k = i.dataset.mv;
      multi[k].value = i.value;
      multi[k].on = true; // typing ticks the field
      body.querySelector(`[data-mk="${k}"]`).checked = true;
    }));
    body.querySelector('#multi-copy').addEventListener('click', () => {
      const fields = hooks.focusedFields?.();
      if (!fields) return;
      for (const [k] of MULTI) multi[k].value = fields[k] || '';
      render();
    });
    body.querySelector('#multi-save').addEventListener('click', () => hooks.saveMulti?.(multi));
    body.querySelector('#multi-all').addEventListener('click', () => hooks.openMulti?.());
  }

  function f2tTab() {
    const mode = Number(get('FileToTag', 'Case', 0)) || 0;
    return `<div class="tool-grid"><div class="tool-left">
        ${maskRow('ft', 'FileToTag', DEFAULT_F2T_MASKS, 'Eksempel på filnavn:')}
        <div class="chk-row">${check('ft-us', 'Erstat _ med mellemrum', bool('FileToTag', 'Underscores', true))}</div>
        ${caseBlock('ft', mode)}
      </div><div class="tool-right">${varsTable(F2T_CODES)}<div class="notes" title="${esc(t(RS.rsF2TFiltypeHint))}">${esc(t(RS.rsF2TNoter))}</div>
        <div class="btn-row"><button class="btn" id="ft-show">${esc(t('Forhåndsvis...'))}</button>
          <button class="btn primary" id="ft-do">${esc(t('Skriv tags'))}</button></div></div></div>`;
  }

  // the tab's options: from the controls when the tab is shown, else as saved
  function inline(prefix) {
    const section = prefix === 'rn' ? 'Rename' : 'FileToTag';
    const $ = (id) => body?.querySelector('#' + id);
    if (!$(prefix + '-mask')) {
      return { mask: get(section, 'Mask', (prefix === 'rn' ? DEFAULT_RENAME_MASKS : DEFAULT_F2T_MASKS)[0]),
        caseMode: Number(get(section, 'Case', 0)) || 0, underscores: bool(section, 'Underscores', prefix !== 'rn'),
        padTrack: bool(section, 'PadTrack', true) };
    }
    const m = body.querySelector(`input[name="${prefix}-mode"]:checked`);
    return { mask: $(prefix + '-mask').value, caseMode: $(prefix + '-case').checked && m ? Number(m.value) : 0,
      underscores: $(prefix + '-us').checked, padTrack: prefix === 'rn' ? $('rn-pad').checked : true };
  }

  // from: SaveInlineOptions — before every action, so the dialogs open with the same options
  function saveInline() {
    if (tab === 0) {
      const o = inline('rn');
      save('Rename', 'Mask', o.mask); save('Rename', 'Case', o.caseMode);
      save('Rename', 'Underscores', o.underscores ? 1 : 0); save('Rename', 'PadTrack', o.padTrack ? 1 : 0);
    }
    if (tab === 2) {
      const o = inline('ft');
      save('FileToTag', 'Mask', o.mask); save('FileToTag', 'Case', o.caseMode); save('FileToTag', 'Underscores', o.underscores ? 1 : 0);
    }
  }

  // from: UpdateInlinePreviews — the mask with field names; the focused file's result as tooltip
  let previewSeq = 0;
  async function updatePreview() {
    const prefix = tab === 0 ? 'rn' : tab === 2 ? 'ft' : '';
    const el = prefix && body.querySelector('#' + prefix + '-preview');
    if (!el) return;
    const o = inline(prefix);
    const tr = hooks.previewTrack?.();
    const ext = tr ? (/\.[^.\\/]*$/.exec(tr.path) || [''])[0] : '.mp3';
    const vars = (prefix === 'rn' ? MENUDATA.renameVars : MENUDATA.f2tVars).map((v) => t(v));
    el.textContent = RENAMETOOLS.maskTemplate(o.mask, ext, vars, prefix === 'rn' && o.underscores ? '_' : ' ');
    if (!tr) { el.title = ''; return; }
    const seq = ++previewSeq;
    let s;
    if (prefix === 'rn') {
      const [row] = await API.planRename([tr], o.mask, o);
      const dir = tr.path.slice(0, tr.path.lastIndexOf('\\') + 1);
      if (row.status === 'Missing') s = t(RS.rsMangler) + row.detail.split(', ').map((x) => t(x)).join(', ');
      else if (!row.newName) s = t(RS.rsUgyldigMaske);
      else s = row.newName.toLowerCase().startsWith(dir.toLowerCase()) ? row.newName.slice(dir.length) : row.newName;
    } else {
      const [m] = await API.matchFileNames([tr.path], o.mask, o.underscores, o.caseMode);
      s = m.ok ? m.used.map((k) => `${t(MENUDATA.fieldCaptions[k])}: ${m.values[k]}`).join('   ') : t(RS.rsFilnavnetPasserIkkeTilMasken);
    }
    if (seq === previewSeq) el.title = `${tr.fileName}  →  ${s}`;
  }

  // from: ButtonVarsClick / VarItemClick — examples replace the mask, codes go in at the cursor
  function varsMenu(prefix, btn) {
    const input = body.querySelector('#' + prefix + '-mask');
    const items = [];
    if (prefix === 'rn' && hooks.maskEditor) items.push({ text: t(RS.rsMaskeEditorMenu), run: () => hooks.maskEditor() }, '-');
    for (const v of (prefix === 'rn' ? MENUDATA.renameVars : MENUDATA.f2tVars)) {
      const bar = v.indexOf('|');
      const code = v.slice(0, bar), cap = t(v).slice(t(v).indexOf('|') + 1);
      if (code === '-') { items.push('-'); continue; }
      items.push({ text: code, key: cap, run: () => {
        if (cap.includes(t(RS.rsEksempel))) input.value = code;
        else input.setRangeText(code, input.selectionStart, input.selectionEnd, 'end');
        input.focus();
        updatePreview();
      } });
    }
    const r = btn.getBoundingClientRect();
    MENU.popup(items, r.left, r.bottom + 2);
  }

  let previewTimer = 0;
  const schedulePreview = () => { clearTimeout(previewTimer); previewTimer = setTimeout(updatePreview, 150); };

  // the options are saved as 1.2 does (SaveInlineOptions)
  function wire(prefix, section) {
    const $ = (id) => body.querySelector('#' + id);
    $(prefix + '-mask')?.addEventListener('change', (e) => save(section, 'Mask', e.target.value));
    $(prefix + '-mask')?.addEventListener('input', schedulePreview);
    body.querySelector('.tool-left')?.addEventListener('change', schedulePreview);
    $(prefix + '-vars')?.addEventListener('click', (e) => varsMenu(prefix, e.currentTarget));
    const act = (id, hook) => $(id)?.addEventListener('click', () => { saveInline(); hooks[hook]?.(); });
    act(prefix + '-show', prefix === 'rn' ? 'renamePreview' : 'f2tPreview');
    act(prefix + '-do', prefix === 'rn' ? 'renameDo' : 'f2tDo');
    act('rn-undo', 'undo');
    $(prefix + '-us')?.addEventListener('change', (e) => save(section, 'Underscores', e.target.checked ? 1 : 0));
    $(prefix + '-pad')?.addEventListener('change', (e) => save(section, 'PadTrack', e.target.checked ? 1 : 0));
    const saveCase = () => {
      const on = $(prefix + '-case').checked;
      $(prefix + '-radios').classList.toggle('off', !on);
      const m = body.querySelector(`input[name="${prefix}-mode"]:checked`);
      save(section, 'Case', on && m ? m.value : 0);
    };
    $(prefix + '-case')?.addEventListener('change', saveCase);
    body.querySelectorAll(`input[name="${prefix}-mode"]`).forEach((r) => r.addEventListener('change', () => {
      $(prefix + '-case').checked = true;
      saveCase();
    }));
  }

  function render() {
    document.querySelectorAll('#tool-tabs .tab').forEach((b) => b.classList.toggle('on', Number(b.dataset.tab) === tab));
    body.innerHTML = [renameTab, multiTab, f2tTab][tab]();
    if (tab === 0) wire('rn', 'Rename');
    if (tab === 1) wireMulti();
    if (tab === 2) wire('ft', 'FileToTag');
    updatePreview();
  }

  window.PANEL = {
    init(settings, h = {}) {
      S = settings;
      hooks = h;
      API.genreList().then((g) => { genres = g; if (tab === 1) render(); });
      body = document.getElementById('tool-body');
      tab = Math.min(2, Math.max(0, Number(get('View', 'ToolTab', 0)) || 0));
      document.querySelectorAll('#tool-tabs .tab').forEach((b) => b.addEventListener('click', () => this.show(Number(b.dataset.tab))));
      render();
    },
    show(i) {
      tab = i;
      save('View', 'ToolTab', i);
      render();
    },
    render,
    inline,
    saveInline,
    updatePreview: schedulePreview,
    /** after a dialog changed masks/options, or the undo log changed */
    reload: (settings) => { if (settings) S = settings; render(); },
    // from: RefreshGenreCombos
    refreshGenres() { API.genreList().then((g) => { genres = g; if (tab === 1) render(); }); },
  };
})();
