// "Rediger flere filer" (1.2's TFormMultiEdit): the same fields in many files. Only ticked
// fields are written; covers can be replaced or removed in all files. MULTI is the part
// node --test can run.
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.MULTI = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  const ptrim = (s) => String(s).replace(/^[\u0000- ]+|[\u0000- ]+$/g, '');
  // from: EditFields
  const EDIT_FIELDS = ['artist', 'album', 'albumArtist', 'composer', 'year', 'disc', 'genre', 'bpm', 'comment',
    'publisher', 'catalogNo', 'grouping', 'conductor', 'copyright', 'mood'];

  // from: FillCommonValues
  function commonValue(tracks, key) {
    const first = tracks[0]?.fields[key] || '';
    const same = tracks.every((tr) => (tr.fields[key] || '') === first);
    return { value: same ? first : '', same };
  }

  // from: ButtonApplyClick — ticked rows that are empty clear their field
  const clearedKeys = (rows) => rows.filter((r) => r.on && !ptrim(r.value)).map((r) => r.key);

  /** rows: [{ key, on, value }]; cover: null | { mode: 'replace', mime, data } | { mode: 'remove' } */
  function buildItems(tracks, rows, cover) {
    const values = {};
    for (const r of rows) if (r.on) values[r.key] = ptrim(r.value);
    const pictures = cover?.mode === 'replace' ? [{ picType: 3, mime: cover.mime, description: '', data: cover.data }] : null;
    return tracks.map((tr) => ({ path: tr.path, values: { ...values }, cover: null, pictures, removeCovers: cover?.mode === 'remove' }));
  }

  return { EDIT_FIELDS, commonValue, clearedKeys, buildItems };
});

(function () {
  'use strict';
  if (typeof document === 'undefined') return;
  const { t, label } = I18N;
  const RS = { ...MENUDATA.rs, ...MENUDATA.unitRs.multieditform };
  const esc = FORMS.esc;
  const cap = (k) => t(MENUDATA.fieldCaptions[k]);
  const SHORT = ['year', 'disc', 'bpm'];

  /** host: { items, scopeCaption, keep, setKeep(on) -> Promise, genres() -> Promise<[string]>,
   *  write(items, onProgress) -> Promise<write-done | null>, cancel() }. Resolves on close. */
  function open(host) {
    return new Promise((resolve) => {
      const n = host.items.length;
      let cover = null, running = false; // cover: { mime, data, name }
      const rowsHtml = MULTI.EDIT_FIELDS.map((k) => {
        const c = MULTI.commonValue(host.items, k);
        return `<label class="chk-label" title="${esc(t(RS.rsSaetFluebenForAtGemme))}"><input type="checkbox" data-mk="${k}"> ${esc(cap(k))}</label>
          <input class="input${SHORT.includes(k) ? ' w170' : ''}" data-mv="${k}" spellcheck="false" value="${esc(c.value)}"
            ${c.same ? '' : `placeholder="${esc(t(RS.rsForskelligeVaerdier))}"`}${k === 'genre' ? ' list="me-genres"' : ''}>`;
      }).join('');
      const m = FORMS.modal(`<h2>${esc(t(RS.rsRedigerFlereFiler) + host.scopeCaption)}</h2>
        <div class="lbl">${esc(t(RS.rsAendringerneGemmesIDFiler, n))}</div>
        <div class="me-body"><div class="me-fields"><div class="me-grid">${rowsHtml}</div><datalist id="me-genres"></datalist></div>
          <fieldset class="radio-group me-cover"><legend>${esc(t('Cover'))}</legend>
            <label class="chk-label"><input type="checkbox" data-replace> ${esc(t('Erstat alle covers med:'))}</label>
            <div class="frow"><button class="btn" data-choose>${esc(label(t('Vælg billede...')))}</button></div>
            <div class="lbl" data-coverfile>${esc(t('(intet billede valgt)'))}</div>
            <div class="me-cover-img" data-img></div>
            <label class="chk-label"><input type="checkbox" data-remove> ${esc(t('Fjern alle cover-billeder'))}</label></fieldset></div>
        <label class="chk-label"><input type="checkbox" data-keep${host.keep ? ' checked' : ''}> ${esc(t('Bevar filernes dato (tidsstempel)'))}</label>
        <progress max="${n}" value="0" hidden></progress>
        <div class="ed-bottom"><span class="lbl grow" data-status></span>
          <button class="btn primary" data-apply>${esc(label(t(RS.rsGemIDFiler, n)))}</button>
          <button class="btn" data-close>${esc(label(t(RS.rsLuk)))}</button></div>`,
      { cls: 'multi-editor', onEscape: () => closeOrCancel(), onEnter: () => apply() });
      const q = (s) => m.el.querySelector(s);
      host.genres().then((g) => { q('#me-genres').innerHTML = g.map((x) => `<option value="${esc(x)}"></option>`).join(''); });

      // from: ValueChange — typing ticks the field
      m.el.addEventListener('input', (e) => {
        const k = e.target.dataset.mv;
        if (k) q(`[data-mk="${k}"]`).checked = true;
      });

      // from: ButtonChooseCoverClick
      async function chooseCover() {
        const p = t('Billeder (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png').split('|');
        const path = await window.__TAURI__.dialog.open({ filters: [{ name: p[0], extensions: ['jpg', 'jpeg', 'png'] }] });
        if (!path) return;
        try {
          const img = await API.readImageFile(path);
          cover = { ...img, name: path.replace(/^.*[\\/]/, '') };
        } catch (e) {
          return DIALOG.info(e === 'tooLarge' ? t('Billedet er for stort (højst 16 MB).') : e === 'notImage' ? t(RS.rsKunJpegOgPngBilleder) : String(e));
        }
        q('[data-coverfile]').textContent = cover.name + t(RS.rsDKb, Math.ceil((cover.data.length * 3) / 4 / 1024));
        q('[data-img]').innerHTML = `<img alt="" src="data:${esc(cover.mime)};base64,${esc(cover.data)}">`;
        q('[data-replace]').checked = true;
        q('[data-remove]').checked = false;
      }
      q('[data-choose]').addEventListener('click', chooseCover);
      // from: CheckReplaceCoverChange / CheckRemoveCoversChange
      q('[data-replace]').addEventListener('change', async (e) => {
        if (!e.target.checked) return;
        q('[data-remove]').checked = false;
        if (!cover) await chooseCover();
        if (!cover) e.target.checked = false;
      });
      q('[data-remove]').addEventListener('change', (e) => { if (e.target.checked) q('[data-replace]').checked = false; });

      const rows = () => MULTI.EDIT_FIELDS.map((k) => ({ key: k, on: q(`[data-mk="${k}"]`).checked, value: q(`[data-mv="${k}"]`).value }));
      function setRunning(on) {
        running = on;
        m.el.querySelectorAll('.me-body input, .me-body button, [data-apply], [data-keep]').forEach((el) => { el.disabled = on; });
        q('[data-close]').textContent = label(t(on ? RS.rsAnnuller : RS.rsLuk));
        q('progress').hidden = false;
      }

      // from: ButtonApplyClick
      async function apply() {
        if (running) return;
        const rs = rows();
        const coverMode = q('[data-remove]').checked ? { mode: 'remove' } : q('[data-replace]').checked && cover ? { mode: 'replace', ...cover } : null;
        if (!rs.some((r) => r.on) && !coverMode) return DIALOG.info(t(RS.rsSaetFluebenVedDeFelter));
        const cleared = MULTI.clearedKeys(rs).map(cap);
        const ok = cleared.length
          ? await DIALOG.confirm(t(RS.rsRydFelter), t(RS.rsFelterneSErTommeOg, cleared.join(', '), n))
          : await DIALOG.confirm(t(RS.rsGem), t(RS.rsGemAendringerneIDFiler, n));
        if (!ok) return;
        setRunning(true);
        const status = q('[data-status]'), bar = q('progress');
        await host.setKeep(q('[data-keep]').checked); // the batch reads it from the ini
        const msg = await host.write(MULTI.buildItems(host.items, rs, coverMode), (p) => {
          bar.value = p.done - 1;
          status.textContent = t(RS.rsGemmerDAfDS, p.done, p.total, host.items[p.done - 1]?.fileName || '');
        });
        setRunning(false);
        bar.value = n;
        if (!msg) return;
        status.textContent = (msg.cancelled ? t(RS.rsAfbrudt) : '') + t(RS.rsGemtIDFilerD, msg.saved, msg.skipped, msg.failed);
        if (msg.errors.length) {
          await DIALOG.info(msg.errors.map((e) => `${e.file}: ${t(e.error)}`).join('\n'), t(RS.rsNogleFilerBlevIkkeGemt));
        }
      }
      q('[data-apply]').addEventListener('click', apply);

      // from: ButtonCloseClick / FormCloseQuery — never close in the middle of a file
      function closeOrCancel() {
        if (running) return host.cancel();
        const keep = q('[data-keep]').checked;
        m.close();
        host.setKeep(keep);
        resolve();
      }
      q('[data-close]').addEventListener('click', closeOrCancel);
      q('[data-mv="artist"]').focus();
    });
  }

  window.MULTIEDITOR = { open };
})();
