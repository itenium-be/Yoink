// Theme data mirrors settings.json (themes.*). Keep gradients/rim/card in sync with the tool
// so the marketing page is a faithful live preview of each notification skin.
const THEMES = {
  unicorn:   { name: 'Unicorn',   hero: '🦄', card: '#18181B', scene: 'sparkles',
    gradient: ['#FF5F6D','#FFC371','#3CFFB0','#36D1DC','#A56BFF'],
    rim: ['#7C3AED','#2563EB','#06B6D4','#22C55E','#EAB308','#F97316','#EC4899'],
    blurb: 'rainbow arc, drifting clouds, sparkles' },
  cosmic:    { name: 'Cosmic',    hero: '🚀', card: '#0B0B1A', scene: 'stars',
    gradient: ['#3A1C71','#5B2A86','#7B2FF7','#2C7DFA','#22D3EE'],
    rim: ['#1E1B4B','#4338CA','#7C3AED','#2563EB','#06B6D4'],
    blurb: 'starfield, nebula, the odd comet' },
  ocean:     { name: 'Ocean',     hero: '🐳', card: '#0A1620', scene: 'bubbles',
    gradient: ['#0EA5E9','#22D3EE','#2DD4BF','#14B8A6','#0891B2'],
    rim: ['#0C4A6E','#0369A1','#0891B2','#06B6D4','#14B8A6'],
    blurb: 'rolling waves under a low sun' },
  sakura:    { name: 'Sakura',    hero: '🌸', card: '#1A1620', scene: 'petals',
    gradient: ['#FF8FB1','#FFB7C5','#FBC2EB','#E0AAFF','#C8A2FF'],
    rim: ['#DB2777','#EC4899','#F472B6','#E879F9','#C084FC'],
    blurb: 'falling blossom petals, parallax branch' },
  matrix:    { name: 'Matrix',    hero: '🐇', card: '#050A05', scene: 'matrix',
    gradient: ['#00FF41','#22C55E','#16A34A','#00C853','#39FF14'],
    rim: ['#052E16','#14532D','#16A34A','#22C55E','#4ADE80'],
    blurb: 'katakana digital rain' },
  dragon:    { name: 'Dragon',    hero: '🐉', card: '#1A0F0A', scene: 'embers',
    gradient: ['#7F1D1D','#DC2626','#F97316','#FBBF24','#FDE047'],
    rim: ['#450A0A','#991B1B','#DC2626','#EA580C','#F59E0B'],
    blurb: 'rising embers over molten lava' },
  vaporwave: { name: 'Vaporwave', hero: '🌴', card: '#160F1F', scene: 'grid',
    gradient: ['#FF6AD5','#C774E8','#AD8CFF','#8795E8','#94D0FF'],
    rim: ['#FF71CE','#B967FF','#01CDFE','#05FFA1','#FFFB96'],
    blurb: 'neon perspective grid, scanlines' },
  robot:     { name: 'Robot',     hero: '🤖', card: '#0E141B', scene: 'circuit',
    gradient: ['#94A3B8','#64748B','#38BDF8','#0EA5E9','#22D3EE'],
    rim: ['#1E293B','#334155','#475569','#0EA5E9','#38BDF8'],
    blurb: 'circuit traces, blinking LEDs' },
  spooky:    { name: 'Spooky',    hero: '🎃', card: '#100A14', scene: 'ghosts',
    gradient: ['#F97316','#EA580C','#7C2D12','#6B21A8','#4C1D95'],
    rim: ['#7C2D12','#9A3412','#EA580C','#6B21A8','#4C1D95'],
    blurb: 'gravestones, drifting ghosts, lightning' },
};

const EVENTS = {
  'done':        { label: 'Done!',     accent: '#22C55E', headline: 'All tests green — pushed to main.', mascot: 'confetti' },
  'needs-input': { label: 'Needs you', accent: '#FF7A18', headline: 'Approve the migration before I continue?', mascot: 'flag' },
};

let activeTheme = 'unicorn';
let activeEvent = 'done';
let scene = null;

function applyTheme(key) {
  const t = THEMES[key];
  if (!t) return;
  activeTheme = key;
  const root = document.documentElement.style;
  // page gradient (vertical wash) + animated rim (conic) built from the theme stops
  root.setProperty('--grad', t.gradient.join(', '));
  root.setProperty('--grad-a', t.gradient[0]);
  root.setProperty('--grad-b', t.gradient[t.gradient.length - 1]);
  root.setProperty('--rim', [...t.rim, t.rim[0]].join(', '));
  root.setProperty('--card', t.card);
  root.setProperty('--accent', t.gradient[2]);

  document.querySelectorAll('.theme-pill').forEach(p =>
    p.setAttribute('aria-pressed', String(p.dataset.theme === key)));
  // notif card replaced by a per-theme video demo; swap the source to match the pill.
  // filenames mostly mirror the theme key — 'vaporwave' is the lone exception (yoink-vaporware.mp4).
  const file = key === 'vaporwave' ? 'vaporware' : key;
  const video = document.getElementById('heroVideo');
  if (video) {
    video.src = `assets/yoink-${file}.mp4`;
    video.load();
  }
  const box = document.getElementById('boxImg');
  if (box) box.src = `assets/boxes/${file}.png`;

  startScene(t);
}

function applyEvent(key) {
  activeEvent = key;
  const e = EVENTS[key];
  document.documentElement.style.setProperty('--event-accent', e.accent);
  const labelEl = document.getElementById('cardLabel');
  if (labelEl) labelEl.textContent = e.label;
  const headlineEl = document.getElementById('cardHeadline');
  if (headlineEl) headlineEl.textContent = e.headline;
  const mascotEl = document.getElementById('cardMascotLabel');
  if (mascotEl) mascotEl.textContent = e.mascot;
  document.querySelectorAll('.event-tab').forEach(b =>
    b.setAttribute('aria-pressed', String(b.dataset.event === key)));
}

// ---- Canvas scene engine: one particle loop, per-theme behaviour --------------------
function startScene(theme) {
  const canvas = document.getElementById('scene');
  if (scene) scene.stop();
  scene = makeScene(canvas, theme);
  scene.start();
}

function makeScene(canvas, theme) {
  const ctx = canvas.getContext('2d');
  let w, h, raf, parts = [], drops = [], t0 = 0, running = false;
  const mode = theme.scene;
  const col = (i) => theme.gradient[i % theme.gradient.length];

  function resize() {
    w = canvas.width = canvas.offsetWidth * devicePixelRatio;
    h = canvas.height = canvas.offsetHeight * devicePixelRatio;
    seed();
  }
  function rnd(a, b) { return a + (b - a) * pseudo(); }
  // deterministic-ish noise without Math.random dependence on first paint
  let s = 1234567;
  function pseudo() { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; }

  function seed() {
    parts = []; drops = [];
    const n = Math.round((w * h) / 26000);
    if (mode === 'matrix') {
      const cols = Math.floor(w / (16 * devicePixelRatio));
      for (let i = 0; i < cols; i++) drops[i] = rnd(0, h);
    } else {
      for (let i = 0; i < n; i++) parts.push(spawn(i, true));
    }
  }
  function spawn(i, init) {
    const base = { x: rnd(0, w), y: rnd(0, h), r: rnd(1, 3.4) * devicePixelRatio,
                   sp: rnd(0.2, 1) * devicePixelRatio, ph: rnd(0, 6.28), c: col(i) };
    if (mode === 'embers' || mode === 'bubbles' || mode === 'sparkles') base.y = init ? rnd(0, h) : h + 10;
    if (mode === 'petals') base.y = init ? rnd(0, h) : -10;
    return base;
  }

  function draw(ts) {
    if (!running) return;
    if (!t0) t0 = ts;
    const time = (ts - t0) / 1000;
    ctx.clearRect(0, 0, w, h);

    if (mode === 'matrix') {
      ctx.font = `${16 * devicePixelRatio}px monospace`;
      for (let i = 0; i < drops.length; i++) {
        const x = i * 16 * devicePixelRatio;
        ctx.fillStyle = i % 7 === 0 ? '#CFFFE0' : col(i);
        ctx.fillText(String.fromCharCode(0x30A0 + Math.floor(pseudo() * 96)), x, drops[i]);
        drops[i] += 6 * devicePixelRatio;
        if (drops[i] > h && pseudo() > 0.975) drops[i] = 0;
      }
      raf = requestAnimationFrame(draw); return;
    }

    if (mode === 'grid') { drawGrid(time); raf = requestAnimationFrame(draw); return; }

    for (const p of parts) {
      ctx.beginPath();
      const tw = 0.55 + 0.45 * Math.sin(time * 2 + p.ph);
      ctx.globalAlpha = (mode === 'sparkles' || mode === 'ghosts') ? tw : 0.8;
      ctx.fillStyle = p.c;
      if (mode === 'petals') {
        ctx.ellipse(p.x + Math.sin(time + p.ph) * 18, p.y, p.r * 2.2, p.r, time + p.ph, 0, 6.28);
        p.y += p.sp; p.x += Math.sin(time * 0.8 + p.ph) * 0.4;
        if (p.y > h + 10) { p.y = -10; p.x = rnd(0, w); }
      } else if (mode === 'embers' || mode === 'bubbles') {
        ctx.arc(p.x + Math.sin(time + p.ph) * 8, p.y, p.r, 0, 6.28);
        p.y -= p.sp; if (p.y < -10) { p.y = h + 10; p.x = rnd(0, w); }
      } else { // stars, sparkles, circuit, ghosts
        ctx.arc(p.x, p.y, p.r, 0, 6.28);
      }
      ctx.fill();
    }
    ctx.globalAlpha = 1;
    raf = requestAnimationFrame(draw);
  }

  function drawGrid(time) {
    const cx = w / 2, horizon = h * 0.46;
    // classic synthwave neon (Kung Fury): hot magenta + cyan, glowing
    const neonA = '#FF2A6D', neonB = '#05D9E8';
    ctx.save();
    ctx.lineWidth = 1.6 * devicePixelRatio;
    ctx.shadowBlur = 12 * devicePixelRatio;

    ctx.strokeStyle = neonB; ctx.shadowColor = neonB; ctx.globalAlpha = 0.7;
    for (let i = -10; i <= 10; i++) {
      ctx.beginPath(); ctx.moveTo(cx + i * 26 * devicePixelRatio, horizon);
      ctx.lineTo(cx + i * 240 * devicePixelRatio, h); ctx.stroke();
    }
    // fractional phase folded into the perspective curve: each line advances one slot
    // per cycle, so when `off` wraps 1→0 the set is identical — no synchronized snap.
    const N = 22, off = (time * 1.6) % 1;
    ctx.strokeStyle = neonA; ctx.shadowColor = neonA;
    for (let i = 0; i <= N; i++) {
      const d = (i + off) / N;
      if (d > 1) continue;
      const yy = horizon + d * d * (h - horizon);
      ctx.globalAlpha = 0.25 + 0.6 * d;   // fade in from the horizon for depth
      ctx.beginPath(); ctx.moveTo(0, yy); ctx.lineTo(w, yy); ctx.stroke();
    }
    ctx.restore();
    ctx.globalAlpha = 1;
  }

  return {
    start() { running = true; resize(); window.addEventListener('resize', resize); raf = requestAnimationFrame(draw); },
    stop() { running = false; cancelAnimationFrame(raf); window.removeEventListener('resize', resize); },
  };
}

// ---- wiring -------------------------------------------------------------------------
function buildPills() {
  const row = document.getElementById('themeRow');
  for (const [key, t] of Object.entries(THEMES)) {
    const b = document.createElement('button');
    b.className = 'theme-pill'; b.dataset.theme = key; b.type = 'button';
    b.setAttribute('aria-pressed', 'false');
    b.innerHTML = `<span class="pill-emoji">${t.hero}</span><span>${t.name}</span>`;
    b.addEventListener('click', () => applyTheme(key));
    row.appendChild(b);
  }
}

function initCopy() {
  document.querySelectorAll('[data-copy]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const code = document.getElementById(btn.dataset.copy).innerText;
      try { await navigator.clipboard.writeText(code); btn.textContent = 'Copied ✓';
        setTimeout(() => (btn.textContent = 'Copy'), 1400); } catch { btn.textContent = 'Copy failed'; }
    });
  });
}

function initInstallTabs() {
  const section = document.getElementById('install');
  const tabs = section.querySelectorAll('.method-tab');
  const select = (method) => {
    section.dataset.method = method;
    tabs.forEach(t => t.setAttribute('aria-selected', String(t.dataset.method === method)));
  };
  tabs.forEach(t => t.addEventListener('click', () => select(t.dataset.method)));
  select(section.dataset.method);
}

document.addEventListener('DOMContentLoaded', () => {
  buildPills();
  initCopy();
  initInstallTabs();
  applyEvent('done');
  applyTheme('unicorn');
});
