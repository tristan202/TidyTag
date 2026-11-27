// Modal message boxes in the window (1.2's MessageDlg): information and Ja/Nej questions.
// While one is open it takes every key, so nothing behind it (F5, shortcuts) can run.
(function (root, factory) {
  const m = factory();
  if (typeof module === 'object' && module.exports) module.exports = m;
  else root.DIALOG_KEYS = m;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  /** Which button a key answers: Enter = the focused button (else the first), Escape = the last. */
  function keyAnswer(key, focused, count) {
    if (key === 'Enter') return focused >= 0 ? focused : 0;
    if (key === 'Escape') return count - 1;
    return null;
  }
  return { keyAnswer };
});

(function () {
  'use strict';
  if (typeof document === 'undefined') return;
  const { t, label } = I18N;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

  function show(title, text, buttons) {
    return new Promise((resolve) => {
      const back = document.createElement('div');
      back.className = 'modal-back';
      back.innerHTML = `<div class="modal" role="dialog" aria-modal="true">
        ${title ? `<h2>${esc(title)}</h2>` : ''}<p class="modal-text">${esc(text)}</p>
        <div class="modal-buttons">${buttons.map((b, i) =>
          `<button class="btn${i === 0 ? ' primary' : ''}" data-i="${i}">${esc(label(t(b.text)))}</button>`).join('')}</div></div>`;
      const btns = [...back.querySelectorAll('[data-i]')];
      const done = (i) => { back.remove(); removeEventListener('keydown', key, true); resolve(buttons[i].value); };
      const key = (e) => {
        e.stopPropagation();
        const focused = btns.indexOf(document.activeElement);
        if (e.key === 'Tab') { // keep the focus on the dialog's buttons
          e.preventDefault();
          const next = (Math.max(0, focused) + (e.shiftKey ? btns.length - 1 : 1)) % btns.length;
          btns[next].focus();
          return;
        }
        const answer = DIALOG_KEYS.keyAnswer(e.key, focused, btns.length);
        if (answer !== null) e.preventDefault(), done(answer);
        else if (!(e.key === ' ' && focused >= 0)) e.preventDefault(); // Space clicks the focused button
      };
      back.addEventListener('click', (e) => { const b = e.target.closest('[data-i]'); if (b) done(Number(b.dataset.i)); });
      addEventListener('keydown', key, true);
      document.body.appendChild(back);
      btns[0].focus();
    });
  }

  window.DIALOG = {
    info: (text, title = '') => show(title, text, [{ text: 'OK', value: true }]),
    confirm: (title, text) => show(title, text, [{ text: 'Ja', value: true }, { text: 'Nej', value: false }]),
    /** 'yes' | 'no' | null (Annuller, Escape) */
    yesNoCancel: (title, text) => show(title, text,
      [{ text: 'Ja', value: 'yes' }, { text: 'Nej', value: 'no' }, { text: 'Annuller', value: null }]),
  };
})();
