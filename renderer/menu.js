// Menu bar, popup menus, the icon bars and keyboard shortcuts, built from MENUDATA (1.2's
// actions and menus). The renderer supplies what each action does and whether it is checked.
(function () {
  'use strict';
  const { t, label, mnemonic } = I18N;
  const D = MENUDATA;
  const LATER = 'Kommer i en senere version';
  let host = null; // { run(id), live(id), enabled(id), checked(id), dynamic(item) -> items }
  let openStack = []; // open popups: { el, items, index }
  let barOpen = -1;

  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  // 'Vær&ktøjer' -> 'Vær<u>k</u>tøjer'
  const withMnemonic = (s) => esc(s.replace(/&&/g, '\u0001')).replace(/&amp;(.)/, '<u>$1</u>').replace(/\u0001/g, '&amp;');

  function actionEnabled(id) {
    const a = D.actions[id];
    return host.live(id) && host.enabled(id);
  }

  // Normalises MENUDATA entries and custom entries to one shape.
  function entries(items) {
    return items.map((i) => {
      if (i === '-') return { sep: true };
      if (i.ref) {
        const a = D.actions[i.ref];
        const [text, keyText] = t(a.text).split('\t');
        return {
          text, key: keyText || a.shortcut, icon: a.icon, id: i.ref, enabled: actionEnabled(i.ref),
          checked: a.check && host.checked(i.ref), later: !host.live(i.ref),
        };
      }
      if (i.special || i.dynamic) {
        const sub = host.dynamic(i);
        return sub ? { ...sub, text: sub.text ?? t(i.text) } : { text: t(i.text), items: [], enabled: false, later: true };
      }
      if (i.items) return { text: t(i.text), items: i.items, enabled: true };
      return i; // custom: { text, run, enabled, checked, radio, items }
    });
  }

  function closeFrom(level) {
    while (openStack.length > level) openStack.pop().el.remove();
    if (level === 0) {
      document.querySelectorAll('.menu-title.open').forEach((b) => b.classList.remove('open'));
      barOpen = -1;
    }
  }
  const closeAll = () => closeFrom(0);

  function activate(e) {
    if (!e || e.sep || e.enabled === false) return;
    if (e.items) return;
    closeAll();
    if (e.run) e.run();
    else if (e.id) host.run(e.id);
  }

  function highlight(level, index) {
    const p = openStack[level];
    if (!p) return;
    p.index = index;
    p.el.querySelectorAll('.menu-item').forEach((el) => el.classList.toggle('active', Number(el.dataset.i) === index));
  }

  function openSub(level, index) {
    const p = openStack[level];
    const e = p.list[index];
    closeFrom(level + 1);
    if (!e || !e.items || e.enabled === false) return;
    const r = p.el.querySelector(`[data-i="${index}"]`).getBoundingClientRect();
    popup(e.items, r.right + 2, r.top - 5, level + 1);
  }

  // Shows a popup menu at (x, y); level > 0 is a submenu of openStack[level - 1].
  function popup(items, x, y, level = 0, keys = false) {
    closeFrom(level);
    const list = entries(items);
    const el = document.createElement('div');
    el.className = 'popup' + (keys ? ' keys' : '');
    el.setAttribute('role', 'menu');
    el.innerHTML = list.map((e, i) => {
      if (e.sep) return '<div class="menu-sep"></div>';
      const mark = e.checked ? icon(e.radio ? 'check' : 'check') : e.icon ? icon(e.icon) : '';
      const tip = e.later ? ` title="${esc(t(LATER))}"` : '';
      return `<div class="menu-item${e.enabled === false ? ' disabled' : ''}" data-i="${i}" role="menuitem"${tip}>
        <span class="mi-icon">${mark}</span><span class="mi-text">${withMnemonic(e.text)}</span>
        ${e.key ? `<span class="mi-key">${esc(e.key)}</span>` : ''}${e.items ? `<span class="mi-sub">${icon('caret')}</span>` : ''}</div>`;
    }).join('');
    document.getElementById('popups').appendChild(el);
    // keep it on screen
    const r = el.getBoundingClientRect();
    el.style.left = Math.max(4, Math.min(x, innerWidth - r.width - 4)) + 'px';
    el.style.top = Math.max(4, Math.min(y, innerHeight - r.height - 4)) + 'px';
    const p = { el, list, index: -1 };
    openStack[level] = p;
    el.addEventListener('mousemove', (ev) => {
      const it = ev.target.closest('.menu-item');
      if (!it || Number(it.dataset.i) === p.index) return;
      highlight(level, Number(it.dataset.i));
      clearTimeout(p.timer);
      p.timer = setTimeout(() => openSub(level, Number(it.dataset.i)), 180);
    });
    el.addEventListener('click', (ev) => {
      const it = ev.target.closest('.menu-item');
      if (!it) return;
      const e = list[Number(it.dataset.i)];
      if (e.items) openSub(level, Number(it.dataset.i));
      else activate(e);
    });
    return el;
  }

  function openBar(i, keys = false) {
    closeAll();
    const btn = document.querySelectorAll('.menu-title')[i];
    if (!btn) return;
    barOpen = i;
    btn.classList.add('open');
    const r = btn.getBoundingClientRect();
    popup(D.menus[i].items, r.left, r.bottom + 2, 0, keys);
    if (keys) highlight(0, openStack[0].list.findIndex((e) => !e.sep && e.enabled !== false));
  }

  function buildBar() {
    const bar = document.getElementById('menus');
    bar.innerHTML = D.menus.map((m, i) => `<button class="menu-title" data-m="${i}" role="menuitem">${withMnemonic(t(m.text))}</button>`).join('');
    bar.querySelectorAll('.menu-title').forEach((b) => {
      const i = Number(b.dataset.m);
      b.addEventListener('mousedown', (ev) => { ev.preventDefault(); barOpen === i ? closeAll() : openBar(i); });
      b.addEventListener('mouseenter', () => { if (barOpen >= 0 && barOpen !== i) openBar(i); });
    });
  }

  function buildButtons(containerId, items) {
    const box = document.getElementById(containerId);
    box.innerHTML = items.map((i) => {
      if (i === '-') return '<span class="sep"></span>';
      const a = D.actions[i.ref];
      const cls = i.ref === 'aChkAll' ? ' ok' : i.ref === 'aUnchkAll' ? ' danger' : '';
      return `<button class="ic${cls}" data-act="${i.ref}">${icon(a.icon)}</button>`;
    }).join('');
    box.querySelectorAll('[data-act]').forEach((b) => b.addEventListener('click', () => host.run(b.dataset.act)));
  }

  // Tooltips, enabled and pressed state of the icon buttons.
  function refreshButtons() {
    document.querySelectorAll('[data-act]').forEach((b) => {
      const a = D.actions[b.dataset.act];
      const hint = label(t(a.hint).split('\t')[0]) + (a.shortcut ? ` (${a.shortcut})` : '');
      b.title = host.live(b.dataset.act) ? hint : `${hint}\n${t(LATER)}`;
      b.setAttribute('aria-label', hint);
      b.disabled = !actionEnabled(b.dataset.act);
      b.classList.toggle('pressed', a.check && host.checked(b.dataset.act));
    });
  }

  // 'Ctrl+Shift+V' etc. from a key event, in 1.2's ShortCut text form
  function keyName(ev) {
    const k = ev.key;
    const map = { ArrowUp: 'Up', ArrowDown: 'Down', Delete: 'Del', Enter: 'Enter', Backspace: 'Backspace' };
    let name = map[k] || (/^F\d+$/.test(k) ? k : k.length === 1 ? k.toUpperCase() : '');
    if (!name) return '';
    return [ev.ctrlKey && 'Ctrl', ev.shiftKey && 'Shift', ev.altKey && 'Alt', name].filter(Boolean).join('+');
  }
  const SHORTCUTS = {};
  for (const [id, a] of Object.entries(D.actions)) if (a.shortcut && !SHORTCUTS[a.shortcut]) SHORTCUTS[a.shortcut] = id;

  function onKey(ev) {
    // menus open: arrows, Enter, Esc
    if (openStack.length) {
      const level = openStack.length - 1;
      const p = openStack[level];
      const step = (d) => {
        const n = p.list.length;
        let i = p.index;
        for (let k = 0; k < n; k++) {
          i = (i + d + n) % n;
          if (!p.list[i].sep && p.list[i].enabled !== false) return highlight(level, i);
        }
      };
      if (ev.key === 'Escape') { level > 0 ? closeFrom(level) : closeAll(); }
      else if (ev.key === 'ArrowDown') step(1);
      else if (ev.key === 'ArrowUp') step(-1);
      else if (ev.key === 'ArrowRight') {
        if (p.list[p.index]?.items) { openSub(level, p.index); step.call(null, 0); highlight(level + 1, openStack[level + 1].list.findIndex((e) => !e.sep && e.enabled !== false)); }
        else if (barOpen >= 0) openBar((barOpen + 1) % D.menus.length, true);
      } else if (ev.key === 'ArrowLeft') {
        if (level > 0) closeFrom(level);
        else if (barOpen >= 0) openBar((barOpen - 1 + D.menus.length) % D.menus.length, true);
      } else if (ev.key === 'Enter') {
        const e = p.list[p.index];
        if (e?.items) openSub(level, p.index); else activate(e);
      } else if (ev.key.length === 1 && !ev.ctrlKey) {
        const i = p.list.findIndex((e) => !e.sep && e.enabled !== false && mnemonic(e.text.replace(/^([^&]*)$/, '&$1')) === ev.key.toLowerCase());
        if (i >= 0) { highlight(level, i); const e = p.list[i]; e.items ? openSub(level, i) : activate(e); }
      } else return;
      ev.preventDefault();
      return;
    }
    // Alt+letter opens a menu (1.2's accelerators)
    if (ev.altKey && !ev.ctrlKey && ev.key.length === 1) {
      const i = D.menus.findIndex((m) => mnemonic(t(m.text)) === ev.key.toLowerCase());
      if (i >= 0) { ev.preventDefault(); openBar(i, true); return; }
    }
    const name = keyName(ev);
    const id = SHORTCUTS[name];
    if (!id) return;
    // in text fields only function keys and Alt/Ctrl+Shift combinations act on files
    const inField = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement?.tagName);
    if (inField && !/^(F\d+|.*Alt\+|Ctrl\+Shift\+)/.test(name)) return;
    ev.preventDefault();
    if (actionEnabled(id)) host.run(id);
  }

  window.MENU = {
    init(h) {
      host = h;
      buildBar();
      buildButtons('toolbar', D.toolbar);
      buildButtons('folderbar', D.folderbar);
      refreshButtons();
      document.addEventListener('keydown', onKey, true);
      document.addEventListener('keydown', (ev) => { if (ev.key === 'Alt') document.body.classList.add('alt-keys'); });
      document.addEventListener('keyup', (ev) => { if (ev.key === 'Alt') document.body.classList.remove('alt-keys'); });
      document.addEventListener('mousedown', (ev) => { if (!ev.target.closest('.popup, .menu-title')) closeAll(); });
      window.addEventListener('blur', closeAll);
    },
    relabel() { buildBar(); refreshButtons(); },
    refresh: refreshButtons,
    popup,
    close: closeAll,
    LATER,
  };
})();
