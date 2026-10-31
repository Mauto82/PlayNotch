/// The OBS overlay page served at `/`.
///
/// Pick a layout to match the space over the camera feed:
///   - `layout=bar`     (default) wide lower-third strip: cover + title/artist + progress. ~3.5:1
///   - `layout=pill`    thin capsule for a corner: small round cover + one line. ~6:1
///   - `layout=square`  big cover with text on top, for side/vertical spaces. ~1:1
///   - `layout=text`    just title and artist, no background. Any ratio.
///   - `layout=video`   muted YouTube embed synced to YouTube Music, with text on
///                      top. Falls back to the cover when there's no playable
///                      video (other players, embedding disabled). ~16:9
///
/// Other options:
///   - `info=0`       hide title and artist (video layout)
///   - `bg=0`         no blurred-artwork background (transparent)
///   - `progress=0`   hide the progress bar
///   - `hide=0`       keep showing when playback is paused/stopped
///   - `radius=24`    corner radius in px (0 for square edges)
///   - `clean=0`      keep "(Remastered …)" / "- Live" style suffixes in titles
///   - `align=right`  mirror the layout (cover on the right)
enum OverlayPage {
    static let html = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>PlayNotch Overlay</title>
<style>
  :root { --accent: #ffffff; --radius: 18px; }
  html, body { margin: 0; height: 100%; background: transparent; overflow: hidden;
    font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif; color: #fff; }
  #root { position: absolute; inset: 0; border-radius: var(--radius); overflow: hidden;
    opacity: 0; transform: translateY(6%); transition: opacity .6s ease, transform .6s ease; }
  #root.visible { opacity: 1; transform: none; }

  .bg { position: absolute; inset: -30%; background-size: cover; background-position: center;
    filter: blur(28px) saturate(1.6) brightness(.55); }
  .shade { position: absolute; inset: 0;
    background: linear-gradient(90deg, rgba(0,0,0,.35), rgba(0,0,0,.1)); }
  body.nobg .bg, body.nobg .shade { display: none; }

  .card { position: relative; height: 100%; box-sizing: border-box; display: flex; align-items: center; }
  body.right .card { flex-direction: row-reverse; text-align: right; }
  .cover { flex: none; aspect-ratio: 1; background: #222 center/cover;
    box-shadow: 0 4px 18px rgba(0,0,0,.5); }
  .meta { min-width: 0; flex: 1; display: flex; flex-direction: column; }

  /* Scrolling line: only moves when the text doesn't fit. */
  .line { overflow: hidden; white-space: nowrap; }
  .line > span { display: inline-block; }
  .line.scroll > span { padding-right: 2em; animation: marquee var(--dur, 10s) ease-in-out infinite alternate; }
  @keyframes marquee { 0%, 15% { transform: translateX(0); } 85%, 100% { transform: translateX(var(--shift)); } }
  body.right .line.scroll > span { padding-right: 0; padding-left: 2em; }

  .title { font-weight: 700; line-height: 1.15; text-shadow: 0 1px 6px rgba(0,0,0,.4); }
  .artist { opacity: .85; line-height: 1.2; }
  .track { height: 4px; border-radius: 99px; background: rgba(255,255,255,.22); overflow: hidden; }
  .fill { height: 100%; width: 0; background: var(--accent); border-radius: 99px; }
  .times { display: flex; justify-content: space-between; opacity: .7; font-variant-numeric: tabular-nums; }
  body.noprogress .track, body.noprogress .times { display: none; }

  /* ---- bar: lower-third strip. Sizes follow height, capped by width. ---- */
  body.bar .card { gap: min(12vh, 3.5vw); padding: min(12vh, 3.5vw); }
  body.bar .cover { height: 100%; border-radius: calc(var(--radius) * .55); }
  body.bar .meta { gap: min(4vh, 1.2vw); }
  body.bar .title { font-size: min(24vh, 7vw); }
  body.bar .artist { font-size: min(16vh, 4.8vw); }
  body.bar .track { height: max(3px, min(4vh, 1.1vw)); margin-top: min(4vh, 1.2vw); }
  body.bar .times { font-size: min(10vh, 3vw); }

  /* ---- pill: one-line capsule ---- */
  body.pill #root { border-radius: 999px; }
  body.pill .card { gap: 5vh; padding: 10vh 8vh 10vh 10vh; }
  body.right.pill .card { padding: 10vh 10vh 10vh 8vh; }
  body.pill .cover { height: 100%; border-radius: 50%; }
  body.pill .meta { justify-content: center; }
  body.pill .title { font-size: 34vh; }
  body.pill .title .sep { opacity: .6; font-weight: 400; }
  body.pill .artist, body.pill .times { display: none; }
  body.pill .track { height: max(2px, 5vh); margin-top: 5vh; }

  /* ---- square: cover-first ---- */
  body.square .card { flex-direction: column; align-items: stretch; justify-content: flex-end;
    padding: 7vmin; gap: 2vmin; text-align: left; }
  body.square .cover { position: absolute; inset: 0; width: 100%; height: 100%; aspect-ratio: auto;
    box-shadow: none; border-radius: 0; }
  body.square .cover::after { content: ""; position: absolute; inset: 0;
    background: linear-gradient(transparent 40%, rgba(0,0,0,.8)); }
  body.square .meta { position: relative; flex: none; gap: 1.5vmin; }
  body.square .title { font-size: 9vmin; }
  body.square .artist { font-size: 6vmin; }
  body.square .track { height: max(3px, 1.2vmin); margin-top: 1.5vmin; }
  body.square .times { font-size: 4vmin; }
  body.square .bg, body.square .shade { display: none; }

  /* ---- text: no box at all ---- */
  body.text #root { border-radius: 0; }
  body.text .bg, body.text .shade, body.text .cover { display: none; }
  body.text .meta { gap: 3vh; }
  body.text .title { font-size: min(38vh, 8vw); text-shadow: 0 2px 10px rgba(0,0,0,.7); }
  body.text .artist { font-size: min(26vh, 5.5vw); text-shadow: 0 2px 10px rgba(0,0,0,.7); }
  body.text .track, body.text .times { display: none; }

  /* ---- video: muted embed, cover + blurred art as the fallback ---- */
  #video { position: absolute; inset: 0; opacity: 0; transition: opacity .5s ease; pointer-events: none; }
  #video iframe { width: 100%; height: 100%; border: 0; }
  body:not(.video) #video { display: none; }
  body.video.has-video #video { opacity: 1; }
  body.video .card { flex-direction: column; align-items: stretch; justify-content: flex-end;
    padding: 4vmin; text-align: left; background: linear-gradient(transparent 55%, rgba(0,0,0,.75)); }
  body.video .cover { position: absolute; inset: 0; width: 100%; height: 100%; aspect-ratio: auto;
    background-color: transparent; background-size: contain; background-repeat: no-repeat;
    box-shadow: none; border-radius: 0; transition: opacity .5s ease; }
  body.video.has-video .cover { opacity: 0; }
  body.video .meta { position: relative; flex: none; gap: 1vmin; }
  body.video .title { font-size: 7vmin; }
  body.video .artist { font-size: 4.5vmin; }
  body.video .track { height: max(3px, 1vmin); margin-top: 1.5vmin; }
  body.video .times { font-size: 3vmin; }
  body.noinfo .title, body.noinfo .artist { display: none; }
  body.video.noinfo.noprogress .card { background: none; }
</style>
</head>
<body>
<div id="root">
  <div class="bg" id="bg"></div>
  <div class="shade"></div>
  <div id="video"><div id="player"></div></div>
  <div class="card">
    <div class="cover" id="cover"></div>
    <div class="meta">
      <div class="line title" id="title"><span></span></div>
      <div class="line artist" id="artist"><span></span></div>
      <div class="track"><div class="fill" id="fill"></div></div>
      <div class="times"><span id="pos">0:00</span><span id="dur">0:00</span></div>
    </div>
  </div>
</div>
<script>
  const q = new URLSearchParams(location.search);
  const layout = ['bar', 'pill', 'square', 'text', 'video'].includes(q.get('layout')) ? q.get('layout') : 'bar';
  document.body.classList.add(layout);
  if (q.get('bg') === '0') document.body.classList.add('nobg');
  if (q.get('info') === '0') document.body.classList.add('noinfo');
  if (q.get('progress') === '0') document.body.classList.add('noprogress');
  if (q.get('align') === 'right') document.body.classList.add('right');
  if (q.has('radius')) document.documentElement.style.setProperty('--radius', q.get('radius') + 'px');
  const hideWhenPaused = q.get('hide') !== '0';
  const clean = q.get('clean') !== '0';

  const $ = id => document.getElementById(id);
  let state = null, lastArt = null, lastText = null;

  // "Song (Remastered 2003)" / "Song - 2011 Remaster" / "Song [Live]" → "Song"
  const tidy = t => !clean ? t : t
    .replace(/\s*[\(\[][^\)\]]*\b(remaster(ed)?|live|version|edit(ion)?|mono|stereo|deluxe|bonus|(re)?mix)\b[^\)\]]*[\)\]]/gi, '')
    .replace(/\s+-\s+.*\b(remaster(ed)?|live|version|edit(ion)?|mono|stereo|(re)?mix)\b.*$/i, '')
    .trim() || t;

  const fmt = s => {
    s = Math.max(0, Math.floor(s || 0));
    return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
  };

  // Set a line's text; enable the marquee only if it overflows.
  function setLine(el, html) {
    const span = el.firstElementChild;
    span.innerHTML = html;
    el.classList.remove('scroll');
    setTimeout(() => {
      const over = span.scrollWidth - el.clientWidth;
      if (over > 2) {
        const dir = document.body.classList.contains('right') ? 1 : -1;
        el.style.setProperty('--shift', (dir * (over + 8)) + 'px');
        el.style.setProperty('--dur', Math.max(4, over / 30) + 's');
        el.classList.add('scroll');
      }
    }, 0);
  }

  const esc = s => String(s || '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  function render() {
    const s = state;
    const visible = s && s.active && (s.playing || !hideWhenPaused);
    $('root').classList.toggle('visible', !!visible);
    if (!s || !s.active) return;

    document.documentElement.style.setProperty('--accent', s.accent || '#fff');

    const title = esc(tidy(s.title)), artist = esc(s.artist);
    const key = title + '|' + artist;
    if (key !== lastText) {
      lastText = key;
      setLine($('title'), layout === 'pill' && artist ? `${title} <span class="sep">· ${artist}</span>` : title);
      setLine($('artist'), artist);
    }

    if (s.artwork !== lastArt) {
      lastArt = s.artwork;
      const img = s.artwork ? `url("${s.artwork}")` : 'none';
      $('cover').style.backgroundImage = img;
      $('bg').style.backgroundImage = img;
    }
  }

  // ---- video layout ----
  // The embed is a second, muted player: it follows the YouTube Music tab and
  // is only revealed once it actually plays, so any failure leaves the cover.
  const MAX_DRIFT = 1.5, SEEK_COOLDOWN = 5000, START_TIMEOUT = 10000;
  let player = null, videoId = null, videoFailed = false, videoPlayed = false;
  let videoStartedAt = 0, lastSeek = 0;

  function showVideo(on) { document.body.classList.toggle('has-video', on); }

  function loadPlayer() {
    window.onYouTubeIframeAPIReady = () => {
      new YT.Player('player', {
        width: '100%', height: '100%',
        playerVars: { mute: 1, controls: 0, disablekb: 1, fs: 0, rel: 0, playsinline: 1,
          iv_load_policy: 3, origin: location.origin },
        events: {
          onReady: e => { e.target.mute(); player = e.target; syncVideo(); },
          onStateChange: e => {
            if (e.data === YT.PlayerState.PLAYING && !videoFailed && videoId) {
              videoPlayed = true;
              showVideo(true);
            }
          },
          // 2/5: bad request, 100: removed, 101/150/153: embedding not allowed.
          onError: () => failVideo(),
        },
      });
    };
    const s = document.createElement('script');
    s.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(s);
  }

  function failVideo() {
    videoFailed = true;
    showVideo(false);
    if (player) player.stopVideo();
  }

  // Where the YouTube Music tab is right now. Same machine as the server, so
  // its timestamp is comparable and more accurate than the time we polled.
  function targetPosition() {
    const elapsed = state.playing ? (Date.now() - state.serverAt) / 1000 : 0;
    return state.position + elapsed;
  }

  function syncVideo() {
    if (!player) return;
    const id = state && state.active && state.videoId ? state.videoId : null;
    if (!id) {
      if (videoId) player.stopVideo();
      videoId = null;
      showVideo(false);
      return;
    }
    if (id !== videoId) {
      videoId = id;
      videoFailed = videoPlayed = false;
      videoStartedAt = Date.now();
      showVideo(false);
      player.loadVideoById({ videoId: id, startSeconds: targetPosition() });
      if (!state.playing) player.pauseVideo();
      return;
    }
    if (videoFailed) return;

    const playerState = player.getPlayerState();
    if (!state.playing) {
      videoStartedAt = Date.now();   // the start timeout only counts while playing
      if (playerState === YT.PlayerState.PLAYING) player.pauseVideo();
    } else if (playerState === YT.PlayerState.PLAYING) {
      const now = Date.now();
      if (Math.abs(player.getCurrentTime() - targetPosition()) > MAX_DRIFT && now - lastSeek > SEEK_COOLDOWN) {
        lastSeek = now;
        player.seekTo(targetPosition(), true);
      }
    } else if (playerState !== YT.PlayerState.BUFFERING) {
      player.playVideo();
    }
    // Never got going (e.g. blocked without an error event): give up.
    if (state.playing && !videoPlayed && Date.now() - videoStartedAt > START_TIMEOUT) failVideo();
  }

  function tick() {
    if (state && state.active) {
      const elapsed = state.playing ? (Date.now() - state.updatedAt) / 1000 : 0;
      const dur = state.duration || 0;
      const pos = dur ? Math.min(state.position + elapsed, dur) : state.position + elapsed;
      $('fill').style.width = dur ? (pos / dur * 100) + '%' : '0';
      $('pos').textContent = fmt(pos);
      $('dur').textContent = fmt(dur);
    }
  }

  async function poll() {
    try {
      const r = await fetch('/now-playing.json', { cache: 'no-store' });
      const s = await r.json();
      // Use the local clock for extrapolation, not the server's timestamp.
      if (s.active) { s.serverAt = s.updatedAt; s.updatedAt = Date.now(); }
      state = s;
    } catch (e) {
      state = null;   // PlayNotch not running
    }
    render();
    if (layout === 'video') syncVideo();
  }

  // Re-measure marquees when OBS resizes the source.
  addEventListener('resize', () => { lastText = null; render(); });

  // Plain timers, not requestAnimationFrame: OBS pauses rAF for browser
  // sources that aren't on air (e.g. the Studio Mode preview side).
  if (layout === 'video') loadPlayer();
  poll();
  setInterval(poll, 1000);
  setInterval(tick, 250);
</script>
</body>
</html>
"""#
}
