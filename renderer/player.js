// The built-in player's bar above the status bar (1.2's BuildPlayerBar, PlayQueueItem,
// StopPlaying, PlayerTimer and the bar's buttons). The sound itself is player.rs.
(function () {
  'use strict';
  const { t } = I18N;
  const RS = MENUDATA.rs;
  const $ = (s) => document.querySelector(s);
  const baseName = (p) => p.replace(/^.*[\\/]/, '');
  const fmt = (s) => LIST.formatDuration(s) || '0:00';

  let host = null; // { all(), saveVolume(v) }
  let q = { files: [], index: -1, sawPlaying: false };
  let timer = 0, ticking = false, dragging = false, duration = 0;

  const setPlayIcon = (pause) => { $('#pl-play').innerHTML = icon(pause ? 'pause' : 'play'); };
  const volume = () => Number($('#pl-vol').value) / 100;

  // from: StopPlaying
  async function stop() {
    clearInterval(timer);
    timer = 0;
    await API.playerStop();
    setPlayIcon(false);
    $('#pl-pos').value = 0;
    $('#pl-time').textContent = '0:00 / 0:00';
  }

  // from: PlayQueueItem
  async function playItem() {
    if (q.index < 0 || q.index >= q.files.length) return stop();
    const path = q.files[q.index];
    q.sawPlaying = false;
    try {
      await API.playerPlay(path, volume());
    } catch (e) {
      q = PLAYTOOLS.queueStopped(q);
      await stop();
      const [text, code] = String(e).split('|');
      return DIALOG.info(`${baseName(path)}: ${t(text, code)}`, t(RS.rsAfspilFil));
    }
    $('#pl-title').textContent = PLAYTOOLS.titleFor(path, host.all());
    $('#pl-title').title = path;
    setPlayIcon(true);
    $('#playerbar').hidden = false;
    clearInterval(timer);
    timer = setInterval(tick, 250);
  }

  // from: PlayerTimer
  async function tick() {
    if (ticking) return;
    ticking = true;
    try {
      const s = await API.playerStatus();
      if (s.state === 'playing') q.sawPlaying = true;
      if (q.sawPlaying && s.state === 'stopped') { // the end of a track: on to the next one
        q = PLAYTOOLS.queueAfterEnd(q);
        await playItem();
        return;
      }
      duration = s.duration;
      $('#pl-time').textContent = `${fmt(s.position)} / ${fmt(s.duration)}`;
      if (s.duration > 0 && !dragging) $('#pl-pos').value = Math.round((s.position / s.duration) * 1000);
    } finally {
      ticking = false;
    }
  }

  // from: StartPlaying
  function start(files, index) {
    if (!files.length) return;
    q = { files: files.slice(), index: Math.max(0, Math.min(files.length - 1, index)), sawPlaying: false };
    return playItem();
  }

  // from: PlayerPlayClick
  async function playPause() {
    const s = await API.playerStatus();
    if (!s.file) {
      if (q.files.length) return playItem();
      return host.playTargets();
    }
    if (s.state === 'playing') {
      await API.playerPause();
      setPlayIcon(false);
    } else {
      await API.playerResume();
      setPlayIcon(true);
    }
  }

  // from: PlayerPrevClick / PlayerNextClick
  async function prev() {
    if (!q.files.length) return;
    const s = await API.playerStatus();
    const r = PLAYTOOLS.queuePrev(q, s.file ? s.position : 0);
    if (r.seekZero) return API.playerSeek(0);
    q = r.q;
    return playItem();
  }
  function next() {
    const n = PLAYTOOLS.queueNext(q);
    if (!n) return;
    q = n;
    return playItem();
  }

  window.PLAYER = {
    init(h, vol) {
      host = h;
      for (const [id, ic, hint] of [['pl-prev', 'prev', RS.rsPlForrige], ['pl-play', 'play', RS.rsAfspilPause], ['pl-stop', 'stop', RS.rsStop],
        ['pl-next', 'next', RS.rsPlNaeste], ['pl-close', 'x', RS.rsLukAfspiller]]) {
        $('#' + id).innerHTML = icon(ic);
        $('#' + id).title = t(hint);
      }
      $('#pl-vol').title = t(RS.rsLydstyrke);
      $('#pl-vol').value = Math.max(0, Math.min(100, vol));
      $('#pl-prev').addEventListener('click', prev);
      $('#pl-play').addEventListener('click', playPause);
      $('#pl-stop').addEventListener('click', stop);
      $('#pl-next').addEventListener('click', next);
      $('#pl-close').addEventListener('click', async () => { await stop(); $('#playerbar').hidden = true; });
      const pos = $('#pl-pos');
      pos.addEventListener('input', () => { dragging = true; });
      // from: PlayerPosChange — a click or a drag on the bar jumps there
      pos.addEventListener('change', () => {
        dragging = false;
        if (duration > 0) API.playerSeek((Number(pos.value) / 1000) * duration);
      });
      // from: PlayerVolChange
      $('#pl-vol').addEventListener('input', () => {
        API.playerVolume(volume());
        host.saveVolume(Number($('#pl-vol').value));
      });
    },
    start,
    stop,
  };
})();
