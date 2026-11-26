// The file list's logic, ported from 1.2's mainform.pas (CellText, CompareInfos, UpdateStatus).
// No DOM here, so node --test can run it.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./menudata.js'), require('./strings.js'));
  else root.LIST = factory(root.MENUDATA, root.I18N);
})(typeof self !== 'undefined' ? self : this, function (MENUDATA, I18N) {
  'use strict';
  const COLUMNS = MENUDATA.columns;
  const t = (s, ...a) => I18N.t(s, ...a);

  // from: FormatDuration (tagutils.pas)
  function formatDuration(seconds) {
    if (!(seconds > 0)) return '';
    const s = Math.round(seconds);
    const two = (n) => String(n).padStart(2, '0');
    return s >= 3600
      ? `${Math.floor(s / 3600)}:${two(Math.floor(s / 60) % 60)}:${two(s % 60)}`
      : `${Math.floor(s / 60)}:${two(s % 60)}`;
  }

  // from: FormatSize — FormatFloat uses the language's decimal separator
  function formatSize(bytes, lang = I18N.lang) {
    if (bytes >= 1024 * 1024) {
      const v = (bytes / (1024 * 1024)).toFixed(1);
      return (lang === 'en' ? v : v.replace('.', ',')) + ' MB';
    }
    return Math.floor((bytes + 1023) / 1024) + ' KB';
  }

  // from: CellText
  function cellText(tr, col) {
    const c = COLUMNS[col];
    switch (c.kind) {
      case 'check': return tr.checked ? '☑' : '☐';
      case 'filename': return tr.fileName;
      case 'field': return tr.fields[c.field] || '';
      case 'duration': return formatDuration(tr.duration);
      case 'bitrate': return tr.bitrate > 0 ? String(tr.bitrate) : '';
      case 'samplerate': return tr.sampleRate > 0 ? String(tr.sampleRate) : '';
      case 'codec': return tr.codec;
      case 'tagtypes':
        if (tr.error) return t('Fejl: ') + tr.error;
        if (!tr.supported) return t('(ikke understøttet endnu)');
        return tr.tagTypes;
      case 'cover': return tr.hasCover ? t('Ja') : '';
      case 'size': return formatSize(tr.fileSize);
      case 'folder': return tr.folder;
      default: return '';
    }
  }

  // from: LeadingNumber (mainform.pas)
  function leadingNumber(s) {
    const m = /^\d+/.exec(s || '');
    return m ? Number(m[0]) : -1;
  }

  // from: NumericValue
  function numericValue(tr, c) {
    switch (c.kind) {
      case 'check': return tr.checked ? 1 : 0;
      case 'field': return leadingNumber(tr.fields[c.field]);
      case 'duration': return tr.duration;
      case 'bitrate': return tr.bitrate;
      case 'samplerate': return tr.sampleRate;
      case 'size': return tr.fileSize;
      default: return 0;
    }
  }

  // UTF8CompareText: case-insensitive, by code point
  function compareText(a, b) {
    const x = a.toLowerCase(), y = b.toLowerCase();
    return x < y ? -1 : x > y ? 1 : 0;
  }

  const cmpNum = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

  // from: CompareInfos — order = { col, desc, col2, desc2 }; ties: col2, then the path
  function compareTracks(a, b, order) {
    const c = COLUMNS[order.col];
    let r = c.numeric ? cmpNum(numericValue(a, c), numericValue(b, c)) : compareText(cellText(a, order.col), cellText(b, order.col));
    if (order.desc) r = -r;
    if (r === 0 && order.col2 >= 0 && order.col2 !== order.col) {
      const c2 = COLUMNS[order.col2];
      r = c2.numeric ? cmpNum(numericValue(a, c2), numericValue(b, c2)) : compareText(cellText(a, order.col2), cellText(b, order.col2));
      if (order.desc2) r = -r;
    }
    if (r === 0) r = compareText(a.path, b.path);
    return r;
  }

  // Rows to draw for a scroll position, plus `overscan` rows above and below.
  function visibleWindow(scrollTop, viewportH, rowH, count, overscan = 10) {
    if (count <= 0) return { first: 0, last: -1 };
    const top = Math.floor(scrollTop / rowH);
    const bottom = Math.ceil((scrollTop + viewportH) / rowH) - 1;
    return { first: Math.max(0, top - overscan), last: Math.min(count - 1, bottom + overscan) };
  }

  // A scan batch for an older folder is dropped.
  function applyBatch(state, msg) {
    if (msg.scanId !== state.scanId) return false;
    for (const tr of msg.tracks) {
      tr.checked = false;
      state.items.push(tr);
    }
    return true;
  }

  // from: UpdateStatus — panels 0..4 (panel 5 is the message)
  function statusTexts(view, selected, hidden) {
    const sum = (list) => list.reduce((s, tr) => s + (tr.duration || 0), 0);
    const total = sum(view), sel = sum(selected);
    return [
      hidden > 0 ? t('Filer: %d (+%d skjult)', view.length, hidden) : t('Filer i alt: %d', view.length),
      t('Markerede: %d', selected.length),
      t('Samlet tid: ') + (total > 0 ? formatDuration(total) : '0:00'),
      t('Markeret tid: ') + (sel > 0 ? formatDuration(sel) : '0:00'),
      t('Afkrydset: %d', view.filter((tr) => tr.checked).length),
    ];
  }

  return { COLUMNS, formatDuration, formatSize, cellText, leadingNumber, compareTracks, visibleWindow, applyBatch, statusTexts };
});
