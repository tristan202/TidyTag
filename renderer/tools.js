// Field tools and track numbering (ports of fieldtools.pas and trackcore.pas) plus the paste
// rule of ActPasteTagExecute. Pure functions on the renderer's track objects; no DOM here.
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.TOOLS = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  // Pascal's Trim: characters <= ' ' only
  const ptrim = (s) => s.replace(/^[\u0000- ]+|[\u0000- ]+$/g, '');
  const get = (tr, k) => tr.fields[k] || '';
  const plan = (values) => ({ values, fields: Object.keys(values) });

  // from: PlanSwap
  function planSwap(tr, a, b) {
    if (a === b || get(tr, a) === get(tr, b)) return null;
    return plan({ [a]: get(tr, b), [b]: get(tr, a) });
  }

  // from: PlanCopy
  function planCopy(tr, src, dst, onlyIfEmpty) {
    if (src === dst || get(tr, src) === get(tr, dst)) return null;
    if (onlyIfEmpty && get(tr, dst)) return null;
    if (!get(tr, src)) return null; // copying nothing would clear the target
    return plan({ [dst]: get(tr, src) });
  }

  // from: CleanSpaces
  function cleanSpaces(s, collapse) {
    let r = ptrim(s);
    if (collapse) {
      r = r.replace(/\t/g, ' ');
      while (r.includes('  ')) r = r.replace(/ {2}/g, ' ');
    }
    return r;
  }

  // from: PlanCleanSpaces — every non-empty field is written again
  function planCleanSpaces(tr) {
    const values = {};
    for (const [k, v] of Object.entries(tr.fields)) {
      if (v) values[k] = cleanSpaces(v, !(k === 'lyrics' || k === 'comment'));
    }
    return Object.keys(values).length ? plan(values) : null;
  }

  const sameText = (a, b) => a.toLowerCase() === b.toLowerCase();

  // from: NameToolOne (Pascal Copy/Pos with 1-based indexes, translated)
  function nameToolOne(s, tool) {
    const t = ptrim(s);
    const n = t.length;
    switch (tool) {
      case 'removeThe':
        return sameText(t.slice(0, 4), 'The ') ? ptrim(t.slice(4)) : s;
      case 'theToEnd':
        return sameText(t.slice(0, 4), 'The ') ? ptrim(t.slice(4)) + ', ' + t.slice(0, 3) : s;
      case 'theToFront':
        return n >= 5 && sameText(t.slice(n - 5), ', The') ? t.slice(n - 3) + ' ' + ptrim(t.slice(0, n - 5)) : s;
      case 'nameToSurnameFirst': {
        if (t.includes(',')) return s;
        const p = t.lastIndexOf(' ');
        return p > 0 ? t.slice(p + 1) + ', ' + ptrim(t.slice(0, p)) : s;
      }
      case 'surnameFirstToName': {
        const p = t.indexOf(', ');
        return p > 0 && !t.slice(p + 2).includes(',') ? ptrim(t.slice(p + 2)) + ' ' + t.slice(0, p) : s;
      }
      default:
        return s;
    }
  }

  // from: ApplyNameTool — several artists in one field ('A; B') one by one
  const applyNameTool = (s, tool) => s.split('; ').map((p) => nameToolOne(p, tool)).join('; ');

  // from: PlanNameTool
  function planNameTool(tr, field, tool) {
    const v = get(tr, field);
    if (!v) return null;
    const n = applyNameTool(v, tool);
    return n === v ? null : plan({ [field]: n });
  }

  // from: ParseTrack
  function parseTrack(s) {
    const t = ptrim(s || '');
    const m = /^\d+/.exec(t);
    if (!m) return null;
    const slash = t.indexOf('/');
    const total = slash >= 0 ? parseInt(ptrim(t.slice(slash + 1)), 10) || 0 : 0;
    return { num: parseInt(m[0], 10) || 0, total };
  }

  const pad = (n, w) => String(n).padStart(w, '0');

  // from: FormatTrack — fmt is one of TrackFormatNames: '7' '07' '007' '7/12' '07/12'
  function formatTrack(num, total, fmt) {
    let r = fmt === '7' || fmt === '7/12' ? String(num) : fmt === '007' ? pad(num, 3) : pad(num, 2);
    if ((fmt === '7/12' || fmt === '07/12') && total > 0) r += '/' + (fmt === '07/12' ? pad(total, 2) : String(total));
    return r;
  }

  // from: PlanTrackNumbers — mode 'format' | 'number'
  function planTrackNumbers(tracks, mode, fmt, startAt, perFolder) {
    const key = (tr) => (perFolder || mode === 'format' ? tr.folder.toLowerCase() : '*');
    const counts = new Map();
    for (const tr of tracks) counts.set(key(tr), (counts.get(key(tr)) || 0) + 1);
    const counters = new Map();
    return tracks.map((tr) => {
      const k = key(tr);
      let num, total;
      if (mode === 'format') {
        const p = parseTrack(get(tr, 'track'));
        if (!p) return get(tr, 'track');
        ({ num, total } = p);
        if (total <= 0) total = counts.get(k);
      } else {
        num = counters.has(k) ? counters.get(k) + 1 : startAt;
        counters.set(k, num);
        total = startAt - 1 + counts.get(k);
      }
      return formatTrack(num, total, fmt);
    });
  }

  // from: ActPasteTagExecute — fields empty in the copied file are not pasted
  function pasteValues(copied, fields) {
    const v = {};
    for (const k of fields) if (copied[k]) v[k] = copied[k];
    return v;
  }

  // from: CanWriteTags (write.rs WRITABLE)
  const WRITABLE = new Set(['mp3', 'flac', 'm4a', 'm4b', 'mp4', 'ogg', 'oga', 'opus', 'wav', 'aif', 'aiff', 'aifc',
    'ape', 'wv', 'mpc', 'ofr', 'wma', 'asf']);
  const canWriteTags = (path) => WRITABLE.has((/\.([^.\\/]+)$/.exec(path) || [])[1]?.toLowerCase());

  // from: TFormTrackTools.UpdatePreview — the name of the row's status text (MENUDATA.rs)
  function trackStatus(tr, newTrack) {
    if (newTrack === get(tr, 'track')) return 'rsUaendret';
    return canWriteTags(tr.path) ? 'rsAendres' : 'rsFiltypenKanIkkeGemmesEndnu';
  }

  /** Write items for the files whose plan is not null. */
  const writeItems = (tracks, planFn) =>
    tracks.map((tr) => [tr, planFn(tr)]).filter(([, p]) => p).map(([tr, p]) => ({ path: tr.path, values: p.values, cover: null }));

  return { planSwap, planCopy, cleanSpaces, planCleanSpaces, applyNameTool, planNameTool, parseTrack, formatTrack,
    planTrackNumbers, pasteValues, writeItems, canWriteTags, trackStatus };
});
