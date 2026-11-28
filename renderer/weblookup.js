// "Web-opslag" (1.2's TFormWebLookup): search releases on MusicBrainz or Discogs, pair the files
// with the release's tracks, then write the chosen fields and the front cover. The searches
// run in Rust (web.rs); the pairing is WEBMATCH; writing is the main window's batch writer.
(function () {
  'use strict';
  const { t, label } = I18N;
  const RS = { ...MENUDATA.rs, ...MENUDATA.unitRs.weblookupform };
  const esc = FORMS.esc;
  const base = (p) => p.replace(/^.*[\\/]/, '');
  const dur = (s) => LIST.formatDuration(s);
  // Rust's errors are 1.2's texts, with arguments after '|'
  const tErr = (e) => { const [text, ...args] = String(e).split('|'); return t(text, ...args); };
  const SOURCES = ['MusicBrainz', 'Discogs'];
  // the "Skriv" check boxes: [Web] key, caption (1.2's weblookupform.lfm)
  const CHECKS = [['Title', 'Titler'], ['Artist', 'Kunstner'], ['Album', 'Album'], ['AlbumArtist', 'Albumkunstner'], ['Year', 'År'],
    ['YearOnly', '(kun årstal)'], ['Track', 'Spornumre'], ['TrackTotal', '(som 07/12)'], ['Label', 'Pladeselskab, katalognr.'],
    ['Disc', 'Disc-nr.'], ['Genre', 'Genre'], ['CoverTags', 'Cover i filerne'], ['CoverFolder', 'Cover som folder.jpg i mappen']];
  const DEFAULTS = { Title: 1, Artist: 1, Album: 1, AlbumArtist: 1, Year: 1, YearOnly: 1, Track: 1, TrackTotal: 0, Disc: 1, Genre: 0, Label: 0, CoverTags: 1, CoverFolder: 0 };

  /** items: the files (TrackDtos); batch: { pos, count } or null.
   *  host: { web() -> [Web] snapshot (lower-case keys), saveWeb(key, value), token() -> string,
   *  editToken() -> Promise<string | null>, keepDate() -> bool, setKeepDate(bool),
   *  write(batchItems) -> Promise<write-done msg | null>, pathKind(path), writeFile(path, base64) }.
   *  Resolves 'written' | 'skipped' | 'stopped'; `changed` tells whether files were written. */
  function open(items, { batch = null, host }) {
    return new Promise((resolve) => {
      const isBatch = !!batch && batch.count > 1;
      const web = host.web();
      const flag = (k) => { const v = web[k.toLowerCase()]; return v === undefined || v === '' ? !!DEFAULTS[k] : !['0', 'false'].includes(String(v).toLowerCase()); };
      let releases = [], relSource = 0, detail = null, rows = [], cover = null, busy = false, selRow = -1, relIndex = -1, changed = false;
      let token = host.token();

      // from: ExecuteBatch — the search fields from the files' common values
      const artist0 = WEBMATCH.commonValue(items, 'albumArtist') || WEBMATCH.commonValue(items, 'artist');
      const title = isBatch ? t(RS.rsWebOpslagBatch, batch.pos, batch.count, items.length) : t(RS.rsWebOpslagDFiler, items.length);
      const m = FORMS.modal(`<h2>${esc(title)}</h2>
        <div class="frow web-search">
          <select name="source">${SOURCES.map((s, i) => `<option value="${i}"${i === (Number(web.source) === 1 ? 1 : 0) ? ' selected' : ''}>${s}</option>`).join('')}</select>
          <button class="btn" data-token>${esc(label(t('Discogs-token...')))}</button>
          <span class="lbl">${esc(t('Kunstner:'))}</span><input class="input" name="artist" spellcheck="false" value="${esc(artist0)}">
          <span class="lbl">${esc(t('Sang:'))}</span><input class="input" name="title" spellcheck="false" value="${esc(items.length === 1 ? items[0].fields.title || '' : '')}">
          <span class="lbl">${esc(t('Album:'))}</span><input class="input" name="album" spellcheck="false" value="${esc(WEBMATCH.commonValue(items, 'album'))}">
          <button class="btn primary" data-search>${esc(label(t('Søg')))}</button>
        </div>
        <div class="track-list web-releases"><table><thead><tr>${['Kunstner', 'Album', 'Dato', 'Land', 'Spor', 'Format', 'Pladeselskab', 'Katalognr.', 'Type']
          .map((c) => `<th>${esc(t(c))}</th>`).join('')}</tr></thead><tbody data-rel></tbody></table></div>
        <div class="lbl">${esc(t('Spor på den valgte udgivelse og de filer, der får dem (flyt filer med Op/Ned):'))}</div>
        <div class="web-mid">
          <div class="web-tracks-col">
            <div class="track-list web-tracks"><table><thead><tr>${['Nr.', 'Titel (fra kilden)', 'Kunstner', 'Længde', 'Fil', 'Længde']
              .map((c) => `<th>${esc(t(c))}</th>`).join('')}</tr></thead><tbody data-tracks></tbody></table></div>
            <div class="frow"><button class="btn" data-up>${esc(label(t('Op')))}</button><button class="btn" data-down>${esc(label(t('Ned')))}</button></div>
          </div>
          <div class="web-side">
            <div class="web-cover"></div><div class="lbl" data-covertext></div>
            <fieldset class="radio-group"><legend>${esc(t('Skriv'))}</legend>
              ${CHECKS.map(([k, c]) => `<label class="chk-label${k === 'YearOnly' || k === 'TrackTotal' ? ' sub' : ''}"><input type="checkbox" data-w="${k}"${flag(k) ? ' checked' : ''}> ${esc(t(c))}</label>`).join('')}
              <label class="chk-label"><input type="checkbox" data-keep${host.keepDate() ? ' checked' : ''}> ${esc(t('Bevar filernes dato'))}</label>
            </fieldset>
          </div>
        </div>
        <div class="track-bottom"><span class="lbl web-status" data-status></span>
          ${isBatch ? `<button class="btn" data-skip>${esc(label(t(RS.rsSpringOver)))}</button>` : ''}
          <button class="btn primary" data-write disabled>${esc(label(t(RS.rsSkrivTags)))}</button>
          <button class="btn" data-close>${esc(label(t(isBatch ? RS.rsStop : 'Luk')))}</button></div>`,
      { cls: 'wide web-lookup', onEscape: () => close('stopped'), onEnter: () => search() });
      const q = (s) => m.el.querySelector(s);
      const source = () => Number(q('[name="source"]').value);
      const sourceName = () => SOURCES[source()];
      const status = (s) => { q('[data-status]').textContent = s; };
      status(t(RS.rsSkrivKunstnerOgAlbumOg));
      q('[data-token]').hidden = source() !== 1;

      // from: SetBusy
      function setBusy(v) {
        busy = v;
        for (const s of ['[data-search]', '[data-up]', '[data-down]', '[name="source"]']) q(s).disabled = v;
        q('[data-write]').disabled = v || !detail;
        m.el.querySelectorAll('.web-releases tbody tr').forEach((r) => r.classList.toggle('off', v));
        document.body.style.cursor = v ? 'progress' : '';
      }
      async function job(call, text) {
        setBusy(true);
        status(text);
        try {
          return { ok: true, value: await call() };
        } catch (e) {
          status(t(RS.rsFejl) + tErr(e));
          return { ok: false };
        } finally {
          setBusy(false);
        }
      }

      // from: ShowTracks — before a release is chosen, just the files
      function showTracks() {
        const fileCells = (i) => (i >= 0 ? `<td>${esc(base(items[i].path))}</td><td>${esc(dur(items[i].duration))}</td>` : '<td></td><td></td>');
        q('[data-tracks]').innerHTML = detail
          ? rows.map((r, i) => {
            const tk = r.trackIdx >= 0 ? detail.tracks[r.trackIdx] : null;
            const nr = tk ? (detail.discCount > 1 ? `${tk.disc}-${String(tk.position).padStart(2, '0')}` : String(tk.position)) : '-';
            const trackCells = tk ? `<td>${esc(tk.title)}</td><td>${esc(tk.artist)}</td><td>${esc(dur(tk.lengthMs / 1000))}</td>`
              : `<td class="muted">${esc(t(RS.rsIntetSporFilenAendresIkke))}</td><td></td><td></td>`;
            return `<tr data-row="${i}" class="${i === selRow ? 'sel' : ''}"><td>${esc(nr)}</td>${trackCells}${fileCells(r.fileIdx)}</tr>`;
          }).join('')
          : items.map((_, i) => `<tr><td></td><td></td><td></td><td></td>${fileCells(i)}</tr>`).join('');
        m.el.querySelector(`[data-row="${selRow}"]`)?.scrollIntoView({ block: 'nearest' });
      }
      // from: ShowCover
      function showCover() {
        q('.web-cover').innerHTML = cover ? `<img alt="" src="data:${esc(cover.mime)};base64,${esc(cover.data)}">` : '';
        q('[data-covertext]').textContent = cover
          ? t(RS.rsCoverDxDDKb, cover.width, cover.height, Math.ceil((cover.data.length * 3) / 4 / 1024))
          : detail ? t(RS.rsIntetCoverFundet) : '';
      }
      function showReleases() {
        q('[data-rel]').innerHTML = releases.map((r, i) => `<tr data-rel-i="${i}" class="${i === relIndex ? 'sel' : ''}">${[
          r.artist, r.title + (r.disambiguation ? ` (${r.disambiguation})` : ''), r.date, r.country, r.trackCount > 0 ? String(r.trackCount) : '',
          r.formats, r.labelName, r.catalogNo, r.releaseType].map((c) => `<td>${esc(c)}</td>`).join('')}</tr>`).join('');
        m.el.querySelector(`[data-rel-i="${relIndex}"]`)?.scrollIntoView({ block: 'nearest' });
      }

      // from: ButtonSearchClick
      async function search() {
        if (busy) return;
        const songTitle = q('[name="title"]').value.trim();
        const src = source();
        const r = await job(() => API.webSearch(src, q('[name="artist"]').value.trim(), q('[name="album"]').value.trim(), songTitle),
          t(RS.rsSoegerPaa) + sourceName() + '...');
        if (!r.ok) return;
        releases = r.value;
        relSource = src; // the releases belong to the service that found them
        relIndex = -1;
        detail = null;
        showReleases();
        if (!releases.length) return status(t(RS.rsIngenUdgivelserFundetProevMed));
        status(t(RS.rsDUdgivelserFundetPaaS, releases.length, sourceName()));
        // a song search is sorted with the original album first; otherwise the first release
        // with as many tracks as there are files, else the best hit
        const same = songTitle ? -1 : releases.findIndex((x) => x.trackCount === items.length);
        loadRelease(same >= 0 ? same : 0);
      }

      // from: LoadRelease
      async function loadRelease(i) {
        if (i < 0 || i >= releases.length || busy) return;
        relIndex = i;
        showReleases();
        detail = null;
        cover = null;
        showCover();
        const r = await job(() => API.webRelease(relSource, releases[i].id), t(RS.rsHenterSporliste));
        if (!r.ok || relIndex !== i) return;
        detail = r.value;
        const match = WEBMATCH.matchFilesToTracks(items, detail, releases[i].hitDisc, releases[i].hitPosition);
        rows = match.rows;
        selRow = -1;
        showTracks();
        const text = t({ title: RS.rsFilerneErParretEfterTitler, hit: RS.rsFilenErParretMedSangen, number: RS.rsFilerneErParretEfterDeres }[match.method]
          || RS.rsFilerneErParretIListens);
        const c = await job(() => API.webCover(relSource, detail.release.id, detail.release.releaseGroupId, detail.coverUrl), text);
        if (relIndex !== i) return;
        cover = c.ok ? c.value : null;
        showCover();
        status(text.replace(t(RS.rsHenterCover), ''));
        q('[data-write]').disabled = false;
      }

      // from: ComboSourceChange — the results of one source mean nothing to the other
      q('[name="source"]').addEventListener('change', () => {
        releases = []; detail = null; cover = null; relIndex = -1;
        showReleases(); showTracks(); showCover();
        q('[data-write]').disabled = true;
        q('[data-token]').hidden = source() !== 1;
        status(t(source() === 1 && !token ? RS.rsDiscogsKraeverEtPersonligtToken : RS.rsTrykSoeg));
      });
      // from: ButtonTokenClick
      q('[data-token]').addEventListener('click', async () => {
        const v = await host.editToken();
        if (v === null) return;
        token = v;
        status(t(token ? RS.rsDiscogsTokenGemtTrykSoeg : RS.rsDiscogsTokenFjernet));
      });

      // from: ButtonUpClick / ButtonDownClick
      function move(delta) {
        if (!detail || selRow < 0) return;
        const to = selRow + delta;
        if (to < 0 || to >= rows.length) return;
        WEBMATCH.moveFile(rows, selRow, delta);
        selRow = to;
        showTracks();
      }

      // from: SaveOptions
      function saveOptions() {
        for (const [k] of CHECKS) host.saveWeb(k, q(`[data-w="${k}"]`).checked ? 1 : 0);
        host.saveWeb('Source', source());
        host.setKeepDate(q('[data-keep]').checked);
      }
      // from: Options
      const options = () => WEBMATCH.options(Object.fromEntries(CHECKS.map(([k]) => [k.toLowerCase(), q(`[data-w="${k}"]`).checked ? '1' : '0'])));

      // from: ButtonWriteClick
      async function write() {
        if (!detail || busy) return;
        const opt = options();
        const pairs = WEBMATCH.pairs(rows);
        if (!opt.fields.size && !opt.coverTags && !opt.coverFolder) return DIALOG.info(t(RS.rsVaelgHvadDerSkalSkrives));
        // in a batch the button itself is the decision; asking again for every song is just a click more
        if (!isBatch && !(await DIALOG.confirm(t(RS.rsSkrivTags), t(RS.rsSkrivOplysningerFraSI, detail.release.title, pairs.length)))) return;
        saveOptions();
        setBusy(true);
        const errors = [];
        let saved = 0, failed = 0, skipped = 0, folders = 0;
        try {
          status(t(RS.rsSkriver) + '...');
          const batchItems = pairs.map((p) => ({ path: items[p.fileIdx].path, values: WEBMATCH.applyTrack(detail, p.trackIdx, opt),
            cover: opt.coverTags && cover ? cover.data : null }));
          // only folder.jpg chosen: nothing to change in the files themselves
          if (batchItems.length && (opt.fields.size || (opt.coverTags && cover))) {
            const msg = await host.write(batchItems);
            if (msg) {
              ({ saved, failed, skipped } = msg);
              errors.push(...msg.errors.map((e) => `${base(e.file)}: ${t(e.error)}`));
              if (saved > 0) changed = true;
            }
          }
          // folder.jpg next to the files (never overwrites an existing one)
          if (opt.coverFolder && cover) {
            for (const dir of WEBMATCH.folderCoverDirs(rows, items)) {
              const target = dir.replace(/\\$/, '') + '\\' + (cover.mime === 'image/png' ? 'folder.png' : 'folder.jpg');
              if ((await host.pathKind(target)) !== 'none') { errors.push(target + t(RS.rsFindesAlleredeIkkeOverskrevet)); continue; }
              try { await host.writeFile(target, cover.data); folders += 1; } catch (e) { errors.push(`${target}: ${tErr(e)}`); }
            }
          }
        } finally {
          setBusy(false);
        }
        status(t(RS.rsGemtIDFilerD, saved, failed, skipped) + (folders > 0 ? t(RS.rsCoverGemtIDMapper, folders) : ''));
        if (errors.length) await DIALOG.info(errors.slice(0, 20).join('\n'), t(RS.rsBemaerk));
        if (isBatch && WEBMATCH.lookupWritten(saved, folders)) close('written'); // on to the next files
      }

      // from: FormCloseQuery — a running web call finishes on its own; wait for it
      function close(result) {
        if (busy) return;
        saveOptions();
        document.body.style.cursor = '';
        m.close();
        resolve({ result, changed });
      }

      m.el.addEventListener('click', (e) => {
        const rel = e.target.closest('[data-rel-i]');
        if (rel && !busy) return loadRelease(Number(rel.dataset.relI));
        const row = e.target.closest('[data-row]');
        if (row) { selRow = Number(row.dataset.row); return showTracks(); }
        if (e.target.closest('[data-search]')) search();
        else if (e.target.closest('[data-up]')) move(-1);
        else if (e.target.closest('[data-down]')) move(1);
        else if (e.target.closest('[data-write]')) write();
        else if (e.target.closest('[data-skip]')) close('skipped');
        else if (e.target.closest('[data-close]')) close('stopped');
      });
      showTracks();
      q('[name="artist"]').focus();
      // from: FormShowBatch — a batch searches right away when there is something to search for
      if (isBatch && q('[name="artist"]').value.trim() && (q('[name="title"]').value.trim() || q('[name="album"]').value.trim())) search();
    });
  }

  window.WEBLOOKUP = { open };
})();
