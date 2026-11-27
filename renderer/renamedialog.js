// "Omdøb filer ud fra tags" / "Omdøb mapper ud fra tags" (1.2's TFormRename): mask with a live
// preview list. The renames can be undone from the main window, which gets the log.
(function () {
  'use strict';
  const { t, label } = I18N;
  const U = MENUDATA.unitRs;
  const RS = { ...MENUDATA.rs, ...U.renamecore, ...U.renameform };
  const esc = FORMS.esc;
  const base = (p) => p.replace(/^.*[\\/]/, '');
  const dirOf = (p) => p.replace(/[\\/][^\\/]*$/, '');
  // from: DefaultMasks / DefaultFolderMasks
  const DEFAULT_MASKS = ['%1 - %2', '%6 - %2', '%6 - %1 - %2', '%1 - %3 - %6 - %2', '%1\\%3\\%6 - %2', '%aa\\%4 - %3\\%6 - %2'];
  const DEFAULT_FOLDER_MASKS = ['%1 - %3', '%1 - %4 - %3', '%4 - %3', '%1\\%4 - %3', '%aa\\%3'];
  const CASE_NAMES = ['rsUaendret', 'rsHvertOrdMedStort', 'rsFoersteBogstavStort', 'rsSmaaBogstaver', 'rsStoreBogstaver'];

  // from: FolderCount
  const folderCount = (items) => new Set(items.map((tr) => dirOf(tr.path).toLowerCase())).size;

  /** host: { all, subset, subsetCaption, prefer, folderMode, get(sec, key, def), save(sec, key, v),
   *  history(section) -> [mask], addToHistory(section, mask), canStart() -> bool, applyLog(log) }.
   *  Resolves with the renames done (for undo). */
  function open(host) {
    return new Promise((resolve) => {
      const fm = host.folderMode;
      const section = fm ? 'RenameFolder' : 'Rename';
      const histSection = fm ? 'FolderMasks' : 'RenameMasks';
      const masks = host.history(histSection);
      const list = masks.length ? masks : fm ? DEFAULT_FOLDER_MASKS : DEFAULT_MASKS;
      const mask0 = host.get(section, 'Mask', list[0]).trim() ? host.get(section, 'Mask', list[0]) : list[0];
      const caseMode = Math.min(4, Math.max(0, parseInt(host.get(section, 'Case', 0), 10) || 0));
      const bool = (k, d) => { const v = host.get(section, k, null); return v === null ? d : !['0', 'false', ''].includes(String(v).toLowerCase()); };
      const scope0 = host.prefer && host.subset.length ? 0 : 1;
      const scopes = fm
        ? [t(RS.rsSDMapper, host.subsetCaption, folderCount(host.subset)), t(RS.rsAlleFilerIListenD, folderCount(host.all))]
        : [host.subsetCaption, t(RS.rsAlleFilerIListenD2, host.all.length)];
      let rows = [], log = [], busy = false;
      const m = FORMS.modal(`<h2>${esc(t(fm ? RS.rsOmdoebMapperUdFraTags : 'Omdøb filer ud fra tags'))}</h2>
        <div class="track-top">
          <div class="form-grid rn-grid">
            <span class="lbl">${esc(t(fm ? 'Mappemaske:' : 'Filnavnsmaske:'))}</span>
            <div><input class="input grow" name="mask" list="rd-masks" spellcheck="false" value="${esc(mask0)}">
              <datalist id="rd-masks">${list.map((x) => `<option value="${esc(x)}"></option>`).join('')}</datalist></div>
            <span class="lbl">${esc(t('Versaler:'))}</span>
            <div class="frow"><select name="case">${CASE_NAMES.map((n, i) => `<option value="${i}"${i === caseMode ? ' selected' : ''}>${esc(t(RS[n]))}</option>`).join('')}</select>
              <label class="chk-label"><input type="checkbox" name="us"${bool('Underscores', false) ? ' checked' : ''}> ${esc(t('Erstat mellemrum med _'))}</label>
              ${fm ? '' : `<label class="chk-label"><input type="checkbox" name="pad"${bool('PadTrack', true) ? ' checked' : ''}> ${esc(t('Spornummer med 2 cifre (%6)'))}</label>`}</div>
          </div>
          <fieldset class="radio-group"><legend>${esc(t('Filer'))}</legend>${scopes.map((s, i) =>
            `<label class="chk-label"><input type="radio" name="scope" value="${i}"${i === scope0 ? ' checked' : ''}> ${esc(s)}</label>`).join('')}</fieldset>
        </div>
        <p class="notes">${esc(t(fm ? RS.FolderVariablesHelp : RS.RenameVariablesHelp))}</p>
        <div class="track-list"><table><thead><tr><th>${esc(t(fm ? RS.rsNuvaerendeMappe : 'Nuværende navn'))}</th>
          <th>${esc(t(fm ? RS.rsNyMappe : 'Nyt navn'))}</th><th>${esc(t('Status'))}</th></tr></thead><tbody></tbody></table></div>
        <div class="track-bottom"><span class="lbl" data-summary></span>
          <button class="btn primary" data-run>${esc(label(t(fm ? RS.rsOmdoebMapper : 'Omdøb')))}</button>
          <button class="btn" data-close>${esc(label(t('Luk')))}</button></div>`,
      { cls: 'wide track-tools', onEscape: () => close() });
      const q = (s) => m.el.querySelector(s);

      const opts = () => ({ mask: q('[name="mask"]').value, caseMode: Number(q('[name="case"]').value),
        underscores: q('[name="us"]').checked, padTrack: fm ? true : q('[name="pad"]').checked });
      const scopeItems = () => (Number(q('[name="scope"]:checked').value) === 0 && host.subset.length ? host.subset : host.all);

      // from: ShowPlan
      function show() {
        q('tbody').innerHTML = rows.map((r) => {
          const st = t(RENAMETOOLS.STATUS_TEXT[r.status]) + (r.detail ? ': ' + r.detail.split(', ').map((x) => t(x)).join(', ') : '');
          return `<tr><td>${esc(base(r.oldName))}</td><td>${esc(r.newName ? RENAMETOOLS.displayName(r.oldName, r.newName) : '')}</td>
            <td class="${['Failed', 'Exists', 'Duplicate', 'Invalid', 'Missing'].includes(r.status) ? 'bad' : ''}">${esc(st)}</td></tr>`;
        }).join('');
        const [name, ...args] = RENAMETOOLS.summary(rows);
        q('[data-summary]').textContent = t(RS[name], ...args);
        q('[data-run]').disabled = busy || !rows.some((r) => r.status === 'Ok');
      }

      // from: UpdatePreview
      let seq = 0;
      async function update() {
        const n = ++seq;
        const o = opts();
        const r = await API.planRename(scopeItems(), o.mask, o, fm);
        if (n === seq) { rows = r; show(); }
      }
      let timer = 0;
      const later = () => { clearTimeout(timer); timer = setTimeout(update, 300); }; // TimerPreview

      function saveOptions() {
        const o = opts();
        host.save(section, 'Mask', o.mask);
        host.save(section, 'Case', o.caseMode);
        host.save(section, 'Underscores', o.underscores ? 1 : 0);
        if (!fm) host.save(section, 'PadTrack', o.padTrack ? 1 : 0);
      }

      // from: ButtonRenameClick
      async function run() {
        if (busy) return;
        await update(); // the files on disk may have changed since the last preview
        const ok = rows.filter((r) => r.status === 'Ok').length;
        if (!ok) return;
        if (!(await DIALOG.confirm(t(fm ? RS.rsOmdoebMapper : RS.rsOmdoebFiler), t(fm ? RS.rsOmdoebDMapper : RS.rsOmdoebDFiler, ok)))) return;
        if (!host.canStart()) return;
        host.addToHistory(histSection, opts().mask);
        saveOptions();
        busy = true;
        show();
        try {
          const r = await API.executeRename(rows);
          rows = r.rows;
          log = log.concat(r.log);
          if (r.log.length) await host.applyLog(r.log); // the tracks move with their files
        } catch (e) {
          DIALOG.info(String(e));
        } finally {
          busy = false;
          show();
        }
      }

      function close() {
        if (busy) return;
        saveOptions();
        m.close();
        resolve(log);
      }

      m.el.addEventListener('input', (e) => { if (e.target.name === 'mask') later(); });
      m.el.addEventListener('change', () => later());
      q('[data-run]').addEventListener('click', run);
      q('[data-close]').addEventListener('click', close);
      update();
      q('[name="mask"]').focus();
    });
  }

  window.RENAMEDIALOG = { open };
})();
