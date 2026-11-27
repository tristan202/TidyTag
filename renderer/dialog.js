// Modal message boxes in the window (1.2's MessageDlg): information and Ja/Nej questions.
(function () {
  'use strict';
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
      const done = (v) => { back.remove(); removeEventListener('keydown', key, true); resolve(v); };
      const key = (e) => {
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); done(buttons[buttons.length - 1].value); }
        else if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); done(buttons[0].value); }
      };
      back.addEventListener('click', (e) => { const b = e.target.closest('[data-i]'); if (b) done(buttons[Number(b.dataset.i)].value); });
      addEventListener('keydown', key, true);
      document.body.appendChild(back);
      back.querySelector('.btn').focus();
    });
  }

  window.DIALOG = {
    info: (text, title = '') => show(title, text, [{ text: 'OK', value: true }]),
    confirm: (title, text) => show(title, text, [{ text: 'Ja', value: true }, { text: 'Nej', value: false }]),
  };
})();
