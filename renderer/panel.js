// The tool panel's three tabs, laid out like 1.2's PageTools. In phase 1 the masks and options
// are shown and saved (same ini keys as 1.2); the actions come in later phases.
(function () {
  'use strict';
  const { t } = I18N;
  const RS = MENUDATA.rs;
  const LATER = 'Kommer i en senere version';
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

  const later = (text, primary) => `<button class="btn${primary ? ' primary' : ''}" disabled title="${esc(t(LATER))}">${esc(t(text))}</button>`;
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
        ${later('Variabler ▾')}</div>
      <div class="frow"><span class="lbl">${esc(t(resultLabel))}</span><div class="preview"></div></div>`;
  }

  function renameTab() {
    const mode = Number(get('Rename', 'Case', 0)) || 0;
    return `<div class="tool-grid"><div class="tool-left">
        ${maskRow('rn', 'Rename', DEFAULT_RENAME_MASKS, 'Eksempel på resultat:')}
        <div class="chk-row">${check('rn-us', 'Erstat mellemrum med _', bool('Rename', 'Underscores', false))}
          ${check('rn-pad', 'Spornummer med 2 cifre (%6)', bool('Rename', 'PadTrack', true))}</div>
        ${caseBlock('rn', mode)}
      </div><div class="tool-right">${varsTable(RENAME_CODES)}<div class="notes">${esc(t(RS.rsRenameNoter))}</div>
        <div class="btn-row">${later('Forhåndsvis...')}${later('Omdøb', true)}${later('Fortryd')}</div></div></div>`;
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
          ${later('Alle felter...')}</div></div></div>`;
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
  }

  function f2tTab() {
    const mode = Number(get('FileToTag', 'Case', 0)) || 0;
    return `<div class="tool-grid"><div class="tool-left">
        ${maskRow('ft', 'FileToTag', DEFAULT_F2T_MASKS, 'Eksempel på filnavn:')}
        <div class="chk-row">${check('ft-us', 'Erstat _ med mellemrum', bool('FileToTag', 'Underscores', true))}</div>
        ${caseBlock('ft', mode)}
      </div><div class="tool-right">${varsTable(F2T_CODES)}<div class="notes" title="${esc(t(RS.rsF2TFiltypeHint))}">${esc(t(RS.rsF2TNoter))}</div>
        <div class="btn-row">${later('Forhåndsvis...')}${later('Skriv tags', true)}</div></div></div>`;
  }

  // the options are saved as 1.2 does (SaveInlineOptions)
  function wire(prefix, section) {
    const $ = (id) => body.querySelector('#' + id);
    $(prefix + '-mask')?.addEventListener('change', (e) => save(section, 'Mask', e.target.value));
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
  };
})();
