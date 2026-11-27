// Cover tools (mainform.pas: ActCoverToTags, ActCoverFromTags, ActCoverAsFolder,
// ResizeFileCovers, ResizeFolderCovers, ActAutoResize) and pictures dropped on the cover
// panels (FormDropFiles). COVERS.dropPlan and isImageFile are what node --test runs.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./save.js'));
  else root.COVERS = factory(root.SAVE);
})(typeof self !== 'undefined' ? self : this, function (SAVE) {
  'use strict';
  const dirOf = (p) => p.replace(/[\\/][^\\/]*$/, '');
  // from: IsImageFile
  const isImageFile = (p) => /\.(jpe?g|png)$/i.test(p);

  // from: FormDropFiles — the file cover takes the checked/selected files; the folder cover is
  // the focused file's folder (as the panel shows it), else the open folder
  function dropPlan(panel, state) {
    if (panel === 'file') return { kind: 'file', items: SAVE.targets(state).items };
    if (panel === 'folder') {
      const tr = state.items[state.focus];
      return { kind: 'folder', dir: tr ? dirOf(tr.path) : state.folder };
    }
    return null;
  }

  /** The folders of `items` in list order, without repeats (case-insensitive, as Windows). */
  function dirsOf(items) {
    const seen = new Map();
    for (const tr of items) { const d = dirOf(tr.path); if (!seen.has(d.toLowerCase())) seen.set(d.toLowerCase(), d); }
    return [...seen.values()];
  }

  // ---------- the actions (DOM, Tauri) ----------
  /** h: { state, requireTargets(), startWrite(what, call, opt), get, save, bool, message(text),
   *  refreshCovers(), navigate(dir) } */
  function actions(h) {
    const { t } = I18N;
    const RS = MENUDATA.rs;
    const baseOf = (p) => p.replace(/^.*[\\/]/, '');
    const showErrors = (title, errors) => errors.length && DIALOG.info(errors.join('\n'), title);
    function coverOpt() {
      const n = (k, d) => { const v = parseInt(h.get('Cover', k, d), 10); return Number.isFinite(v) ? v : d; };
      return { maxSide: n('MaxSide', 600), quality: n('Quality', 90), toJpeg: h.bool('Cover', 'ToJpeg', false) };
    }
    function saveOpt(o) {
      h.save('Cover', 'MaxSide', o.maxSide);
      h.save('Cover', 'Quality', o.quality);
      h.save('Cover', 'ToJpeg', o.toJpeg ? 1 : 0);
    }
    const askOpt = async (title) => { const o = await FORMS.coverResize(t(title), coverOpt()); if (o) saveOpt(o); return o; };

    // from: ActCoverToTags
    async function coverIn() {
      const items = await h.requireTargets();
      if (!items) return;
      const what = t(RS.rsMappeCoverIFiler);
      const dirs = dirsOf(items), has = await API.folderCovers(dirs);
      const withCover = new Set(dirs.filter((_, i) => has[i]).map((d) => d.toLowerCase()));
      const n = items.filter((tr) => withCover.has(dirOf(tr.path).toLowerCase())).length;
      if (!n) return DIALOG.info(t(RS.rsIngenAfMapperneHarEtCover), what);
      const text = t(RS.rsLaegMappensCoverIndIDFiler, n) + (n < items.length ? '\n' + t(RS.rsDFilerLiggerIMapperUdenCover, items.length - n) : '');
      if (!(await DIALOG.confirm(what, text))) return;
      h.startWrite(what, (id) => API.coverToTagsBatch(items.map((tr) => tr.path), id), { showSkipped: false });
    }

    // from: ActCoverFromTags — per folder the first file with a cover
    async function coverOut() {
      const items = await h.requireTargets();
      if (!items) return;
      const what = t(RS.rsCoverTilMappe);
      const dirs = dirsOf(items), has = await API.folderCovers(dirs);
      const first = dirs.map((d) => items.find((tr) => tr.hasCover && dirOf(tr.path).toLowerCase() === d.toLowerCase()));
      const existing = has.filter(Boolean).length;
      const without = dirs.filter((_, i) => !has[i] && !first[i]).length;
      const todo = dirs.map((_, i) => (!has[i] && first[i] ? first[i].path : null)).filter(Boolean);
      if (!todo.length) return DIALOG.info(t(RS.rsIngenMapperAtGemme, existing, without), what);
      if (!(await DIALOG.confirm(what, t(RS.rsGemFilernesCoverIDMapper, todo.length, existing, without)))) return;
      const r = await API.coverFromTags(todo);
      h.message(t(RS.rsCoverGemtIDMapper, r.done));
      h.refreshCovers();
      showErrors(what, r.errors);
    }

    // from: ActCoverAsFolder — the focused file, else the first in the list
    async function coverAsFolder() {
      const tr = h.state.items[h.state.focus] || h.state.items[0];
      if (!tr || !tr.hasCover) return DIALOG.info(t(RS.rsDenMarkeredeFilHarIntetCover), t(RS.rsBrugFilensCoverSomMappeCover));
      try {
        let r = await API.coverAsFolder(tr.path, false);
        if (!r.written) {
          if (!(await DIALOG.confirm(t(RS.rsMappensCover), t(RS.rsSFindesAlleredeErstatDet, baseOf(r.target))))) return;
          r = await API.coverAsFolder(tr.path, true);
        }
        h.message(t(RS.rsMappensCoverGemtSom) + r.target);
        h.refreshCovers();
      } catch (e) {
        DIALOG.info(t(RS.rsBilledetKunneIkkeGemmes) + '\n' + t(String(e)), t(RS.rsMappensCover));
      }
    }

    // from: ActResizeFileCovers / ResizeFileCovers
    async function resizeFiles() {
      const opt = await askOpt(RS.rsSkalerCoverIFilerne);
      if (!opt) return;
      const items = await h.requireTargets();
      if (!items) return;
      const what = t(RS.rsSkalerCover);
      if (!(await DIALOG.confirm(what, t(RS.rsSkalerCoverIDFiler, items.length, opt.maxSide)))) return;
      const paths = items.filter((tr) => tr.hasCover).map((tr) => tr.path);
      h.startWrite(what, (id) => API.resizeFileCoversBatch(paths, opt, id), { showSkipped: false });
    }

    // from: ActResizeFolderCovers / ResizeFolderCovers
    async function resizeFolders() {
      const opt = await askOpt(RS.rsSkalerMappeCover);
      if (!opt) return;
      const items = await h.requireTargets();
      if (!items) return;
      const title = t(RS.rsSkalerMappeCover);
      const all = dirsOf(items), has = await API.folderCovers(all);
      const dirs = all.filter((_, i) => has[i]);
      if (!dirs.length) return DIALOG.info(t(RS.rsIngenAfMapperneHarEtCover), title);
      if (!(await DIALOG.confirm(title, t(RS.rsSkalerCoverIDMapper, dirs.length, opt.maxSide)))) return;
      const r = await API.resizeFolderCovers(dirs, opt);
      h.message(t(RS.rsCoverGemtIDMapper, r.done));
      h.refreshCovers();
      showErrors(title, r.errors);
    }

    // from: ActAutoResize — turning it on asks for the size first
    async function toggleAutoResize() {
      const on = !h.bool('Cover', 'AutoResize', false);
      if (on && !(await askOpt(RS.rsSkalerStoreCoverVedGem))) return;
      h.save('Cover', 'AutoResize', on ? 1 : 0);
      MENU.refresh();
    }

    // from: FormDropFiles
    async function drop(paths, panel) {
      if (!paths.length) return;
      if ((await API.pathKind(paths[0])) === 'dir') return h.navigate(paths[0]); // a folder dropped anywhere opens it
      const img = paths.find(isImageFile);
      const plan = dropPlan(panel, h.state);
      if (!img || !plan) return;
      let pic;
      try {
        pic = await API.readImageFile(img);
      } catch (e) {
        return DIALOG.info(e === 'notImage' ? t(RS.rsKunJpegOgPngBilleder) : e === 'tooLarge' ? t('Billedet er for stort (højst 16 MB).') : String(e));
      }
      if (plan.kind === 'folder') {
        if (!plan.dir) return;
        const target = plan.dir + '\\' + (pic.mime === 'image/png' ? 'folder.png' : 'folder.jpg');
        if ((await API.pathKind(target)) !== 'none'
          && !(await DIALOG.confirm(t(RS.rsMappensCover), t(RS.rsSFindesAlleredeErstatDet, baseOf(target))))) return;
        try {
          await API.writeFile(target, pic.data);
        } catch (e) {
          return DIALOG.info(t(RS.rsBilledetKunneIkkeGemmes) + '\n' + String(e));
        }
        h.refreshCovers();
        return h.message(t(RS.rsMappensCoverGemtSom) + baseOf(target));
      }
      const items = await h.requireTargets();
      if (!items) return;
      if (!(await DIALOG.confirm(t(RS.rsFilensCover), t(RS.rsSaetBilledetSomForsideCover, items.length)))) return;
      h.startWrite(t(RS.rsCover), (id) => API.writeTagsBatch(items.map((tr) => ({ path: tr.path, values: {}, cover: pic.data })), id));
    }

    return { coverIn, coverOut, coverAsFolder, resizeFiles, resizeFolders, toggleAutoResize, drop };
  }

  return { dropPlan, isImageFile, dirsOf, actions };
});
