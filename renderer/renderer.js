// TidyTag 2, phase 1: wires the window together — settings, language, menus, the folder tree,
// the virtual file list, covers and the status bar. Behaviour follows 1.2's mainform.pas.
(function () {
  'use strict';
  const { t, label } = I18N;
  const RS = MENUDATA.rs;
  const COLS = LIST.COLUMNS;
  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const norm = (p) => p.replace(/[\\/]+$/, '').toLowerCase();

  // ---------- settings (same file and keys as 1.2) ----------
  const SECTIONS = ['Main', 'Editor', 'View', 'Rename', 'FileToTag', 'RenameMasks', 'FileToTagMasks', 'AddressHistory', 'Favorites',
    'Tracks', 'Cover', 'RenameFolder', 'FolderMasks', 'RenameReplace', 'RenameKeepCase', 'RenameActions', 'SavedRenameMasks',
    'Player', 'Playlist', 'Players', 'ExtraPlayers'];
  const S = {};
  async function loadSettings() {
    await Promise.all(SECTIONS.map(async (sec) => {
      const o = {};
      for (const [k, v] of await API.settingsSection(sec)) o[k.toLowerCase()] = v;
      S[sec.toLowerCase()] = o;
    }));
  }
  const get = (sec, key, def = '') => S[sec.toLowerCase()]?.[key.toLowerCase()] ?? def;
  const bool = (sec, key, def) => { const v = get(sec, key, null); return v === null ? def : !['0', 'false', ''].includes(String(v).toLowerCase()); };
  function save(sec, key, value) {
    (S[sec.toLowerCase()] ||= {})[key.toLowerCase()] = String(value);
    API.settingsSet(sec, key, value);
  }
  const list = (sec, n) => Array.from({ length: n }, (_, i) => get(sec, 'Dir' + i)).filter(Boolean);
  function saveList(sec, items) {
    S[sec.toLowerCase()] = Object.fromEntries(items.map((p, i) => ['dir' + i, p]));
    API.settingsWriteSection(sec, items.map((p, i) => ['Dir' + i, p]));
  }

  // ---------- state ----------
  const state = {
    folder: '', scanId: 0, scanning: false, writing: false, busyWrites: 0, batchId: 0, message: '',
    all: [], // every file of the folder: TrackDto + checked (+ hidden); 1.2's FItems
    items: [], // the files shown (FView): what the list, the actions and the status bar use
    filter: { tagType: '', text: '', field: 0, whole: false, matchCase: false },
    sort: { col: 1, desc: false, col2: -1, desc2: false }, // 1.2 starts sorted on the file name
    sel: new Set(), focus: -1, anchor: -1,
    view: { tools: true, folders: true, address: true, filter: true, subfolders: false },
    history: [], favorites: [],
  };
  const widths = COLS.map((c) => c.width);
  const ROW = 24;

  // ---------- texts ----------
  function applyTexts() {
    document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = label(t(el.dataset.i18n)); });
    document.querySelectorAll('[data-icon]').forEach((el) => { el.innerHTML = icon(el.dataset.icon); });
    const sel = $('#lang-select');
    sel.innerHTML = `<option value="">${esc(t(RS.rsAutomatiskWindowsSprog))}</option>` +
      Object.entries(I18N.LANGS).map(([c, n]) => `<option value="${c}">${esc(n)}</option>`).join('');
    sel.value = get('Main', 'Language', '');
    sel.title = t(RS.rsSprogLanguage);
    $('#tagtype').innerHTML = MENUDATA.tagTypes.map((s, i) =>
      `<option>${esc(i === 0 ? t(RS.rsAlleTagtyper) : i === MENUDATA.tagTypes.length - 1 ? t(RS.rsIngenTagsFilter) : s)}</option>`).join('');
    $('#filter-field').innerHTML = [t(RS.rsFilnavn2), ...Object.values(MENUDATA.fieldCaptions).map((c) => t(c)), t(RS.rsAlleFelter)]
      .map((s) => `<option>${esc(s)}</option>`).join('');
  }

  function setLanguage(code) {
    save('Main', 'Language', code);
    I18N.setLang(I18N.effectiveLanguage(code, navigator.language));
    document.documentElement.lang = I18N.lang;
    applyTexts();
    MENU.relabel();
    PANEL.render();
    renderHeader();
    renderRows();
    updateStatus();
  }

  // ---------- panels shown / hidden (Vis menu) ----------
  function applyView() {
    $('#tools').hidden = !state.view.tools;
    $('#folders').hidden = !state.view.folders;
    $('#splitter').hidden = !state.view.folders;
    $('#addressbar').hidden = !state.view.address;
    $('#filterbar').hidden = !state.view.filter;
    MENU.refresh();
  }
  function toggleView(key, sec, iniKey) {
    state.view[key] = !state.view[key];
    save(sec, iniKey, state.view[key] ? 1 : 0);
    applyView();
  }

  // ---------- navigation and scanning ----------
  async function navigate(path, { fromTree = false } = {}) {
    if (!path) return;
    state.folder = path;
    $('#address').value = path;
    API.window().setTitle('TidyTag - ' + path);
    save('Main', 'LastFolder', path);
    // address history: newest first, at most 20 (1.2 reads Dir0..Dir19)
    state.history = [path, ...state.history.filter((p) => norm(p) !== norm(path))].slice(0, 20);
    saveList('AddressHistory', state.history);
    $('#address-history').innerHTML = state.history.map((p) => `<option value="${esc(p)}"></option>`).join('');
    if (!fromTree) TREE.reveal(path);
    showFolderCover(path);
    startScan();
  }

  function startScan() {
    state.scanId += 1;
    state.all = [];
    state.items = [];
    state.sel.clear();
    state.focus = state.anchor = -1;
    state.scanning = true;
    state.message = t('Søger efter filer...');
    $('#list').scrollTop = 0;
    renderRows();
    updateStatus();
    showFileCover();
    API.scanStart(state.folder, state.view.subfolders, state.scanId);
  }

  // the master list is sorted (none in manual order), then the view is built again
  function sortItems() {
    if (state.sort.col >= 0) state.all.sort((a, b) => LIST.compareTracks(a, b, state.sort));
    LISTVIEW.rebuildView(state, FIELD_KEYS);
  }

  API.on('scan-batch', (msg) => {
    if (!LIST.applyBatch(state, msg)) return;
    sortItems();
    renderRows();
    updateStatus();
  });
  API.on('scan-progress', (msg) => {
    if (msg.scanId !== state.scanId) return;
    state.message = t('Læser tags: %d af %d filer...', msg.done, msg.total);
    updateStatus();
  });
  // ---------- saving from the multi tab (1.2's ButtonMultiSaveClick / WriteFieldsBatch) ----------
  let writeWhat = '', writeShowsSkipped = true, writeQuiet = false, writeWaiter = null, writeProgress = null;
  /** Starts one batch command; `call(batchId)` invokes it. Resolves with the write-done message
   *  (null when the batch could not start); onProgress gets each write-progress; quiet: the
   *  caller shows the errors itself. */
  async function startWrite(what, call, { showSkipped = true, onProgress = null, quiet = false } = {}) {
    writeWhat = what;
    writeShowsSkipped = showSkipped;
    writeQuiet = quiet;
    writeProgress = onProgress;
    state.writing = true;
    state.batchId += 1;
    MENU.refresh();
    const done = new Promise((resolve) => { writeWaiter = resolve; });
    try {
      await call(state.batchId);
    } catch (e) {
      state.writing = false;
      writeWaiter = null;
      MENU.refresh();
      await DIALOG.info(String(e));
      return null;
    }
    return done;
  }
  function saveMulti(form) {
    return SAVE.save(state, form, {
      info: (text, title) => DIALOG.info(text, title),
      confirm: (title, text) => DIALOG.confirm(title, text),
      write: (items) => startWrite(t(RS.rsMultiFilTagEditor), (id) => API.writeTagsBatch(items, id)),
    });
  }

  // closing while a file is being written could stop an in-place write halfway
  // single writes outside a batch count too
  const counted = (fn) => async (...args) => {
    state.busyWrites += 1;
    try { return await fn(...args); } finally { state.busyWrites -= 1; }
  };
  for (const k of ['saveTag', 'coverFromTags', 'coverAsFolder', 'resizeFolderCovers', 'writeFile', 'executeRename',
    'undoRename', 'renameOne', 'recycle', 'copyMove', 'savePlaylist']) API[k] = counted(API[k]);
  API.window().onCloseRequested(async (ev) => { // Tauri waits for this before it closes
    const action = SAVE.closeAction(state, TAGEDITOR.isOpen());
    if (action === 'wait') {
      ev.preventDefault();
      DIALOG.info(t('Vent, til gemningen er færdig.'));
    } else if (action === 'ask' && !(await TAGEDITOR.closeQuery())) ev.preventDefault();
  });

  API.on('write-progress', (msg) => {
    if (msg.batchId !== state.batchId) return;
    state.message = t(RS.rsSDAfD, writeWhat, msg.done, msg.total);
    updateStatus();
    writeProgress?.(msg);
  });
  API.on('write-done', (msg) => {
    if (msg.batchId !== state.batchId) return;
    state.writing = false;
    // the files read again replace their rows; ticks and selection stay
    const byPath = new Map(msg.tracks.map((tr) => [tr.path.toLowerCase(), tr]));
    state.all = state.all.map((old) => {
      const tr = byPath.get(old.path.toLowerCase());
      if (!tr) return old;
      tr.checked = old.checked;
      if (state.sel.has(old)) { state.sel.delete(old); state.sel.add(tr); }
      return tr;
    });
    sortItems();
    renderRows();
    state.message = SAVE.doneText(writeWhat, msg.saved, msg.failed, writeShowsSkipped ? msg.skipped : 0);
    updateStatus();
    MENU.refresh();
    showFileCover();
    const waiter = writeWaiter;
    writeWaiter = writeProgress = null;
    waiter?.(msg);
    if (msg.errors.length && !writeQuiet) {
      DIALOG.info(msg.errors.map((e) => `${e.file}: ${t(e.error)}`).join('\n'), t(RS.rsNogleFilerBlevIkkeGemt));
    }
  });

  API.on('scan-done', (msg) => {
    if (msg.scanId !== state.scanId) return;
    state.scanning = false;
    state.message = '';
    if (bool('View', 'AutoFitColumns', false)) autoFit();
    applyPendingSelect(false);
    renderRows();
    selectionChanged();
  });

  // ---------- the virtual file list ----------
  const listEl = $('#list'), headEl = $('#list-head'), rowsEl = $('#list-rows');
  const cellClass = (c) => (c.kind === 'check' ? 'cell chk' : c.numeric ? 'cell num' : 'cell');

  function renderHeader() {
    headEl.innerHTML = COLS.map((c, i) => {
      const sorted = state.sort.col === i;
      const arrow = sorted ? `<span class="arrow">${state.sort.desc ? '▼' : '▲'}</span>` : '';
      return `<div class="hcell${c.numeric ? ' num' : ''}${sorted ? ' sorted' : ''}" data-c="${i}" style="width:${widths[i]}px">${esc(t(c.caption))}${arrow}<span class="grip" data-g="${i}"></span></div>`;
    }).join('');
  }

  // from: FileListColumnClick — the old column becomes the second sort column
  headEl.addEventListener('click', (ev) => {
    if (ev.target.classList.contains('grip')) return;
    const h = ev.target.closest('.hcell');
    if (!h) return;
    const i = Number(h.dataset.c);
    const s = state.sort;
    if (i === s.col) s.desc = !s.desc;
    else { s.col2 = s.col; s.desc2 = s.desc; s.col = i; s.desc = false; }
    sortItems();
    renderHeader();
    renderRows();
  });

  // column widths: drag the grip
  headEl.addEventListener('mousedown', (ev) => {
    const g = ev.target.closest('.grip');
    if (!g) return;
    ev.preventDefault();
    const i = Number(g.dataset.g), x0 = ev.clientX, w0 = widths[i];
    const move = (e) => { widths[i] = Math.max(24, w0 + e.clientX - x0); renderHeader(); renderRows(); };
    const up = () => { removeEventListener('mousemove', move); removeEventListener('mouseup', up); };
    addEventListener('mousemove', move);
    addEventListener('mouseup', up);
  });

  function renderRows() {
    const n = state.items.length;
    rowsEl.style.height = n * ROW + 'px';
    const viewport = listEl.clientHeight - headEl.offsetHeight;
    const { first, last } = LIST.visibleWindow(Math.max(0, listEl.scrollTop), viewport, ROW, n);
    let html = '';
    for (let r = first; r <= last; r++) {
      const tr = state.items[r];
      const cls = 'row' + (r % 2 ? ' alt' : '') + (state.sel.has(tr) ? ' sel' : '') + (r === state.focus ? ' focus' : '') + (tr.checked ? ' checked' : '');
      html += `<div class="${cls}" data-r="${r}" style="top:${r * ROW}px">` + COLS.map((c, i) => {
        const text = LIST.cellText(tr, i);
        const err = c.kind === 'tagtypes' && tr.error ? ' err' : '';
        return `<div class="${cellClass(c)}${err}" style="width:${widths[i]}px" title="${esc(text)}">${esc(text)}</div>`;
      }).join('') + '</div>';
    }
    rowsEl.innerHTML = html;
  }
  listEl.addEventListener('scroll', () => requestAnimationFrame(renderRows));
  new ResizeObserver(() => renderRows()).observe(listEl);

  function selectedTracks() { return state.items.filter((tr) => state.sel.has(tr)); }

  function setFocus(r, { extend = false, toggle = false } = {}) {
    const n = state.items.length;
    if (!n) return;
    r = Math.max(0, Math.min(n - 1, r));
    if (extend && state.anchor >= 0) {
      state.sel.clear();
      const [a, b] = [Math.min(state.anchor, r), Math.max(state.anchor, r)];
      for (let i = a; i <= b; i++) state.sel.add(state.items[i]);
    } else if (toggle) {
      const tr = state.items[r];
      state.sel.has(tr) ? state.sel.delete(tr) : state.sel.add(tr);
      state.anchor = r;
    } else {
      state.sel.clear();
      state.sel.add(state.items[r]);
      state.anchor = r;
    }
    state.focus = r;
    keepVisible(r);
    renderRows();
    selectionChanged();
  }
  function keepVisible(r) {
    if (r < 0) return;
    const top = r * ROW, viewport = listEl.clientHeight - headEl.offsetHeight;
    if (top < listEl.scrollTop) listEl.scrollTop = top;
    else if (top + ROW > listEl.scrollTop + viewport) listEl.scrollTop = top + ROW - viewport;
  }

  let coverTimer = 0;
  function selectionChanged() {
    updateStatus();
    PANEL.updatePreview();
    MENU.refresh();
    clearTimeout(coverTimer);
    coverTimer = setTimeout(showFileCover, 120);
  }

  rowsEl.addEventListener('mousedown', (ev) => {
    const row = ev.target.closest('.row');
    if (!row) return;
    const r = Number(row.dataset.r);
    if (ev.target.closest('.chk')) { // the ☑ column toggles that file
      const tr = state.items[r];
      tr.checked = !tr.checked;
      renderRows();
      updateStatus();
      return;
    }
    if (ev.button === 2 && state.sel.has(state.items[r])) return; // right click keeps the selection
    setFocus(r, { extend: ev.shiftKey, toggle: ev.ctrlKey });
  });
  rowsEl.addEventListener('dblclick', (ev) => { if (ev.target.closest('.row') && !ev.target.closest('.chk')) editTag(); });
  rowsEl.addEventListener('contextmenu', (ev) => {
    ev.preventDefault();
    if (!ev.target.closest('.row')) return;
    MENU.popup(MENUDATA.popup, ev.clientX, ev.clientY);
  });

  listEl.addEventListener('keydown', (ev) => {
    if (ev.defaultPrevented) return; // a shortcut (Ctrl+Up: Flyt fil op) took the key
    const page = Math.max(1, Math.floor((listEl.clientHeight - headEl.offsetHeight) / ROW) - 1);
    const moves = { ArrowDown: 1, ArrowUp: -1, PageDown: page, PageUp: -page };
    const opt = { extend: ev.shiftKey };
    if (ev.key in moves) setFocus((state.focus < 0 ? 0 : state.focus + moves[ev.key]), opt);
    else if (ev.key === 'Home') setFocus(0, opt);
    else if (ev.key === 'End') setFocus(state.items.length - 1, opt);
    else if (ev.key === 'Enter') editTag();
    else if (ev.key === ' ') { // Mellemrum: (un)check the selected files
      const sel = selectedTracks();
      const on = !sel.every((tr) => tr.checked);
      sel.forEach((tr) => { tr.checked = on; });
      renderRows();
      updateStatus();
    } else return;
    ev.preventDefault();
  });

  // ---------- covers ----------
  function showCover(box, cover) {
    const img = box.querySelector('.cover-img');
    img.innerHTML = cover ? `<img alt="" src="data:${esc(cover.mime)};base64,${esc(cover.data)}" />`
      : `<span class="cover-empty" data-i18n="Træk et billede hertil">${esc(label(t('Træk et billede hertil')))}</span>`;
  }
  async function showFileCover() {
    const tr = state.items[state.focus];
    const cover = tr && tr.hasCover ? await API.readCover(tr.path) : null;
    if (tr === state.items[state.focus]) showCover($('#file-cover'), cover);
  }
  async function showFolderCover(dir) {
    const cover = await API.folderCover(dir);
    if (dir === state.folder) showCover($('#folder-cover'), cover);
  }

  // ---------- status bar ----------
  function updateStatus() {
    const texts = LIST.statusTexts(state.items, selectedTracks(), state.all.length - state.items.length);
    texts.forEach((s, i) => { $('#sb-' + i).textContent = s; });
    $('#sb-5').textContent = state.message;
  }

  // ---------- favourites (1.2's popup) ----------
  function favoritesPopup() {
    const btn = document.querySelector('[data-act="aFav"]').getBoundingClientRect();
    const open = state.favorites.findIndex((p) => norm(p) === norm(state.folder));
    const items = [
      { text: t(RS.rsTilfoejDenAabneMappe), icon: 'star', enabled: !!state.folder && open < 0,
        run: () => { state.favorites.push(state.folder); saveList('Favorites', state.favorites); } },
      { text: t(RS.rsFjernDenAabneMappe), enabled: open >= 0,
        run: () => { state.favorites.splice(open, 1); saveList('Favorites', state.favorites); } },
    ];
    if (state.favorites.length) items.push('-', ...state.favorites.map((p) => ({ text: p.replace(/&/g, '&&'), run: () => navigate(p) })));
    MENU.popup(items, btn.left, btn.bottom + 2);
  }

  // ---------- tag tools (1.2's RunFieldPlans and friends) ----------
  const FIELD_KEYS = Object.keys(MENUDATA.fieldCaptions);
  const cap = (k) => t(MENUDATA.fieldCaptions[k]);
  const tools = { swapA: 'artist', swapB: 'albumArtist', copySrc: 'artist', copyDst: 'albumArtist', copyOnlyEmpty: true,
    syncDir: 'V1ToV2', syncExisting: 'BlankOnly', clip: null };

  // from: RequireTargets — null when nothing can start (and 1.2's message was shown)
  async function requireTargets() {
    if (!SAVE.canStartBatch(state)) { await DIALOG.info(t(RS.rsVentVenligstTilAlleTags)); return null; }
    const { items } = SAVE.targets(state);
    if (!items.length) { await DIALOG.info(t(RS.rsAfkrydsEllerMarkerDeFiler)); return null; }
    return items;
  }
  // after a question the window may have moved on (a scan, another batch): ask again
  async function stillTargets(items) {
    if (!SAVE.canStartBatch(state)) { await DIALOG.info(t(RS.rsVentVenligstTilAlleTags)); return null; }
    const now = SAVE.targets(state).items.filter((tr) => items.includes(tr));
    if (!now.length) { await DIALOG.info(t(RS.rsAfkrydsEllerMarkerDeFiler)); return null; }
    return now;
  }

  // from: RunFieldPlans
  async function runPlans(what, planFn) {
    const items = await requireTargets();
    if (!items) return;
    const n = TOOLS.writeItems(items, planFn).length;
    if (!n) return DIALOG.info(t(RS.rsIngenFilerAendres), what);
    if (!(await DIALOG.confirm(what, t(RS.rsAendreDFiler, n)))) return;
    const now = await stillTargets(items);
    if (now) startWrite(what, (id) => API.writeTagsBatch(TOOLS.writeItems(now, planFn), id));
  }
  const swap = (a, b) => runPlans(t(RS.rsBytSS, cap(a), cap(b)), (tr) => TOOLS.planSwap(tr, a, b));

  async function swapFields() {
    const r = await FORMS.fieldPair(t(RS.rsBytFelter), t(RS.rsFelt1), t(RS.rsFelt2), '', tools.swapA, tools.swapB, false);
    if (!r) return;
    Object.assign(tools, { swapA: r.a, swapB: r.b });
    swap(r.a, r.b);
  }
  async function copyField() {
    const r = await FORMS.fieldPair(t(RS.rsKopierFelt), t(RS.rsFraFelt), t(RS.rsTilFelt), t(RS.rsKunHvisFeltetErTomt),
      tools.copySrc, tools.copyDst, tools.copyOnlyEmpty);
    if (!r) return;
    Object.assign(tools, { copySrc: r.a, copyDst: r.b, copyOnlyEmpty: r.check });
    runPlans(t(RS.rsKopierSTilS, cap(r.a), cap(r.b)), (tr) => TOOLS.planCopy(tr, r.a, r.b, r.check));
  }
  const nameTool = (tool) => runPlans(t(RS.rsKunstnerVaerktoejer), (tr) => TOOLS.planNameTool(tr, 'artist', tool));

  // from: ActCopyTag / ActPasteTag. [Main] PasteFields holds TTagField ordinals.
  function copyTag() {
    const tr = state.items[state.focus];
    if (!tr) return;
    tools.clip = { ...tr.fields };
    state.message = t(RS.rsTagKopieretFra) + tr.fileName;
    updateStatus();
    MENU.refresh();
  }
  function pasteFields() {
    const s = get('Main', 'PasteFields', '');
    if (!s) return FIELD_KEYS.filter((k) => !['title', 'track'].includes(k) && !k.startsWith('rg'));
    return s.split(',').map((n) => FIELD_KEYS[parseInt(n, 10)]).filter(Boolean);
  }
  async function pasteTag() {
    if (!tools.clip) return;
    const items = await requireTargets();
    if (!items) return;
    const fields = await FORMS.fieldSet(t(RS.rsIndsaetTag), t(RS.rsVaelgFelterDerIndsaettesID, items.length), tools.clip, pasteFields());
    if (!fields) return;
    save('Main', 'PasteFields', fields.map((k) => FIELD_KEYS.indexOf(k)).join(','));
    const values = TOOLS.pasteValues(tools.clip, fields);
    if (!Object.keys(values).length) return;
    const now = await stillTargets(items);
    if (now) startWrite(t(RS.rsIndsaetTag), (id) => API.writeTagsBatch(now.map((tr) => ({ path: tr.path, values, cover: null })), id));
  }

  // from: ActID3Sync / RunID3Sync
  async function id3Sync() {
    const r = await FORMS.id3Sync(tools.syncDir, tools.syncExisting);
    if (!r) return;
    Object.assign(tools, { syncDir: r.direction, syncExisting: r.existing });
    const what = t(RS.rsMpTagSynkronisering);
    const items = await requireTargets();
    if (!items) return;
    const mp3 = items.filter((tr) => /\.mp3$/i.test(tr.path));
    if (!mp3.length) return DIALOG.info(t(RS.rsIngenMpFiler), what);
    if (!(await DIALOG.confirm(what, t(RS.rsSynkroniserTagsIDMpFiler, mp3.length)))) return;
    const now = await stillTargets(mp3);
    if (now) startWrite(what, (id) => API.id3SyncBatch(now.map((tr) => tr.path), r.direction, r.existing, id), { showSkipped: false });
  }

  // from: ActRemoveTags
  async function removeTags() {
    const items = await requireTargets();
    if (!items) return;
    const what = t(RS.rsFjernTags);
    if (!(await DIALOG.confirm(what, t(RS.rsFjernAlleTagsIDFiler, items.length) + '\n\n' + t(RS.rsFjernTagsForklaring)))) return;
    const now = await stillTargets(items);
    if (now) startWrite(what, (id) => API.removeTagsBatch(now.map((tr) => tr.path), id), { showSkipped: false });
  }

  // from: ActTracks — the whole list, or the checked/selected files
  async function trackTools() {
    if (!SAVE.canStartBatch(state) || !state.items.length) return;
    const { items, scope } = SAVE.targets(state);
    const keep = await TRACKTOOLS.open({
      all: state.items.slice(), subset: items, prefer: scope === 'checked' || items.length > 1,
      subsetCaption: t(scope === 'checked' ? RS.rsAfkrydsedeFilerD : RS.rsMarkeredeFilerD, items.length),
      keep: bool('Editor', 'KeepTimestamp', false), get, save,
      write: async (writeItems, keepDate, onProgress) => {
        if (!SAVE.canStartBatch(state)) { await DIALOG.info(t(RS.rsVentVenligstTilAlleTags)); return null; }
        await setKeepDate(keepDate); // the batch reads it from the ini
        return startWrite(t('Spornumre'), (id) => API.writeTagsBatch(writeItems, id), { onProgress, quiet: true });
      },
    });
    setKeepDate(keep);
  }
  async function setKeepDate(on) {
    (S.editor ||= {}).keeptimestamp = on ? '1' : '0';
    await API.settingsSet('Editor', 'KeepTimestamp', on ? 1 : 0);
    MENU.refresh();
  }

  // from: EditSelected — the focused file, otherwise the first; moves with Gem og forrige/næste
  async function editTag() {
    if (!SAVE.canStartBatch(state) || !state.items.length) return;
    const start = state.focus >= 0 ? state.focus : 0;
    const files = state.items.slice(); // the list cannot change while the editor is open
    await TAGEDITOR.open({
      index: start, count: files.length, fileAt: (i) => files[i]?.path || '',
      keep: bool('Editor', 'KeepTimestamp', false), setKeep: setKeepDate, genres: () => API.genreList(),
      saved: (i, track) => { // from: FileSaved
        const old = files[i], at = state.items.indexOf(old);
        if (at < 0) return;
        track.checked = old.checked;
        if (state.sel.has(old)) { state.sel.delete(old); state.sel.add(track); }
        state.items[at] = files[i] = track;
        renderRows();
        updateStatus();
      },
    });
    selectionChanged();
  }

  // from: ActMultiEdit — the checked (else selected) files
  async function multiEdit() {
    const items = await requireTargets();
    if (!items) return;
    const { scope } = SAVE.targets(state);
    await MULTIEDITOR.open({
      items, keep: bool('Editor', 'KeepTimestamp', false), setKeep: setKeepDate, genres: () => API.genreList(),
      scopeCaption: t(scope === 'checked' ? RS.rsAfkrydsedeFilerD : RS.rsMarkeredeFilerD, items.length),
      write: (writeItems, onProgress) => startWrite(t(RS.rsMultiFilTagEditor), (id) => API.writeTagsBatch(writeItems, id),
        { onProgress, quiet: true }),
      cancel: () => API.writeCancel(),
    });
    selectionChanged();
  }

  // ---------- cover tools and pictures dropped on the cover panels ----------
  const covers = COVERS.actions({
    state, requireTargets, startWrite, get, save, bool, navigate,
    message: (text) => { state.message = text; updateStatus(); },
    refreshCovers: () => { if (state.folder) showFolderCover(state.folder); showFileCover(); },
  });
  $('#file-cover').addEventListener('contextmenu', (ev) => { // 1.2's CoverPopup
    ev.preventDefault();
    MENU.popup([{ ref: 'aCoverAsFolder' }], ev.clientX, ev.clientY);
  });
  window.__TAURI__.webview.getCurrentWebview().onDragDropEvent((ev) => {
    const p = ev.payload;
    if (p.type !== 'drop' || document.querySelector('.modal-back')) return; // not behind a dialog
    const el = document.elementFromPoint(p.position.x / devicePixelRatio, p.position.y / devicePixelRatio);
    covers.drop(p.paths, el?.closest('#file-cover') ? 'file' : el?.closest('#folder-cover') ? 'folder' : 'list');
  });

  // ---------- renaming (phase 4) ----------
  let undoLog = null, undoWhat = '';
  // from: SetUndoLog
  function setUndoLog(log, what) {
    undoLog = log;
    undoWhat = what;
    MENU.refresh();
    PANEL.reload();
  }

  // from: LoadMaskHistory / AddMaskToHistory ([RenameMasks] etc., Mask0.. newest first)
  function maskHistory(section) {
    const list = [];
    for (let i = 0; i < 15; i++) { const m = get(section, 'Mask' + i); if (m) list.push(m); }
    return list;
  }
  function addToHistory(section, mask) {
    const list = RENAMETOOLS.addMaskToHistory(RENAMETOOLS.historyFor(section, maskHistory(section)), mask);
    S[section.toLowerCase()] = Object.fromEntries(list.map((m, i) => ['mask' + i, m]));
    API.settingsWriteSection(section, list.map((m, i) => ['Mask' + i, m]));
  }

  // from: ApplyRenameLog — the list, the open folder, the address bar and the tree follow
  async function applyRenameLog(log, reverse) {
    const mapped = await API.mapPaths([...state.all.map((tr) => tr.path), state.folder], log, reverse);
    const before = state.folder;
    RENAMETOOLS.applyLog(state, mapped.slice(0, -1), mapped[mapped.length - 1]);
    if (state.folder !== before) {
      $('#address').value = state.folder;
      API.window().setTitle('TidyTag - ' + state.folder);
      save('Main', 'LastFolder', state.folder);
    }
    await TREE.reload();
    TREE.reveal(state.folder);
    sortItems();
    renderRows();
    selectionChanged();
  }

  const statusTr = (s) => t(s);
  // from: ButtonRenameDoClick
  async function renameDo() {
    const items = await requireTargets();
    if (!items) return;
    const o = PANEL.inline('rn');
    const rows = await API.planRename(items, o.mask, o);
    const c = RENAMETOOLS.renameConfirm(rows, statusTr);
    if (!c.okCount) return DIALOG.info(c.problems || t(RS.rsAlleFilerHarAlleredeDet), t(RS.rsIntetAtOmdoebe));
    const text = t(RS.rsOmdoebDFilerS, c.okCount, c.skipped > 0 ? t(RS.rsDSpringesOverBrugForhaandsvis, c.skipped) : '');
    if (!(await DIALOG.confirm(t(RS.rsOmdoebFiler), text + '\n\n' + c.examples))) return;
    if (!SAVE.canStartBatch(state)) return DIALOG.info(t(RS.rsVentVenligstTilAlleTags));
    addToHistory('RenameMasks', o.mask);
    PANEL.saveInline();
    let r;
    try { r = await API.executeRename(rows); } catch (e) { return DIALOG.info(String(e)); }
    const failed = r.rows.filter((x) => x.status === 'Failed');
    if (r.log.length) {
      setUndoLog(r.log, t(RS.rsFilerFlertal));
      await applyRenameLog(r.log, false);
    }
    state.message = t(RS.rsDFilerOmdoebtDFejl, r.log.length, failed.length);
    updateStatus();
    if (failed.length) {
      DIALOG.info(failed.map((x) => `${x.oldName.replace(/^.*[\\/]/, '')}: ${t(x.detail)}`).join('\n'), t(RS.rsNogleFilerBlevIkkeOmdoebt));
    }
  }

  // from: ButtonF2TWriteClick
  async function f2tDo() {
    const items = await requireTargets();
    if (!items) return;
    const o = PANEL.inline('ft');
    const matches = await API.matchFileNames(items.map((tr) => tr.path), o.mask, o.underscores, o.caseMode);
    const r = RENAMETOOLS.f2tItems(items, matches);
    if (!r.ready) return DIALOG.info(t(RS.rsIngenFilerAendresDPasser, r.noMatch), t(RS.rsIntetAtSkrive));
    const text = t(RS.rsSkrivTagsFraFilnavnetI, r.ready, r.noMatch > 0 ? t(RS.rsDPasserIkkeTilMasken, r.noMatch) : '');
    if (!(await DIALOG.confirm(t(RS.rsSkrivTags), text))) return;
    const now = await stillTargets(items);
    if (!now) return;
    addToHistory('FileToTagMasks', o.mask);
    PANEL.saveInline();
    const paths = new Set(now.map((tr) => tr.path));
    startWrite(t(RS.rsTagsFraFilnavn), (id) => API.writeTagsBatch(r.items.filter((it) => paths.has(it.path)), id));
  }

  const scopeCaption = (scope, n) => t(scope === 'checked' ? RS.rsAfkrydsedeFilerD : RS.rsMarkeredeFilerD, n);

  // from: ActRenameDialog / ActRenameFolder
  async function renameDialog(folderMode) {
    if (!SAVE.canStartBatch(state) || !state.items.length) return;
    if (!folderMode) PANEL.saveInline();
    const { items, scope } = SAVE.targets(state);
    const log = await RENAMEDIALOG.open({
      all: state.items.slice(), subset: items, subsetCaption: scopeCaption(scope, items.length),
      prefer: scope === 'checked' || items.length > 1, folderMode, get, save,
      history: maskHistory, addToHistory, canStart: () => SAVE.canStartBatch(state),
      applyLog: (l) => applyRenameLog(l, false),
    });
    if (log.length) setUndoLog(log, t(folderMode ? RS.rsMapperFlertal : RS.rsFilerFlertal));
    PANEL.reload();
    selectionChanged();
  }

  // from: ActFileToTagDialog
  async function f2tDialog() {
    if (!SAVE.canStartBatch(state) || !state.items.length) return;
    PANEL.saveInline();
    const { items, scope } = SAVE.targets(state);
    const keep = await F2TDIALOG.open({
      all: state.items.slice(), subset: items, subsetCaption: scopeCaption(scope, items.length),
      prefer: scope === 'checked' || items.length > 1, keep: bool('Editor', 'KeepTimestamp', false), get, save,
      history: maskHistory, addToHistory,
      write: async (writeItems, keepDate, onProgress) => {
        if (!SAVE.canStartBatch(state)) { await DIALOG.info(t(RS.rsVentVenligstTilAlleTags)); return null; }
        await setKeepDate(keepDate);
        return startWrite(t(RS.rsTagsFraFilnavn), (id) => API.writeTagsBatch(writeItems, id), { onProgress, quiet: true });
      },
    });
    setKeepDate(keep);
    PANEL.reload();
    selectionChanged();
  }

  // the tree or the list: F6 renames what had the focus last (1.2: ShellTree.Focused)
  let treeFocused = false;
  document.addEventListener('focusin', (e) => {
    if (e.target.closest('#tree')) treeFocused = true;
    else if (e.target.closest('#list')) treeFocused = false;
  });

  // from: RenameFileDialog — one file at a time, < Forrige / Næste >, each change renamed at once
  async function renameFileDialog() {
    if (!state.items.length) return;
    let idx = state.focus >= 0 ? state.focus : 0;
    const log = [];
    // the order when the dialog opened, as 1.2 (a rename re-sorts the list, but Næste goes on to
    // the next file in this order); the track objects themselves follow the renames
    const files = state.items.slice();
    await new Promise((resolve) => {
      const m = FORMS.modal(`<h2 data-title></h2><div class="lbl ellipsis" data-dir></div>
        <div class="frow"><span class="lbl">${esc(t(RS.rsNytNavn))}</span><input class="input grow" name="name" spellcheck="false"><span data-ext></span></div>
        <div class="modal-buttons"><button class="btn" data-go="-1">${esc(label(t(RS.rsForrige)))}</button>
          <button class="btn" data-go="1">${esc(label(t(RS.rsNaeste)))}</button><span class="grow"></span>
          <button class="btn primary" data-go="0">${esc(label(t('OK')))}</button><button class="btn" data-cancel>${esc(label(t('Annuller')))}</button></div>`,
      { cls: 'form wide', onEscape: () => { m.close(); resolve(); }, onEnter: () => go(0) });
      const q = (s) => m.el.querySelector(s);
      const parts = (tr) => { const i = tr.fileName.lastIndexOf('.'); return i > 0 ? [tr.fileName.slice(0, i), tr.fileName.slice(i)] : [tr.fileName, '']; };
      function show() {
        const tr = files[idx];
        q('[data-title]').textContent = t(RS.rsOmdoebFilTitel, idx + 1, files.length);
        q('[data-dir]').textContent = tr.folder;
        const [stem, ext] = parts(tr);
        q('[name="name"]').value = stem;
        q('[data-ext]').textContent = ext;
        q('[data-go="-1"]').disabled = idx === 0;
        q('[data-go="1"]').disabled = idx === files.length - 1;
        q('[name="name"]').select();
        state.sel.clear(); state.sel.add(tr); state.focus = state.anchor = state.items.indexOf(tr);
        renderRows();
      }
      async function go(step) {
        const tr = files[idx];
        const [stem, ext] = parts(tr);
        const name = q('[name="name"]').value.trim();
        if (name !== stem) {
          try {
            const item = await API.renameOne(tr.path, name + ext);
            log.push(item);
            await applyRenameLog([item], false);
          } catch (e) {
            const text = e === 'invalid' ? t(RS.rsUgyldigtNavn) : e === 'exists' ? t(RS.rsFiltypeFindes, name + ext) : String(e);
            await DIALOG.info(text, t(RS.rsKunneIkkeOmdoebe));
            return; // stays on this file
          }
        }
        if (step === 0) { m.close(); resolve(); return; }
        idx = Math.max(0, Math.min(files.length - 1, idx + step));
        show();
      }
      m.el.addEventListener('click', (e) => {
        const b = e.target.closest('[data-go]');
        if (b) go(Number(b.dataset.go));
        else if (e.target.closest('[data-cancel]')) { m.close(); resolve(); }
      });
      show();
    });
    if (log.length) setUndoLog(log, t(RS.rsManuelOmdoebning));
    selectionChanged();
  }

  // from: RenameFolderManual — the tree's folder
  async function renameFolderManual() {
    const dir = TREE.selectedPath.replace(/[\\/]+$/, '');
    const name = dir.slice(dir.lastIndexOf('\\') + 1);
    if (!dir || /^[a-z]:$/i.test(dir) || !name) return;
    const r = await FORMS.form(t(RS.rsOmdoebMappeTitel), `<div class="frow"><span class="lbl">${esc(t(RS.rsNytNavn))}</span>
      <input class="input grow" name="name" spellcheck="false" value="${esc(name)}"></div>`, (m) => m.querySelector('[name="name"]').value.trim(), { wide: true });
    if (r === null || r === name) return;
    try {
      const item = await API.renameOne(dir, r);
      await applyRenameLog([item], false);
      setUndoLog([item], t(RS.rsManuelOmdoebning));
    } catch (e) {
      DIALOG.info(e === 'invalid' ? t(RS.rsUgyldigtNavn) : e === 'exists' ? t(RS.rsFiltypeFindes, r) : String(e), t(RS.rsKunneIkkeOmdoebe));
    }
  }

  // from: ActUndo
  async function undoRename() {
    if (!undoLog) return;
    const log = undoLog;
    if (!(await DIALOG.confirm(t(RS.rsFortrydOmdoebning), t(RS.rsGivDFilerMapperDeres, log.length)))) return;
    if (!SAVE.canStartBatch(state)) return DIALOG.info(t(RS.rsVentVenligstTilAlleTags));
    let r;
    try { r = await API.undoRename(log); } catch (e) { return DIALOG.info(String(e)); }
    await applyRenameLog(r.restoredLog, true); // only what really moved back
    setUndoLog(null, '');
    state.message = t(RS.rsDFilerMapperFikDeres, r.restored);
    updateStatus();
    if (r.errors.length) {
      DIALOG.info(t(RS.rsDFilerMapperFikDeres2, r.restored) + '\n' + r.errors.map((x) => t(x)).join('\n'), t(RS.rsFortrydOmdoebning));
    }
  }

  // a section as 1.2 writes it whole (EraseSection + WriteString), kept in the settings snapshot
  function writeSection(sec, rows) {
    S[sec.toLowerCase()] = Object.fromEntries(rows.map(([k, v]) => [k.toLowerCase(), v]));
    return API.settingsWriteSection(sec, rows);
  }

  // from: ActRenameWords
  async function editWords() {
    const w = await RENAMEEDIT.words(RENAMETOOLS.wordsFromIni(S.renamereplace, S.renamekeepcase));
    if (!w) return;
    const ini = RENAMETOOLS.wordsToIni(w);
    await writeSection('RenameReplace', ini.RenameReplace);
    await writeSection('RenameKeepCase', ini.RenameKeepCase);
    selectionChanged(); // the live rename result uses them
  }

  // from: MaskEditorClick / RenameMaskPreview
  async function maskEditor() {
    PANEL.saveInline();
    const o = PANEL.inline('rn');
    const saved = [];
    for (let i = 1; i <= (parseInt(get('SavedRenameMasks', 'Count', 0), 10) || 0); i++) saved.push(get('SavedRenameMasks', 'Mask' + i));
    const preview = async (mask) => {
      const tr = state.items[state.focus] || state.items[0];
      if (!tr) return '';
      const [row] = await API.planRename([tr], mask, o);
      if (row.status === 'Missing') return t(RS.rsMangler) + row.detail.split(', ').map((x) => t(x)).join(', ');
      if (!row.newName) return t(RS.rsUgyldigMaske);
      return RENAMETOOLS.displayName(tr.path, row.newName);
    };
    const r = await RENAMEEDIT.mask(t(RS.rsMaskeEditorTitel), o.mask, MENUDATA.renameVars.map((v) => t(v)), preview, saved);
    await writeSection('SavedRenameMasks', [['Count', String(r.saved.length)], ...r.saved.map((m, i) => ['Mask' + (i + 1), m])]);
    if (r.mask === null) return;
    save('Rename', 'Mask', r.mask);
    PANEL.reload();
  }

  const renameActions = () => RENAMETOOLS.actionsFromIni(S.renameactions);
  // from: ActManageActions
  async function manageActions() {
    const a = await RENAMEEDIT.actions(renameActions(), PANEL.inline('rn').mask);
    if (a) await writeSection('RenameActions', RENAMETOOLS.actionsToIni(a));
  }

  // from: RunRenameAction — files first, then the folders of the renamed files; one undo step
  async function runRenameAction(act) {
    const items = await requireTargets();
    if (!items) return;
    const opt = PANEL.inline('rn');
    const filePlan = act.fileMask ? await API.planRename(items, act.fileMask, opt) : [];
    const fileCount = filePlan.filter((r) => r.status === 'Ok').length;
    let msg = t(RS.rsKoerHandlingenS, act.name) + '\n';
    if (act.fileMask) msg += '\n' + t(RS.rsFilerDOmdoebesMedS, fileCount, act.fileMask);
    if (act.folderMask) msg += '\n' + t(RS.rsMapperneOmdoebesMedS, act.folderMask);
    if (!(await DIALOG.confirm(t(RS.rsOmdoebningshandling), msg))) return;
    if (!SAVE.canStartBatch(state)) return DIALOG.info(t(RS.rsVentVenligstTilAlleTags));
    let fileLog = [], folderLog = [], failedRows = [];
    try {
      if (fileCount > 0) {
        const r = await API.executeRename(filePlan);
        fileLog = r.log;
        failedRows = r.rows.filter((x) => x.status === 'Failed').map((x) => `${x.oldName.replace(/^.*[\\/]/, '')}: ${t(x.detail)}`);
        if (fileLog.length) await applyRenameLog(fileLog, false);
      }
      if (act.folderMask) {
        const folderPlan = await API.planRename(items, act.folderMask, opt, true); // after the file renames
        if (folderPlan.some((r) => r.status === 'Ok')) {
          const r = await API.executeRename(folderPlan);
          folderLog = r.log;
          failedRows = failedRows.concat(r.rows.filter((x) => x.status === 'Failed').map((x) => `${x.oldName}: ${t(x.detail)}`));
          if (folderLog.length) await applyRenameLog(folderLog, false);
        }
      }
    } catch (e) {
      DIALOG.info(String(e));
    }
    const log = fileLog.concat(folderLog);
    if (log.length) setUndoLog(log, t(RS.rsFilerMapper));
    state.message = t(RS.rsHandlingDFilerDMapperDFejl, act.name, fileLog.length, folderLog.length, failedRows.length);
    updateStatus();
    if (failedRows.length) DIALOG.info(failedRows.join('\n'), t(RS.rsNogleFilerBlevIkkeOmdoebt));
  }

  // ---------- phase 5: the filter row, manual order, columns ----------
  function refreshView() {
    LISTVIEW.rebuildView(state, FIELD_KEYS);
    renderRows();
    selectionChanged();
  }
  // from: ButtonFilterApplyClick
  function applyFilter() {
    state.filter.text = $('#filter-text').value.trim();
    state.filter.field = $('#filter-field').selectedIndex;
    refreshView();
  }
  // from: FilterOptionChange (and the two check boxes, which MatchesFilter reads live)
  function filterOptions() {
    const i = $('#tagtype').selectedIndex;
    state.filter.tagType = i > 0 ? MENUDATA.tagTypes[i] : '';
    state.filter.whole = $('#filter-whole').checked;
    state.filter.matchCase = $('#filter-case').checked;
    refreshView();
  }
  // from: ButtonShowAllClick
  function showAll() {
    $('#filter-text').value = '';
    LISTVIEW.showAll(state, FIELD_KEYS);
    renderRows();
    selectionChanged();
  }
  $('#filter-apply').addEventListener('click', applyFilter);
  $('#filter-text').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); applyFilter(); }
    else if (e.key === 'Escape' && e.target.value) { e.preventDefault(); showAll(); } // FormKeyDown
  });
  $('#filter-hide').addEventListener('click', () => { LISTVIEW.hideSelected(state, FIELD_KEYS); renderRows(); selectionChanged(); });
  $('#filter-all').addEventListener('click', showAll);
  for (const id of ['#tagtype', '#filter-whole', '#filter-case']) $(id).addEventListener('change', filterOptions);

  // from: ActFindExecute
  function findFilter() {
    if (!state.view.filter) toggleView('filter', 'View', 'Filter');
    $('#filter-text').focus();
    $('#filter-text').select();
  }

  function manualOrder() {
    renderHeader();
    renderRows();
    state.message = t(RS.rsManuelRaekkefoelgeKlikPaaEn);
    updateStatus();
  }
  function moveSelected(delta) {
    if (!LISTVIEW.moveSelected(state, delta)) return;
    keepVisible(state.focus);
    manualOrder();
  }

  // from: AutoFitColumns — measured in the list's own font
  function autoFit() {
    const cs = getComputedStyle(rowsEl);
    const ctx = document.createElement('canvas').getContext('2d');
    ctx.font = `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
    const cols = COLS.map((c) => ({ caption: t(c.caption) }));
    LISTVIEW.autoFitWidths(state.items, cols, widths, (s) => ctx.measureText(s).width, (tr, c) => LIST.cellText(tr, c))
      .forEach((w, i) => { widths[i] = Math.ceil(w); });
    renderHeader();
    renderRows();
  }
  function toggleAutoFitAfterScan() {
    const on = !bool('View', 'AutoFitColumns', false);
    save('View', 'AutoFitColumns', on ? 1 : 0);
    if (on) autoFit();
    MENU.refresh();
  }

  // ---------- paths from Explorer (a second start, or this start's command line) ----------
  let pending = [], lastOpen = { dir: '', tick: 0 }, incoming = [], incomingTimer = 0;
  const samePath = (a, b) => norm(a) === norm(b);
  // from: ApplyPendingSelect — false when none of the waiting files is in the list
  function applyPendingSelect(extend) {
    const found = LISTVIEW.pendingIndexes(state.items, pending);
    if (!found.length) return false;
    pending = [];
    if (!extend) state.sel.clear();
    for (const i of found) state.sel.add(state.items[i]);
    state.focus = state.anchor = found[0];
    keepVisible(found[0]);
    renderRows();
    return true;
  }
  // from: OpenPaths / PrepareOpen
  async function openPaths(paths) {
    const kinds = await Promise.all(paths.map((p) => API.pathKind(p)));
    const old = state.scanning ? pending.slice() : [];
    const { dir, select } = LISTVIEW.prepareOpen(paths, (p) => kinds[paths.indexOf(p)] === 'dir');
    pending = select;
    if (select.length) lastOpen = { dir, tick: Date.now() };
    // still reading the folder of this start's own file: add to its selection
    if (dir && state.scanning && pending.length && samePath(dir, state.folder)) {
      for (const p of old) if (!pending.some((q) => samePath(q, p))) pending.push(p);
      return;
    }
    if (!dir) return;
    // files already in the list are just selected
    if (pending.length && !state.scanning && applyPendingSelect(samePath(dir, lastOpen.dir) && Date.now() - lastOpen.tick < 5000)) {
      selectionChanged();
      return;
    }
    navigate(dir);
  }
  // from: PathsReceived / TimerIncomingTimer — Explorer starts one process per selected file;
  // wait until the last one has called, and while a dialog is open
  API.on('paths-received', (paths) => {
    incoming.push(...paths);
    clearTimeout(incomingTimer);
    incomingTimer = setTimeout(function tick() {
      if (document.querySelector('.modal-back')) { incomingTimer = setTimeout(tick, 400); return; }
      openPaths(incoming.splice(0));
    }, 400);
  });

  // ---------- folders ----------
  /** InputQuery: one text field; resolves to the text or null. */
  function askText(title, prompt) {
    return new Promise((resolve) => {
      const m = FORMS.modal(`<h2>${esc(title)}</h2><div class="lbl">${esc(prompt)}</div>
        <div class="frow"><input class="input grow" name="v" spellcheck="false"></div>
        <div class="modal-buttons"><span class="grow"></span><button class="btn primary" data-ok>${esc(label(t('OK')))}</button>
          <button class="btn" data-cancel>${esc(label(t('Annuller')))}</button></div>`,
      { cls: 'form wide', onEscape: () => done(null), onEnter: () => done(field.value) });
      const field = m.el.querySelector('[name="v"]');
      const done = (v) => { m.close(); resolve(v); };
      m.el.addEventListener('click', (e) => {
        if (e.target.closest('[data-ok]')) done(field.value);
        else if (e.target.closest('[data-cancel]')) done(null);
      });
      field.focus();
    });
  }
  // from: ActNewFolderExecute
  async function newFolder() {
    if (!state.folder) return;
    const name = await askText(t(RS.rsNyMappe3), t(RS.rsNavnPaaDenNyeMappe) + state.folder + ':');
    if (name === null) return;
    let dir;
    try {
      dir = await API.createFolder(state.folder, name);
    } catch (e) {
      if (e) await DIALOG.info(t(e) + '\n' + state.folder.replace(/\\$/, '') + '\\' + name.trim());
      return;
    }
    await TREE.refresh(state.folder);
    state.message = t(RS.rsMappeOprettet) + dir.replace(/^.*\\/, '');
    updateStatus();
  }
  async function expandFolders() {
    document.body.style.cursor = 'wait';
    try { await TREE.expandSelected(); } finally { document.body.style.cursor = ''; }
  }

  // ---------- file actions: Recycle Bin, copy/move, extensions, Explorer ----------
  const dialogs = () => window.__TAURI__.dialog;
  const baseOf = (p) => p.replace(/^.*[\\/]/, '');
  const pickFolder = (title) => dialogs().open({ directory: true, title, defaultPath: state.folder || undefined });
  // "<name>: <Danish text>" from Rust: the text part is translated (file names have no ':')
  const tErr = (e) => { const i = e.lastIndexOf(': '); return i < 0 ? t(e) : e.slice(0, i + 2) + t(e.slice(i + 2)); };
  const run = async (call) => { try { return await call(); } catch (e) { await DIALOG.info(String(e)); return null; } };

  // from: ActDeleteFilesExecute
  async function deleteFiles() {
    const items = await requireTargets();
    if (!items) return;
    if (!(await DIALOG.confirm(t(RS.rsSletFiler), t(RS.rsLaegDFilerIPapirkurven, items.length)))) return;
    const r = await run(() => API.recycle(items.map((tr) => tr.path)));
    if (!r) return;
    const gone = new Set(items.filter((_, i) => !r.exists[i]));
    state.all = state.all.filter((tr) => !gone.has(tr));
    state.sel.clear();
    refreshView();
    state.message = t(RS.rsDFilerLagtIPapirkurven, r.gone);
    updateStatus();
    if (r.errors.length) DIALOG.info(r.errors.map(tErr).join('\n'), t(RS.rsSletFiler));
  }

  // from: ActCopyToExecute / ActMoveToExecute / CopyOrMoveTo
  async function copyOrMoveTo(move) {
    const title = t(move ? RS.rsFlytTilMappe : RS.rsKopierTilMappe);
    const dir = await pickFolder(title);
    if (!dir) return;
    const items = await requireTargets();
    if (!items) return;
    if (!(await DIALOG.confirm(title, t(move ? RS.rsFlytDFilerTilS : RS.rsKopierDFilerTilS, items.length, dir)))) return;
    const r = await run(() => API.copyMove(items.map((tr) => tr.path), dir, move));
    if (!r) return;
    if (move) {
      LISTVIEW.afterMove(state, items, r, (p) => LISTVIEW.inScanScope(p, state.folder, state.view.subfolders), FIELD_KEYS);
      renderRows();
      selectionChanged();
    } else if (r.count > 0 && LISTVIEW.inScanScope(dir.replace(/\\$/, '') + '\\x', state.folder, state.view.subfolders)) {
      startScan(); // the copies belong in the list
    }
    state.message = t(move ? RS.rsDFilerFlyttetTilS : RS.rsDFilerKopieretTilS, r.count, dir);
    updateStatus();
    if (r.errors.length) DIALOG.info(r.errors.map(tErr).join('\n'), title);
  }

  // from: ActDeleteFolderCoversExecute
  async function deleteFolderCovers() {
    const items = await requireTargets();
    if (!items) return;
    const dirs = [...new Map(items.map((tr) => [tr.folder.toLowerCase(), tr.folder])).entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)).map(([, d]) => d);
    const title = t(RS.rsSletMappeCover);
    const files = await API.folderCoverFiles(dirs);
    if (!files.length) return DIALOG.info(t(RS.rsIngenAfMapperneHarEtCover), title);
    if (!(await DIALOG.confirm(title, t(RS.rsLaegDMappeCoverIPapirkurven, files.length, dirs.length)))) return;
    const r = await run(() => API.recycle(files));
    if (!r) return;
    state.message = t(RS.rsDFilerLagtIPapirkurven, r.gone);
    updateStatus();
    if (state.folder) showFolderCover(state.folder);
    showFileCover();
    if (r.errors.length) DIALOG.info(r.errors.map(tErr).join('\n'), title);
  }

  // from: ActChangeExtExecute — kind 0: .mp4 → .m4a, 1: → .m4b, 2: .m4b → .m4a
  async function changeExt(kind) {
    const items = await requireTargets();
    if (!items) return;
    const title = t(RS.rsSkiftFiltype);
    const rows = await API.planExtChange(items.map((tr) => tr.path), kind);
    if (!rows.length) return DIALOG.info(t(RS.rsIngenFilerMedFiltypen), title);
    const errors = rows.filter((r) => r.status === 'Exists').map((r) => t(RS.rsFiltypeFindes, baseOf(r.newName)));
    let res = { rows: [], log: [] };
    if (rows.some((r) => r.status === 'Ok')) {
      res = await run(() => API.executeRename(rows));
      if (!res) return;
    }
    errors.push(...res.rows.filter((r) => r.status === 'Failed').map((r) => `${baseOf(r.oldName)}: ${t(r.detail)}`));
    if (res.log.length) {
      setUndoLog(res.log, t(RS.rsSkiftFiltype));
      await applyRenameLog(res.log, false);
    }
    state.message = t(RS.rsFiltypeSkiftet, res.log.length);
    updateStatus();
    if (errors.length) DIALOG.info(errors.join('\n'), title);
  }

  // from: ActOpenFolderExecute
  async function openFolder() {
    const dir = await pickFolder(t(RS.rsVaelgMappe));
    if (dir) navigate(dir);
  }
  // from: ActShowInExplorerExecute / ActPropertiesExecute — the focused file, else the folder
  function showInExplorer() {
    const tr = state.items[state.focus];
    if (tr) run(() => API.showInExplorer(tr.path, true));
    else if (state.folder) run(() => API.showInExplorer(state.folder, false));
  }
  function showProperties() {
    const p = state.items[state.focus]?.path || state.folder;
    if (p) run(() => API.showProperties(p));
  }

  // ---------- playing: the built-in player, "Afspil med" and playlists ----------
  let playerAvailable = false, playWithCache = []; // RebuildPlayWith's list, read at start and after "Vælg program"
  const playInternal = () => bool('Player', 'Internal', true) && playerAvailable;
  const iniList = (sec) => PLAYTOOLS.listFromIni(Object.entries(S[sec.toLowerCase()] || {}));
  const playTargets = () => { const { files, index } = PLAYTOOLS.playTargets(state); return PLAYER.start(files, index); };
  const reportPlay = (e) => DIALOG.info(String(e), t(RS.rsAfspilFil));
  async function refreshPlayWith() { playWithCache = await API.playWithList(); }

  // from: PlayWith — the program set for the file's type in the settings, else Windows' own
  async function playWith(path) {
    const prog = PLAYTOOLS.playerFor(path, iniList('Players'));
    try { await (prog ? API.runProgram(prog, path) : API.openDefault(path)); } catch (e) { reportPlay(e); }
  }
  // from: PlayExternal — several files go as a temporary playlist, which every player understands
  async function playExternal(prog, files) {
    try {
      const target = files.length === 1 ? files[0]
        : await API.tempPlaylist(files.map((f) => state.all.find((tr) => tr.path === f)).filter(Boolean));
      await (prog ? API.runProgram(prog, target) : API.openDefault(target));
    } catch (e) { reportPlay(e); }
  }
  // from: ActPlayExecute
  async function playFile() {
    if (playInternal()) return playTargets();
    const tr = state.items[state.focus];
    if (tr) playWith(tr.path);
  }
  // from: ActPlayFolderExecute
  async function playFolder() {
    if (!state.items.length) return;
    if (playInternal()) return PLAYER.start(state.items.map((tr) => tr.path), 0);
    try { playWith(await API.tempPlaylist(state.items)); } catch (e) { reportPlay(e); }
  }
  // from: PlayWithClick — -1 the built-in player, -2 Windows' own program, -3 choose a program
  async function playWithClick(tag) {
    if (tag === -1) return playTargets();
    let sel = selectedTracks();
    if (!sel.length && state.items[state.focus]) sel = [state.items[state.focus]];
    if (!sel.length) return;
    const files = sel.map((tr) => tr.path);
    if (tag === -2) return playExternal('', files);
    if (tag === -3) {
      const exe = await dialogs().open({ filters: [{ name: t(RS.rsProgrammer) + ' (*.exe)', extensions: ['exe'] }] });
      if (!exe) return;
      const extra = [...iniList('ExtraPlayers'), exe];
      const rows = PLAYTOOLS.listToIni(extra);
      S.extraplayers = Object.fromEntries(rows.map(([k, v]) => [k.toLowerCase(), v]));
      await API.settingsWriteSection('ExtraPlayers', rows);
      await refreshPlayWith();
      return playExternal(exe, files);
    }
    return playExternal(playWithCache[tag].path, files);
  }
  function playWithMenu() {
    return [
      ...(playerAvailable ? [{ text: t(RS.rsTidyTagAfspiller), run: () => playWithClick(-1) }] : []),
      ...playWithCache.map((p, i) => ({ text: p.name.replace(/&/g, '&&'), run: () => playWithClick(i) })),
      { text: t(RS.rsWindowsStandard), run: () => playWithClick(-2) },
      '-',
      { text: t(RS.rsVaelgProgram), run: () => playWithClick(-3) },
    ];
  }

  // from: SavePlaylistDialog — the playlist's folder from the settings when it exists
  async function playlistDir(items) {
    const pl = get('Playlist', 'Folder', '');
    return pl && (await API.pathKind(pl)) === 'dir' ? pl.replace(/\\$/, '') : items[0].folder;
  }
  async function savePlaylistDialog(items) {
    if (!items.length) return DIALOG.info(t(RS.rsDerErIngenFilerAt));
    const parts = t(RS.rsPlaylisteUtfMUM).split('|');
    const filters = [];
    for (let i = 0; i + 1 < parts.length; i += 2) filters.push({ name: parts[i], extensions: [parts[i + 1].replace(/^\*\./, '')] });
    let target = await dialogs().save({
      title: t(RS.rsGemPlayliste), filters,
      defaultPath: (await playlistDir(items)) + '\\' + baseOf(items[0].folder) + '.m3u8',
    });
    if (!target) return;
    if (!/\.[^\\.]+$/.test(baseOf(target))) target += '.m3u8'; // DefaultExt
    if (await run(() => API.savePlaylist(target, items, bool('Playlist', 'FullPaths', false))) === null) return;
    state.message = t(RS.rsPlaylisteMedDFilerGemt, items.length, baseOf(target));
    updateStatus();
  }
  // from: ActQuickPlaylistExecute
  async function quickPlaylist() {
    const title = t(RS.rsGemPlaylisteHurtigt);
    const { items } = SAVE.targets(state);
    if (!items.length) return DIALOG.info(t(RS.rsDerErIngenFilerAt), title);
    const name = (await API.quickPlaylistName(items[0], get('Playlist', 'NameMask', '%f'))) || baseOf(items[0].folder);
    const target = (await playlistDir(items)) + '\\' + name + '.m3u8';
    if ((await API.pathKind(target)) !== 'none' && !(await DIALOG.confirm(title, t(RS.rsPlaylisteFindesOverskriv, baseOf(target))))) return;
    if (await run(() => API.savePlaylist(target, items, bool('Playlist', 'FullPaths', false))) === null) return;
    state.message = t(RS.rsPlaylisteMedDFilerGemt, items.length, target);
    updateStatus();
  }

  // ---------- actions that work in phase 1 ----------
  const checkAll = (fn) => { state.items.forEach(fn); renderRows(); updateStatus(); };
  const ACTIONS = {
    aRefresh: () => state.folder && startScan(),
    aExit: () => API.window().close(),
    aSelAll: () => { state.items.forEach((tr) => state.sel.add(tr)); renderRows(); selectionChanged(); },
    aSelNone: () => { state.sel.clear(); renderRows(); selectionChanged(); },
    aChkSel: () => checkAll((tr) => { if (state.sel.has(tr)) tr.checked = true; }),
    aUnchkSel: () => checkAll((tr) => { if (state.sel.has(tr)) tr.checked = false; }),
    aChkAll: () => checkAll((tr) => { tr.checked = true; }),
    aUnchkAll: () => checkAll((tr) => { tr.checked = false; }),
    aInvert: () => checkAll((tr) => { tr.checked = !tr.checked; }),
    FActToolsPanel: () => toggleView('tools', 'View', 'ToolsPanel'),
    FActFolders: () => toggleView('folders', 'View', 'Folders'),
    aCloseFolders: () => toggleView('folders', 'View', 'Folders'),
    FActAddress: () => toggleView('address', 'View', 'Address'),
    FActFilter: () => toggleView('filter', 'View', 'Filter'),
    FActSubfolders: () => { toggleView('subfolders', 'Main', 'Subfolders'); if (state.folder) startScan(); },
    aTabRename: () => showTab(0),
    aTabMulti: () => showTab(1),
    aTabF2T: () => showTab(2),
    aUp: () => { const p = state.folder.replace(/[\\/]+$/, ''); const i = p.lastIndexOf('\\'); if (i > 1) navigate(p.slice(0, i + (i === 2 ? 1 : 0))); },
    aFav: favoritesPopup,
    aTreeRefresh: () => TREE.reload(),
    FActKeepDate: () => save('Editor', 'KeepTimestamp', bool('Editor', 'KeepTimestamp', false) ? 0 : 1),
    // phase 3: tag tools
    aSwapAT: () => swap('artist', 'title'),
    aSwapAA: () => swap('artist', 'album'),
    aSwapLT: () => swap('album', 'title'),
    aSwap: swapFields,
    aCopyField: copyField,
    aClean: () => runPlans(t(RS.rsRydMellemrum), TOOLS.planCleanSpaces),
    'NameTools[ntRemoveThe]': () => nameTool('removeThe'),
    'NameTools[ntTheToEnd]': () => nameTool('theToEnd'),
    'NameTools[ntTheToFront]': () => nameTool('theToFront'),
    'NameTools[ntNameToSurnameFirst]': () => nameTool('nameToSurnameFirst'),
    'NameTools[ntSurnameFirstToName]': () => nameTool('surnameFirstToName'),
    aCopy: copyTag,
    FActPaste: pasteTag,
    aSync: id3Sync,
    aRemoveTags: removeTags,
    aTracks: trackTools,
    aEdit: editTag,
    aMulti: multiEdit,
    aRenameDlg: () => renameDialog(false),
    aRenameFolder: () => renameDialog(true),
    aF2TDlg: f2tDialog,
    aRenameManual: () => (treeFocused ? renameFolderManual() : renameFileDialog()),
    FActUndo: undoRename,
    aWords: editWords,
    FActManageActions: manageActions,
    aCoverIn: covers.coverIn,
    aCoverOut: covers.coverOut,
    aCoverAsFolder: covers.coverAsFolder,
    aResizeFiles: covers.resizeFiles,
    aResizeFolders: covers.resizeFolders,
    FActAutoResize: covers.toggleAutoResize,
    // phase 5
    aFind: findFilter,
    aMoveUp: () => moveSelected(-1),
    aMoveDown: () => moveSelected(1),
    aRandom: () => { LISTVIEW.shuffle(state, FIELD_KEYS); manualOrder(); },
    aAutoFit: autoFit,
    FActAutoFitAfterScan: toggleAutoFitAfterScan,
    aExpandFolders: expandFolders,
    aCollapseFolders: () => { TREE.collapseAll(); TREE.reveal(state.folder); },
    aNewFolder: newFolder,
    FActDeleteFiles: deleteFiles,
    aCopyTo: () => copyOrMoveTo(false),
    aMoveTo: () => copyOrMoveTo(true),
    aDelFolderCover: deleteFolderCovers,
    aExtM4A: () => changeExt(0),
    aExtM4B: () => changeExt(1),
    aExtM4BBack: () => changeExt(2),
    aOpen: openFolder,
    aExplorer: showInExplorer,
    aProperties: showProperties,
    aPlay: playFile,
    aPlayFolder: playFolder,
    aPlChecked: () => savePlaylistDialog(SAVE.targets(state).items),
    aPlAll: () => savePlaylistDialog(state.items),
    aQuickPlaylist: quickPlaylist,
  };
  const ENABLED = {
    aUp: () => !!state.folder,
    aCopy: () => state.focus >= 0,
    FActPaste: () => !!tools.clip,
    aTracks: () => state.items.length > 0,
    aEdit: () => state.items.length > 0,
    aRenameDlg: () => state.items.length > 0,
    aRenameFolder: () => state.items.length > 0,
    aF2TDlg: () => state.items.length > 0,
    aRenameManual: () => treeFocused || state.items.length > 0,
    FActUndo: () => !!undoLog,
    aMoveUp: () => state.sel.size > 0,
    aMoveDown: () => state.sel.size > 0,
    aNewFolder: () => !!state.folder,
  };
  const CHECKED = {
    FActToolsPanel: () => state.view.tools, FActFolders: () => state.view.folders,
    FActAddress: () => state.view.address, FActFilter: () => state.view.filter, FActSubfolders: () => state.view.subfolders,
    FActKeepDate: () => bool('Editor', 'KeepTimestamp', false),
    FActAutoResize: () => bool('Cover', 'AutoResize', false),
    FActAutoFitAfterScan: () => bool('View', 'AutoFitColumns', false),
  };
  function showTab(i) {
    if (!state.view.tools) toggleView('tools', 'View', 'ToolsPanel');
    PANEL.show(i);
  }

  // menus filled at run time
  function dynamic(item) {
    if (item.special === 'language') {
      const cur = get('Main', 'Language', '');
      return {
        text: t(RS.rsSprogLanguage), enabled: true,
        items: [{ text: t(RS.rsAutomatiskWindowsSprog), checked: cur === '', radio: true, run: () => setLanguage('') },
          ...Object.entries(I18N.LANGS).map(([c, n]) => ({ text: n, checked: cur === c, radio: true, run: () => setLanguage(c) }))],
      };
    }
    if (item.special === 'albumArtist') {
      const cur = Number(get('Main', 'AlbumArtistRule', 0)) || 0;
      return {
        text: t(RS.rsAlbumkunstnerVedGem), enabled: true,
        items: [RS.rsAlbumkunstnerIngen, RS.rsAlbumkunstnerHvisTom, RS.rsAlbumkunstnerAltid].map((text, i) =>
          ({ text: t(text), checked: cur === i, radio: true, run: () => save('Main', 'AlbumArtistRule', i) })),
      };
    }
    if (item.dynamic && item.text === MENUDATA.rs.rsOmdoebningshandlingerMenu) { // from: RebuildActionsMenu
      const acts = renameActions();
      return { text: t(item.text), enabled: true,
        items: [...acts.map((a) => ({ text: a.name.replace(/&/g, '&&'), run: () => runRenameAction(a) })), ...(acts.length ? ['-'] : []),
          { ref: 'FActManageActions' }] };
    }
    if (item.dynamic && item.text === RS.rsSenesteMapper) { // from: RebuildRecentMenu
      const recent = state.history.slice(0, 15);
      return { text: t(item.text), enabled: recent.length > 0, items: recent.map((p) => ({ text: p.replace(/&/g, '&&'), run: () => navigate(p) })) };
    }
    if (item.dynamic && item.text === RS.rsAfspilMed) return { text: t(item.text), enabled: true, items: playWithMenu() }; // from: RebuildPlayWith
    return null;
  }

  // ---------- splitter (tree width, [Main] TreeWidth) ----------
  $('#splitter').addEventListener('mousedown', (ev) => {
    ev.preventDefault();
    const sp = $('#splitter'), x0 = ev.clientX, w0 = $('#folders').offsetWidth;
    sp.classList.add('drag');
    const move = (e) => { $('#folders').style.width = Math.max(140, Math.min(innerWidth - 300, w0 + e.clientX - x0)) + 'px'; };
    const up = () => {
      sp.classList.remove('drag');
      removeEventListener('mousemove', move);
      removeEventListener('mouseup', up);
      save('Main', 'TreeWidth', $('#folders').offsetWidth);
      renderRows();
    };
    addEventListener('mousemove', move);
    addEventListener('mouseup', up);
  });

  // an action that fails must say so, not just do nothing
  addEventListener('error', (e) => DIALOG.info(String(e.error || e.message)));
  addEventListener('unhandledrejection', (e) => DIALOG.info(String(e.reason)));

  // ---------- start ----------
  async function start() {
    await loadSettings();
    I18N.setLang(I18N.effectiveLanguage(get('Main', 'Language', ''), navigator.language));
    document.documentElement.lang = I18N.lang;
    state.view = {
      tools: bool('View', 'ToolsPanel', true), folders: bool('View', 'Folders', true),
      address: bool('View', 'Address', true), filter: bool('View', 'Filter', true),
      subfolders: bool('Main', 'Subfolders', false),
    };
    state.history = list('AddressHistory', 20);
    state.favorites = list('Favorites', 50);
    const tw = Number(get('Main', 'TreeWidth', 0));
    if (tw > 0) $('#folders').style.width = tw + 'px';
    applyTexts();
    MENU.init({
      run: (id) => ACTIONS[id]?.(),
      live: (id) => !!ACTIONS[id],
      hint: (id) => (id === 'FActUndo' && undoLog ? t(RS.rsFortrydOmdoebningAfDS, undoLog.length, undoWhat) : undefined),
      enabled: (id) => !!ACTIONS[id] && (!ENABLED[id] || ENABLED[id]()),
      checked: (id) => !!CHECKED[id]?.(),
      dynamic,
    });
    PANEL.init(S, {
      saveMulti,
      focusedFields: () => state.items[state.focus]?.fields,
      previewTrack: () => state.items[state.focus] || state.items[0],
      renameDo, f2tDo,
      renamePreview: () => ACTIONS.aRenameDlg?.(),
      f2tPreview: () => ACTIONS.aF2TDlg?.(),
      undo: () => ACTIONS.FActUndo?.(),
      canUndo: () => !!undoLog,
      maskEditor,
      openMulti: () => ACTIONS.aMulti(),
    });
    PLAYER.init({ all: () => state.all, playTargets, saveVolume: (v) => save('Player', 'Volume', v) }, Number(get('Player', 'Volume', 80)));
    API.playerAvailable().then((a) => { playerAvailable = a; });
    refreshPlayWith();
    applyView();
    renderHeader();
    renderRows();
    updateStatus();
    $('#lang-select').addEventListener('change', (e) => setLanguage(e.target.value));
    $('#address').addEventListener('keydown', (e) => { if (e.key === 'Enter') navigate(e.target.value.trim()); });
    $('#address').addEventListener('change', (e) => { if (state.history.includes(e.target.value)) navigate(e.target.value); });
    await TREE.init($('#tree'), (path) => navigate(path, { fromTree: true }));
    const last = get('Main', 'FixedStartFolder', '0') === '1' && get('Main', 'StartFolder') ? get('Main', 'StartFolder') : get('Main', 'LastFolder');
    const given = await API.startPaths(); // from Explorer's "Åbn i TidyTag"
    if (given.length) openPaths(given);
    else if (last) navigate(last);
  }
  start();
})();
