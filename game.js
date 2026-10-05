// Intersection Control — a basic traffic-light game.
// One north–south street crosses one east–west street; each street has
// two lanes (one per direction). The player switches which street has green.
(() => {
  'use strict';

  // ---- World geometry (logical canvas units) ----
  const W = 640, H = 640, CX = W / 2, CY = H / 2;
  const ROAD_HALF = 40;          // each street is 80 wide: two 40-wide lanes
  const LANE_OFF = 20;           // lane centre offset from street centre
  const SIDEWALK = 16;
  const CROSSWALK = 18;
  const SPAWN_PAD = 40;          // cars spawn this far off-screen

  // Distance along a lane path, measured to a car's front bumper.
  const ENTRY_S = (W / 2 + SPAWN_PAD) - ROAD_HALF; // front reaches intersection
  const EXIT_S = ENTRY_S + ROAD_HALF * 2;          // front leaves intersection
  const STOP_S = ENTRY_S - CROSSWALK - 4;          // stop line
  const PATH_LEN = W + SPAWN_PAD * 2;

  // ---- Tuning ----
  const YELLOW_TIME = 2.2;
  const ALL_RED_TIME = 1.4;
  const ANGRY_AFTER = 8;         // seconds stopped before a driver starts honking
  const ACCEL = 160, BRAKE = 260, HARD_BRAKE = 520, MIN_GAP = 9;
  const DRAIN_PER_ANGRY = 2.5;   // patience lost per second per honking driver
  const DRAIN_PER_BLOCKED = 4;   // per second per lane backed up off-screen
  const REFILL_PER_CAR = 1;

  // Each approach is described by its travel direction. `pos(s)` maps the
  // distance along the path to a screen point; `angle` is the heading.
  const APPROACHES = {
    N: { axis: 'NS', name: 'Northbound', angle: -Math.PI / 2, pos: s => ({ x: CX + LANE_OFF, y: H + SPAWN_PAD - s }) },
    S: { axis: 'NS', name: 'Southbound', angle: Math.PI / 2, pos: s => ({ x: CX - LANE_OFF, y: -SPAWN_PAD + s }) },
    E: { axis: 'EW', name: 'Eastbound', angle: 0, pos: s => ({ x: -SPAWN_PAD + s, y: CY + LANE_OFF }) },
    W: { axis: 'EW', name: 'Westbound', angle: Math.PI, pos: s => ({ x: W + SPAWN_PAD - s, y: CY - LANE_OFF }) },
  };
  const KEYS = Object.keys(APPROACHES);

  const CAR_COLORS = ['#e8eef3', '#2c3e57', '#b8372f', '#d6a12b', '#4c7a5a', '#8a96a3', '#1f2328', '#3d6fb0', '#c96b2c'];
  const TRUCK_COLORS = ['#f0f0ea', '#c9cdd1', '#5a6470'];

  // ---- DOM ----
  const canvas = document.getElementById('board');
  const ctx = canvas.getContext('2d');
  const el = id => document.getElementById(id);
  const ui = {
    cleared: el('stat-cleared'), time: el('stat-time'), best: el('stat-best'),
    patienceFill: el('patience-fill'), patienceValue: el('patience-value'), patienceBar: el('patience-bar'),
    signalNS: el('signal-ns'), signalEW: el('signal-ew'), rush: el('rush'),
    switchBtn: el('switch-btn'), overlay: el('overlay'), overlayTitle: el('overlay-title'),
    overlayBody: el('overlay-body'), startBtn: el('start-btn'), pauseBtn: el('pause-btn'),
  };

  // ---- Persistent best score (per browser, optional) ----
  const loadBest = () => { try { return Number(localStorage.getItem('intersection-best')) || 0; } catch { return 0; } };
  const saveBest = v => { try { localStorage.setItem('intersection-best', String(v)); } catch { /* storage unavailable */ } };

  // ---- Game state ----
  let state;
  let best = loadBest();

  function newState() {
    const lanes = {};
    for (const k of KEYS) lanes[k] = { cars: [], timer: 1 + Math.random() * 3, pending: 0 };
    return {
      mode: 'ready', // ready | running | paused | over
      t: 0,
      cleared: 0,
      patience: 100,
      lanes,
      signal: { green: 'NS', phase: 'green', timer: 0, id: 0 },
      rush: null,               // { lane, until }
      nextRush: 22,
      honkPulse: 0,
    };
  }

  // ---- Signals ----
  function lightFor(axis) {
    const sig = state.signal;
    if (sig.phase === 'allred' || axis !== sig.green) return 'red';
    return sig.phase; // green | yellow
  }

  function requestSwitch() {
    if (state.mode !== 'running') return;
    const sig = state.signal;
    if (sig.phase !== 'green') return; // already changing
    sig.phase = 'yellow';
    sig.timer = 0;
    sig.id++;
  }

  function updateSignal(dt) {
    const sig = state.signal;
    sig.timer += dt;
    if (sig.phase === 'yellow' && sig.timer >= YELLOW_TIME) {
      sig.phase = 'allred'; sig.timer = 0;
    } else if (sig.phase === 'allred' && sig.timer >= ALL_RED_TIME) {
      sig.phase = 'green'; sig.timer = 0;
      sig.green = sig.green === 'NS' ? 'EW' : 'NS';
    }
  }

  // ---- Traffic generation ----
  function laneRate(key) {
    const base = 0.16 + Math.min(0.24, state.t * 0.0025); // cars per second
    return state.rush && state.rush.lane === key ? base * 2.6 : base;
  }

  const expRand = mean => -Math.log(1 - Math.random()) * mean;

  function makeCar() {
    const truck = Math.random() < 0.12;
    return {
      s: 0, v: 0,
      len: truck ? 40 : 24 + Math.random() * 6,
      wid: truck ? 18 : 15,
      maxV: truck ? 80 + Math.random() * 10 : 96 + Math.random() * 30,
      color: truck ? pick(TRUCK_COLORS) : pick(CAR_COLORS),
      truck,
      wait: 0,
      commit: -1,
    };
  }

  const pick = arr => arr[Math.floor(Math.random() * arr.length)];

  function updateSpawns(dt) {
    for (const k of KEYS) {
      const lane = state.lanes[k];
      lane.timer -= dt;
      if (lane.timer <= 0) {
        lane.pending = Math.min(lane.pending + 1, 9);
        lane.timer = expRand(1 / laneRate(k));
      }
      if (lane.pending > 0) {
        const last = lane.cars[lane.cars.length - 1];
        const room = last ? last.s - last.len - MIN_GAP : Infinity;
        if (room > 6) {
          const car = makeCar();
          car.v = Math.min(car.maxV, Math.sqrt(2 * BRAKE * Math.max(0, room)));
          lane.cars.push(car);
          lane.pending--;
        }
      }
    }

    // Rush hour surges on one random approach.
    if (state.rush && state.t >= state.rush.until) state.rush = null;
    if (!state.rush && state.t >= state.nextRush) {
      state.rush = { lane: pick(KEYS), until: state.t + 12 };
      state.nextRush = state.t + 24 + Math.random() * 10;
    }
  }

  // ---- Driving ----
  function updateLane(key, dt) {
    const lane = state.lanes[key];
    const light = lightFor(APPROACHES[key].axis);
    const sigId = state.signal.id;

    for (let i = 0; i < lane.cars.length; i++) {
      const c = lane.cars[i];
      let vMax = c.maxV;

      // Keep distance from the car ahead.
      if (i > 0) {
        const lead = lane.cars[i - 1];
        const gap = lead.s - lead.len - c.s - MIN_GAP;
        vMax = Math.min(vMax, Math.sqrt(2 * BRAKE * Math.max(0, gap)));
      }

      // Obey the signal while still before the stop line.
      let mustStop = false;
      if (c.s <= STOP_S && light !== 'green' && c.commit !== sigId) {
        const d = STOP_S - c.s;
        if (light === 'yellow' && (c.v * c.v) / (2 * HARD_BRAKE) > d) {
          c.commit = sigId; // too close to stop safely: clear the intersection
        } else {
          mustStop = true;
          vMax = Math.min(vMax, Math.sqrt(2 * BRAKE * d));
        }
      }

      if (c.v < vMax) c.v = Math.min(vMax, c.v + ACCEL * dt);
      else c.v = Math.max(vMax, c.v - HARD_BRAKE * 1.5 * dt);

      const before = c.s;
      c.s += c.v * dt;
      if (mustStop && before <= STOP_S && c.s > STOP_S) { c.s = STOP_S; c.v = 0; }
      if (i > 0) {
        const lead = lane.cars[i - 1];
        const maxS = lead.s - lead.len - 2;
        if (c.s > maxS) { c.s = Math.max(before, maxS); c.v = Math.min(c.v, lead.v); }
      }

      if (c.v < 4 && c.s <= STOP_S + 1) c.wait += dt;
    }

    // Remove cars that drove off the far edge.
    while (lane.cars.length && lane.cars[0].s - lane.cars[0].len > PATH_LEN) {
      lane.cars.shift();
      state.cleared++;
      state.patience = Math.min(100, state.patience + REFILL_PER_CAR);
    }
  }

  function updatePatience(dt) {
    let angry = 0, blocked = 0;
    for (const k of KEYS) {
      const lane = state.lanes[k];
      for (const c of lane.cars) if (isAngry(c)) angry++;
      if (lane.pending > 0) blocked++;
    }
    state.patience -= (angry * DRAIN_PER_ANGRY + blocked * DRAIN_PER_BLOCKED) * dt;
    state.angry = angry;
    if (state.patience <= 0) {
      state.patience = 0;
      endShift();
    }
  }

  const isAngry = c => c.wait > ANGRY_AFTER && c.s <= STOP_S + 1;

  function update(dt) {
    state.t += dt;
    state.honkPulse += dt;
    updateSignal(dt);
    updateSpawns(dt);
    for (const k of KEYS) updateLane(k, dt);
    updatePatience(dt);
  }

  // ---- Rendering ----
  let scale = 1;
  const background = document.createElement('canvas');

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const size = canvas.getBoundingClientRect().width;
    canvas.width = Math.round(size * dpr);
    canvas.height = Math.round(size * dpr);
    scale = (size * dpr) / W;
    background.width = canvas.width;
    background.height = canvas.height;
    drawBackground(background.getContext('2d'));
  }

  // Seeded RNG so the city looks the same every shift.
  function seeded(seed) {
    return () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
  }

  function drawBackground(g) {
    g.setTransform(scale, 0, 0, scale, 0, 0);
    const rnd = seeded(42);

    // Sidewalk concrete everywhere, then city blocks, then streets on top.
    g.fillStyle = '#9da5ad';
    g.fillRect(0, 0, W, H);

    const blockSize = CX - ROAD_HALF - SIDEWALK;
    const corners = [
      { x: 0, y: 0, kind: 'buildings' },
      { x: CX + ROAD_HALF + SIDEWALK, y: 0, kind: 'buildings' },
      { x: 0, y: CY + ROAD_HALF + SIDEWALK, kind: 'park' },
      { x: CX + ROAD_HALF + SIDEWALK, y: CY + ROAD_HALF + SIDEWALK, kind: 'buildings' },
    ];
    for (const c of corners) {
      if (c.kind === 'park') drawPark(g, c.x, c.y, blockSize, rnd);
      else drawBuildings(g, c.x, c.y, blockSize, rnd);
    }

    // Sidewalk joints.
    g.strokeStyle = 'rgba(40, 48, 56, 0.18)';
    g.lineWidth = 1;
    for (let p = 0; p < W; p += 16) {
      for (const off of [CX - ROAD_HALF - SIDEWALK, CX + ROAD_HALF]) {
        g.beginPath(); g.moveTo(off, p); g.lineTo(off + SIDEWALK, p); g.stroke();
        g.beginPath(); g.moveTo(p, off); g.lineTo(p, off + SIDEWALK); g.stroke();
      }
    }

    // Streets.
    g.fillStyle = '#3a4048';
    g.fillRect(CX - ROAD_HALF, 0, ROAD_HALF * 2, H);
    g.fillRect(0, CY - ROAD_HALF, W, ROAD_HALF * 2);

    // Curbs.
    g.strokeStyle = '#c7ccd1';
    g.lineWidth = 2;
    const e = ROAD_HALF + 1;
    for (const [x1, y1, x2, y2] of [
      [CX - e, 0, CX - e, CY - e], [CX + e, 0, CX + e, CY - e],
      [CX - e, CY + e, CX - e, H], [CX + e, CY + e, CX + e, H],
      [0, CY - e, CX - e, CY - e], [0, CY + e, CX - e, CY + e],
      [CX + e, CY - e, W, CY - e], [CX + e, CY + e, W, CY + e],
    ]) { g.beginPath(); g.moveTo(x1, y1); g.lineTo(x2, y2); g.stroke(); }

    // Markings, drawn once per approach in the eastbound frame and rotated.
    for (const k of KEYS) {
      g.save();
      g.translate(CX, CY);
      g.rotate(APPROACHES[k].angle);
      g.translate(-CX, -CY);
      drawApproachMarkings(g);
      g.restore();
    }
  }

  function drawBuildings(g, x, y, size, rnd) {
    g.fillStyle = '#7d858d';
    g.fillRect(x, y, size, size);
    const roofs = ['#5b6670', '#6f6a63', '#4f5a52', '#73665f', '#56606b'];
    const split = 0.4 + rnd() * 0.2;
    const cols = [size * split, size * (1 - split)];
    let cx = x;
    for (const w of cols) {
      const rows = 1 + Math.floor(rnd() * 2);
      let cy = y;
      for (let r = 0; r < rows; r++) {
        const h = rows === 1 ? size : r === 0 ? size * (0.4 + rnd() * 0.2) : size - (cy - y);
        const bx = cx + 4, by = cy + 4, bw = w - 8, bh = h - 8;
        g.fillStyle = roofs[Math.floor(rnd() * roofs.length)];
        g.fillRect(bx, by, bw, bh);
        // Parapet edge and rooftop units.
        g.strokeStyle = 'rgba(255, 255, 255, 0.12)';
        g.lineWidth = 2;
        g.strokeRect(bx + 3, by + 3, bw - 6, bh - 6);
        const units = 1 + Math.floor(rnd() * 3);
        for (let u = 0; u < units; u++) {
          const uw = 12 + rnd() * 18, uh = 10 + rnd() * 14;
          const ux = bx + 10 + rnd() * Math.max(1, bw - uw - 20);
          const uy = by + 10 + rnd() * Math.max(1, bh - uh - 20);
          g.fillStyle = 'rgba(20, 24, 28, 0.25)';
          g.fillRect(ux + 3, uy + 3, uw, uh);
          g.fillStyle = '#a9b0b6';
          g.fillRect(ux, uy, uw, uh);
        }
        cy += h;
      }
      cx += w;
    }
  }

  function drawPark(g, x, y, size, rnd) {
    g.fillStyle = '#5d7d4f';
    g.fillRect(x, y, size, size);
    g.strokeStyle = '#b8b09c';
    g.lineWidth = 8;
    g.beginPath();
    g.moveTo(x + size, y + 10);
    g.quadraticCurveTo(x + size * 0.45, y + size * 0.4, x + 10, y + size);
    g.stroke();
    for (let i = 0; i < 26; i++) {
      const tx = x + 14 + rnd() * (size - 28), ty = y + 14 + rnd() * (size - 28);
      const r = 8 + rnd() * 10;
      g.fillStyle = 'rgba(20, 30, 18, 0.3)';
      g.beginPath(); g.arc(tx + 3, ty + 3, r, 0, Math.PI * 2); g.fill();
      g.fillStyle = rnd() < 0.5 ? '#3f6a3a' : '#4b7a43';
      g.beginPath(); g.arc(tx, ty, r, 0, Math.PI * 2); g.fill();
    }
  }

  // Markings for the approach that travels east (arrives from the left).
  function drawApproachMarkings(g) {
    const edge = CX - ROAD_HALF;
    // Double yellow centre line up to the crosswalk.
    g.fillStyle = '#e3b23c';
    g.fillRect(0, CY - 3, edge - CROSSWALK - 4, 2);
    g.fillRect(0, CY + 1, edge - CROSSWALK - 4, 2);
    // Stop line across the inbound lane.
    g.fillStyle = '#eef0ea';
    g.fillRect(edge - CROSSWALK - 8, CY + 2, 4, ROAD_HALF - 2);
    // Zebra crosswalk spanning the whole street.
    for (let y = CY - ROAD_HALF + 3; y < CY + ROAD_HALF - 3; y += 8) {
      g.fillRect(edge - CROSSWALK + 2, y, CROSSWALK - 4, 4);
    }
  }

  function drawSignalHead(g, light) {
    // Eastbound frame: mounted on the near-right corner.
    const x = CX - ROAD_HALF - CROSSWALK - 12, y = CY + ROAD_HALF + 6;
    g.fillStyle = '#15181c';
    roundRect(g, x - 4, y, 28, 11, 3); g.fill();
    const lamps = [['red', '#e5484d'], ['yellow', '#f2a91f'], ['green', '#30c070']];
    lamps.forEach(([name, color], i) => {
      const on = light === name;
      g.fillStyle = on ? color : '#2b3036';
      g.beginPath(); g.arc(x + 2 + i * 8, y + 5.5, 3, 0, Math.PI * 2); g.fill();
      if (on) {
        g.fillStyle = color + '55';
        g.beginPath(); g.arc(x + 2 + i * 8, y + 5.5, 7, 0, Math.PI * 2); g.fill();
      }
    });
    // Glow on the stop line itself so the state reads at a glance.
    const glow = { red: '#e5484d', yellow: '#f2a91f', green: '#30c070' }[light];
    g.fillStyle = glow + '40';
    g.fillRect(CX - ROAD_HALF - CROSSWALK - 22, CY + 2, 14, ROAD_HALF - 4);
  }

  function roundRect(g, x, y, w, h, r) {
    g.beginPath();
    g.moveTo(x + r, y);
    g.arcTo(x + w, y, x + w, y + h, r);
    g.arcTo(x + w, y + h, x, y + h, r);
    g.arcTo(x, y + h, x, y, r);
    g.arcTo(x, y, x + w, y, r);
    g.closePath();
  }

  function drawCar(g, c, key) {
    const a = APPROACHES[key];
    const p = a.pos(c.s - c.len / 2);
    g.save();
    g.translate(p.x, p.y);
    g.rotate(a.angle);
    const L = c.len, Wd = c.wid;
    // Shadow.
    g.fillStyle = 'rgba(0, 0, 0, 0.3)';
    roundRect(g, -L / 2 + 2, -Wd / 2 + 2, L, Wd, 4); g.fill();
    // Body.
    g.fillStyle = c.color;
    roundRect(g, -L / 2, -Wd / 2, L, Wd, c.truck ? 2 : 5); g.fill();
    if (c.truck) {
      g.fillStyle = 'rgba(0, 0, 0, 0.18)';
      g.fillRect(-L / 2 + 2, -Wd / 2 + 2, L - 14, Wd - 4);
      g.fillStyle = '#2a3a4a';
      g.fillRect(L / 2 - 8, -Wd / 2 + 2, 4, Wd - 4);
    } else {
      // Windshield and rear window.
      g.fillStyle = '#26323e';
      g.fillRect(L * 0.1, -Wd / 2 + 2, L * 0.18, Wd - 4);
      g.fillRect(-L * 0.36, -Wd / 2 + 2.5, L * 0.12, Wd - 5);
    }
    // Brake lights when slowing or stopped.
    if (c.v < c.maxV * 0.5) {
      g.fillStyle = '#ff3b3b';
      g.fillRect(-L / 2, -Wd / 2 + 1, 2, 3);
      g.fillRect(-L / 2, Wd / 2 - 4, 2, 3);
    }
    g.restore();

    // Waiting indicator: a ring that fills toward honking.
    if (c.wait > 2 && c.s <= STOP_S + 1) {
      const head = a.pos(c.s - c.len / 2);
      const frac = Math.min(1, c.wait / ANGRY_AFTER);
      const angry = frac >= 1;
      g.lineWidth = 2.5;
      g.strokeStyle = 'rgba(0, 0, 0, 0.45)';
      g.beginPath(); g.arc(head.x, head.y, 9, 0, Math.PI * 2); g.stroke();
      g.strokeStyle = angry ? '#ff4d4f' : frac > 0.6 ? '#f2a91f' : '#e8edf2';
      g.beginPath(); g.arc(head.x, head.y, 9, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2); g.stroke();
      if (angry && Math.sin(state.honkPulse * 10) > -0.3) {
        g.fillStyle = '#ff4d4f';
        g.font = '700 13px Overpass, system-ui, sans-serif';
        g.textAlign = 'center';
        g.textBaseline = 'middle';
        g.fillText('!', head.x, head.y + 1);
      }
    }
  }

  // Off-screen queue warning at the edge a lane enters from.
  function drawBacklog(g, lane) {
    if (!lane.pending) return;
    const flash = 0.55 + 0.45 * Math.sin(state.honkPulse * 8);
    const x = 6, y = CY + LANE_OFF;
    g.globalAlpha = flash;
    g.fillStyle = '#e5484d';
    roundRect(g, x, y - 9, 30, 18, 4); g.fill();
    g.globalAlpha = 1;
    g.fillStyle = '#fff';
    g.font = '700 11px "Overpass Mono", ui-monospace, monospace';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.save();
    g.translate(x + 15, y);
    g.rotate(-currentRotation); // keep the text upright
    g.fillText('+' + lane.pending, 0, 1);
    g.restore();
  }
  let currentRotation = 0;

  function render() {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(background, 0, 0);
    ctx.setTransform(scale, 0, 0, scale, 0, 0);

    for (const k of KEYS) {
      ctx.save();
      ctx.translate(CX, CY);
      ctx.rotate(APPROACHES[k].angle);
      ctx.translate(-CX, -CY);
      drawSignalHead(ctx, lightFor(APPROACHES[k].axis));
      ctx.restore();
    }

    for (const k of KEYS) for (const c of state.lanes[k].cars) drawCar(ctx, c, k);

    for (const k of KEYS) {
      ctx.save();
      ctx.translate(CX, CY);
      currentRotation = APPROACHES[k].angle;
      ctx.rotate(currentRotation);
      ctx.translate(-CX, -CY);
      drawBacklog(ctx, state.lanes[k]);
      ctx.restore();
    }
  }

  // ---- HUD ----
  const fmtTime = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
  const LIGHT_TEXT = { green: 'Green', yellow: 'Yellow', red: 'Red' };

  function updateHud() {
    ui.cleared.textContent = state.cleared;
    ui.time.textContent = fmtTime(state.t);
    ui.best.textContent = Math.max(best, state.cleared);
    const p = Math.ceil(state.patience);
    ui.patienceFill.style.width = state.patience + '%';
    ui.patienceValue.textContent = p + '%';
    ui.patienceBar.setAttribute('aria-valuenow', p);
    ui.patienceBar.dataset.level = p > 55 ? 'ok' : p > 25 ? 'warn' : 'bad';
    for (const [node, axis] of [[ui.signalNS, 'NS'], [ui.signalEW, 'EW']]) {
      const light = lightFor(axis);
      node.dataset.light = light;
      node.querySelector('.signal-state').textContent = LIGHT_TEXT[light];
    }
    ui.rush.hidden = !state.rush;
    if (state.rush) ui.rush.textContent = `Rush: ${APPROACHES[state.rush.lane].name.toLowerCase()} traffic`;
    ui.switchBtn.disabled = state.mode !== 'running' || state.signal.phase !== 'green';
    ui.pauseBtn.disabled = state.mode !== 'running' && state.mode !== 'paused';
    ui.pauseBtn.textContent = state.mode === 'paused' ? 'Resume' : 'Pause';
  }

  // ---- Flow ----
  function showOverlay(title, body, button) {
    ui.overlayTitle.textContent = title;
    ui.overlayBody.innerHTML = body;
    ui.startBtn.textContent = button;
    ui.overlay.hidden = false;
  }

  function startShift() {
    state = newState();
    state.mode = 'running';
    ui.overlay.hidden = true;
  }

  function endShift() {
    state.mode = 'over';
    const newBest = state.cleared > best;
    if (newBest) { best = state.cleared; saveBest(best); }
    showOverlay(
      'Shift over',
      `<p>The city ran out of patience after <strong>${fmtTime(state.t)}</strong>.</p>` +
      `<p>You moved <strong>${state.cleared}</strong> cars through the intersection.` +
      (newBest ? ' That is your new best.' : ` Your best is ${best}.`) + '</p>',
      'Start new shift'
    );
  }

  function togglePause() {
    if (state.mode === 'running') {
      state.mode = 'paused';
      showOverlay('Paused', '<p>Traffic is frozen. Resume when you are ready.</p>', 'Resume');
    } else if (state.mode === 'paused') {
      state.mode = 'running';
      ui.overlay.hidden = true;
    }
  }

  ui.startBtn.addEventListener('click', () => {
    if (state.mode === 'paused') togglePause();
    else startShift();
  });
  ui.switchBtn.addEventListener('click', requestSwitch);
  ui.pauseBtn.addEventListener('click', togglePause);
  canvas.addEventListener('pointerdown', e => { e.preventDefault(); requestSwitch(); });
  window.addEventListener('keydown', e => {
    if (e.code === 'Space' || e.code === 'Enter') {
      if (e.target instanceof HTMLButtonElement) return; // let buttons handle their own keys
      e.preventDefault();
      if (state.mode === 'running') requestSwitch();
      else if (state.mode !== 'paused') startShift();
    } else if (e.code === 'KeyP' || e.code === 'Escape') {
      togglePause();
    }
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && state.mode === 'running') togglePause();
  });
  window.addEventListener('resize', resize);

  // ---- Main loop ----
  let last = performance.now();
  function frame(now) {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    if (state.mode === 'running') update(dt);
    render();
    updateHud();
    requestAnimationFrame(frame);
  }

  state = newState();
  // Pre-fill a little traffic so the ready screen shows a live street.
  for (let i = 0; i < 300; i++) { updateSignal(0.02); updateSpawns(0.02); for (const k of KEYS) updateLane(k, 0.02); }
  state.t = 0; state.cleared = 0; state.patience = 100; state.mode = 'ready';
  for (const k of KEYS) for (const c of state.lanes[k].cars) c.wait = 0;

  resize();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(resize);
  requestAnimationFrame(frame);
})();
