// Playing and playlists without DOM (from mainform.pas: PlayTargets, PlayQueueItem, PlayerTimer,
// PlayerPrevClick, PlayerNextClick; progoptions.pas: PlayerFor, ReadList/WriteList).
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.PLAYTOOLS = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  const baseName = (p) => p.replace(/^.*[\\/]/, '');

  /** from: PlayTargets — the selected files when there are several, otherwise the whole view
   *  from the focused file on (so "next" goes on through the list). */
  function playTargets(state) {
    const sel = state.items.filter((tr) => state.sel.has(tr));
    if (sel.length > 1) return { files: sel.map((tr) => tr.path), index: 0 };
    const focus = state.items[state.focus];
    if (!focus) return { files: [], index: 0 };
    return { files: state.items.map((tr) => tr.path), index: state.items.indexOf(focus) };
  }

  /** from: PlayerFor — [Players] entries 'ext=program'; '*' is the fallback; '' = Windows' own. */
  function playerFor(path, players) {
    const m = /\.([^.\\/]*)$/.exec(path);
    const ext = m ? m[1].toLowerCase() : '';
    let star = '';
    for (const p of players) {
      const e = p.indexOf('=');
      if (e < 1) continue;
      let k = p.slice(0, e).trim().toLowerCase();
      if (k.startsWith('.')) k = k.slice(1);
      if (k === ext) return p.slice(e + 1).trim();
      if (k === '*') star = p.slice(e + 1).trim();
    }
    return star;
  }

  // from: PlayQueueItem — 'Artist - Title' when both are set, else the file name
  function titleFor(path, all) {
    const tr = all.find((x) => x.path.toLowerCase() === path.toLowerCase());
    if (tr && tr.fields.artist && tr.fields.title) return `${tr.fields.artist} - ${tr.fields.title}`;
    return baseName(path);
  }

  // The queue is { files, index, sawPlaying }; index -1 = stopped.
  // from: PlayerTimer — the end of a track: on to the next one, or stop after the last
  const queueAfterEnd = (q) => ({ ...q, index: q.index + 1 < q.files.length ? q.index + 1 : -1, sawPlaying: false });
  // from: PlayerPrevClick — like most players: back to the start first, the previous track within 3 seconds
  function queuePrev(q, position) {
    if (position > 3) return { q, seekZero: true };
    return { q: { ...q, index: q.index > 0 ? q.index - 1 : q.index, sawPlaying: false }, seekZero: false };
  }
  // from: PlayerNextClick — null on the last track (nothing happens)
  const queueNext = (q) => (q.index + 1 < q.files.length ? { ...q, index: q.index + 1, sawPlaying: false } : null);
  // from: PlayQueueItem's error branch (StopPlaying)
  const queueStopped = (q) => ({ ...q, index: -1, sawPlaying: false });

  // from: WriteList / ReadList — Item<n> with quoted values; read in file order, whatever the key
  const listToIni = (items) => items.map((v, i) => ['Item' + i, `"${v}"`]);
  const unquote = (s) => (s.length >= 2 && s[0] === '"' && s[s.length - 1] === '"' ? s.slice(1, -1) : s);
  const listFromIni = (rows) => rows.map(([, v]) => unquote(v));

  return { playTargets, playerFor, titleFor, queueAfterEnd, queuePrev, queueNext, queueStopped, listToIni, listFromIni };
});
