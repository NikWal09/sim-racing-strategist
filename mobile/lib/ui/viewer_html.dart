/// Samodzielna strona HTML do przeglądania/porównywania telemetrii — port 1:1
/// szablonu z `tools/telemetry_viewer.py`. Dane okrążeń wstrzykujemy w miejsce
/// `/*__DATA__*/`. Strona robi wszystko w JS (mapa toru, wykresy, porównanie,
/// delta), więc wygląda identycznie jak wersja komputerowa.
library;

import 'dart:convert';

String buildViewerHtml(List<Map<String, dynamic>> laps) =>
    _viewerTemplate.replaceFirst('/*__DATA__*/', jsonEncode(laps));

const String _viewerTemplate = r'''<!DOCTYPE html>
<html lang="pl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Telemetria GT7 - przegladarka okrazen</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: "Segoe UI", Roboto, system-ui, sans-serif;
         background: #14171c; color: #e6e9ef; }
  header { padding: 14px 18px; background: #1b1f27; border-bottom: 1px solid #2a2f3a; }
  header h1 { margin: 0; font-size: 17px; font-weight: 600; }
  header .sub { color: #8b93a4; font-size: 12px; margin-top: 3px; }
  .layout { display: flex; min-height: calc(100vh - 58px); }
  .side { width: 290px; flex: 0 0 290px; background: #1b1f27; border-right: 1px solid #2a2f3a;
          padding: 14px; overflow-y: auto; }
  .main { flex: 1; padding: 14px 18px; min-width: 0; }
  label.fld { display: block; font-size: 12px; color: #8b93a4; margin: 0 0 5px; }
  select { width: 100%; padding: 7px 8px; background: #11141a; color: #e6e9ef;
           border: 1px solid #2a2f3a; border-radius: 7px; font-size: 13px; }
  .laps { margin-top: 16px; display: flex; flex-direction: column; gap: 6px; }
  .lap { display: flex; align-items: center; gap: 9px; padding: 8px 9px; border-radius: 8px;
         background: #11141a; border: 1px solid #2a2f3a; cursor: pointer; user-select: none; }
  .lap:hover { border-color: #3a4150; }
  .lap.on { border-color: #4f8cff; background: #18202e; }
  .lap .sw { width: 12px; height: 12px; border-radius: 3px; flex: 0 0 12px; background: #555; }
  .lap .meta { display: flex; flex-direction: column; line-height: 1.25; min-width: 0; }
  .lap .t { font-size: 14px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .lap .s { font-size: 11px; color: #8b93a4; white-space: nowrap; overflow: hidden;
            text-overflow: ellipsis; }
  .card { background: #1b1f27; border: 1px solid #2a2f3a; border-radius: 10px;
          padding: 12px; margin-bottom: 14px; }
  .card h2 { margin: 0 0 8px; font-size: 13px; font-weight: 600; color: #c7cdd9; }
  canvas { display: block; width: 100%; }
  .charts { display: flex; flex-direction: column; gap: 14px; }
  .hint { color: #8b93a4; font-size: 12px; }
  .empty { padding: 40px; text-align: center; color: #8b93a4; }
  .legend { display: flex; flex-wrap: wrap; gap: 12px; font-size: 12px; margin-top: 6px; }
  .legend span { display: inline-flex; align-items: center; gap: 6px; }
  .legend i { width: 11px; height: 11px; border-radius: 3px; display: inline-block; }
  .viewbar { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; flex-wrap: wrap; }
  .vbtn { background: #1b1f27; color: #c7cdd9; border: 1px solid #2a2f3a;
          border-radius: 7px; padding: 6px 14px; font-size: 13px; cursor: pointer; }
  .vbtn:hover { border-color: #3a4150; }
  .vbtn.on { background: #18202e; border-color: #4f8cff; color: #fff; }
  .seg { margin-left: auto; font-size: 13px; display: flex; gap: 12px; align-items: center;
         font-variant-numeric: tabular-nums; }
  .seg i { width: 10px; height: 10px; border-radius: 3px; display: inline-block;
           margin-right: 4px; }
</style>
</head>
<body>
<header>
  <h1>Telemetria GT7 - przegladarka okrazen</h1>
  <div class="sub" id="sub">Wczytywanie...</div>
</header>
<div class="layout">
  <aside class="side">
    <label class="fld" for="trackSel">Tor (grupa okrazen)</label>
    <select id="trackSel"></select>
    <div class="laps" id="lapList"></div>
  </aside>
  <main class="main" id="mainArea"></main>
</div>

<script>
const LAPS = /*__DATA__*/;
const COLORS = ["#4f8cff","#ff5c5c","#3fcf8e","#ffb020","#b07cff","#22c3d6","#ff7ac0","#9fe04f"];

// --- przygotowanie danych ---
LAPS.forEach((lap, i) => {
  lap._idx = i;
  const ch = {}; lap.channels.forEach((c, k) => ch[c] = k);
  lap._ch = ch;
  const xi = ch.x, zi = ch.z, S = lap.samples;
  const dist = new Array(S.length); dist[0] = 0;
  for (let j = 1; j < S.length; j++) {
    const dx = S[j][xi] - S[j-1][xi], dz = S[j][zi] - S[j-1][zi];
    dist[j] = dist[j-1] + Math.hypot(dx, dz);
  }
  lap._dist = dist;
  lap._len = dist[dist.length-1] || 1;
});

function buildGroups() {
  const g = [];
  const rel = (a, b) => Math.abs(a - b) / Math.max(a, b, 1);
  LAPS.forEach(l => {
    const fp = l.fingerprint || { length_m: l._len, width_m: 0, height_m: 0 };
    let grp = g.find(x => rel(x.len, fp.length_m) < 0.03
                       && rel(x.w, fp.width_m) < 0.07
                       && rel(x.h, fp.height_m) < 0.07);
    if (!grp) { grp = { laps: [], len: fp.length_m, w: fp.width_m, h: fp.height_m }; g.push(grp); }
    grp.laps.push(l);
  });
  g.sort((a, b) => b.laps.length - a.laps.length);
  g.forEach((grp, i) => {
    grp.id = i;
    grp.label = "Tor " + (i + 1) + " (~" + Math.round(grp.len) + " m, "
              + grp.laps.length + " okr.)";
  });
  return g;
}

const GROUPS = buildGroups();
function groupById(id) { return GROUPS.find(g => g.id === id); }
function lapsForTrack(id) { const g = groupById(id); return g ? g.laps : []; }

let curTrack = null;
const selected = new Set();

function colorFor(idx) {
  const list = [...selected];
  const pos = list.indexOf(idx);
  return COLORS[(pos < 0 ? list.length : pos) % COLORS.length];
}

function initTracks() {
  const sel = document.getElementById("trackSel");
  document.getElementById("sub").textContent =
    LAPS.length + " okrazen, " + GROUPS.length + " torow(y)";
  if (!GROUPS.length) {
    document.getElementById("mainArea").innerHTML =
      '<div class="empty">Brak nagran. Pojezdz w GT7 z wlaczonym nagrywaniem,' +
      ' a tu pojawia sie okrazenia.</div>';
    return;
  }
  sel.innerHTML = "";
  GROUPS.forEach(g => {
    const o = document.createElement("option");
    o.value = g.id; o.textContent = g.label;
    sel.appendChild(o);
  });
  sel.onchange = () => setTrack(parseInt(sel.value, 10));
  setTrack(GROUPS[0].id);
}

function setTrack(id) {
  curTrack = id;
  selected.clear();
  view = { a: 0, b: 1 };
  const laps = lapsForTrack(id);
  if (laps.length) selected.add(laps[0]._idx);
  renderLapList();
  renderMain();
}

function renderLapList() {
  const box = document.getElementById("lapList");
  box.innerHTML = "";
  lapsForTrack(curTrack).forEach(lap => {
    const on = selected.has(lap._idx);
    const el = document.createElement("div");
    el.className = "lap" + (on ? " on" : "");
    const date = (lap.recorded_at||"").replace("T"," ").slice(0,16);
    el.innerHTML =
      '<span class="sw" style="background:' + (on?colorFor(lap._idx):"#555") + '"></span>' +
      '<span class="meta"><span class="t">' + lap.lap_time + '</span>' +
      '<span class="s">okr. ' + lap.lap_number + ' &middot; ' + (lap.car_name || ('auto ' + lap.car_code)) +
      ' &middot; ' + date + '</span></span>';
    el.onclick = () => {
      if (selected.has(lap._idx)) selected.delete(lap._idx);
      else selected.add(lap._idx);
      renderLapList(); renderMain();
    };
    box.appendChild(el);
  });
}

let view = { a: 0, b: 1 };
const CHARTS = [];
const CHART_PAD = { l: 38, r: 8 };

function setView(a, b) {
  a = Math.max(0, Math.min(a, b));
  b = Math.min(1, Math.max(a, b));
  if (b - a < 0.005) return;
  view = { a: a, b: b };
  renderMain();
}
function resetView() { view = { a: 0, b: 1 }; renderMain(); }
function setSector(i) { setView(i / 3, (i + 1) / 3); }
function isFullView() { return view.a === 0 && view.b === 1; }
function isSector(i) {
  return Math.abs(view.a - i / 3) < 1e-6 && Math.abs(view.b - (i + 1) / 3) < 1e-6;
}

function fmtTime(s) {
  if (!isFinite(s)) return "-";
  const m = Math.floor(s / 60), r = s - m * 60;
  const sec = r.toFixed(3);
  return (m > 0 ? m + ":" + (r < 10 ? "0" : "") + sec : sec);
}

function segTime(lap) {
  const S = lap.samples, D = lap._dist, L = lap._len, ti = lap._ch.t;
  let t0 = null, t1 = null;
  for (let j = 0; j < S.length; j++) {
    const f = D[j] / L;
    if (f > view.b) break;
    if (f >= view.a) { if (t0 === null) t0 = S[j][ti]; t1 = S[j][ti]; }
  }
  return (t0 !== null && t1 !== null && t1 > t0) ? t1 - t0 : NaN;
}

let cursorF = null;
let _rafPending = false;

function redrawCharts() {
  CHARTS.forEach(d => d());
  drawMap();
}
function scheduleRedraw() {
  if (_rafPending) return;
  _rafPending = true;
  const raf = (typeof window !== "undefined" && window.requestAnimationFrame)
    ? window.requestAnimationFrame.bind(window) : (cb => cb());
  raf(() => { _rafPending = false; redrawCharts(); });
}
function setCursor(f) { cursorF = f; scheduleRedraw(); }
function clearCursor() { if (cursorF !== null) { cursorF = null; scheduleRedraw(); } }

function locAt(lap, f) {
  const D = lap._dist;
  const target = Math.max(0, Math.min(1, f)) * lap._len;
  let lo = 0, hi = D.length - 1;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (D[mid] < target) lo = mid + 1; else hi = mid; }
  const j = Math.max(1, lo);
  const d0 = D[j - 1], d1 = D[j];
  const t = d1 > d0 ? (target - d0) / (d1 - d0) : 0;
  return { j: j - 1, t: Math.max(0, Math.min(1, t)) };
}
function valueAt(lap, f, getY) {
  const p = locAt(lap, f);
  const j2 = Math.min(p.j + 1, lap.samples.length - 1);
  return getY(lap, p.j) * (1 - p.t) + getY(lap, j2) * p.t;
}
function tAtFrac(lap, f) { return valueAt(lap, f, (l, j) => l.samples[j][l._ch.t]); }
function posAtFrac(lap, f) {
  return {
    x: valueAt(lap, f, (l, j) => l.samples[j][l._ch.x]),
    z: valueAt(lap, f, (l, j) => l.samples[j][l._ch.z]),
  };
}

function fastestSelected() {
  const sel = [...selected].map(i => LAPS[i]);
  return sel.reduce((a, b) => (b.lap_ms < a.lap_ms ? b : a), sel[0]);
}

function selHas(chName) {
  const sel = [...selected].map(i => LAPS[i]);
  return sel.length > 0 && sel.every(l => chName in l._ch);
}

function renderMain() {
  const m = document.getElementById("mainArea");
  if (!selected.size) {
    m.innerHTML = '<div class="empty">Zaznacz okrazenie z listy po lewej.</div>';
    return;
  }
  const vb =
    '<div class="viewbar">' +
      '<button class="vbtn' + (isFullView() ? ' on' : '') +
        '" onclick="resetView()">Cale okrazenie</button>' +
      [0, 1, 2].map(i => '<button class="vbtn' + (isSector(i) ? ' on' : '') +
        '" onclick="setSector(' + i + ')">S' + (i + 1) + '</button>').join("") +
      '<span class="hint">Przeciagnij myszka po wykresie, by przyblizyc fragment toru.</span>' +
      '<span class="seg" id="segInfo"></span>' +
    '</div>';
  m.innerHTML = vb +
    '<div class="card"><h2>Mapa toru (nitka) - kolor = predkosc' +
    (isFullView() ? '' : ', podswietlony wybrany fragment') + '</h2>' +
    '<canvas id="mapC"></canvas><div class="legend" id="mapLeg"></div></div>' +
    '<div class="charts">' +
      (selected.size >= 2
        ? chartCard("Delta do najszybszego z zaznaczonych [s]", "cDelta") : '') +
      chartCard("Predkosc [km/h]", "cSpeed") +
      chartCard("Gaz [%]", "cThrottle") +
      chartCard("Hamulec [%]", "cBrake") +
      chartCard("Bieg", "cGear") +
      chartCard("Obroty [RPM]", "cRPM") +
      chartCard("Kierownica [rad]", "cSteer") +
      (selHas("fuel_pct")
        ? chartCard("Paliwo [%] (diagnostyka spalania)", "cFuel") : '') +
    '</div>';
  drawAllCharts();
  drawMap();
  drawLegend();
  drawSegInfo();
  window.onresize = () => { drawAllCharts(); drawMap(); };
}

function chartCard(title, id) {
  return '<div class="card"><h2>' + title + '</h2><canvas id="' + id + '"></canvas></div>';
}

function setupCanvas(id, cssH) {
  const c = document.getElementById(id);
  const w = c.clientWidth || c.parentElement.clientWidth - 24;
  const dpr = window.devicePixelRatio || 1;
  c.style.height = cssH + "px";
  c.width = w * dpr; c.height = cssH * dpr;
  const ctx = c.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { ctx, w, h: cssH };
}

function speedColor(v, vmin, vmax) {
  const t = vmax > vmin ? (v - vmin) / (vmax - vmin) : 0.5;
  const h = (1 - t) * 220;
  return "hsl(" + h + ",80%,55%)";
}

function drawMap() {
  const { ctx, w, h } = setupCanvas("mapC", 420);
  ctx.clearRect(0, 0, w, h);
  const pad = 24;
  let minX=1e9, maxX=-1e9, minZ=1e9, maxZ=-1e9, vmin=1e9, vmax=-1e9;
  const sel = [...selected].map(i => LAPS[i]);
  const inView = (lap, j) => {
    const f = lap._dist[j] / lap._len;
    return f >= view.a && f <= view.b;
  };
  sel.forEach(lap => {
    const ch = lap._ch;
    lap.samples.forEach((s, j) => {
      minX=Math.min(minX,s[ch.x]); maxX=Math.max(maxX,s[ch.x]);
      minZ=Math.min(minZ,s[ch.z]); maxZ=Math.max(maxZ,s[ch.z]);
      if (inView(lap, j)) {
        vmin=Math.min(vmin,s[ch.speed_kph]); vmax=Math.max(vmax,s[ch.speed_kph]);
      }
    });
  });
  const sx = (w-2*pad)/((maxX-minX)||1), sz=(h-2*pad)/((maxZ-minZ)||1);
  const sc = Math.min(sx, sz);
  const offX = pad + ((w-2*pad) - (maxX-minX)*sc)/2;
  const offZ = pad + ((h-2*pad) - (maxZ-minZ)*sc)/2;
  const px = x => offX + (x-minX)*sc;
  const py = z => h - (offZ + (z-minZ)*sc);
  const single = sel.length === 1;

  if (!isFullView()) {
    sel.forEach(lap => {
      const ch = lap._ch, S = lap.samples;
      ctx.lineWidth = 2; ctx.strokeStyle = "#3a4150";
      ctx.beginPath();
      S.forEach((s, j) => { const X=px(s[ch.x]), Y=py(s[ch.z]);
        j ? ctx.lineTo(X,Y) : ctx.moveTo(X,Y); });
      ctx.stroke();
    });
  }

  sel.forEach(lap => {
    const ch = lap._ch, S = lap.samples;
    if (single) {
      ctx.lineWidth = 3; ctx.lineCap = "round";
      for (let j = 1; j < S.length; j++) {
        if (!inView(lap, j) || !inView(lap, j - 1)) continue;
        ctx.beginPath();
        ctx.moveTo(px(S[j-1][ch.x]), py(S[j-1][ch.z]));
        ctx.lineTo(px(S[j][ch.x]), py(S[j][ch.z]));
        ctx.strokeStyle = speedColor(S[j][ch.speed_kph], vmin, vmax);
        ctx.stroke();
      }
    } else {
      ctx.lineWidth = 2.5; ctx.strokeStyle = colorFor(lap._idx);
      ctx.beginPath();
      let started = false;
      S.forEach((s, j) => {
        if (!inView(lap, j)) { started = false; return; }
        const X=px(s[ch.x]), Y=py(s[ch.z]);
        started ? ctx.lineTo(X,Y) : ctx.moveTo(X,Y);
        started = true;
      });
      ctx.stroke();
    }
  });

  if (cursorF !== null && cursorF >= view.a && cursorF <= view.b) {
    sel.forEach(lap => {
      const p = posAtFrac(lap, cursorF);
      ctx.beginPath();
      ctx.arc(px(p.x), py(p.z), 5, 0, 2 * Math.PI);
      ctx.fillStyle = single ? "#ffffff" : colorFor(lap._idx);
      ctx.fill();
      ctx.strokeStyle = "#14171c"; ctx.lineWidth = 2; ctx.stroke();
    });
  }
}

function drawSegInfo() {
  const el = document.getElementById("segInfo");
  if (!el) return;
  const sel = [...selected].map(i => LAPS[i]);
  if (isFullView()) {
    el.innerHTML = "";
    return;
  }
  el.innerHTML = "Czas fragmentu: " + sel.map(l =>
    '<span><i style="background:' + colorFor(l._idx) + '"></i>' +
    fmtTime(segTime(l)) + '</span>').join("");
}

function drawLegend() {
  const leg = document.getElementById("mapLeg");
  const sel = [...selected].map(i => LAPS[i]);
  if (sel.length === 1) {
    leg.innerHTML =
      '<span><i style="background:hsl(220,80%,55%)"></i>wolno</span>' +
      '<span><i style="background:hsl(110,80%,55%)"></i>srednio</span>' +
      '<span><i style="background:hsl(0,80%,55%)"></i>szybko</span>';
  } else {
    leg.innerHTML = sel.map(l =>
      '<span><i style="background:' + colorFor(l._idx) + '"></i>' +
      l.lap_time + '</span>').join("");
  }
}

function lineChart(id, getY, yMin, yMax, opts) {
  opts = opts || {};
  const { ctx, w, h } = setupCanvas(id, opts.height || 150);
  ctx.clearRect(0, 0, w, h);
  const pad = { l: CHART_PAD.l, r: CHART_PAD.r, t: 8, b: 16 };
  const W = w - pad.l - pad.r, H = h - pad.t - pad.b;
  const span = (view.b - view.a) || 1;
  const X = f => pad.l + ((f - view.a) / span) * W;
  const Y = v => pad.t + (1 - (v - yMin) / ((yMax - yMin) || 1)) * H;
  ctx.strokeStyle = "#2a2f3a"; ctx.lineWidth = 1; ctx.fillStyle = "#6b7280";
  ctx.font = "10px system-ui";
  const ticks = opts.ticks || [yMin, (yMin+yMax)/2, yMax];
  ticks.forEach(t => {
    const y = Y(t);
    ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(w-pad.r, y); ctx.stroke();
    ctx.fillText(opts.fmt ? opts.fmt(t) : t.toFixed(1), 4, y+3);
  });
  if (opts.zero && yMin < 0 && yMax > 0) {
    ctx.strokeStyle = "#3a4150"; ctx.beginPath();
    ctx.moveTo(pad.l, Y(0)); ctx.lineTo(w-pad.r, Y(0)); ctx.stroke();
  }
  ctx.save();
  ctx.beginPath(); ctx.rect(pad.l, 0, W, h); ctx.clip();
  const selLaps = [...selected].map(i => LAPS[i]);
  selLaps.forEach(lap => {
    const S = lap.samples, D = lap._dist, L = lap._len;
    ctx.lineWidth = 1.8; ctx.strokeStyle = opts.color ? opts.color(lap) : colorFor(lap._idx);
    ctx.beginPath();
    for (let j = 0; j < S.length; j++) {
      const x = X(D[j] / L), y = Y(getY(lap, j));
      j ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    }
    ctx.stroke();
  });
  ctx.restore();

  if (cursorF !== null && cursorF >= view.a && cursorF <= view.b && selLaps.length) {
    const cx = X(cursorF);
    ctx.strokeStyle = "#9aa3b2"; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(cx, 0); ctx.lineTo(cx, h - pad.b); ctx.stroke();
    ctx.font = "10px system-ui";
    const meters = Math.round(cursorF * selLaps[0]._len);
    ctx.fillStyle = "#c7cdd9";
    ctx.fillText(meters + " m", Math.min(cx + 4, w - 52), h - 4);
    const fmtV = opts.cursorFmt || (v => (opts.fmt ? opts.fmt(v) : v.toFixed(1)));
    selLaps.forEach((lap, k) => {
      const v = valueAt(lap, cursorF, getY);
      const col = colorFor(lap._idx);
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.arc(cx, Y(v), 3.5, 0, 2 * Math.PI); ctx.fill();
      const label = fmtV(v);
      const tw = ctx.measureText(label).width;
      const bx = Math.min(cx + 8, w - tw - 26), by = pad.t + 4 + k * 18;
      ctx.fillStyle = "rgba(17, 20, 26, 0.92)";
      ctx.fillRect(bx, by, tw + 20, 15);
      ctx.strokeStyle = "#2a2f3a";
      ctx.strokeRect(bx + 0.5, by + 0.5, tw + 19, 14);
      ctx.fillStyle = col; ctx.fillRect(bx + 4, by + 4, 7, 7);
      ctx.fillStyle = "#e6e9ef"; ctx.fillText(label, bx + 15, by + 11);
    });
  }
}

function attachSelect(c, redraw) {
  let x0 = null;
  c.style.cursor = "crosshair";
  const pxToFrac = x => {
    const W = c.clientWidth - CHART_PAD.l - CHART_PAD.r;
    const t = Math.max(0, Math.min(1, (x - CHART_PAD.l) / (W || 1)));
    return view.a + t * (view.b - view.a);
  };
  c.onmousedown = e => { x0 = e.offsetX; cursorF = null; e.preventDefault(); };
  c.onmousemove = e => {
    if (x0 === null) {
      setCursor(pxToFrac(e.offsetX));
      return;
    }
    redraw();
    const ctx = c.getContext("2d");
    const a = Math.min(x0, e.offsetX), wsel = Math.abs(e.offsetX - x0);
    ctx.fillStyle = "rgba(255, 92, 92, 0.16)";
    ctx.fillRect(a, 0, wsel, c.clientHeight);
    ctx.strokeStyle = "rgba(255, 92, 92, 0.6)";
    ctx.strokeRect(a + 0.5, 0.5, wsel - 1, c.clientHeight - 1);
  };
  c.onmouseup = e => {
    if (x0 === null) return;
    const x1 = e.offsetX;
    if (Math.abs(x1 - x0) > 8) {
      setView(pxToFrac(Math.min(x0, x1)), pxToFrac(Math.max(x0, x1)));
    } else {
      redraw();
    }
    x0 = null;
  };
  c.onmouseleave = () => { if (x0 !== null) { redraw(); x0 = null; } clearCursor(); };
}

function addChart(id, getY, yMin, yMax, opts) {
  const draw = () => lineChart(id, getY, yMin, yMax, opts);
  draw();
  attachSelect(document.getElementById(id), draw);
  CHARTS.push(draw);
}

function drawAllCharts() {
  CHARTS.length = 0;
  const sel = [...selected].map(i => LAPS[i]);
  let vmax = 0, gmax = 1, rmax = 1000, smax = 0.2;
  sel.forEach(l => l.samples.forEach(s => {
    vmax = Math.max(vmax, s[l._ch.speed_kph]);
    gmax = Math.max(gmax, s[l._ch.gear]);
    rmax = Math.max(rmax, s[l._ch.rpm]);
    smax = Math.max(smax, Math.abs(s[l._ch.steering]));
  }));
  vmax = Math.ceil((vmax + 10) / 20) * 20;
  rmax = Math.ceil(rmax / 1000) * 1000;
  smax = Math.ceil(smax * 10) / 10;
  const gearTicks = [];
  for (let g = 0; g <= gmax; g += (gmax > 6 ? 2 : 1)) gearTicks.push(g);

  if (sel.length >= 2) {
    const ref = fastestSelected();
    let dmax = 0.5;
    sel.forEach(l => {
      const ti = l._ch.t;
      l._delta = l.samples.map((s, j) =>
        l === ref ? 0 : s[ti] - tAtFrac(ref, l._dist[j] / l._len));
      l._delta.forEach(v => { if (isFinite(v)) dmax = Math.max(dmax, Math.abs(v)); });
    });
    dmax = Math.ceil(dmax * 2) / 2;
    addChart("cDelta", (l, j) => l._delta[j], -dmax, dmax,
      { height: 130, zero: true, ticks: [-dmax, 0, dmax], fmt: v => v.toFixed(1),
        cursorFmt: v => (v >= 0 ? "+" : "") + v.toFixed(2) + " s" });
  }

  addChart("cSpeed", (l, j) => l.samples[j][l._ch.speed_kph], 0, vmax,
    { height: 150, fmt: v => v.toFixed(0),
      cursorFmt: v => v.toFixed(1) + " km/h" });
  addChart("cThrottle", (l, j) => l.samples[j][l._ch.throttle] * 100, 0, 100,
    { height: 120, ticks: [0, 50, 100], fmt: v => v.toFixed(0),
      cursorFmt: v => v.toFixed(0) + " %" });
  addChart("cBrake", (l, j) => l.samples[j][l._ch.brake] * 100, 0, 100,
    { height: 120, ticks: [0, 50, 100], fmt: v => v.toFixed(0),
      cursorFmt: v => v.toFixed(0) + " %" });
  addChart("cGear", (l, j) => l.samples[j][l._ch.gear], 0, gmax,
    { height: 110, ticks: gearTicks, fmt: v => v.toFixed(0),
      cursorFmt: v => v.toFixed(0) });
  addChart("cRPM", (l, j) => l.samples[j][l._ch.rpm], 0, rmax,
    { height: 120, fmt: v => v.toFixed(0),
      cursorFmt: v => Math.round(v) + " rpm" });
  addChart("cSteer", (l, j) => l.samples[j][l._ch.steering], -smax, smax,
    { height: 130, zero: true, ticks: [-smax, 0, smax], fmt: v => v.toFixed(1),
      cursorFmt: v => {
        const deg = Math.abs(v) * 180 / Math.PI;
        return (v < 0 ? "L " : v > 0 ? "P " : "") + deg.toFixed(0) + "°";
      } });

  if (selHas("fuel_pct")) {
    let fmin = 100, fmax = 0;
    sel.forEach(l => l.samples.forEach(s => {
      const v = s[l._ch.fuel_pct];
      fmin = Math.min(fmin, v); fmax = Math.max(fmax, v);
    }));
    fmin = Math.max(0, Math.floor(fmin - 1));
    fmax = Math.min(100, Math.ceil(fmax + 1));
    if (fmax - fmin < 2) fmax = Math.min(100, fmin + 2);
    addChart("cFuel", (l, j) => l.samples[j][l._ch.fuel_pct], fmin, fmax,
      { height: 120, fmt: v => v.toFixed(1),
        cursorFmt: v => v.toFixed(2) + " %" });
  }
}

initTracks();
</script>
</body>
</html>
''';
