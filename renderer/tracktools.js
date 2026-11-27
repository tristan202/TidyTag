// "Spornumre" (1.2's TFormTrackTools): reformat the track numbers or number the files in list
// order, with a live preview, then write only the Track field.
(function () {
  'use strict';
  const { t, label } = I18N;
  const RS = { ...MENUDATA.rs, ...MENUDATA.unitRs.tracktoolsform }; // the form's own texts win
  const esc = FORMS.esc;
  const FORMATS = ['7', '07', '007', '7/12', '07/12']; // TrackFormatNames
  const base = (p) => p.replace(/^.*[\\/]/, '');
  const statusText = (s) => t(RS[s]);

  /** host: { all, subset, subsetCaption, prefer, keep, get(sec, key, def), save(sec, key, v),
   *  write(items, onProgress) -> Promise<write-done message | null> }. Resolves with the
   *  "Bevar filernes dato" state when the dialog closes. */
  function open(host) {
    return new Promise((resolve) => {
      const num = (k, def) => { const n = parseInt(host.get('Tracks', k, def), 10); return Number.isFinite(n) ? n : def; };
      const opt = {
        mode: num('Mode', 0) === 1 ? 1 : 0,
        format: Math.min(FORMATS.length - 1, Math.max(0, num('Format', 1))),
        start: num('Start', 1),
        perFolder: !['0', 'false'].includes(String(host.get('Tracks', 'PerFolder', '1')).toLowerCase()),
        scope: host.prefer && host.subset.length ? 0 : 1,
      };
      let rows = [], busy = false;
      const radio = (name, i, text, on) =>
        `<label class="chk-label"><input type="radio" name="${name}" value="${i}"${on ? ' checked' : ''}> ${esc(text)}</label>`;
      const m = FORMS.modal(`<h2>${esc(t('Spornumre'))}</h2>
        <div class="track-top">
          <fieldset class="radio-group"><legend>${esc(t('Handling'))}</legend>
            ${radio('mode', 0, t(RS.rsFormaterEksisterendeSpornumre), opt.mode === 0)}
            ${radio('mode', 1, t(RS.rsNummererIListensRaekkefoelge), opt.mode === 1)}</fieldset>
          <div class="form-grid">
            <span class="lbl">${esc(t('Format:'))}</span><select name="format">${FORMATS.map((f, i) =>
              `<option value="${i}"${i === opt.format ? ' selected' : ''}>${f}</option>`).join('')}</select>
            <span class="lbl" data-num>${esc(t('Start ved:'))}</span><input class="input num" type="number" name="start" min="0" max="9999" value="${opt.start}" data-num>
            <span></span><label class="chk-label" data-num><input type="checkbox" name="perFolder"${opt.perFolder ? ' checked' : ''} data-num> ${esc(t('Start forfra i hver mappe'))}</label>
          </div>
          <fieldset class="radio-group"><legend>${esc(t('Filer'))}</legend>
            ${radio('scope', 0, host.subsetCaption, opt.scope === 0)}
            ${radio('scope', 1, t(RS.rsAlleFilerIListenD, host.all.length), opt.scope === 1)}</fieldset>
        </div>
        <div class="track-list"><table><thead><tr><th>${esc(t('Fil'))}</th><th>${esc(t('Spor nu'))}</th><th>${esc(t('Nyt spor'))}</th>
          <th>${esc(t('Status'))}</th><th>${esc(t('Mappe'))}</th></tr></thead><tbody></tbody></table></div>
        <div class="track-bottom"><label class="chk-label"><input type="checkbox" name="keep"${host.keep ? ' checked' : ''}> ${esc(t('Bevar filernes dato'))}</label>
          <span class="lbl" data-summary></span>
          <button class="btn primary" data-write>${esc(label(t(RS.rsGemSpornumre)))}</button>
          <button class="btn" data-close>${esc(label(t('Luk')))}</button></div>`,
      { cls: 'wide track-tools', onEscape: () => close() });
      const q = (s) => m.el.querySelector(s);
      const summary = q('[data-summary]'), writeBtn = q('[data-write]');

      function read() {
        opt.mode = Number(q('[name="mode"]:checked').value);
        opt.format = Number(q('[name="format"]').value);
        opt.start = parseInt(q('[name="start"]').value, 10) || 0;
        opt.perFolder = q('[name="perFolder"]').checked;
        opt.scope = Number(q('[name="scope"]:checked').value);
      }
      const count = (s) => rows.filter((r) => r.status === s).length;

      // from: UpdatePreview
      function update() {
        read();
        const items = opt.scope === 0 && host.subset.length ? host.subset : host.all;
        m.el.querySelectorAll('[data-num]').forEach((el) => { el.classList.toggle('off', opt.mode === 0); if ('disabled' in el) el.disabled = opt.mode === 0; });
        const next = TOOLS.planTrackNumbers(items, opt.mode === 1 ? 'number' : 'format', FORMATS[opt.format], opt.start, opt.perFolder);
        rows = items.map((tr, i) => ({ tr, now: tr.fields.track || '', next: next[i], status: TOOLS.trackStatus(tr, next[i]), detail: '' }));
        show();
      }

      // from: ShowRows
      function show() {
        q('tbody').innerHTML = rows.map((r) => `<tr><td>${esc(r.tr.fileName)}</td><td>${esc(r.now)}</td><td>${esc(r.next)}</td>
          <td class="${r.status === 'rsFejl' ? 'bad' : ''}">${esc(statusText(r.status) + (r.detail ? ': ' + t(r.detail) : ''))}</td><td>${esc(base(r.tr.folder))}</td></tr>`).join('');
        summary.textContent = count('rsGemt') + count('rsFejl') > 0
          ? t(RS.rsDFilerGemtDFejl, count('rsGemt'), count('rsFejl'))
          : t(RS.rsDAendresDUaendretD, count('rsAendres'), count('rsUaendret'), count('rsFiltypenKanIkkeGemmesEndnu'));
        writeBtn.disabled = busy || count('rsAendres') === 0;
      }

      function saveOptions() {
        host.save('Tracks', 'Mode', opt.mode);
        host.save('Tracks', 'Format', opt.format);
        host.save('Tracks', 'Start', opt.start);
        host.save('Tracks', 'PerFolder', opt.perFolder ? 1 : 0);
      }

      // from: ButtonWriteClick
      async function write() {
        const todo = rows.filter((r) => r.status === 'rsAendres');
        if (!todo.length || busy) return;
        if (!(await DIALOG.confirm(t(RS.rsGemSpornumre), t(RS.rsGemNyeSpornumreID, todo.length)))) return;
        saveOptions();
        busy = true;
        show();
        const msg = await host.write(todo.map((r) => ({ path: r.tr.path, values: { track: r.next }, cover: null })), q('[name="keep"]').checked,
          (p) => { summary.textContent = t(RS.rsGemmerDAfDS, p.done, p.total, todo[p.done - 1]?.tr.fileName || ''); });
        busy = false;
        if (msg) {
          const saved = new Set(msg.tracks.map((x) => x.path.toLowerCase()));
          const failed = new Map(msg.errors.map((e) => [e.file.toLowerCase(), e.error]));
          for (const r of todo) {
            if (saved.has(r.tr.path.toLowerCase())) Object.assign(r, { status: 'rsGemt', now: r.next });
            else if (failed.has(r.tr.fileName.toLowerCase())) Object.assign(r, { status: 'rsFejl', detail: failed.get(r.tr.fileName.toLowerCase()) });
            else r.status = 'rsFejl';
          }
        }
        show();
      }

      function close() {
        if (busy) return; // the batch is running; it finishes on its own
        read();
        saveOptions();
        const keep = q('[name="keep"]').checked;
        m.close();
        resolve(keep);
      }

      m.el.addEventListener('change', (e) => { if (!busy && !e.target.matches('[name="keep"]')) update(); });
      m.el.addEventListener('input', (e) => { if (!busy && e.target.matches('[name="start"]')) update(); });
      writeBtn.addEventListener('click', write);
      q('[data-close]').addEventListener('click', close);
      update();
      q('[name="mode"]:checked').focus();
    });
  }

  window.TRACKTOOLS = { open };
})();
