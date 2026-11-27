// "Tags fra filnavn" (1.2's TFormFileToTag): the mask with a live preview that has a column per
// field the mask fills, then Skriv tags for the ready files.
(function () {
  'use strict';
  const { t, label } = I18N;
  const U = MENUDATA.unitRs;
  const RS = { ...MENUDATA.rs, ...U.renamecore, ...U.filenametags, ...U.filetotagform };
  const esc = FORMS.esc;
  const DEFAULT_MASKS = ['%1 - %2', '%6 - %2', '%6 - %1 - %2', '%6. %2', '%6 %1 - %2', '%1\\%3\\%6 - %2', '%1\\%4 - %3\\%6 - %2'];
  const CASE_NAMES = ['rsUaendret', 'rsHvertOrdMedStort', 'rsFoersteBogstavStort', 'rsSmaaBogstaver', 'rsStoreBogstaver'];
  const NUMERIC = ['track', 'disc', 'year', 'bpm'];
  // from: RowStatusText
  const STATUS = { ready: 'rsKlar', unchanged: 'rsUaendret', noMatch: 'rsPasserIkkeTilMasken', notWritable: 'rsFiltypenKanIkkeGemmesEndnu',
    saved: 'rsGemt', failed: 'rsFejl' };

  /** host: { all, subset, subsetCaption, prefer, keep, get, save, history(section), addToHistory(section, mask),
   *  write(items, keep, onProgress) -> Promise<write-done | null> }. Resolves with "Bevar filens dato". */
  function open(host) {
    return new Promise((resolve) => {
      const masks = host.history('FileToTagMasks');
      const list = masks.length ? masks : DEFAULT_MASKS;
      const saved = host.get('FileToTag', 'Mask', list[0]);
      const mask0 = saved.trim() ? saved : list[0];
      const caseMode = Math.min(4, Math.max(0, parseInt(host.get('FileToTag', 'Case', 0), 10) || 0));
      const usOn = !['0', 'false'].includes(String(host.get('FileToTag', 'Underscores', '1')).toLowerCase());
      const scope0 = host.prefer && host.subset.length ? 0 : 1;
      let rows = [], fields = [], busy = false;
      const m = FORMS.modal(`<h2>${esc(t('Tags fra filnavn'))}</h2>
        <div class="track-top">
          <div class="form-grid rn-grid">
            <span class="lbl">${esc(t('Filnavnsmaske:'))}</span>
            <div><input class="input grow" name="mask" list="fd-masks" spellcheck="false" value="${esc(mask0)}">
              <datalist id="fd-masks">${list.map((x) => `<option value="${esc(x)}"></option>`).join('')}</datalist></div>
            <span class="lbl">${esc(t('Versaler:'))}</span>
            <div class="frow"><select name="case">${CASE_NAMES.map((n, i) => `<option value="${i}"${i === caseMode ? ' selected' : ''}>${esc(t(RS[n]))}</option>`).join('')}</select>
              <label class="chk-label"><input type="checkbox" name="us"${usOn ? ' checked' : ''}> ${esc(t('Erstat _ med mellemrum'))}</label></div>
          </div>
          <fieldset class="radio-group"><legend>${esc(t('Filer'))}</legend>${[host.subsetCaption, t(RS.rsAlleFilerIListenD, host.all.length)].map((s, i) =>
            `<label class="chk-label"><input type="radio" name="scope" value="${i}"${i === scope0 ? ' checked' : ''}> ${esc(s)}</label>`).join('')}</fieldset>
        </div>
        <p class="notes">${esc(t(RS.FileToTagVariablesHelp))}</p>
        <div class="track-list"><table><thead></thead><tbody></tbody></table></div>
        <div class="track-bottom"><label class="chk-label"><input type="checkbox" name="keep"${host.keep ? ' checked' : ''}> ${esc(t('Bevar filens dato'))}</label>
          <span class="lbl" data-summary></span>
          <button class="btn primary" data-run>${esc(label(t(RS.rsSkrivTags)))}</button>
          <button class="btn" data-close>${esc(label(t('Luk')))}</button></div>`,
      { cls: 'wide track-tools', onEscape: () => close() });
      const q = (s) => m.el.querySelector(s);
      const opts = () => ({ mask: q('[name="mask"]').value, caseMode: Number(q('[name="case"]').value), underscores: q('[name="us"]').checked });
      const scopeItems = () => (Number(q('[name="scope"]:checked').value) === 0 && host.subset.length ? host.subset : host.all);
      const count = (s) => rows.filter((r) => r.status === s).length;

      // from: ShowRows — file, one column per field in the mask, status
      function show() {
        q('thead').innerHTML = `<tr><th>${esc(t(RS.rsFil))}</th>${fields.map((k) =>
          `<th class="${NUMERIC.includes(k) ? 'num' : ''}">${esc(t(MENUDATA.fieldCaptions[k]))}</th>`).join('')}<th>${esc(t(RS.rsStatus))}</th></tr>`;
        q('tbody').innerHTML = rows.map((r) => `<tr><td>${esc(r.tr.fileName)}</td>${fields.map((k) => `<td>${esc(r.m.ok ? r.m.values[k] || '' : '')}</td>`).join('')}
          <td class="${r.status === 'failed' ? 'bad' : ''}">${esc(t(RS[STATUS[r.status]]) + (r.detail ? ': ' + t(r.detail) : ''))}</td></tr>`).join('');
        q('[data-summary]').textContent = count('saved') + count('failed') > 0
          ? t(RS.rsDFilerGemtDFejl, count('saved'), count('failed'))
          : t(RS.rsDKlarDUaendretD, count('ready'), count('unchanged'), count('noMatch'), count('notWritable'));
        q('[data-run]').disabled = busy || count('ready') === 0;
      }

      // from: UpdatePreview
      let seq = 0;
      async function update() {
        const n = ++seq;
        const o = opts();
        const items = scopeItems();
        const [ms, cols] = await Promise.all([API.matchFileNames(items.map((tr) => tr.path), o.mask, o.underscores, o.caseMode),
          API.maskFields(o.mask)]);
        if (n !== seq) return;
        fields = cols;
        rows = items.map((tr, i) => {
          const mt = ms[i];
          let status;
          if (!mt.ok) status = 'noMatch';
          else if (!TOOLS.canWriteTags(tr.path)) status = 'notWritable';
          else status = mt.used.every((k) => (mt.values[k] || '') === (tr.fields[k] || '')) ? 'unchanged' : 'ready';
          return { tr, m: mt, status, detail: '' };
        });
        show();
      }
      let timer = 0;
      const later = () => { clearTimeout(timer); timer = setTimeout(update, 300); };

      function saveOptions() {
        const o = opts();
        host.save('FileToTag', 'Mask', o.mask);
        host.save('FileToTag', 'Case', o.caseMode);
        host.save('FileToTag', 'Underscores', o.underscores ? 1 : 0);
      }

      // from: ButtonWriteClick
      async function run() {
        const ready = rows.filter((r) => r.status === 'ready');
        if (busy || !ready.length) return;
        if (!(await DIALOG.confirm(t(RS.rsSkrivTags), t(RS.rsSkrivTagsIDFiler, ready.length)))) return;
        host.addToHistory('FileToTagMasks', opts().mask);
        saveOptions();
        busy = true;
        show();
        const items = ready.map((r) => ({ path: r.tr.path, values: Object.fromEntries(r.m.used.map((k) => [k, r.m.values[k] || ''])), cover: null }));
        const msg = await host.write(items, q('[name="keep"]').checked,
          (p) => { q('[data-summary]').textContent = t(RS.rsSkriverDAfDS, p.done, p.total, ready[p.done - 1]?.tr.fileName || ''); });
        busy = false;
        if (msg) {
          const savedPaths = new Set(msg.tracks.map((x) => x.path.toLowerCase()));
          const failed = new Map(msg.errors.map((e) => [e.file.toLowerCase(), e.error]));
          for (const r of ready) {
            if (savedPaths.has(r.tr.path.toLowerCase())) r.status = 'saved';
            else Object.assign(r, { status: 'failed', detail: failed.get(r.tr.fileName.toLowerCase()) || '' });
          }
        }
        show();
      }

      function close() {
        if (busy) return;
        saveOptions();
        const keep = q('[name="keep"]').checked;
        m.close();
        resolve(keep);
      }

      m.el.addEventListener('input', (e) => { if (e.target.name === 'mask') later(); });
      m.el.addEventListener('change', (e) => { if (e.target.name !== 'keep') later(); });
      q('[data-run]').addEventListener('click', run);
      q('[data-close]').addEventListener('click', close);
      update();
      q('[name="mask"]').focus();
    });
  }

  window.F2TDIALOG = { open };
})();
