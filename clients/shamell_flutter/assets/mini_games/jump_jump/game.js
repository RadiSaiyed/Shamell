(() => {
  'use strict';

  // ════════════════════════════ DOM ════════════════════════════
  const $ = id => document.getElementById(id);
  const canvas      = $('game');
  const ctx         = canvas.getContext('2d');
  const els = {
    score:       $('score'),
    combo:       $('combo'),
    startOver:   $('startOverlay'),
    endOver:     $('endOverlay'),
    playBtn:     $('playBtn'),
    restartBtn:  $('restartBtn'),
    shareBtn:    $('shareBtn'),
    endScore:    $('endScore'),
    endBest:     $('endBest'),
    startBest:   $('startBest'),
    chargeBar:   $('chargeBar'),
    chargeFill:  $('chargeFill'),
    muteBtn:     $('muteBtn'),
  };

  // ════════════════════════ Konstanten ═════════════════════════
  const COS30   = Math.cos(Math.PI / 6);
  const SIN30   = Math.sin(Math.PI / 6);
  const ISO_RX  = COS30 * Math.SQRT2;          // ≈ 1.225  (horiz. Radius eines XZ-Kreises)
  const ISO_RY  = SIN30 * Math.SQRT2;          // ≈ 0.707  (vert. Radius)

  const GRAVITY        = 1500;
  const MAX_CHARGE_S   = 1.4;
  const MIN_VH         = 80;
  const MAX_VH         = 380;
  const MIN_VY         = 420;
  const MAX_VY         = 620;
  const CENTER_TOL     = 5.5;
  const SPAWN_MIN_GAP  = 60;
  const SPAWN_MAX_GAP  = 130;

  // Block-Paletten (top, links-Seite, rechts-Seite, Akzent)
  const PALETTES = [
    { top: '#ffd9d2', l: '#ffb6ad', r: '#ec8a82', a: '#d96b62' },
    { top: '#d8e6ff', l: '#aec4f5', r: '#7e9be4', a: '#5d7fc9' },
    { top: '#fff0cf', l: '#f5d999', r: '#dcb45f', a: '#bd9540' },
    { top: '#d6f3df', l: '#a8dbb8', r: '#73b88a', a: '#599a6f' },
    { top: '#ecd9ff', l: '#c8a8eb', r: '#9776c5', a: '#7a5cab' },
    { top: '#ffe2cc', l: '#f0bf99', r: '#d3935f', a: '#b27545' },
    { top: '#cdeeec', l: '#9ed4d2', r: '#6aaeac', a: '#4f9290' },
  ];
  const SPECIAL_PALETTE = { top: '#ffe27a', l: '#f4b400', r: '#c98a00', a: '#8c6000' };

  // Tageszeit-Themen, Score-getrieben (lerp dazwischen)
  const THEMES = [
    { stop: 0,   skyTop: '#fef5ee', skyMid: '#f5e9d9', skyBot: '#e9d8c2', glow: [255, 200, 170, 0.30] },
    { stop: 18,  skyTop: '#e8f1ff', skyMid: '#cfdef5', skyBot: '#a8c5e5', glow: [255, 240, 210, 0.28] },
    { stop: 40,  skyTop: '#ffd9b5', skyMid: '#f0a5b8', skyBot: '#9b85c6', glow: [255, 200, 220, 0.36] },
    { stop: 75,  skyTop: '#3a345c', skyMid: '#251f44', skyBot: '#0d0a1f', glow: [120, 130, 200, 0.42] },
  ];

  // ════════════════════════════ SFX ════════════════════════════
  const SFX = (() => {
    let actx, enabled = localStorage.getItem('jumpjump.sound') === 'on';
    function ensure() {
      if (!actx && enabled) {
        try { actx = new (window.AudioContext || window.webkitAudioContext)(); }
        catch { /* ignore */ }
      }
      if (actx?.state === 'suspended') actx.resume();
    }
    function tone(f, dur, type = 'sine', vol = 0.12, attack = 0.005) {
      if (!enabled) return;
      ensure();
      if (!actx) return;
      const t = actx.currentTime;
      const o = actx.createOscillator();
      const g = actx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(f, t);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vol, t + attack);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g).connect(actx.destination);
      o.start(t); o.stop(t + dur + 0.05);
    }
    function sweep(f1, f2, dur, type = 'sine', vol = 0.12) {
      if (!enabled) return;
      ensure();
      if (!actx) return;
      const t = actx.currentTime;
      const o = actx.createOscillator();
      const g = actx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(f1, t);
      o.frequency.exponentialRampToValueAtTime(f2, t + dur);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(vol, t + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g).connect(actx.destination);
      o.start(t); o.stop(t + dur + 0.05);
    }
    return {
      get enabled() { return enabled; },
      toggle() {
        enabled = !enabled;
        localStorage.setItem('jumpjump.sound', enabled ? 'on' : 'off');
        if (enabled) ensure();
        return enabled;
      },
      charge() { sweep(220, 540, 0.5, 'sine', 0.06); },
      jump()   { tone(420, 0.10, 'triangle', 0.12); },
      land()   { tone(140, 0.08, 'square', 0.08); tone(70, 0.12, 'square', 0.06); },
      perfect(){ tone(880, 0.13, 'sine', 0.13); setTimeout(() => tone(1320, 0.18, 'sine', 0.10), 70); },
      bonus()  { tone(660, 0.10, 'sine', 0.10); setTimeout(() => tone(990, 0.14, 'sine', 0.10), 80); },
      over()   { sweep(440, 80, 0.55, 'sawtooth', 0.10); },
    };
  })();

  // ═════════════════════════════ State ═════════════════════════
  let dpr = 1, W = 0, H = 0;
  let last = 0, running = false;
  let best = +localStorage.getItem('jumpjump.best') || 0;
  els.startBest.textContent = best;
  let game = null;

  // Initial Mute-Button-State
  if (SFX.enabled) els.muteBtn.classList.remove('muted');
  else             els.muteBtn.classList.add('muted');

  // ═════════════════════════ Setup ═════════════════════════════
  function newGame() {
    game = {
      blocks: [],
      player: {
        x: 0, y: 0, z: 0,
        vx: 0, vy: 0, vz: 0,
        squash: 0,
        stretch: 0,
        state: 'idle',          // idle | charging | jumping | dead
        chargeStart: 0,
        charge: 0,
        dir: 'x',
        idle: 0,
      },
      camera: { x: 0, z: 0, tx: 0, tz: 0 },
      score: 0,
      combo: 0,
      shake: 0,
      flash: 0,
      blockWobble: 0,
      blockWobbleId: -1,
      slowmo: 0,
      tick: 0,
      particles: [],
      trail: [],
      rings: [],
      popups: [],
      dust: makeDust(20),
    };

    const first = makeBlock(0, 0, { shape: 'cube', size: 40, paletteIdx: 0 });
    game.blocks.push(first);
    spawnNext();

    const p = game.player;
    p.x = first.x; p.z = first.z; p.y = first.h;

    centerCamera(true);
    updateScore(false);
  }

  function makeBlock(x, z, opts = {}) {
    const size = opts.size ?? (28 + Math.random() * 18);
    const shape = opts.shape ?? (Math.random() < 0.65 ? 'cube' : 'cylinder');
    const palette = opts.paletteIdx != null
      ? PALETTES[opts.paletteIdx]
      : PALETTES[Math.floor(Math.random() * PALETTES.length)];
    return {
      x, z,
      w: size, d: size,
      h: size * (shape === 'cylinder' ? 0.62 : 0.55),
      shape,
      palette,
      special: false,
      spawnT: opts.spawnT ?? 1,
      bob: 0,
    };
  }

  function spawnNext() {
    const cur = game.blocks[game.blocks.length - 1];
    const dir = Math.random() < 0.5 ? 'x' : 'z';
    const gap = SPAWN_MIN_GAP + Math.random() * (SPAWN_MAX_GAP - SPAWN_MIN_GAP);
    const size = 26 + Math.random() * 18;
    let nx = cur.x, nz = cur.z;
    const dist = gap + (cur.w + size) / 2;
    if (dir === 'x') nx += dist; else nz += dist;

    const next = makeBlock(nx, nz, { size });
    next.spawnT = 0;

    if (game.score >= 8 && Math.random() < 0.15) {
      next.shape = 'cylinder';
      next.w = next.d = 22;
      next.h = 16;
      next.special = true;
      next.palette = SPECIAL_PALETTE;
    }

    game.blocks.push(next);
    while (game.blocks.length > 5) game.blocks.shift();
  }

  function centerCamera(immediate = false) {
    const a = game.blocks[game.blocks.length - 2] ?? game.blocks[0];
    const b = game.blocks[game.blocks.length - 1];
    game.camera.tx = (a.x + b.x) / 2;
    game.camera.tz = (a.z + b.z) / 2;
    if (immediate) { game.camera.x = game.camera.tx; game.camera.z = game.camera.tz; }
  }

  function makeDust(n) {
    const d = [];
    for (let i = 0; i < n; i++) {
      d.push({
        sx: Math.random() * 1, sy: Math.random() * 1, // normalisiert (0-1)
        vx: (Math.random() - 0.5) * 0.012,
        vy: -0.005 - Math.random() * 0.012,
        r: 1 + Math.random() * 2,
        a: 0.08 + Math.random() * 0.18,
      });
    }
    return d;
  }

  // ═══════════════════════ Projektion ══════════════════════════
  function project(wx, wy, wz) {
    const cx = wx - game.camera.x;
    const cz = wz - game.camera.z;
    return {
      x: W * 0.5 + (cx - cz) * COS30,
      y: H * 0.62 - ((cx + cz) * SIN30 + wy)
    };
  }

  // ═══════════════════════════ Resize ══════════════════════════
  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    const r = canvas.getBoundingClientRect();
    W = r.width || 360;
    H = r.height || 600;
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener('resize', resize);

  // ═════════════════════ Theme-Interpolation ═══════════════════
  function lerp(a, b, t) { return a + (b - a) * t; }
  function lerpColor(c1, c2, t) {
    const r1 = parseInt(c1.slice(1, 3), 16), g1 = parseInt(c1.slice(3, 5), 16), b1 = parseInt(c1.slice(5, 7), 16);
    const r2 = parseInt(c2.slice(1, 3), 16), g2 = parseInt(c2.slice(3, 5), 16), b2 = parseInt(c2.slice(5, 7), 16);
    const r = Math.round(lerp(r1, r2, t)), g = Math.round(lerp(g1, g2, t)), b = Math.round(lerp(b1, b2, t));
    return `rgb(${r},${g},${b})`;
  }
  function currentTheme(score) {
    let from = THEMES[0], to = THEMES[1], t = 0;
    for (let i = 0; i < THEMES.length - 1; i++) {
      if (score >= THEMES[i].stop && score < THEMES[i + 1].stop) {
        from = THEMES[i]; to = THEMES[i + 1];
        const span = THEMES[i + 1].stop - THEMES[i].stop;
        t = (score - THEMES[i].stop) / span;
        break;
      }
      if (score >= THEMES[THEMES.length - 1].stop) {
        from = to = THEMES[THEMES.length - 1]; t = 0; break;
      }
    }
    const easeT = t * t * (3 - 2 * t);
    return {
      skyTop: lerpColor(from.skyTop, to.skyTop, easeT),
      skyMid: lerpColor(from.skyMid, to.skyMid, easeT),
      skyBot: lerpColor(from.skyBot, to.skyBot, easeT),
      glow: from.glow.map((v, i) => lerp(v, to.glow[i], easeT)),
    };
  }

  // ════════════════════════ Rendering ══════════════════════════
  function drawBg() {
    const th = currentTheme(game.score);
    const g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, th.skyTop);
    g.addColorStop(0.55, th.skyMid);
    g.addColorStop(1, th.skyBot);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);

    // Boden-Glow (radial)
    const gG = ctx.createRadialGradient(W * 0.5, H * 0.72, 30, W * 0.5, H * 0.72, W * 0.95);
    const [r, gC, b, a] = th.glow;
    gG.addColorStop(0, `rgba(${r|0},${gC|0},${b|0},${a})`);
    gG.addColorStop(1, `rgba(${r|0},${gC|0},${b|0},0)`);
    ctx.fillStyle = gG;
    ctx.fillRect(0, 0, W, H);

    // Sterne in der Nacht
    if (game.score >= 60) {
      const nightT = Math.min(1, (game.score - 60) / 25);
      ctx.globalAlpha = nightT * 0.7;
      ctx.fillStyle = '#fff';
      const seed = 47;
      for (let i = 0; i < 35; i++) {
        const sx = ((i * 9301 + seed * 49297) % 233280) / 233280 * W;
        const sy = ((i * 51749 + seed * 71993) % 233280) / 233280 * H * 0.55;
        const tw = 0.7 + 0.3 * Math.sin(game.tick * 2 + i);
        ctx.beginPath();
        ctx.arc(sx, sy, 0.7 + (i % 3) * 0.4, 0, Math.PI * 2);
        ctx.globalAlpha = nightT * 0.8 * tw;
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }

    // Staub-Partikel
    ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
    for (const d of game.dust) {
      ctx.globalAlpha = d.a;
      ctx.beginPath();
      ctx.arc(d.sx * W, d.sy * H, d.r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function fillPath(pts) {
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
    ctx.closePath();
    ctx.fill();
  }
  function strokePath(pts) {
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
    ctx.closePath();
    ctx.stroke();
  }

  function drawAOShadow(b, alpha) {
    // weicher Boden-Schatten
    const margin = 4;
    const sh = [
      project(b.x - b.w / 2 - margin, 0, b.z - b.d / 2 - margin),
      project(b.x + b.w / 2 + margin, 0, b.z - b.d / 2 - margin),
      project(b.x + b.w / 2 + margin, 0, b.z + b.d / 2 + margin),
      project(b.x - b.w / 2 - margin, 0, b.z + b.d / 2 + margin),
    ];
    ctx.fillStyle = `rgba(40, 30, 25, ${0.10 * alpha})`;
    fillPath(sh);
  }

  function drawCube(b, isCurrent) {
    const wob = (isCurrent && game.blockWobble > 0)
      ? Math.sin(game.tick * 30) * game.blockWobble * 0.6 : 0;
    const sOff = (1 - b.spawnT) * 80;
    const a = b.spawnT;

    const x0 = b.x - b.w / 2, x1 = b.x + b.w / 2;
    const z0 = b.z - b.d / 2, z1 = b.z + b.d / 2;
    const yB = wob - sOff, yT = b.h + wob - sOff;

    if (b.spawnT > 0.3) drawAOShadow(b, a);

    ctx.globalAlpha = a;

    const top = [
      project(x0, yT, z0), project(x1, yT, z0),
      project(x1, yT, z1), project(x0, yT, z1),
    ];
    const left = [
      project(x0, yB, z0), project(x0, yT, z0),
      project(x0, yT, z1), project(x0, yB, z1),
    ];
    const right = [
      project(x0, yB, z0), project(x1, yB, z0),
      project(x1, yT, z0), project(x0, yT, z0),
    ];

    ctx.fillStyle = b.palette.l; fillPath(left);
    ctx.fillStyle = b.palette.r; fillPath(right);

    // Top mit dezentem Verlauf
    const tg = ctx.createLinearGradient(top[0].x, top[0].y, top[2].x, top[2].y);
    tg.addColorStop(0, b.palette.top);
    tg.addColorStop(1, b.palette.l);
    ctx.fillStyle = tg;
    fillPath(top);

    // Kanten-Highlight oben
    ctx.strokeStyle = 'rgba(255,255,255,.35)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(top[0].x, top[0].y);
    ctx.lineTo(top[1].x, top[1].y);
    ctx.lineTo(top[2].x, top[2].y);
    ctx.stroke();

    // Outline
    ctx.strokeStyle = 'rgba(0,0,0,.06)';
    strokePath(top);
    strokePath(left);
    strokePath(right);

    if (b.special) drawSpecialMark(b.x, b.h + wob - sOff, b.z);

    ctx.globalAlpha = 1;
  }

  function drawCylinder(b, isCurrent) {
    const wob = (isCurrent && game.blockWobble > 0)
      ? Math.sin(game.tick * 30) * game.blockWobble * 0.6 : 0;
    const sOff = (1 - b.spawnT) * 80;
    const a = b.spawnT;

    const r = b.w / 2;
    const yB = wob - sOff, yT = b.h + wob - sOff;
    const top = project(b.x, yT, b.z);
    const bot = project(b.x, yB, b.z);
    const rH = r * ISO_RX, rV = r * ISO_RY;

    if (b.spawnT > 0.3) drawAOShadow(b, a);

    ctx.globalAlpha = a;

    // Seite (mit vertikalem Verlauf)
    const sg = ctx.createLinearGradient(0, top.y, 0, bot.y + rV);
    sg.addColorStop(0, b.palette.l);
    sg.addColorStop(1, b.palette.r);
    ctx.fillStyle = sg;
    ctx.beginPath();
    ctx.moveTo(top.x + rH, top.y);
    ctx.lineTo(bot.x + rH, bot.y);
    ctx.ellipse(bot.x, bot.y, rH, rV, 0, 0, Math.PI, false);
    ctx.lineTo(top.x - rH, top.y);
    ctx.ellipse(top.x, top.y, rH, rV, 0, Math.PI, 0, true);
    ctx.closePath();
    ctx.fill();

    // Top-Ellipse (heller, mit Innenverlauf)
    const tg = ctx.createRadialGradient(
      top.x, top.y - rV * 0.3, 0,
      top.x, top.y, rH * 1.1
    );
    tg.addColorStop(0, '#ffffff');
    tg.addColorStop(0.4, b.palette.top);
    tg.addColorStop(1, b.palette.l);
    ctx.fillStyle = tg;
    ctx.beginPath();
    ctx.ellipse(top.x, top.y, rH, rV, 0, 0, Math.PI * 2);
    ctx.fill();

    // Top-Outline
    ctx.strokeStyle = 'rgba(0,0,0,.07)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.ellipse(top.x, top.y, rH, rV, 0, 0, Math.PI * 2);
    ctx.stroke();

    if (b.special) drawSpecialMark(b.x, b.h + wob - sOff, b.z);

    ctx.globalAlpha = 1;
  }

  function drawSpecialMark(wx, wy, wz) {
    const c = project(wx, wy + 0.05, wz);
    // pulsierender Kern
    const pulse = 1 + Math.sin(game.tick * 4) * 0.15;
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(c.x, c.y, 4.5 * pulse, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = 'rgba(180, 110, 0, 0.7)';
    ctx.lineWidth = 1.5;
    ctx.stroke();
  }

  function drawBlock(b, isCurrent) {
    if (b.shape === 'cylinder') drawCylinder(b, isCurrent);
    else                         drawCube(b, isCurrent);
  }

  function drawTrail() {
    const t = game.trail;
    if (t.length < 2) return;
    for (let i = 0; i < t.length; i++) {
      const seg = t[i];
      const aT = i / t.length;
      const alpha = aT * 0.35 * (seg.life / 0.5);
      if (alpha < 0.01) continue;
      const s = project(seg.x, seg.y + 14, seg.z);
      ctx.globalAlpha = alpha;
      ctx.fillStyle = '#1a1f2e';
      ctx.beginPath();
      ctx.arc(s.x, s.y, 2 + aT * 4, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function drawPlayer() {
    const p = game.player;
    const baseR = 10;
    const baseH = 28;

    const sq = p.squash + Math.sin(p.idle) * 0.018;
    const stretchY = 1 + p.stretch * 0.4;
    const r = baseR * (1 + sq * 0.55);
    const h = baseH * (1 - sq * 0.62) * stretchY;
    const headR = r * 0.85;

    // Schatten unter Spieler
    const surfY = surfaceUnderPlayer();
    if (surfY != null) {
      const fall = Math.max(0, p.y - surfY);
      const al = Math.max(0.06, 0.30 - fall / 320);
      const sc = 1 - Math.min(0.55, fall / 380);
      const s = project(p.x, surfY + 0.05, p.z);
      ctx.fillStyle = `rgba(40, 30, 25, ${al})`;
      ctx.beginPath();
      ctx.ellipse(s.x, s.y, r * sc * 1.25, r * sc * 0.55, 0, 0, Math.PI * 2);
      ctx.fill();
    }

    const bottom = project(p.x, p.y, p.z);
    const top    = project(p.x, p.y + h, p.z);
    const head   = project(p.x, p.y + h + headR * 0.6, p.z);

    let lean = 0;
    if (p.state === 'jumping') {
      lean = (p.dir === 'x' ? 1 : -1) * 0.18;
    }
    const dx = lean * h * 0.4;

    // Körper
    const bodyGrad = ctx.createLinearGradient(bottom.x - r, top.y, bottom.x + r, bottom.y);
    bodyGrad.addColorStop(0, '#454a64');
    bodyGrad.addColorStop(0.6, '#2a3145');
    bodyGrad.addColorStop(1, '#16192a');
    ctx.fillStyle = bodyGrad;

    const cx = bottom.x;
    ctx.beginPath();
    ctx.moveTo(cx - r, bottom.y);
    ctx.bezierCurveTo(
      cx - r * 0.92, bottom.y - h * 0.42,
      cx - r * 0.62 + dx, top.y + r * 0.5,
      cx - r * 0.42 + dx, top.y
    );
    ctx.bezierCurveTo(
      cx - r * 0.42 + dx, top.y - r * 0.42,
      cx + r * 0.42 + dx, top.y - r * 0.42,
      cx + r * 0.42 + dx, top.y
    );
    ctx.bezierCurveTo(
      cx + r * 0.62 + dx, top.y + r * 0.5,
      cx + r * 0.92, bottom.y - h * 0.42,
      cx + r, bottom.y
    );
    ctx.bezierCurveTo(
      cx + r, bottom.y + r * 0.55,
      cx - r, bottom.y + r * 0.55,
      cx - r, bottom.y
    );
    ctx.closePath();
    ctx.fill();

    // Sockel-Highlight
    ctx.fillStyle = 'rgba(255, 255, 255, .10)';
    ctx.beginPath();
    ctx.ellipse(cx, bottom.y - 2, r * 0.7, r * 0.22, 0, 0, Math.PI * 2);
    ctx.fill();

    // Halsring
    ctx.fillStyle = 'rgba(255, 255, 255, .14)';
    ctx.beginPath();
    ctx.ellipse(cx + dx, top.y, r * 0.42, r * 0.12, 0, 0, Math.PI * 2);
    ctx.fill();

    // Kopf
    const headGrad = ctx.createRadialGradient(
      head.x + dx - headR * 0.35, head.y - headR * 0.35, 0,
      head.x + dx, head.y, headR * 1.1
    );
    headGrad.addColorStop(0, '#5a6080');
    headGrad.addColorStop(0.5, '#2a3145');
    headGrad.addColorStop(1, '#16192a');
    ctx.fillStyle = headGrad;
    ctx.beginPath();
    ctx.arc(head.x + dx, head.y, headR, 0, Math.PI * 2);
    ctx.fill();

    // Glanz
    ctx.fillStyle = 'rgba(255, 255, 255, .22)';
    ctx.beginPath();
    ctx.arc(head.x + dx - headR * 0.32, head.y - headR * 0.36, headR * 0.38, 0, Math.PI * 2);
    ctx.fill();

    // Augen
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(head.x + dx - 3, head.y + 0.6, 1.6, 0, Math.PI * 2);
    ctx.arc(head.x + dx + 3, head.y + 0.6, 1.6, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#000';
    ctx.beginPath();
    ctx.arc(head.x + dx - 3, head.y + 0.9, 0.7, 0, Math.PI * 2);
    ctx.arc(head.x + dx + 3, head.y + 0.9, 0.7, 0, Math.PI * 2);
    ctx.fill();

    // Krönchen-Knopf
    const knob = project(p.x, p.y + h + headR * 1.4, p.z);
    ctx.fillStyle = '#16192a';
    ctx.beginPath();
    ctx.arc(knob.x + dx, knob.y, 2.4, 0, Math.PI * 2);
    ctx.fill();
  }

  function surfaceUnderPlayer() {
    const p = game.player;
    let bestY = null;
    for (const b of game.blocks) {
      if (overBlock(p.x, p.z, b)) {
        if (bestY == null || b.h > bestY) bestY = b.h;
      }
    }
    return bestY;
  }

  function drawParticles() {
    for (const pt of game.particles) {
      const s = project(pt.x, pt.y, pt.z);
      ctx.globalAlpha = Math.min(1, pt.life * 2.2);
      ctx.fillStyle = pt.color;
      ctx.beginPath();
      ctx.arc(s.x, s.y, pt.size, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  function drawRings() {
    for (const r of game.rings) {
      const center = project(r.x, r.y + 0.05, r.z);
      const t = 1 - r.life / r.lifeMax;
      const radius = 4 + t * 70;
      const alpha = (1 - t) * 0.85;
      ctx.strokeStyle = `rgba(255, 200, 60, ${alpha})`;
      ctx.lineWidth = 3 * (1 - t * 0.5) + 0.5;
      ctx.beginPath();
      ctx.ellipse(center.x, center.y, radius * ISO_RX, radius * ISO_RY, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  function drawPopups() {
    for (const p of game.popups) {
      const t = 1 - p.life / p.lifeMax;
      const offset = -t * 60;
      const alpha = p.life > 0.2 ? 1 : (p.life / 0.2);
      const scale = 1 + Math.min(0.25, (p.lifeMax - p.life) * 2);
      const s = project(p.x, p.y + 22, p.z);
      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.translate(s.x, s.y + offset);
      ctx.scale(scale, scale);
      ctx.font = `bold ${p.size}px -apple-system, "SF Pro Display", system-ui`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.lineWidth = 4;
      ctx.strokeStyle = 'rgba(255, 255, 255, .85)';
      ctx.strokeText(p.text, 0, 0);
      ctx.fillStyle = p.color;
      ctx.fillText(p.text, 0, 0);
      ctx.restore();
    }
  }

  function draw() {
    drawBg();

    ctx.save();
    if (game.shake > 0) {
      ctx.translate(
        (Math.random() - 0.5) * game.shake,
        (Math.random() - 0.5) * game.shake
      );
    }

    // Tiefen-Sortierung: höhere (x+z) = weiter weg = zuerst
    const sorted = game.blocks
      .map(b => b)
      .sort((a, b) => (b.x + b.z) - (a.x + a.z));
    const pDepth = game.player.x + game.player.z;
    const curIdx = game.blocks.length >= 2 ? game.blocks.length - 2 : 0;

    let inserted = false;
    for (const b of sorted) {
      if (!inserted && (b.x + b.z) < pDepth - 0.5) {
        drawTrail();
        drawPlayer();
        inserted = true;
      }
      drawBlock(b, game.blocks.indexOf(b) === curIdx);
    }
    if (!inserted) {
      drawTrail();
      drawPlayer();
    }

    drawParticles();
    drawRings();
    drawPopups();

    ctx.restore();

    // Vollbild-Flash
    if (game.flash > 0.01) {
      ctx.fillStyle = `rgba(255, 200, 70, ${game.flash * 0.28})`;
      ctx.fillRect(0, 0, W, H);
    }

    // Vignette (subtil)
    const vg = ctx.createRadialGradient(W / 2, H / 2, H * 0.4, W / 2, H / 2, H * 0.85);
    vg.addColorStop(0, 'rgba(0, 0, 0, 0)');
    vg.addColorStop(1, 'rgba(0, 0, 0, 0.18)');
    ctx.fillStyle = vg;
    ctx.fillRect(0, 0, W, H);
  }

  // ════════════════════════════ Update ═════════════════════════
  function update(dtRaw) {
    const dt = game.slowmo > 0 ? dtRaw * 0.35 : dtRaw;
    game.slowmo = Math.max(0, game.slowmo - dtRaw);

    game.tick += dt;
    const p = game.player;
    const cur = currentBlock();
    const next = nextBlock();

    p.idle += dt * 3;

    // Lade-Phase
    if (p.state === 'charging') {
      const t = (performance.now() - p.chargeStart) / 1000;
      p.charge = Math.min(t / MAX_CHARGE_S, 1);
      p.squash = p.charge * 0.55;
      els.chargeFill.style.width = (p.charge * 100) + '%';
    } else {
      p.squash *= Math.max(0, 1 - dt * 9);
    }
    p.stretch *= Math.max(0, 1 - dt * 12);

    // Sprung-Phase
    if (p.state === 'jumping') {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.z += p.vz * dt;
      p.vy -= GRAVITY * dt;

      // Trail
      if (game.tick * 1000 % 1 < 16) { /* throttle */ }
      game.trail.push({ x: p.x, y: p.y, z: p.z, life: 0.5 });
      if (game.trail.length > 14) game.trail.shift();

      if (p.vy < 0) {
        let target = null;
        if (overBlock(p.x, p.z, next) && p.y <= next.h) target = { b: next, isNew: true };
        else if (overBlock(p.x, p.z, cur) && p.y <= cur.h) target = { b: cur, isNew: false };

        if (target) land(target.b, target.isNew);
        else if (p.y < -120) gameOver();
      }
    }

    // Lebenszeiten
    decayList(game.particles, dt, pt => {
      pt.x += pt.vx * dt;
      pt.y += pt.vy * dt;
      pt.z += pt.vz * dt;
      pt.vy -= 800 * dt;
    });
    decayList(game.trail, dt);
    decayList(game.rings, dt);
    decayList(game.popups, dt, pp => { /* drift handled via t in draw */ });

    // Block-Spawn-Animation
    for (const b of game.blocks) {
      if (b.spawnT < 1) b.spawnT = Math.min(1, b.spawnT + dt * 4);
    }

    // Kamera-Lerp
    const camLerp = Math.min(1, dt * 4.5);
    game.camera.x += (game.camera.tx - game.camera.x) * camLerp;
    game.camera.z += (game.camera.tz - game.camera.z) * camLerp;

    // Effekt-Decay
    game.shake *= Math.max(0, 1 - dt * 7);
    game.flash *= Math.max(0, 1 - dt * 3.5);
    game.blockWobble *= Math.max(0, 1 - dt * 8);

    // Staub
    for (const d of game.dust) {
      d.sx += d.vx * dt;
      d.sy += d.vy * dt;
      if (d.sy < -0.05) { d.sy = 1.05; d.sx = Math.random(); }
      if (d.sx < -0.05) d.sx = 1.05;
      else if (d.sx > 1.05) d.sx = -0.05;
    }
  }

  function decayList(list, dt, mut) {
    for (let i = list.length - 1; i >= 0; i--) {
      if (mut) mut(list[i]);
      list[i].life -= dt;
      if (list[i].life <= 0) list.splice(i, 1);
    }
  }

  function currentBlock() { return game.blocks[game.blocks.length - 2] ?? game.blocks[0]; }
  function nextBlock()    { return game.blocks[game.blocks.length - 1]; }

  function overBlock(x, z, b) {
    if (b.shape === 'cylinder') {
      const r = b.w / 2;
      const dx = x - b.x, dz = z - b.z;
      return dx * dx + dz * dz <= r * r;
    }
    return Math.abs(x - b.x) <= b.w / 2 && Math.abs(z - b.z) <= b.d / 2;
  }

  // ═════════════════════════════ Land/GameOver ═════════════════
  function land(block, isNew) {
    const p = game.player;
    p.y = block.h;
    p.vx = p.vy = p.vz = 0;
    p.state = 'idle';
    p.squash = 0;
    p.stretch = 0.65;

    burst(p.x, block.h, p.z, 10);
    game.shake = 6;
    game.blockWobble = 1.5;
    game.blockWobbleId = game.blocks.indexOf(block);
    els.chargeFill.style.width = '0%';
    els.chargeBar.classList.remove('show');

    if (isNew) {
      const dx = p.x - block.x, dz = p.z - block.z;
      const dist = Math.hypot(dx, dz);
      const isCenter = dist < CENTER_TOL;

      let gained;
      if (isCenter) {
        game.combo += 1;
        gained = 2 * game.combo;
        showCombo(`× ${game.combo}  Perfekt!`);
        game.flash = 1;
        game.slowmo = 0.25;
        burst(p.x, block.h + 12, p.z, 26, true);
        pulseRing(p.x, block.h, p.z);
        pulseRing(p.x, block.h, p.z, 0.18);
        popup(p.x, block.h, p.z, `+${gained}`, '#ffb400', 30);
        SFX.perfect();
      } else if (block.special) {
        game.combo = 0;
        gained = 8;
        showCombo('+8  Bonus');
        game.flash = 0.7;
        burst(p.x, block.h + 12, p.z, 18, true);
        popup(p.x, block.h, p.z, '+8 Bonus', '#f4b400', 26);
        SFX.bonus();
      } else {
        game.combo = 0;
        gained = 1;
        popup(p.x, block.h, p.z, '+1', '#1a1f2e', 22);
        SFX.land();
      }

      game.score += gained;
      updateScore(true);
      spawnNext();
      centerCamera();
    } else {
      game.combo = 0;
      showCombo('Beinahe…');
      popup(p.x, block.h, p.z, '0', '#999', 22);
      SFX.land();
    }
  }

  function gameOver() {
    running = false;
    game.player.state = 'dead';
    els.chargeBar.classList.remove('show');
    els.chargeFill.style.width = '0%';

    if (game.score > best) {
      best = game.score;
      localStorage.setItem('jumpjump.best', best);
    }
    els.endScore.textContent = game.score;
    els.endBest.textContent = best;
    els.startBest.textContent = best;
    SFX.over();
    setTimeout(() => els.endOver.classList.remove('hidden'), 320);
  }

  function showCombo(text) {
    els.combo.textContent = text;
    els.combo.classList.add('show');
    clearTimeout(showCombo._t);
    showCombo._t = setTimeout(() => els.combo.classList.remove('show'), 1200);
  }
  function updateScore(animate) {
    els.score.textContent = game.score;
    if (animate) {
      els.score.classList.remove('bump');
      void els.score.offsetWidth;
      els.score.classList.add('bump');
    }
  }

  // ═════════════════════════════ FX ═════════════════════════════
  function burst(x, y, z, n, gold = false) {
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = 60 + Math.random() * 140;
      game.particles.push({
        x, y, z,
        vx: Math.cos(a) * s,
        vz: Math.sin(a) * s,
        vy: 100 + Math.random() * 220,
        life: 0.4 + Math.random() * 0.4,
        lifeMax: 0.8,
        color: gold
          ? ['#ffd93d', '#ffe27a', '#fff'][i % 3]
          : ['#ff8a8a', '#ffd0c5', '#fff'][i % 3],
        size: 2 + Math.random() * 3,
      });
    }
  }
  function pulseRing(x, y, z, delay = 0) {
    setTimeout(() => {
      if (!game) return;
      game.rings.push({ x, y, z, life: 0.7, lifeMax: 0.7 });
    }, delay * 1000);
  }
  function popup(x, y, z, text, color, size = 22) {
    game.popups.push({ x, y, z, text, color, size, life: 1.1, lifeMax: 1.1 });
  }

  // ═══════════════════════════ Input ═══════════════════════════
  let pointerDown = false;
  function down(e) {
    if (!running) return;
    if (e.cancelable) e.preventDefault();
    if (game.player.state !== 'idle') return;
    pointerDown = true;
    game.player.state = 'charging';
    game.player.chargeStart = performance.now();
    game.player.charge = 0;
    els.chargeBar.classList.add('show');
    SFX.charge();
  }
  function up(e) {
    if (!running) return;
    if (e.cancelable) e.preventDefault();
    if (!pointerDown || game.player.state !== 'charging') return;
    pointerDown = false;
    release();
  }
  function release() {
    const p = game.player;
    const cur = currentBlock();
    const next = nextBlock();
    const charge = Math.min(p.charge, 1);

    const vh = MIN_VH + charge * (MAX_VH - MIN_VH);
    const vy = MIN_VY + charge * (MAX_VY - MIN_VY);

    const dx = next.x - cur.x, dz = next.z - cur.z;
    if (dx >= dz) { p.vx = vh; p.vz = 0; p.dir = 'x'; }
    else          { p.vx = 0;  p.vz = vh; p.dir = 'z'; }

    p.vy = vy;
    p.state = 'jumping';
    p.squash = 0;
    p.stretch = 0.55;
    els.chargeBar.classList.remove('show');
    SFX.jump();
  }

  canvas.addEventListener('mousedown', down);
  window.addEventListener('mouseup', up);
  canvas.addEventListener('touchstart', down, { passive: false });
  canvas.addEventListener('touchend', up, { passive: false });
  canvas.addEventListener('touchcancel', up, { passive: false });
  canvas.addEventListener('contextmenu', e => e.preventDefault());

  // Mute-Toggle
  els.muteBtn.addEventListener('click', () => {
    const on = SFX.toggle();
    els.muteBtn.classList.toggle('muted', !on);
  });

  // ════════════════════════════ Steuerung ══════════════════════
  function startGame() {
    els.startOver.classList.add('hidden');
    els.endOver.classList.add('hidden');
    newGame();
    running = true;
  }
  els.playBtn.addEventListener('click', startGame);
  els.restartBtn.addEventListener('click', startGame);
  els.shareBtn.addEventListener('click', async () => {
    const text = `Ich habe ${game.score} Punkte in Jump Jump erreicht. Schaffst du mehr?`;
    try {
      if (navigator.share) await navigator.share({ title: 'Jump Jump', text });
      else {
        await navigator.clipboard.writeText(text);
        const orig = els.shareBtn.textContent;
        els.shareBtn.textContent = 'In Zwischenablage kopiert';
        setTimeout(() => els.shareBtn.textContent = orig, 1300);
      }
    } catch { /* abgebrochen */ }
  });

  // ═════════════════════════════ Loop ══════════════════════════
  function loop(now) {
    if (!last) last = now;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    if (running) update(dt);
    else         updateIdle(dt);
    draw();
    requestAnimationFrame(loop);
  }

  function updateIdle(dt) {
    if (!game) return;
    game.tick += dt;
    game.player.idle += dt * 3;
    // Staub auch im Idle bewegen
    for (const d of game.dust) {
      d.sx += d.vx * dt;
      d.sy += d.vy * dt;
      if (d.sy < -0.05) { d.sy = 1.05; d.sx = Math.random(); }
      if (d.sx < -0.05) d.sx = 1.05;
      else if (d.sx > 1.05) d.sx = -0.05;
    }
    decayList(game.popups, dt);
    decayList(game.rings, dt);
    decayList(game.particles, dt, pt => {
      pt.x += pt.vx * dt;
      pt.y += pt.vy * dt;
      pt.z += pt.vz * dt;
      pt.vy -= 800 * dt;
    });
    // sanftes Block-Spawn auch im Idle
    for (const b of game.blocks) {
      if (b.spawnT < 1) b.spawnT = Math.min(1, b.spawnT + dt * 4);
    }
  }

  // Init
  resize();
  newGame();
  running = false;
  requestAnimationFrame(loop);
})();
