// Saving tags: which files, which values, and 1.2's messages (TargetItems, ButtonMultiSaveClick,
// WriteFieldsBatch in mainform.pas). No DOM here, so node --test can run it.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./menudata.js'), require('./strings.js'));
  else root.SAVE = factory(root.MENUDATA, root.I18N);
})(typeof self !== 'undefined' ? self : this, function (MENUDATA, I18N) {
  'use strict';
  const RS = MENUDATA.rs;
  const t = (s, ...a) => I18N.t(s, ...a);

  // from: TargetItems — the checked files, otherwise the selected ones
  function targets(state) {
    const checked = state.items.filter((tr) => tr.checked);
    if (checked.length) return { items: checked, scope: 'checked' };
    return { items: state.items.filter((tr) => state.sel.has(tr)), scope: 'selected' };
  }

  // from: ButtonMultiSaveClick — only ticked fields, trimmed; empty ones are cleared
  function multiValues(form) {
    const fields = {}, cleared = [];
    for (const [key, f] of Object.entries(form)) {
      if (!f.on) continue;
      fields[key] = f.value.trim();
      if (!fields[key]) cleared.push(t(MENUDATA.fieldCaptions[key]));
    }
    return { fields, cleared };
  }

  function confirmText(n, cleared) {
    return t(RS.rsGemIDFiler, n) + (cleared.length ? '\n' + t(RS.rsDisseFelterBliverRyddet) + cleared.join(', ') : '');
  }

  // from: WriteFieldsBatch
  function doneText(what, saved, failed, skipped) {
    return t(RS.rsSGemtIDFiler, what, saved, failed, skipped > 0 ? t(RS.rsDSprungetOverFiltype, skipped) : '');
  }

  // from: CanStartBatch (1.2 also refuses while tags are being read)
  const canStartBatch = (state) => !state.scanning && !state.writing;

  // closing while a file is being written could stop an in-place write halfway (a batch, or a
  // single save: the tag editor, folder covers); an open tag editor asks about unsaved changes
  const closeAction = (state, editorOpen) =>
    (state.writing || state.busyWrites > 0 ? 'wait' : editorOpen ? 'ask' : 'close');

  /** The multi tab's Gem tags, as ButtonMultiSaveClick. `ui` = { info(text, title), confirm(title, text),
   *  write(items) }. Everything is checked again after the question: the window is not blocked
   *  while it is open (F5 can start reading the folder). */
  async function save(state, form, ui) {
    const { fields, cleared } = multiValues(form);
    if (!Object.keys(fields).length) return ui.info(t(RS.rsSaetFluebenVedDeFelter));
    if (!canStartBatch(state)) return ui.info(t(RS.rsVentVenligstTilAlleTags));
    const { items } = targets(state);
    if (!items.length) return ui.info(t(RS.rsAfkrydsEllerMarkerDeFiler));
    if (!(await ui.confirm(t(RS.rsGemTags), confirmText(items.length, cleared)))) return;
    if (!canStartBatch(state)) return ui.info(t(RS.rsVentVenligstTilAlleTags));
    const now = targets(state).items.filter((tr) => items.includes(tr));
    if (!now.length) return ui.info(t(RS.rsAfkrydsEllerMarkerDeFiler));
    return ui.write(now.map((tr) => ({ path: tr.path, values: fields, cover: null })));
  }

  return { targets, multiValues, confirmText, doneText, canStartBatch, closeAction, save };
});
