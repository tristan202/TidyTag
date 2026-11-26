// The Mapper tree: drives, then subfolders loaded when a node is opened.
(function () {
  'use strict';
  const norm = (p) => p.replace(/[\\/]+$/, '').toLowerCase();
  const isUnder = (path, dir) => { const a = norm(path), b = norm(dir); return a === b || a.startsWith(b + '\\'); };

  let box, onSelect;
  let roots = [];     // nodes: { name, path, hasChildren, children: null | [], open, el, depth, kind }
  let selected = null;

  function render() {
    const rows = [];
    const walk = (nodes, depth) => {
      for (const n of nodes) {
        n.depth = depth;
        rows.push(n);
        if (n.open && n.children) walk(n.children, depth + 1);
      }
    };
    walk(roots, 0);
    box.innerHTML = '';
    for (const n of rows) {
      const el = document.createElement('div');
      el.className = 'tnode' + (n.open ? ' open' : '') + (n === selected ? ' sel' : '');
      el.setAttribute('role', 'treeitem');
      el.style.paddingLeft = 4 + n.depth * 16 + 'px';
      el.innerHTML = `<span class="tcaret${n.hasChildren ? '' : ' leaf'}">${icon('caret')}</span>${icon(n.kind, 'ticon')}<span class="tlabel"></span>`;
      el.querySelector('.tlabel').textContent = n.name;
      el.title = n.path;
      el.querySelector('.tcaret').addEventListener('click', (ev) => { ev.stopPropagation(); toggle(n); });
      el.addEventListener('click', () => select(n, true));
      el.addEventListener('dblclick', () => toggle(n));
      n.el = el;
      box.appendChild(el);
    }
  }

  async function load(n) {
    if (n.children) return;
    const list = await API.listDirs(n.path);
    n.children = list.map((d) => ({ ...d, kind: 'folder', children: null, open: false }));
    n.hasChildren = n.children.length > 0;
  }

  async function toggle(n) {
    if (!n.hasChildren) return;
    if (!n.open) await load(n);
    n.open = !n.open;
    render();
  }

  function select(n, user) {
    selected = n;
    render();
    selected.el?.scrollIntoView({ block: 'nearest' });
    if (user) onSelect(n.path);
  }

  // Opens the tree down to `path` and selects it (without calling onSelect).
  async function reveal(path) {
    let nodes = roots, node = null;
    for (;;) {
      let next = nodes.find((n) => isUnder(path, n.path));
      if (!next && node) {
        // the folder may be newer than the cached listing: read the parent again once
        node.children = null;
        await load(node);
        nodes = node.children;
        next = nodes.find((n) => isUnder(path, n.path));
      }
      if (!next) break;
      node = next;
      if (norm(node.path) === norm(path)) break;
      await load(node);
      node.open = true;
      nodes = node.children;
    }
    selected = node && norm(node.path) === norm(path) ? node : null;
    render();
    selected?.el?.scrollIntoView({ block: 'nearest' });
  }

  function* walkAll(nodes = roots) {
    for (const n of nodes) { yield n; if (n.open && n.children) yield* walkAll(n.children); }
  }

  function onKey(ev) {
    const list = [...walkAll()];
    const i = list.indexOf(selected);
    if (ev.key === 'ArrowDown' && i < list.length - 1) select(list[i + 1], true);
    else if (ev.key === 'ArrowUp' && i > 0) select(list[i - 1], true);
    else if (ev.key === 'ArrowRight' && selected && !selected.open) toggle(selected);
    else if (ev.key === 'ArrowLeft' && selected) {
      if (selected.open) toggle(selected);
      else { const parent = list.find((n) => n.children && n.children.includes(selected)); if (parent) select(parent, true); }
    } else return;
    ev.preventDefault();
  }

  window.TREE = {
    async init(container, handler) {
      box = container;
      onSelect = handler;
      box.addEventListener('keydown', onKey);
      await this.reload();
    },
    async reload() {
      const keep = selected?.path;
      const drives = await API.listDrives();
      roots = drives.map((d) => ({ ...d, kind: 'drive', children: null, open: false }));
      render();
      if (keep) await reveal(keep);
    },
    reveal,
    collapseAll() { for (const n of walkAll()) n.open = false; render(); },
    get selectedPath() { return selected?.path || ''; },
  };
})();
