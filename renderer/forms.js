// Small form dialogs from tooldialogs.pas: AskFieldPair, AskFieldSet, AskID3Sync and
// AskCoverResize. Each resolves to the answer, or null for Annuller. Like DIALOG, an open form
// takes every key (Enter = OK, Escape = Annuller), so nothing behind it can run.
(function () {
  'use strict';
  const { t, label } = I18N;
  const RS = MENUDATA.rs;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const FIELDS = Object.keys(MENUDATA.fieldCaptions);
  const cap = (k) => t(MENUDATA.fieldCaptions[k]);

  /** body: HTML; collect(modal) gives the answer (or undefined to keep the form open). */
  function form(title, body, collect, { wide = false } = {}) {
    return new Promise((resolve) => {
      const back = document.createElement('div');
      back.className = 'modal-back';
      back.innerHTML = `<div class="modal form${wide ? ' wide' : ''}" role="dialog" aria-modal="true">
        <h2>${esc(title)}</h2><div class="form-body">${body}</div>
        <div class="modal-buttons"><button class="btn primary" data-ok>${esc(label(t('OK')))}</button>
        <button class="btn" data-cancel>${esc(label(t('Annuller')))}</button></div></div>`;
      const modal = back.firstElementChild;
      const done = (v) => { back.remove(); removeEventListener('keydown', key, true); resolve(v); };
      const ok = () => { const v = collect(modal); if (v !== undefined) done(v); };
      const key = (e) => {
        e.stopPropagation();
        const focusables = [...modal.querySelectorAll('input, select, button')].filter((el) => !el.disabled);
        if (e.key === 'Tab') { // keep the focus in the form
          e.preventDefault();
          const i = focusables.indexOf(document.activeElement);
          focusables[(i + (e.shiftKey ? focusables.length - 1 : 1) + focusables.length) % focusables.length]?.focus();
        } else if (e.key === 'Escape') {
          e.preventDefault();
          done(null);
        } else if (e.key === 'Enter') {
          e.preventDefault();
          if (document.activeElement?.tagName === 'BUTTON') document.activeElement.click();
          else ok();
        }
      };
      modal.querySelector('[data-ok]').addEventListener('click', ok);
      modal.querySelector('[data-cancel]').addEventListener('click', () => done(null));
      addEventListener('keydown', key, true);
      document.body.appendChild(back);
      (modal.querySelector('.form-body input, .form-body select') || modal.querySelector('[data-ok]')).focus();
    });
  }

  const fieldSelect = (name, sel) =>
    `<select name="${name}">${FIELDS.map((k) => `<option value="${k}"${k === sel ? ' selected' : ''}>${esc(cap(k))}</option>`).join('')}</select>`;
  const check = (name, caption, on) =>
    `<label class="chk-label"><input type="checkbox" name="${name}"${on ? ' checked' : ''}> ${esc(caption)}</label>`;
  const radios = (name, legend, options, sel) =>
    `<fieldset class="radio-group"><legend>${esc(legend)}</legend>${options.map(([v, text]) =>
      `<label class="chk-label"><input type="radio" name="${name}" value="${v}"${v === sel ? ' checked' : ''}> ${esc(text)}</label>`).join('')}</fieldset>`;
  const val = (m, name) => m.querySelector(`[name="${name}"]`);

  // from: AskFieldPair — the same field twice counts as Annuller
  function fieldPair(title, fromCaption, toCaption, checkCaption, a, b, chk) {
    return form(title, `<div class="form-grid">
        <span class="lbl">${esc(fromCaption)}</span>${fieldSelect('a', a)}
        <span class="lbl">${esc(toCaption)}</span>${fieldSelect('b', b)}
        ${checkCaption ? `<span></span>${check('check', checkCaption, chk)}` : ''}</div>`,
    (m) => {
      const r = { a: val(m, 'a').value, b: val(m, 'b').value, check: checkCaption ? val(m, 'check').checked : chk };
      return r.a === r.b ? null : r;
    });
  }

  // from: AskFieldSet — only fields with a value are listed; the others keep their choice
  function fieldSet(title, prompt, values, fields) {
    const shown = FIELDS.filter((k) => values[k]);
    const short = (v) => { const s = String(v).replace(/\r?\n/g, ' / '); return s.length > 60 ? s.slice(0, 57) + '...' : s; };
    return form(title, `<p class="lbl">${esc(prompt)}</p><div class="check-list">${shown.map((k) =>
        `<label class="chk-label"><input type="checkbox" data-k="${k}"${fields.includes(k) ? ' checked' : ''}> ${esc(cap(k))}:&nbsp; ${esc(short(values[k]))}</label>`).join('')}</div>
      <div class="btn-row"><button class="btn" type="button" data-all>${esc(t(RS.rsAlle))}</button>
      <button class="btn" type="button" data-none>${esc(t(RS.rsIngen))}</button></div>`,
    (m) => {
      const on = new Set(fields);
      m.querySelectorAll('[data-k]').forEach((c) => (c.checked ? on.add(c.dataset.k) : on.delete(c.dataset.k)));
      return FIELDS.filter((k) => on.has(k));
    }, { wide: true });
  }
  // the Alle/Ingen buttons (delegated: the form is built from a string)
  addEventListener('click', (e) => {
    const b = e.target.closest('[data-all], [data-none]');
    if (!b) return;
    b.closest('.modal').querySelectorAll('[data-k]').forEach((c) => { c.checked = b.hasAttribute('data-all'); });
  });

  // from: AskID3Sync — direction 'V1ToV2' | 'V2ToV1', existing 'Skip' | 'BlankOnly' | 'Overwrite'
  function id3Sync(direction, existing) {
    return form(t(RS.rsMpTagSynkronisering),
      radios('dir', t(RS.rsRetning), [['V1ToV2', t(RS.rsIdV1TilIdV2)], ['V2ToV1', t(RS.rsIdV2TilIdV1)]], direction) +
      radios('ex', t(RS.rsHvisTagFindes), [['Skip', t(RS.rsSkrivIkke)], ['BlankOnly', t(RS.rsKunTommeFelter)],
        ['Overwrite', t(RS.rsOverskrivFelter)]], existing) +
      `<p class="notes">${esc(t(RS.rsSyncHjaelp))}</p>`,
    (m) => ({ direction: m.querySelector('[name="dir"]:checked').value, existing: m.querySelector('[name="ex"]:checked').value }),
    { wide: true });
  }

  const clampInt = (v, lo, hi, def) => { const n = parseInt(v, 10); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : def; };

  // from: AskCoverResize — opt { maxSide, quality, toJpeg }
  function coverResize(title, opt) {
    return form(title, `<div class="form-grid">
        <span class="lbl">${esc(t(RS.rsStoersteSide))}</span><input class="input num" type="number" name="side" min="50" max="5000" value="${opt.maxSide}">
        <span class="lbl">${esc(t(RS.rsJpegKvalitet))}</span><input class="input num" type="number" name="q" min="1" max="100" value="${opt.quality}"></div>
      ${check('jpeg', t(RS.rsKonverterPngTilJpeg), opt.toJpeg)}<p class="notes">${esc(t(RS.rsSkaleringHjaelp))}</p>`,
    (m) => ({
      maxSide: clampInt(val(m, 'side').value, 50, 5000, opt.maxSide),
      quality: clampInt(val(m, 'q').value, 1, 100, opt.quality),
      toJpeg: val(m, 'jpeg').checked,
    }));
  }

  window.FORMS = { form, fieldPair, fieldSet, id3Sync, coverResize };
})();
