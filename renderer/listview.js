// The filtered view of the file list (1.2's FItems and FView): `state.all` holds every file of
// the folder, `state.items` the ones shown. Pure, so node --test runs it.
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.LISTVIEW = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  const dirOf = (p) => p.replace(/[\\/][^\\/]*$/, '');
  const same = (a, b) => a.toLowerCase() === b.toLowerCase();

  // from: IsWordCharW — letters and digits form words
  const isWordChar = (c) => c.toUpperCase() !== c.toLowerCase() || (c >= '0' && c <= '9');

  // from: ContainsText
  function containsText(hay, needle, whole) {
    let start = 0;
    for (;;) {
      const p = hay.indexOf(needle, start);
      if (p < 0) return false;
      const end = p + needle.length;
      if (!whole || ((p === 0 || !isWordChar(hay[p - 1])) && (end >= hay.length || !isWordChar(hay[end])))) return true;
      start = p + 1;
    }
  }

  /** from: MatchesFilter. f = { tagType: token ('' = all, '-' = no tags), text, field, whole, matchCase };
   *  field 0 is the file name, 1..keys.length a tag field, anything above all of them. */
  function matchesFilter(tr, f, keys) {
    if (f.tagType) {
      if (f.tagType === '-') {
        if (tr.tagTypes || tr.error) return false;
      } else if (!String(tr.tagTypes || '').includes(f.tagType)) return false;
    }
    if (!f.text) return true;
    let hay;
    if (f.field === 0) hay = tr.fileName;
    else if (f.field <= keys.length) hay = tr.fields[keys[f.field - 1]] || '';
    else hay = [tr.fileName, ...keys.map((k) => tr.fields[k] || '')].join('\u0001');
    let needle = f.text;
    if (!f.matchCase) {
      hay = hay.toLowerCase();
      needle = needle.toLowerCase();
    }
    return containsText(hay, needle, f.whole);
  }

  // from: RebuildView — the focus and the selection stay with their files
  function rebuildView(state, keys) {
    const focused = state.items[state.focus], anchored = state.items[state.anchor];
    state.items = state.all.filter((tr) => !tr.hidden && matchesFilter(tr, state.filter, keys));
    const shown = new Set(state.items);
    for (const tr of [...state.sel]) if (!shown.has(tr)) state.sel.delete(tr);
    state.focus = focused ? state.items.indexOf(focused) : -1;
    state.anchor = anchored ? state.items.indexOf(anchored) : -1;
  }

  // from: ButtonHideSelectedClick
  function hideSelected(state, keys) {
    for (const tr of state.sel) tr.hidden = true;
    state.sel.clear();
    rebuildView(state, keys);
  }

  // from: ButtonShowAllClick
  function showAll(state, keys) {
    for (const tr of state.all) tr.hidden = false;
    state.filter.text = '';
    rebuildView(state, keys);
  }

  // from: MoveSelected — swaps in the view and the same two files in the master list
  function moveSelected(state, delta) {
    const sel = state.items.map((tr, i) => (state.sel.has(tr) ? i : -1)).filter((i) => i >= 0);
    if (!sel.length) return false;
    if (delta < 0 && sel[0] === 0) return false;
    if (delta > 0 && sel[sel.length - 1] === state.items.length - 1) return false;
    const swap = (arr, i, j) => { const x = arr[i]; arr[i] = arr[j]; arr[j] = x; };
    for (let k = 0; k < sel.length; k++) {
      const a = delta < 0 ? sel[k] : sel[sel.length - 1 - k];
      const b = a + delta;
      const ia = state.all.indexOf(state.items[a]), ib = state.all.indexOf(state.items[b]);
      swap(state.items, a, b);
      if (ia >= 0 && ib >= 0) swap(state.all, ia, ib);
    }
    state.sort.col = state.sort.col2 = -1;
    state.focus = state.anchor = sel[0] + delta;
    return true;
  }

  // from: ActRandomOrderExecute
  function shuffle(state, keys, rnd = Math.random) {
    for (let i = state.all.length - 1; i >= 1; i--) {
      const j = Math.floor(rnd() * (i + 1));
      const x = state.all[i]; state.all[i] = state.all[j]; state.all[j] = x;
    }
    state.sort.col = state.sort.col2 = -1; // manual order until a column is clicked
    rebuildView(state, keys);
  }

  /** from: PrepareOpen — the folder to show for paths from Explorer: the first folder among
   *  them, otherwise the first file's folder, whose files are selected after the scan. */
  function prepareOpen(paths, isDir) {
    const d = paths.find(isDir);
    if (d) return { dir: d, select: [] };
    if (!paths.length) return { dir: '', select: [] };
    const dir = dirOf(paths[0]);
    return { dir, select: paths.filter((p) => same(dirOf(p), dir)) };
  }

  /** from: AutoFitColumns — measure(text) gives pixels, cellText(row, col) the cell's text. */
  function autoFitWidths(rows, cols, widths, measure, cellText) {
    const n = Math.min(rows.length, 1000); // enough to judge the width, quick for big lists
    return cols.map((c, ci) => {
      if (ci === 0) return widths[0]; // the check mark
      let best = measure(c.caption) + 24;
      for (let i = 0; i < n; i++) best = Math.max(best, measure(cellText(rows[i], ci)) + 16);
      return Math.min(best, 450);
    });
  }

  /** from: ApplyPendingSelect — the view indexes of the waiting files, case-insensitive. */
  function pendingIndexes(items, pending) {
    const want = new Set(pending.map((p) => p.toLowerCase()));
    return items.map((tr, i) => (want.has(tr.path.toLowerCase()) ? i : -1)).filter((i) => i >= 0);
  }

  return { matchesFilter, rebuildView, hideSelected, showAll, moveSelected, shuffle, prepareOpen, autoFitWidths, pendingIndexes };
});
