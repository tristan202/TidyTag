// "Rediger tag" (1.2's TFormTagEdit): every field of one file, its pictures and lyrics, with
// Gem og forrige / Gem / Gem og næste. EDITOR_STATE is the part node --test can run.
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.EDITOR_STATE = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  const ptrim = (s) => String(s).replace(/^[\u0000- ]+|[\u0000- ]+$/g, '');
  const FLAGS = ['compilation', 'podcast'];

  const create = (index, count) => ({ index, count, modified: false });
  const setModified = (st, on) => { st.modified = on; };
  // from: FormCloseQuery — only closing can lose changes; the move buttons save first
  const needsQuestion = (st, action) => st.modified && action === 'close';
  // from: UpdateButtons
  const next = (index, count) => ({ prev: index > 0, next: index < count - 1 });
  // from: IsTrueFlag
  function isTrueFlag(s) {
    const t = ptrim(s || '').toLowerCase();
    return t === 'true' || t === 'yes' || (/^[+-]?\d+$/.test(t) && parseInt(t, 10) !== 0);
  }
  // from: SaveCurrent — trimmed text; flags as '1' or ''
  function collectFields(raw) {
    const out = {};
    for (const [k, v] of Object.entries(raw)) out[k] = FLAGS.includes(k) ? (v ? '1' : '') : ptrim(v);
    return out;
  }
  return { create, setModified, needsQuestion, next, isTrueFlag, collectFields, FLAGS };
});

(function () {
  'use strict';
  if (typeof document === 'undefined') return;
  const E = EDITOR_STATE;
  const { t, label } = I18N;
  const RS = { ...MENUDATA.rs, ...MENUDATA.unitRs.tageditform };
  const esc = FORMS.esc;
  const cap = (k) => t(MENUDATA.fieldCaptions[k]);
  const KEYS = Object.keys(MENUDATA.fieldCaptions);
  const MORE_LEFT = ['conductor', 'lyricist', 'origArtist', 'remixer', 'publisher', 'catalogNo', 'isrc'];
  const MORE_RIGHT = ['copyright', 'encodedBy', 'url', 'grouping', 'subtitle', 'mood', 'initialKey'];
  const SORT = ['sortTitle', 'sortArtist', 'sortAlbumArtist', 'sortAlbum', 'sortComposer'];
  const RG = ['rgTrackGain', 'rgTrackPeak', 'rgAlbumGain', 'rgAlbumPeak'];
  // from: PictureTypeName
  const PIC_TYPES = { 0: 'Andet', 1: 'Fil-ikon', 2: 'Fil-ikon', 3: 'Forside', 4: 'Bagside', 5: 'Indlægsseddel', 6: 'Medie (CD)',
    7: 'Solist', 8: 'Kunstner', 9: 'Dirigent', 10: 'Orkester', 11: 'Komponist', 12: 'Tekstforfatter', 13: 'Optagested',
    14: 'Under optagelse', 15: 'Under optagelse', 18: 'Illustration', 19: 'Kunstnerlogo', 20: 'Udgiverlogo' };
  const picTypeName = (n) => t(PIC_TYPES[n] || 'Billede');
  const extOf = (mime) => ({ 'image/png': 'png', 'image/gif': 'gif', 'image/bmp': 'bmp' })[mime] || 'jpg';
  const dirOf = (p) => p.replace(/[\\/][^\\/]*$/, '');
  const baseOf = (p) => p.replace(/^.*[\\/]/, '');
  const dialog = () => window.__TAURI__.dialog;
  // a Lazarus filter ('Name|*.a;*.b|...'), translated whole as 1.2 does, for the Tauri dialog
  const filters = (laz) => {
    const p = t(laz).split('|'), out = [];
    for (let i = 0; i + 1 < p.length; i += 2) out.push({ name: p[i], extensions: p[i + 1].split(';').map((x) => x.replace(/^\*\./, '')) });
    return out;
  };

  function utf8Base64(text) {
    const bytes = new TextEncoder().encode(text);
    let bin = '';
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(bin);
  }

  const input = (k, cls = 'grow') => `<input class="input ${cls}" data-f="${k}" spellcheck="false">`;
  const row = (k, cls) => `<span class="lbl">${esc(cap(k))}</span>${input(k, cls)}`;

  /** host: { index, count, fileAt(i) -> path, keep, setKeep(on) -> Promise, saved(i, track),
   *  genres() -> Promise<[string]> }. Resolves when the editor is closed. */
  function open(host) {
    return new Promise((resolve) => {
      const st = E.create(host.index, host.count);
      let tag = null, pictures = [], pic = 0, loading = false, busy = false;
      const tab = (id, text, on) => `<button class="tab${on ? ' on' : ''}" data-tab="${id}">${esc(t(text))}</button>`;
      const m = FORMS.modal(`<h2 data-title></h2><div class="lbl ellipsis" data-file></div>
        <div class="tabs">${tab('gen', 'Generelt', true)}${tab('more', 'Flere felter')}${tab('sort', 'Sortering')}${tab('rg', 'ReplayGain')}${tab('lyr', 'Sangtekst')}</div>
        <div class="tab-page" data-page="gen"><div class="ed-general">
          <div class="ed-grid">${row('title')}${row('artist')}${row('album')}${row('albumArtist')}${row('composer')}
            <span class="lbl">${esc(cap('year'))}</span><div class="frow">${input('year', 'w90')}
              <span class="lbl">${esc(cap('track'))}</span>${input('track', 'w70')}<span class="lbl">${esc(cap('disc'))}</span>${input('disc', 'w60')}</div>
            <span class="lbl">${esc(cap('genre'))}</span><div class="frow"><input class="input grow" data-f="genre" list="ed-genres" spellcheck="false">
              <datalist id="ed-genres"></datalist><span class="lbl">${esc(cap('bpm'))}</span>${input('bpm', 'w90')}</div>
            <span class="lbl top">${esc(cap('comment'))}</span><textarea class="input" data-f="comment" rows="5"></textarea></div>
          <div class="ed-cover"><div class="ed-cover-img" data-img></div><div class="lbl" data-picinfo></div>
            <div class="frow"><button class="btn" data-act="add">${esc(label(t('Tilføj...')))}</button>
              <button class="btn" data-act="remove">${esc(label(t('Fjern')))}</button>
              <button class="btn" data-act="savepic">${esc(label(t('Gem som...')))}</button></div>
            <div class="frow"><button class="btn" data-act="prevpic">&lt;</button><button class="btn" data-act="nextpic">&gt;</button></div></div></div></div>
        <div class="tab-page" data-page="more" hidden><div class="ed-more">
          <div class="ed-grid">${MORE_LEFT.map((k) => row(k)).join('')}</div>
          <div class="ed-grid">${MORE_RIGHT.map((k) => row(k)).join('')}</div>
          ${E.FLAGS.map((k) => `<label class="chk-label"><input type="checkbox" data-f="${k}"> ${esc(cap(k))}</label>`).join('')}</div></div>
        <div class="tab-page" data-page="sort" hidden><div class="ed-grid narrow">${SORT.map((k) => row(k)).join('')}</div>
          <p class="notes">${esc(t(RS.rsSorteringsfelterBestemmerHvordanAfspillereSorterer))}</p></div>
        <div class="tab-page" data-page="rg" hidden><div class="ed-grid narrow">${RG.map((k) => row(k)).join('')}</div>
          <p class="notes">${esc(t(RS.rsRGEditorHjaelp))}</p></div>
        <div class="tab-page" data-page="lyr" hidden><textarea class="input ed-lyrics" data-f="lyrics"></textarea>
          <div class="frow"><button class="btn" data-act="loadlyr">${esc(label(t('Indlæs fra tekstfil...')))}</button>
            <button class="btn" data-act="savelyr">${esc(label(t('Gem som tekstfil...')))}</button>
            <button class="btn" data-act="clearlyr">${esc(label(t('Ryd')))}</button></div></div>
        <div class="lbl" data-info></div>
        <div class="ed-bottom"><label class="chk-label"><input type="checkbox" data-keep${host.keep ? ' checked' : ''}> ${esc(t('Bevar filens dato (tidsstempel) ved gem'))}</label>
          <span class="grow"></span>
          <button class="btn" data-act="saveprev">${esc(label(t('Gem og forrige')))}</button>
          <button class="btn primary" data-act="save"></button>
          <button class="btn" data-act="savenext">${esc(label(t('Gem og næste')))}</button>
          <button class="btn" data-act="close">${esc(label(t('Luk')))}</button></div>`,
      { cls: 'tag-editor', onEscape: () => close(), onEnter: () => act('save') });
      const q = (s) => m.el.querySelector(s);
      const fieldEls = () => [...m.el.querySelectorAll('[data-f]')];
      host.genres().then((g) => { q('#ed-genres').innerHTML = g.map((x) => `<option value="${esc(x)}"></option>`).join(''); });

      function setModified(on) {
        E.setModified(st, on);
        q('[data-act="save"]').textContent = label(t(on ? RS.rsGem : RS.rsGem2));
      }
      const writable = () => tag && !tag.track.error && TOOLS.canWriteTags(tag.track.path);
      // from: UpdateButtons
      function updateButtons() {
        const w = writable(), has = pictures.length > 0, mv = E.next(st.index, st.count);
        const en = { save: w, saveprev: w && mv.prev, savenext: w && mv.next, add: w, remove: w && has, savepic: has,
          prevpic: has && pic > 0, nextpic: has && pic < pictures.length - 1 };
        for (const [k, on] of Object.entries(en)) q(`[data-act="${k}"]`).disabled = busy || !on;
      }

      // from: LoadFile
      async function load(index) {
        const path = host.fileAt(index);
        if (!path) return;
        const r = await API.readTag(path);
        tag = r;
        st.index = index;
        pictures = r.pictures.slice();
        pic = 0;
        loading = true;
        for (const el of fieldEls()) {
          const v = r.track.fields[el.dataset.f] || '';
          if (el.type === 'checkbox') el.checked = E.isTrueFlag(v); else el.value = v;
        }
        loading = false;
        q('[data-file]').textContent = baseOf(path);
        q('[data-file]').title = path;
        q('[data-title]').textContent = t(RS.rsRedigerTagDAfD, index + 1, st.count, baseOf(path));
        const tr = r.track;
        let info = tr.error ? t(RS.rsFejlVedLaesning) + t(tr.error)
          : t(RS.rsSSDKbitS, tr.codec, LIST.formatDuration(tr.duration), tr.bitrate, tr.sampleRate, tr.channels, tr.tagTypes || t(RS.rsIngenTags));
        if (!TOOLS.canWriteTags(path)) info += t(RS.rsKanIkkeGemmeDenneFiltype);
        q('[data-info]').textContent = info;
        showPicture();
        setModified(false);
      }

      // from: ShowPicture
      function showPicture() {
        const box = q('[data-img]'), infoEl = q('[data-picinfo]');
        if (!pictures.length) {
          box.innerHTML = '';
          infoEl.textContent = t(RS.rsIntetBillede);
          return updateButtons();
        }
        pic = Math.max(0, Math.min(pic, pictures.length - 1));
        const p = pictures[pic];
        const text = t(RS.rsBilledeDAfDS, pic + 1, pictures.length, picTypeName(p.picType), extOf(p.mime).toUpperCase());
        const kb = t(RS.rsDKb, Math.ceil((p.data.length * 3) / 4 / 1024));
        infoEl.textContent = text + kb;
        const img = new Image();
        img.alt = '';
        img.onload = () => { if (img.naturalWidth) infoEl.textContent = text + t(RS.rsDxD, img.naturalWidth, img.naturalHeight) + kb; };
        img.src = `data:${p.mime};base64,${p.data}`;
        box.replaceChildren(img);
        updateButtons();
      }

      // from: SaveCurrent
      async function saveCurrent() {
        const raw = {};
        for (const el of fieldEls()) raw[el.dataset.f] = el.type === 'checkbox' ? el.checked : el.value;
        const fields = E.collectFields(raw);
        for (const k of KEYS) if (!(k in fields)) fields[k] = ''; // every field is written, as 1.2
        busy = true;
        updateButtons();
        try {
          await host.setKeep(q('[data-keep]').checked); // the save reads it from the ini
          const track = await API.saveTag(tag.track.path, fields, pictures);
          setModified(false);
          host.saved(st.index, track);
          return true;
        } catch (e) {
          await DIALOG.info(`${t(RS.rsTagsBlevIkkeGemtI)}\n${tag.track.path}\n\n${t(String(e))}`, t(RS.rsKunneIkkeGemme));
          return false;
        } finally {
          busy = false;
          updateButtons();
        }
      }

      async function addPicture() {
        const path = await dialog().open({ filters: filters('Billeder (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png') });
        if (!path) return;
        let img;
        try {
          img = await API.readImageFile(path);
        } catch (e) {
          return DIALOG.info(e === 'tooLarge' ? t('Billedet er for stort (højst 16 MB).') : e === 'notImage' ? t(RS.rsKunJpegOgPngBilleder) : String(e));
        }
        // the first picture becomes the front cover; further ones are "other"
        pictures.push({ picType: pictures.length ? 0 : 3, mime: img.mime, description: '', data: img.data });
        pic = pictures.length - 1;
        showPicture();
        setModified(true);
      }
      async function savePicture() {
        const p = pictures[pic];
        if (!p) return;
        const ext = p.mime === 'image/png' ? 'png' : 'jpg';
        const path = await dialog().save({ defaultPath: dirOf(tag.track.path) + '\\folder.' + ext,
          filters: filters(ext === 'png' ? RS.rsPngBilledePng : RS.rsJpegBilledeJpg) });
        if (path) await API.writeFile(path, p.data).catch((e) => DIALOG.info(String(e)));
      }
      async function loadLyrics() {
        const path = await dialog().open({ filters: filters('Tekstfiler (*.txt;*.lrc)|*.txt;*.lrc|Alle filer (*.*)|*.*') });
        if (!path) return;
        try {
          q('[data-f="lyrics"]').value = (await API.readTextFile(path)).replace(/\r\n/g, '\n');
          setModified(true);
        } catch (e) { DIALOG.info(String(e)); }
      }
      async function saveLyrics() {
        const path = await dialog().save({ defaultPath: tag.track.path.replace(/\.[^.\\/]*$/, '') + '.txt',
          filters: filters('Tekstfil (*.txt)|*.txt') });
        if (!path) return;
        const text = q('[data-f="lyrics"]').value.replace(/\r?\n/g, '\r\n');
        await API.writeFile(path, utf8Base64(text.endsWith('\r\n') || !text ? text : text + '\r\n')).catch((e) => DIALOG.info(String(e)));
      }

      async function act(a) {
        if (busy) return;
        const b = q(`[data-act="${a}"]`);
        if (b && b.disabled) return;
        if (a === 'save') { if (await saveCurrent()) load(st.index); }
        else if (a === 'saveprev') { if (await saveCurrent()) load(st.index - 1); }
        else if (a === 'savenext') { if (await saveCurrent()) load(st.index + 1); }
        else if (a === 'close') close();
        else if (a === 'add') addPicture();
        else if (a === 'remove') { pictures.splice(pic, 1); showPicture(); setModified(true); }
        else if (a === 'savepic') savePicture();
        else if (a === 'prevpic') { pic -= 1; showPicture(); }
        else if (a === 'nextpic') { pic += 1; showPicture(); }
        else if (a === 'loadlyr') loadLyrics();
        else if (a === 'savelyr') saveLyrics();
        else if (a === 'clearlyr') { q('[data-f="lyrics"]').value = ''; setModified(true); }
      }

      // from: FormCloseQuery
      async function close() {
        if (busy) return;
        if (E.needsQuestion(st, 'close')) {
          const r = await DIALOG.yesNoCancel(t(RS.rsGemAendringer), t(RS.rsDerErAendringerSomIkke));
          if (r === null || (r === 'yes' && !(await saveCurrent()))) return;
        }
        const keep = q('[data-keep]').checked;
        m.close();
        host.setKeep(keep);
        resolve();
      }

      m.el.addEventListener('click', (e) => {
        const tb = e.target.closest('[data-tab]');
        if (tb) {
          m.el.querySelectorAll('[data-tab]').forEach((x) => x.classList.toggle('on', x === tb));
          m.el.querySelectorAll('[data-page]').forEach((p) => { p.hidden = p.dataset.page !== tb.dataset.tab; });
          return;
        }
        const b = e.target.closest('[data-act]');
        if (b) act(b.dataset.act);
      });
      m.el.addEventListener('input', (e) => { if (!loading && e.target.matches('[data-f]')) setModified(true); });
      m.el.addEventListener('change', (e) => { if (!loading && e.target.matches('[data-f][type="checkbox"]')) setModified(true); });
      load(host.index).then(() => q('[data-f="title"]').focus());
    });
  }

  window.TAGEDITOR = { open };
})();
