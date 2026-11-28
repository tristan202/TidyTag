// Renaming helpers without DOM (from mainform.pas: MaskTemplate, AddMaskToHistory,
// ButtonRenameDoClick, ButtonF2TWriteClick, ApplyRenameLog), so node --test can run them.
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.RENAMETOOLS = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  const MAX_MASKS = 15;
  const baseName = (p) => p.replace(/^.*[\\/]/, '');
  const dirName = (p) => p.replace(/[\\/][^\\/]*$/, '');

  // from: RenameStatusText (core rename.rs status_text); the caller translates them
  const STATUS_TEXT = {
    Ok: 'Omdøbes', Unchanged: 'Uændret', Missing: 'Mangler felt', Exists: 'Findes allerede',
    Duplicate: 'Samme navn som en anden fil', Invalid: 'Ugyldigt navn', Done: 'Omdøbt', Failed: 'Fejl',
  };

  // from: MaskTemplate — '%1 - %2' -> '<Kunstner> - <Titel>.mp3'; vars are 'code|caption'
  // entries (translated), the longest matching code wins (%aa before %a...)
  function maskTemplate(mask, ext, vars, spacesTo) {
    const codes = [];
    for (const v of vars) {
      const bar = v.indexOf('|');
      const code = v.slice(0, bar);
      // variables only: '%' plus letters/digits, not the examples such as '%6 - %1 - %2'
      if (code.length < 2 || code[0] !== '%' || code.includes(' ') || code.indexOf('%', 1) >= 0) continue;
      let cap = v.slice(bar + 1);
      const p = cap.indexOf(' ('); // 'Udgivelsesdato (hele datoen)' -> 'Udgivelsesdato'
      if (p > 0) cap = cap.slice(0, p);
      codes.push([code, cap]);
    }
    let r = '';
    for (let i = 0; i < mask.length;) {
      let best = null;
      if (mask[i] === '%') for (const c of codes) if (mask.startsWith(c[0], i) && (!best || c[0].length > best[0].length)) best = c;
      if (best) {
        r += '<' + best[1] + '>';
        i += best[0].length;
      } else {
        r += mask[i] === ' ' && spacesTo !== ' ' ? spacesTo : mask[i];
        i += 1;
      }
    }
    return r ? r + ext : '';
  }

  // from: DefaultMasks (renameform.pas), DefaultFolderMasks, DefaultMasks (filetotagform.pas)
  const DEFAULT_MASKS = {
    RenameMasks: ['%1 - %2', '%6 - %2', '%6 - %1 - %2', '%1 - %3 - %6 - %2', '%1\\%3\\%6 - %2', '%aa\\%4 - %3\\%6 - %2'],
    FolderMasks: ['%1 - %3', '%1 - %4 - %3', '%4 - %3', '%1\\%4 - %3', '%aa\\%3'],
    FileToTagMasks: ['%1 - %2', '%6 - %2', '%6 - %1 - %2', '%6. %2', '%6 %1 - %2', '%1\\%3\\%6 - %2', '%1\\%4 - %3\\%6 - %2'],
  };
  // from: LoadMaskHistory — an empty history shows (and keeps) the defaults
  const historyFor = (section, list) => (list.length ? list.slice() : DEFAULT_MASKS[section].slice());

  // from: AddMaskToHistory — newest first, no duplicates, at most 15
  function addMaskToHistory(list, mask) {
    if (!mask.trim()) return list.slice();
    return [mask, ...list.filter((m) => m !== mask)].slice(0, MAX_MASKS);
  }

  // from: ButtonRenameDoClick — the question's examples and the "nothing to rename" problems
  function renameConfirm(rows, tr) {
    const okCount = rows.filter((r) => r.status === 'Ok').length;
    const skipped = rows.length - okCount - rows.filter((r) => r.status === 'Unchanged').length;
    let examples = '', problems = '';
    for (const r of rows) {
      if (r.status === 'Ok' && examples.length < 400) examples += `${baseName(r.oldName)}  →  ${baseName(r.newName)}\n`;
      if (r.status !== 'Unchanged' && r.status !== 'Ok' && problems.length < 600) {
        problems += `${baseName(r.oldName)}: ${tr(STATUS_TEXT[r.status])}${r.detail ? ` (${tr(r.detail)})` : ''}\n`;
      }
    }
    return { okCount, skipped, examples, problems };
  }

  // from: ButtonF2TWriteClick — a file is written only when one of the mask's fields changes,
  // and then only the mask's fields
  function f2tItems(tracks, matches) {
    const items = [];
    let noMatch = 0;
    tracks.forEach((tr, i) => {
      const m = matches[i];
      if (!m || !m.ok) { noMatch += 1; return; }
      if (!m.used.some((k) => (m.values[k] || '') !== (tr.fields[k] || ''))) return;
      const values = {};
      for (const k of m.used) values[k] = m.values[k] || '';
      items.push({ path: tr.path, values, cover: null });
    });
    return { items, ready: items.length, noMatch };
  }

  /** ApplyRenameLog's list part: `mapped` are the paths of `state.all` (every file, the hidden
   *  ones too) after the log (map_paths), `folder` the open folder's. The track objects stay
   *  (ticks, selection). True if anything moved. */
  function applyLog(state, mapped, folder) {
    let changed = false;
    state.all.forEach((tr, i) => {
      const p = mapped[i];
      if (!p || p === tr.path) return;
      tr.path = p;
      tr.folder = dirName(p);
      tr.fileName = baseName(p);
      changed = true;
    });
    if (folder && folder !== state.folder) {
      state.folder = folder;
      changed = true;
    }
    return changed;
  }

  // from: TFormRename.ShowPlan — [rs name, ...arguments] of the summary line
  function summary(rows) {
    const n = (s) => rows.filter((r) => r.status === s).length;
    if (n('Done') > 0) return ['rsDOmdoebtDFejlKan', n('Done'), n('Failed')];
    return ['rsDOmdoebesDUaendretD', n('Ok'), n('Unchanged'), rows.length - n('Ok') - n('Unchanged') - n('Done')];
  }

  // from: DisplayName (renameform.pas) — the new name relative to the old folder when it stays below it
  function displayName(oldName, newName) {
    const dir = oldName.slice(0, oldName.lastIndexOf('\\') + 1);
    return newName.toLowerCase().startsWith(dir.toLowerCase()) ? newName.slice(dir.length) : newName;
  }

  // from: Quote / Unquote (appsettings.pas) — quotes keep leading/trailing spaces (' & ') in the ini
  const quote = (s) => `"${s}"`;
  const unquote = (s) => (s && s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"' ? s.slice(1, -1) : s || '');
  const count = (sec) => Math.max(0, parseInt(sec?.count, 10) || 0);

  // from: SaveRenameWords — { from, to, keep } -> the rows of [RenameReplace] and [RenameKeepCase]
  function wordsToIni(w) {
    const replace = [['Count', String(w.from.length)]];
    w.from.forEach((f, i) => replace.push([`From${i + 1}`, quote(f)], [`To${i + 1}`, quote(w.to[i] ?? '')]));
    return { RenameReplace: replace, RenameKeepCase: [['Count', String(w.keep.length)], ...w.keep.map((k, i) => [`Word${i + 1}`, quote(k)])] };
  }

  // from: LoadRenameWords — the two sections as { lower-case key: value }
  function wordsFromIni(replace, keep) {
    const w = { from: [], to: [], keep: [] };
    for (let i = 1; i <= count(replace); i++) {
      w.from.push(unquote(replace[`from${i}`]));
      w.to.push(unquote(replace[`to${i}`]));
    }
    for (let i = 1; i <= count(keep); i++) w.keep.push(unquote(keep[`word${i}`]));
    return w;
  }

  // from: SaveRenameActions
  function actionsToIni(actions) {
    const rows = [['Count', String(actions.length)]];
    actions.forEach((a, i) => rows.push([`Name${i + 1}`, quote(a.name)], [`FileMask${i + 1}`, quote(a.fileMask)], [`FolderMask${i + 1}`, quote(a.folderMask)]));
    return rows;
  }

  // from: LoadRenameActions
  function actionsFromIni(sec) {
    const out = [];
    for (let i = 1; i <= count(sec); i++) {
      out.push({ name: unquote(sec[`name${i}`]), fileMask: unquote(sec[`filemask${i}`]), folderMask: unquote(sec[`foldermask${i}`]) });
    }
    return out;
  }

  return { STATUS_TEXT, DEFAULT_MASKS, historyFor, maskTemplate, addMaskToHistory, renameConfirm, f2tItems, applyLog, summary, displayName,
    wordsToIni, wordsFromIni, actionsToIni, actionsFromIni };
});
