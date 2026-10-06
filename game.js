// Intersection Control — run the signals at a city intersection.
// Each level defines the lanes on both streets and the signal groups the
// player controls. Signals do not protect the player: giving green to two
// conflicting groups lets cars drive into each other.
(() => {
  'use strict';

  // ---- World geometry (logical canvas units) ----
  const W = 640, H = 640, CX = W / 2, CY = H / 2, HALF = W / 2;
  const LANE_W = 26;
  const SIDEWALK = 16;
  const CROSSWALK = 18;
  const STOP_GAP = 6;            // space between stop line and crosswalk
  const PAD = 40;                // cars spawn this far off-screen

  // ---- Tuning ----
  const YELLOW_TIME = 2.5;
  const ACCEL = 150, BRAKE = 260, HARD_BRAKE = 520, MIN_GAP = 8;
  const TURN_SPEED = { L: 62, R: 38 };
  const DRAIN_PER_ANGRY = 1.6;   // patience lost per second per honking driver
  const DRAIN_PER_BLOCKED = 4;   // per second per approach backed up off-screen
  const REFILL_PER_CAR = 1.2;
  const CRASH_PATIENCE = 12;
  const MAX_CRASHES = 3;
  const CONFLICT_DIST = 15;      // path centrelines closer than this can collide
  const WRECK_TIME = 5;

  // Travel directions. `d` is the heading; `r` points to the driver's right.
  const DIRS = {
    N: { name: 'Northbound', d: { x: 0, y: -1 }, road: 'NS' },
    S: { name: 'Southbound', d: { x: 0, y: 1 }, road: 'NS' },
    E: { name: 'Eastbound', d: { x: 1, y: 0 }, road: 'EW' },
    W: { name: 'Westbound', d: { x: -1, y: 0 }, road: 'EW' },
  };
  for (const k in DIRS) {
    const d = DIRS[k].d;
    DIRS[k].r = { x: -d.y, y: d.x };
  }
  const DIR_KEYS = Object.keys(DIRS);
  const LEFT_OF = { N: 'W', W: 'S', S: 'E', E: 'N' };
  const RIGHT_OF = { N: 'E', E: 'S', S: 'W', W: 'N' };

  // ---- Levels ----
  // Lane specs list a road's lanes in one direction, inner lane first:
  // L = left-turn lane, T = straight, TR = straight or right.
  const LEVELS = [
    {
      name: 'First Shift', street: 'Main St & 1st Ave',
      lanes: { NS: ['TR'], EW: ['TR'] },
      groups: [
        { label: 'Main St', dirs: ['N', 'S'], move: 'T' },
        { label: '1st Ave', dirs: ['E', 'W'], move: 'T' },
      ],
      goal: 20, rate: { NS: [0.13, 0.2], EW: [0.13, 0.2] }, left: 0, right: 0.15, angry: 9, rush: false,
      intro: 'The signal buttons sit next to the cars they control, and the arrows show which way those cars go. Turn one street red before you turn the other green. If both are green, cars will crash.',
      tip: 'After you switch a street off, wait for the yellow to end and for the last cars to clear the box.',
    },
    {
      name: 'Turn Lanes', street: 'Main St & 1st Ave',
      lanes: { NS: ['L', 'TR'], EW: ['L', 'TR'] },
      groups: [
        { label: 'Main St', dirs: ['N', 'S'], move: 'T' },
        { label: 'Main St', dirs: ['N', 'S'], move: 'L' },
        { label: '1st Ave', dirs: ['E', 'W'], move: 'T' },
        { label: '1st Ave', dirs: ['E', 'W'], move: 'L' },
      ],
      goal: 30, rate: { NS: [0.14, 0.22], EW: [0.14, 0.22] }, left: 0.3, right: 0.12, angry: 15, rush: false,
      intro: 'Both streets now have a left-turn lane with its own arrow. Opposite left turns can go at the same time. A left arrow cannot run with the same street’s straight traffic.',
      tip: 'A signal button with a red ! would conflict with traffic that is still moving.',
    },
    {
      name: 'Main St Widens', street: 'Main St & 2nd Ave',
      lanes: { NS: ['L', 'T', 'TR'], EW: ['L', 'TR'] },
      groups: [
        { label: 'Main St', dirs: ['N', 'S'], move: 'T' },
        { label: 'Main St', dirs: ['N', 'S'], move: 'L' },
        { label: '2nd Ave', dirs: ['E', 'W'], move: 'T' },
        { label: '2nd Ave', dirs: ['E', 'W'], move: 'L' },
      ],
      goal: 45, rate: { NS: [0.22, 0.32], EW: [0.12, 0.2] }, left: 0.25, right: 0.12, angry: 15, rush: false,
      intro: 'Main St gets a second through lane and much more traffic. 2nd Ave is quieter, but its drivers still lose patience.',
      tip: 'Give Main St longer greens and keep the side street’s turns short.',
    },
    {
      name: 'Split Phases', street: 'Main St & 3rd Ave',
      lanes: { NS: ['L', 'T', 'TR'], EW: ['L', 'T', 'TR'] },
      groups: [
        { label: 'Northbound', dirs: ['N'], move: 'T' },
        { label: 'Northbound', dirs: ['N'], move: 'L' },
        { label: 'Southbound', dirs: ['S'], move: 'T' },
        { label: 'Southbound', dirs: ['S'], move: 'L' },
        { label: '3rd Ave', dirs: ['E', 'W'], move: 'T' },
        { label: '3rd Ave', dirs: ['E', 'W'], move: 'L' },
      ],
      goal: 60, rate: { NS: [0.24, 0.34], EW: [0.18, 0.26] }, left: 0.28, right: 0.12, angry: 16, rush: true,
      intro: 'Northbound and southbound Main St have separate controls now. One direction’s straight and left can run together, which clears a long queue quickly. Rush-hour surges start here.',
      tip: 'Northbound straight with northbound left is safe. Northbound left with southbound straight is not.',
    },
    {
      name: 'Downtown Rush', street: 'Main St & Broadway',
      lanes: { NS: ['L', 'T', 'T', 'TR'], EW: ['L', 'T', 'TR'] },
      groups: [
        { label: 'Northbound', dirs: ['N'], move: 'T' },
        { label: 'Northbound', dirs: ['N'], move: 'L' },
        { label: 'Southbound', dirs: ['S'], move: 'T' },
        { label: 'Southbound', dirs: ['S'], move: 'L' },
        { label: 'Eastbound', dirs: ['E'], move: 'T' },
        { label: 'Eastbound', dirs: ['E'], move: 'L' },
        { label: 'Westbound', dirs: ['W'], move: 'T' },
        { label: 'Westbound', dirs: ['W'], move: 'L' },
      ],
      goal: 80, rate: { NS: [0.3, 0.42], EW: [0.22, 0.3] }, left: 0.28, right: 0.12, angry: 16, rush: true,
      intro: 'Every direction and every turn has its own signal. Eight switches, heavy traffic, and frequent rush-hour surges.',
      tip: 'Some combinations across streets are safe too. Watch for the red ! to find the ones that are not.',
    },
  ];

  const CAR_COLORS = ['#e8eef3', '#2c3e57', '#b8372f', '#d6a12b', '#4c7a5a', '#8a96a3', '#1f2328', '#3d6fb0', '#c96b2c'];
  const TRUCK_COLORS = ['#f0f0ea', '#c9cdd1', '#5a6470'];
  const LIGHT_COLOR = { red: '#e5484d', yellow: '#f2a91f', green: '#30c070' };

  const pick = arr => arr[Math.floor(Math.random() * arr.length)];
  const expRand = mean => -Math.log(1 - Math.random()) * mean;
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- Geometry ----
  function buildGeometry(level) {
    const half = { NS: level.lanes.NS.length * LANE_W, EW: level.lanes.EW.length * LANE_W };
    // `cross` is how far the box extends along a direction; `self` is the
    // half-width of the road that direction travels on.
    const ext = k => {
      const road = DIRS[k].road;
      return { cross: half[road === 'NS' ? 'EW' : 'NS'], self: half[road] };
    };
    const paths = [];
    const lamps = [];
    for (const k of DIR_KEYS) {
      const spec = level.lanes[DIRS[k].road];
      spec.forEach((laneSpec, i) => {
        for (const move of laneSpec.split('')) {
          const p = buildPath(level, k, i, move, ext);
          p.group = level.groups.findIndex(g => g.dirs.includes(k) && (g.move === 'L') === (move === 'L'));
          paths.push(p);
        }
        const { d, r } = DIRS[k];
        const e = ext(k);
        const u = -e.cross - CROSSWALK - STOP_GAP + 9, v = LANE_W * (i + 0.5);
        const kind = laneSpec === 'L' ? 'L' : 'T';
        lamps.push({
          dir: k, lane: i, u, v, kind,
          x: CX + d.x * u + r.x * v, y: CY + d.y * u + r.y * v,
          group: level.groups.findIndex(g => g.dirs.includes(k) && (g.move === 'L') === (kind === 'L')),
        });
      });
    }
    const geo = { half, ext, paths, lamps };
    geo.conflicts = computeConflicts(level, paths);
    return geo;
  }

  function buildPath(level, k, i, move, ext) {
    const { d, r } = DIRS[k];
    const e = ext(k);
    const off = LANE_W * (i + 0.5);
    const P = (u, v) => ({ x: CX + d.x * u + r.x * v, y: CY + d.y * u + r.y * v });
    const pts = [P(-(HALF + PAD), off), P(-e.cross, off)];
    let exitDir, exitLane;
    const STEPS = 24;
    if (move === 'T') {
      exitDir = k; exitLane = i;
      pts.push(P(e.cross, off));
    } else if (move === 'L') {
      exitDir = LEFT_OF[k]; exitLane = 0;
      // Quarter ellipse around the far-left corner of the box.
      const a = off + e.self, b = LANE_W * 0.5 + e.cross;
      for (let j = 1; j <= STEPS; j++) {
        const t = (j / STEPS) * Math.PI / 2;
        pts.push(P(-e.cross + b * Math.sin(t), -e.self + a * Math.cos(t)));
      }
    } else {
      exitDir = RIGHT_OF[k];
      exitLane = level.lanes[DIRS[exitDir].road].length - 1;
      // Tight curve around the near-right corner.
      const offX = LANE_W * (exitLane + 0.5);
      const a = e.self - off, b = e.cross - offX;
      for (let j = 1; j <= STEPS; j++) {
        const t = (j / STEPS) * Math.PI / 2;
        pts.push(P(-e.cross + b * Math.sin(t), e.self - a * Math.cos(t)));
      }
    }
    const jEnd = pts.length - 1;
    const exitD = DIRS[exitDir].d;
    const remain = HALF + PAD - ext(exitDir).cross;
    const last = pts[jEnd];
    pts.push({ x: last.x + exitD.x * remain, y: last.y + exitD.y * remain });

    const cum = [0];
    for (let j = 1; j < pts.length; j++) cum.push(cum[j - 1] + dist(pts[j], pts[j - 1]));
    const A = cum[1];
    return {
      dir: k, lane: i, move, pts, cum,
      len: cum[cum.length - 1],
      A,
      exitStart: cum[jEnd],
      stopS: A - CROSSWALK - STOP_GAP,
      laneKey: k + i,
      exitKey: exitDir + exitLane,
    };
  }

  function pointAt(p, s) {
    const cum = p.cum, pts = p.pts, n = pts.length;
    let lo = 0;
    if (s >= cum[n - 2]) lo = n - 2;
    else if (s > 0) {
      let hi = n - 2;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (cum[mid] <= s) lo = mid; else hi = mid - 1;
      }
    }
    const a = pts[lo], b = pts[lo + 1];
    const t = (s - cum[lo]) / (cum[lo + 1] - cum[lo]);
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, angle: Math.atan2(b.y - a.y, b.x - a.x) };
  }

  // Two signal groups conflict if any of their paths come close inside the box.
  function computeConflicts(level, paths) {
    const samples = paths.map(p => {
      const out = [];
      for (let s = p.A - 2; s <= p.exitStart + 12; s += 3) out.push(pointAt(p, s));
      return out;
    });
    const conflicts = level.groups.map(() => new Set());
    for (let i = 0; i < paths.length; i++) {
      for (let j = i + 1; j < paths.length; j++) {
        const p = paths[i], q = paths[j];
        if (p.group === q.group || p.laneKey === q.laneKey) continue;
        if (conflicts[p.group].has(q.group)) continue;
        let hit = false;
        for (const a of samples[i]) {
          for (const b of samples[j]) if (dist(a, b) < CONFLICT_DIST) { hit = true; break; }
          if (hit) break;
        }
        if (hit) { conflicts[p.group].add(q.group); conflicts[q.group].add(p.group); }
      }
    }
    return conflicts;
  }

  // ---- DOM ----
  const canvas = document.getElementById('board');
  const ctx = canvas.getContext('2d');
  const el = id => document.getElementById(id);
  const ui = {
    post: el('post'), level: el('stat-level'), cleared: el('stat-cleared'), goalFill: el('goal-fill'),
    crashes: el('stat-crashes'), time: el('stat-time'),
    patienceFill: el('patience-fill'), patienceValue: el('patience-value'), patienceBar: el('patience-bar'),
    signals: el('signals'), signalButtons: [], rush: el('rush'), overlay: el('overlay'), card: el('overlay-card'),
    pauseBtn: el('pause-btn'), levelsBtn: el('levels-btn'),
    freeplayBar: el('freeplay-bar'), liveDensity: el('live-density'), liveDensityValue: el('live-density-value'),
  };

  // ---- Progress (per browser, optional) ----
  function loadProgress() {
    try {
      const p = JSON.parse(localStorage.getItem('intersection-progress'));
      if (p && typeof p.unlocked === 'number') return { unlocked: p.unlocked, best: p.best || {} };
    } catch { /* storage unavailable */ }
    return { unlocked: 1, best: {} };
  }
  function saveProgress() {
    try { localStorage.setItem('intersection-progress', JSON.stringify(progress)); } catch { /* storage unavailable */ }
  }
  const progress = loadProgress();

  // ---- Game state ----
  let state;
  let geo;

  function newState(levelIndex, level = LEVELS[levelIndex], freeplay = null) {
    geo = buildGeometry(level);
    const spawners = {};
    for (const k of DIR_KEYS) spawners[k] = { timer: Math.random() * 2, pending: [], blockedFor: 0 };
    return {
      levelIndex, level, freeplay,
      mode: 'intro', // intro | running | paused | won | lost
      t: 0, cleared: 0, crashes: 0, patience: 100,
      groups: level.groups.map((g, i) => ({ ...g, state: i === 0 ? 'green' : 'red', timer: 0, cycle: 0, busy: 0 })),
      cars: [], wrecks: [], particles: [], flashes: [],
      spawners,
      rush: null, nextRush: 25,
      shake: 0, pulse: 0,
      failAt: null, failReason: '',
      hover: -1,
    };
  }

  function prefill() {
    for (let i = 0; i < 350; i++) step(0.02, true);
    state.t = 0; state.cleared = 0; state.patience = 100;
    for (const c of state.cars) c.wait = 0;
  }

  // ---- Signals ----
  function toggleGroup(i) {
    if (state.mode !== 'running' || state.failAt !== null) return;
    const g = state.groups[i];
    if (!g) return;
    if (g.state === 'green') { g.state = 'yellow'; g.timer = 0; g.cycle++; }
    else if (g.state === 'red') g.state = 'green';
  }

  function updateGroups(dt) {
    for (const g of state.groups) {
      if (g.state !== 'yellow') continue;
      g.timer += dt;
      if (g.timer >= YELLOW_TIME) g.state = 'red';
    }
  }

  // ---- Traffic generation ----
  function laneRate(k) {
    const [r0, r1] = state.level.rate[DIRS[k].road];
    const prog = Math.min(1, state.cleared / state.level.goal);
    const base = r0 + (r1 - r0) * prog;
    return state.rush && state.rush.dir === k ? base * 2.4 : base;
  }

  function pickMove(k) {
    const spec = state.level.lanes[DIRS[k].road];
    if (spec.includes('L') && Math.random() < state.level.left) return 'L';
    return Math.random() < state.level.right ? 'R' : 'T';
  }

  function makeCar(path) {
    const truck = Math.random() < 0.12;
    return {
      path, s: 0, v: 0,
      len: truck ? 38 : 22 + Math.random() * 6,
      wid: truck ? 17 : 14,
      maxV: truck ? 78 + Math.random() * 10 : 95 + Math.random() * 30,
      color: truck ? pick(TRUCK_COLORS) : pick(CAR_COLORS),
      truck, wait: 0, commit: -1,
    };
  }

  function updateSpawns(dt, tails) {
    for (const k of DIR_KEYS) {
      const sp = state.spawners[k];
      sp.timer -= dt;
      if (sp.timer <= 0) {
        if (sp.pending.length < 10) sp.pending.push(pickMove(k));
        sp.timer = expRand(1 / laneRate(k));
      }
      if (!sp.pending.length) { sp.blockedFor = 0; continue; }

      // Pick the emptiest lane that allows the next driver's movement.
      const move = sp.pending[0];
      let best = null, bestRoom = 4;
      for (const p of geo.paths) {
        if (p.dir !== k || p.move !== move) continue;
        const room = tails[p.laneKey] === undefined ? Infinity : tails[p.laneKey] - MIN_GAP;
        if (room > bestRoom) { best = p; bestRoom = room; }
      }
      if (best) {
        const car = makeCar(best);
        car.v = Math.min(car.maxV, Math.sqrt(2 * BRAKE * Math.max(0, bestRoom)));
        state.cars.push(car);
        tails[best.laneKey] = -car.len;
        sp.pending.shift();
        sp.blockedFor = 0;
      } else {
        sp.blockedFor += dt;
      }
    }

    if (!state.level.rush) return;
    if (state.rush && state.t >= state.rush.until) state.rush = null;
    if (!state.rush && state.t >= state.nextRush) {
      state.rush = { dir: pick(DIR_KEYS), until: state.t + 12 };
      state.nextRush = state.t + 22 + Math.random() * 10;
    }
  }

  // ---- Driving ----
  function updateCars(dt) {
    // Index cars by the approach lane and exit lane they share with others.
    const byLane = {}, byExit = {};
    for (const c of state.cars) {
      (byLane[c.path.laneKey] ||= []).push(c);
      (byExit[c.path.exitKey] ||= []).push(c);
    }

    for (const c of state.cars) {
      const p = c.path;
      let vMax = c.maxV;

      // Slow down for the turn.
      const tv = TURN_SPEED[p.move];
      if (tv && c.s < p.exitStart) vMax = Math.min(vMax, Math.sqrt(tv * tv + 2 * BRAKE * Math.max(0, p.A - c.s)));

      // Gap to whoever is ahead in the same approach lane or exit lane.
      let gap = Infinity;
      for (const o of byLane[p.laneKey]) {
        if (o === c || o.s <= c.s) continue;
        if (o.path !== p && o.s - o.len >= p.A + 2) continue; // went a different way
        gap = Math.min(gap, o.s - o.len - c.s);
      }
      const ec = c.s - p.exitStart;
      for (const o of byExit[p.exitKey]) {
        if (o === c) continue;
        const eo = o.s - o.path.exitStart;
        if (eo <= ec || (o.path !== p && eo <= 0)) continue;
        gap = Math.min(gap, eo - o.len - ec);
      }
      // Stop short of wrecks on the road ahead.
      if (state.wrecks.length && c.s < p.len) {
        for (const w of state.wrecks) {
          for (let q = 6; q <= 72; q += 6) {
            if (dist(pointAt(p, c.s + q), w) < 16) { gap = Math.min(gap, q - 10); break; }
          }
        }
      }
      vMax = Math.min(vMax, Math.sqrt(2 * BRAKE * Math.max(0, gap - MIN_GAP)));

      // Obey the signal while still before the stop line.
      let mustStop = false;
      const g = state.groups[p.group];
      if (c.s <= p.stopS && g.state !== 'green' && c.commit !== g.cycle) {
        const d = p.stopS - c.s;
        if (g.state === 'yellow' && (c.v * c.v) / (2 * HARD_BRAKE) > d) {
          c.commit = g.cycle; // too close to stop: clear the intersection
        } else {
          mustStop = true;
          vMax = Math.min(vMax, Math.sqrt(2 * BRAKE * d));
        }
      }

      if (c.v < vMax) c.v = Math.min(vMax, c.v + ACCEL * dt);
      else c.v = Math.max(vMax, c.v - HARD_BRAKE * 1.5 * dt);
      const before = c.s;
      c.s += c.v * dt;
      if (mustStop && before <= p.stopS && c.s > p.stopS) { c.s = p.stopS; c.v = 0; }

      if (c.v < 4 && c.s <= p.stopS + 1) c.wait += dt;
    }

    // Cars that left the map count as cleared.
    const keep = [];
    for (const c of state.cars) {
      if (c.s - c.len > c.path.len) {
        state.cleared++;
        state.patience = Math.min(100, state.patience + REFILL_PER_CAR);
      } else keep.push(c);
    }
    state.cars = keep;
  }

  function laneTails() {
    // Rear position of the last car in each approach lane.
    const tails = {};
    for (const c of state.cars) {
      const rear = c.s - c.len;
      const k = c.path.laneKey;
      if (rear < c.path.A && (tails[k] === undefined || rear < tails[k])) tails[k] = rear;
    }
    return tails;
  }

  // ---- Crashes ----
  function bodyCircles(c) {
    const r = c.wid / 2 - 1;
    return [0.18, 0.5, 0.82].map(f => { const pt = pointAt(c.path, c.s - c.len * f); pt.r = r; return pt; });
  }

  function detectCrashes() {
    const zone = state.cars.filter(c => c.s > c.path.A - 6 && c.s - c.len < c.path.exitStart + 6);
    const circles = zone.map(bodyCircles);
    const hit = new Set();
    for (let i = 0; i < zone.length; i++) {
      for (let j = i + 1; j < zone.length; j++) {
        const a = zone[i], b = zone[j];
        if (a.path === b.path || a.path.laneKey === b.path.laneKey) continue;
        if (hit.has(a) || hit.has(b)) continue;
        let touch = false;
        for (const ca of circles[i]) {
          for (const cb of circles[j]) if (dist(ca, cb) < ca.r + cb.r) { touch = true; break; }
          if (touch) break;
        }
        if (touch) { hit.add(a); hit.add(b); crash(a, b); }
      }
    }
    if (hit.size) state.cars = state.cars.filter(c => !hit.has(c));
  }

  function crash(a, b) {
    const poses = [a, b].map(c => ({ c, pose: pointAt(c.path, c.s - c.len / 2) }));
    const mid = { x: (poses[0].pose.x + poses[1].pose.x) / 2, y: (poses[0].pose.y + poses[1].pose.y) / 2 };
    for (const { c, pose } of poses) {
      const push = c.v * 0.55;
      state.wrecks.push({
        x: pose.x, y: pose.y, angle: pose.angle,
        vx: Math.cos(pose.angle) * push, vy: Math.sin(pose.angle) * push,
        spin: (Math.random() < 0.5 ? -1 : 1) * (2 + Math.random() * 4),
        len: c.len, wid: c.wid, color: c.color, truck: c.truck,
        t: 0, smokeTimer: 0,
      });
    }
    for (let i = 0; i < 26; i++) {
      const ang = Math.random() * Math.PI * 2, sp = 90 + Math.random() * 220;
      state.particles.push({ kind: 'spark', x: mid.x, y: mid.y, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp, life: 0, max: 0.3 + Math.random() * 0.5 });
    }
    for (let i = 0; i < 12; i++) {
      const ang = Math.random() * Math.PI * 2, sp = 40 + Math.random() * 110;
      state.particles.push({
        kind: 'debris', x: mid.x, y: mid.y, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
        life: 0, max: 1.6 + Math.random(), size: 2 + Math.random() * 3,
        color: pick([a.color, b.color, '#cfd6dc', '#1c2126']), rot: Math.random() * 6, spin: (Math.random() - 0.5) * 12,
      });
    }
    state.flashes.push({ x: mid.x, y: mid.y, t: 0 });
    state.shake = reducedMotion ? 0 : 0.5;
    state.crashes++;
    state.patience = Math.max(0, state.patience - CRASH_PATIENCE);
    if (hasLimits() && state.crashes >= MAX_CRASHES && state.failAt === null) {
      state.failAt = state.t + 1.8;
      state.failReason = `${MAX_CRASHES} crashes. The city pulled you off signal duty.`;
    }
  }

  function updateEffects(dt) {
    for (const w of state.wrecks) {
      w.t += dt;
      w.x += w.vx * dt; w.y += w.vy * dt;
      const f = Math.exp(-4 * dt);
      w.vx *= f; w.vy *= f;
      w.angle += w.spin * dt;
      w.spin *= Math.exp(-3 * dt);
      w.smokeTimer -= dt;
      if (w.t < 3.5 && w.smokeTimer <= 0) {
        w.smokeTimer = 0.14;
        state.particles.push({
          kind: 'smoke', x: w.x + (Math.random() - 0.5) * 8, y: w.y + (Math.random() - 0.5) * 8,
          vx: 6 + Math.random() * 8, vy: -8 - Math.random() * 8, life: 0, max: 1.4 + Math.random() * 0.6,
        });
      }
    }
    state.wrecks = state.wrecks.filter(w => w.t < WRECK_TIME);

    for (const p of state.particles) {
      p.life += dt;
      p.x += p.vx * dt; p.y += p.vy * dt;
      const drag = p.kind === 'spark' ? 3 : p.kind === 'debris' ? 4 : 0.6;
      const f = Math.exp(-drag * dt);
      p.vx *= f; p.vy *= f;
      if (p.rot !== undefined) { p.rot += p.spin * dt; p.spin *= f; }
    }
    state.particles = state.particles.filter(p => p.life < p.max);
    for (const fl of state.flashes) fl.t += dt;
    state.flashes = state.flashes.filter(fl => fl.t < 1.4);
    state.shake = Math.max(0, state.shake - dt);
  }

  // ---- Patience, busy groups, win/lose ----
  const hasLimits = () => !state.freeplay || state.freeplay.limits;
  const isAngry = c => c.wait > state.level.angry && c.s <= c.path.stopS + 1;

  function updateStatus(dt) {
    for (const g of state.groups) g.busy = 0;
    let angry = 0;
    for (const c of state.cars) {
      const p = c.path;
      if (c.s > p.stopS + 0.5 && c.s - c.len < p.exitStart) state.groups[p.group].busy++;
      if (isAngry(c)) angry++;
    }
    let blocked = 0;
    for (const k of DIR_KEYS) if (state.spawners[k].blockedFor > 1) blocked++;
    state.patience -= (angry * DRAIN_PER_ANGRY + blocked * DRAIN_PER_BLOCKED) * dt;
    if (!hasLimits()) { state.patience = Math.max(0, state.patience); return; }

    if (state.failAt === null) {
      if (state.patience <= 0) {
        state.patience = 0;
        state.failAt = state.t + 0.3;
        state.failReason = 'Drivers waited too long and the city ran out of patience.';
      } else if (state.cleared >= state.level.goal) {
        winLevel();
      }
    }
    if (state.failAt !== null && state.t >= state.failAt) loseLevel();
  }

  function step(dt, quiet) {
    state.t += dt;
    state.pulse += dt;
    updateGroups(dt);
    updateSpawns(dt, laneTails());
    updateCars(dt);
    if (!quiet) {
      detectCrashes();
      updateEffects(dt);
      updateStatus(dt);
    }
  }

  // ---- Rendering ----
  let scale = 1;
  const background = document.createElement('canvas');

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const size = canvas.getBoundingClientRect().width;
    if (!size) return;
    canvas.width = Math.round(size * dpr);
    canvas.height = Math.round(size * dpr);
    scale = (size * dpr) / W;
    background.width = canvas.width;
    background.height = canvas.height;
    drawBackground(background.getContext('2d'));
  }

  function seeded(seed) {
    return () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
  }

  // Local frame for one approach: +u is the direction of travel, +v is the driver's right.
  function approachFrame(g, k) {
    const { d, r } = DIRS[k];
    g.transform(d.x, d.y, r.x, r.y, CX, CY);
  }

  function drawBackground(g) {
    g.setTransform(scale, 0, 0, scale, 0, 0);
    const rnd = seeded(7 + state.levelIndex * 13);
    const hN = geo.half.NS, hE = geo.half.EW;

    g.fillStyle = '#9da5ad';
    g.fillRect(0, 0, W, H);

    const left = CX - hN - SIDEWALK, right = CX + hN + SIDEWALK;
    const top = CY - hE - SIDEWALK, bottom = CY + hE + SIDEWALK;
    drawBuildings(g, 0, 0, left, top, rnd);
    drawBuildings(g, right, 0, W - right, top, rnd);
    drawPark(g, 0, bottom, left, H - bottom, rnd);
    drawCompass(g, 26, H - 30);
    drawBuildings(g, right, bottom, W - right, H - bottom, rnd);

    // Sidewalk joints.
    g.strokeStyle = 'rgba(40, 48, 56, 0.18)';
    g.lineWidth = 1;
    for (let p = 0; p < W; p += 16) {
      for (const x of [left, CX + hN]) { g.beginPath(); g.moveTo(x, p); g.lineTo(x + SIDEWALK, p); g.stroke(); }
      for (const y of [top, CY + hE]) { g.beginPath(); g.moveTo(p, y); g.lineTo(p, y + SIDEWALK); g.stroke(); }
    }

    g.fillStyle = '#3a4048';
    g.fillRect(CX - hN, 0, hN * 2, H);
    g.fillRect(0, CY - hE, W, hE * 2);

    g.strokeStyle = '#c7ccd1';
    g.lineWidth = 2;
    const ex = hN + 1, ey = hE + 1;
    for (const [x1, y1, x2, y2] of [
      [CX - ex, 0, CX - ex, CY - ey], [CX + ex, 0, CX + ex, CY - ey],
      [CX - ex, CY + ey, CX - ex, H], [CX + ex, CY + ey, CX + ex, H],
      [0, CY - ey, CX - ex, CY - ey], [0, CY + ey, CX - ex, CY + ey],
      [CX + ex, CY - ey, W, CY - ey], [CX + ex, CY + ey, W, CY + ey],
    ]) { g.beginPath(); g.moveTo(x1, y1); g.lineTo(x2, y2); g.stroke(); }

    for (const k of DIR_KEYS) {
      g.save();
      approachFrame(g, k);
      drawApproachMarkings(g, k);
      g.restore();
    }
  }

  function drawApproachMarkings(g, k) {
    const e = geo.ext(k);
    const spec = state.level.lanes[DIRS[k].road];
    const uStop = -e.cross - CROSSWALK - STOP_GAP;
    const far = -(HALF + PAD);

    // Double yellow centre line.
    g.fillStyle = '#e3b23c';
    g.fillRect(far, -2.5, uStop + 4 - far, 1.6);
    g.fillRect(far, 0.9, uStop + 4 - far, 1.6);

    // Lane lines: solid beside a turn lane, dashed between through lanes.
    g.fillStyle = '#eef0ea';
    for (let j = 1; j < spec.length; j++) {
      const v = LANE_W * j - 1;
      if (spec[j - 1] === 'L') g.fillRect(uStop - 150, v, 150, 2);
      for (let u = far; u < (spec[j - 1] === 'L' ? uStop - 150 : uStop); u += 24) g.fillRect(u, v, 12, 2);
      for (let u = far; u < uStop + 8; u += 24) g.fillRect(u, -LANE_W * j - 1, 12, 2);
    }

    // Stop line and crosswalk.
    g.fillRect(uStop + 1, 2, 4, e.self - 2);
    for (let v = -e.self + 3; v < e.self - 3; v += 8) g.fillRect(-e.cross - CROSSWALK + 2, v, CROSSWALK - 4, 4);

    // Painted lane arrows.
    g.strokeStyle = 'rgba(238, 240, 234, 0.85)';
    g.fillStyle = 'rgba(238, 240, 234, 0.85)';
    g.lineWidth = 2.5;
    spec.forEach((laneSpec, i) => drawLaneArrow(g, uStop - 46, LANE_W * (i + 0.5), laneSpec));
  }

  function drawLaneArrow(g, u, v, spec) {
    const head = (x, y, dx, dy) => {
      g.beginPath();
      g.moveTo(x + dx * 6, y + dy * 6);
      g.lineTo(x - dy * 4, y + dx * 4);
      g.lineTo(x + dy * 4, y - dx * 4);
      g.closePath(); g.fill();
    };
    g.beginPath();
    if (spec === 'L') {
      g.moveTo(u - 12, v); g.lineTo(u + 4, v); g.lineTo(u + 4, v - 6);
      g.stroke(); head(u + 4, v - 6, 0, -1);
    } else {
      g.moveTo(u - 12, v); g.lineTo(u + 8, v);
      g.stroke(); head(u + 8, v, 1, 0);
      if (spec.includes('R')) {
        g.beginPath(); g.moveTo(u - 2, v); g.lineTo(u - 2, v + 6); g.stroke();
        head(u - 2, v + 6, 0, 1);
      }
    }
  }

  function drawBuildings(g, x, y, w, h, rnd) {
    g.fillStyle = '#7d858d';
    g.fillRect(x, y, w, h);
    const roofs = ['#5b6670', '#6f6a63', '#4f5a52', '#73665f', '#56606b'];
    const split = 0.4 + rnd() * 0.2;
    let cx = x;
    for (const cw of [w * split, w * (1 - split)]) {
      const rows = 1 + Math.floor(rnd() * 2);
      let cy = y;
      for (let r = 0; r < rows; r++) {
        const ch = rows === 1 ? h : r === 0 ? h * (0.4 + rnd() * 0.2) : h - (cy - y);
        const bx = cx + 4, by = cy + 4, bw = cw - 8, bh = ch - 8;
        if (bw > 8 && bh > 8) {
          g.fillStyle = roofs[Math.floor(rnd() * roofs.length)];
          g.fillRect(bx, by, bw, bh);
          g.strokeStyle = 'rgba(255, 255, 255, 0.12)';
          g.lineWidth = 2;
          g.strokeRect(bx + 3, by + 3, bw - 6, bh - 6);
          const units = 1 + Math.floor(rnd() * 3);
          for (let u = 0; u < units; u++) {
            const uw = Math.min(bw - 12, 12 + rnd() * 18), uh = Math.min(bh - 12, 10 + rnd() * 14);
            if (uw < 4 || uh < 4) continue;
            const ux = bx + 6 + rnd() * Math.max(1, bw - uw - 12);
            const uy = by + 6 + rnd() * Math.max(1, bh - uh - 12);
            g.fillStyle = 'rgba(20, 24, 28, 0.25)';
            g.fillRect(ux + 3, uy + 3, uw, uh);
            g.fillStyle = '#a9b0b6';
            g.fillRect(ux, uy, uw, uh);
          }
        }
        cy += ch;
      }
      cx += cw;
    }
  }

  function drawPark(g, x, y, w, h, rnd) {
    g.fillStyle = '#5d7d4f';
    g.fillRect(x, y, w, h);
    g.strokeStyle = '#b8b09c';
    g.lineWidth = 8;
    g.beginPath();
    g.moveTo(x + w, y + 10);
    g.quadraticCurveTo(x + w * 0.45, y + h * 0.4, x + 10, y + h);
    g.stroke();
    const trees = Math.round((w * h) / 2000);
    for (let i = 0; i < trees; i++) {
      const tx = x + 12 + rnd() * Math.max(1, w - 24), ty = y + 12 + rnd() * Math.max(1, h - 24);
      const r = 7 + rnd() * 9;
      g.fillStyle = 'rgba(20, 30, 18, 0.3)';
      g.beginPath(); g.arc(tx + 3, ty + 3, r, 0, Math.PI * 2); g.fill();
      g.fillStyle = rnd() < 0.5 ? '#3f6a3a' : '#4b7a43';
      g.beginPath(); g.arc(tx, ty, r, 0, Math.PI * 2); g.fill();
    }
  }

  function drawCompass(g, x, y) {
    g.fillStyle = 'rgba(22, 27, 33, 0.75)';
    g.beginPath(); g.arc(x, y, 16, 0, Math.PI * 2); g.fill();
    g.fillStyle = '#e5484d';
    g.beginPath(); g.moveTo(x, y - 11); g.lineTo(x + 5, y + 1); g.lineTo(x - 5, y + 1); g.closePath(); g.fill();
    g.fillStyle = '#e8edf2';
    g.beginPath(); g.moveTo(x, y + 11); g.lineTo(x + 5, y + 1); g.lineTo(x - 5, y + 1); g.closePath(); g.fill();
    g.font = '800 11px Overpass, system-ui, sans-serif';
    g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillStyle = '#e8edf2';
    g.fillText('N', x, y - 23);
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

  function drawLamps(g) {
    for (const lamp of geo.lamps) {
      const color = LIGHT_COLOR[state.groups[lamp.group].state];
      g.save();
      approachFrame(g, lamp.dir);
      if (state.hover === lamp.group) {
        g.fillStyle = 'rgba(242, 169, 31, 0.22)';
        g.fillRect(lamp.u - 110, lamp.v - LANE_W / 2 + 2, 110, LANE_W - 4);
      }
      g.fillStyle = '#15181c';
      g.beginPath(); g.arc(lamp.u, lamp.v, 6.5, 0, Math.PI * 2); g.fill();
      g.fillStyle = color;
      if (lamp.kind === 'L') {
        // Arrow pointing toward the driver's left (-v).
        g.beginPath();
        g.moveTo(lamp.u, lamp.v - 5);
        g.lineTo(lamp.u + 4.5, lamp.v - 0.5);
        g.lineTo(lamp.u - 4.5, lamp.v - 0.5);
        g.closePath(); g.fill();
        g.fillRect(lamp.u - 1.6, lamp.v - 1, 3.2, 5);
      } else {
        g.beginPath(); g.arc(lamp.u, lamp.v, 4.2, 0, Math.PI * 2); g.fill();
      }
      g.restore();
    }
  }

  function drawCarBody(g, x, y, angle, c, wrecked) {
    g.save();
    g.translate(x, y);
    g.rotate(angle);
    const L = c.len, Wd = c.wid;
    g.fillStyle = 'rgba(0, 0, 0, 0.3)';
    roundRect(g, -L / 2 + 2, -Wd / 2 + 2, L, Wd, 4); g.fill();
    g.fillStyle = c.color;
    roundRect(g, -L / 2, -Wd / 2, L, Wd, c.truck ? 2 : 5); g.fill();
    if (c.truck) {
      g.fillStyle = 'rgba(0, 0, 0, 0.18)';
      g.fillRect(-L / 2 + 2, -Wd / 2 + 2, L - 14, Wd - 4);
      g.fillStyle = '#2a3a4a';
      g.fillRect(L / 2 - 8, -Wd / 2 + 2, 4, Wd - 4);
    } else {
      g.fillStyle = '#26323e';
      g.fillRect(L * 0.1, -Wd / 2 + 2, L * 0.18, Wd - 4);
      g.fillRect(-L * 0.36, -Wd / 2 + 2.5, L * 0.12, Wd - 5);
    }
    if (wrecked) {
      // Crumpled front and scorch.
      g.fillStyle = 'rgba(20, 20, 20, 0.45)';
      roundRect(g, -L / 2, -Wd / 2, L, Wd, 4); g.fill();
      g.strokeStyle = 'rgba(255, 255, 255, 0.5)';
      g.lineWidth = 1.2;
      g.beginPath();
      g.moveTo(L / 2 - 6, -Wd / 2 + 1); g.lineTo(L / 2 - 2, -2); g.lineTo(L / 2 - 7, 2); g.lineTo(L / 2 - 3, Wd / 2 - 1);
      g.stroke();
    } else if (c.v < c.maxV * 0.5) {
      g.fillStyle = '#ff3b3b';
      g.fillRect(-L / 2, -Wd / 2 + 1, 2, 3);
      g.fillRect(-L / 2, Wd / 2 - 4, 2, 3);
    }
    g.restore();
  }

  function drawWaitRing(g, c) {
    const angryAfter = state.level.angry;
    if (c.wait <= angryAfter * 0.3 || c.s > c.path.stopS + 1) return;
    const at = pointAt(c.path, c.s - c.len / 2);
    const frac = Math.min(1, c.wait / angryAfter);
    g.lineWidth = 2.5;
    g.strokeStyle = 'rgba(0, 0, 0, 0.45)';
    g.beginPath(); g.arc(at.x, at.y, 8, 0, Math.PI * 2); g.stroke();
    g.strokeStyle = frac >= 1 ? '#ff4d4f' : frac > 0.6 ? '#f2a91f' : '#e8edf2';
    g.beginPath(); g.arc(at.x, at.y, 8, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2); g.stroke();
    if (frac >= 1 && Math.sin(state.pulse * 10) > -0.3) {
      g.fillStyle = '#ff4d4f';
      g.font = '700 12px Overpass, system-ui, sans-serif';
      g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText('!', at.x, at.y + 1);
    }
  }

  function drawEffects(g) {
    for (const p of state.particles) {
      const k = 1 - p.life / p.max;
      if (p.kind === 'smoke') {
        const r = 5 + (p.life / p.max) * 16;
        g.fillStyle = `rgba(60, 64, 70, ${0.45 * k})`;
        g.beginPath(); g.arc(p.x, p.y, r, 0, Math.PI * 2); g.fill();
      } else if (p.kind === 'spark') {
        g.strokeStyle = `rgba(255, ${190 + Math.round(60 * k)}, 90, ${k})`;
        g.lineWidth = 1.6;
        g.beginPath(); g.moveTo(p.x, p.y); g.lineTo(p.x - p.vx * 0.04, p.y - p.vy * 0.04); g.stroke();
      } else {
        g.save();
        g.globalAlpha = Math.min(1, k * 2);
        g.translate(p.x, p.y); g.rotate(p.rot);
        g.fillStyle = p.color;
        g.fillRect(-p.size / 2, -p.size / 2, p.size, p.size);
        g.restore();
      }
    }
    for (const fl of state.flashes) {
      if (fl.t < 0.3) {
        const k = fl.t / 0.3;
        g.fillStyle = `rgba(255, 244, 214, ${0.85 * (1 - k)})`;
        g.beginPath(); g.arc(fl.x, fl.y, 10 + k * 40, 0, Math.PI * 2); g.fill();
      }
      const pop = Math.min(1, fl.t / 0.15);
      const alpha = fl.t > 1 ? 1 - (fl.t - 1) / 0.4 : 1;
      g.save();
      g.globalAlpha = Math.max(0, alpha);
      g.translate(fl.x, fl.y - 30 - fl.t * 10);
      g.scale(0.6 + 0.4 * pop, 0.6 + 0.4 * pop);
      g.font = '800 22px Overpass, system-ui, sans-serif';
      g.textAlign = 'center'; g.textBaseline = 'middle';
      g.lineWidth = 4;
      g.strokeStyle = '#161b21';
      g.strokeText('CRASH', 0, 0);
      g.fillStyle = '#e5484d';
      g.fillText('CRASH', 0, 0);
      g.restore();
    }
  }

  function drawBacklog(g) {
    for (const k of DIR_KEYS) {
      const sp = state.spawners[k];
      if (sp.blockedFor <= 1 || !sp.pending.length) continue;
      const { d, r } = DIRS[k];
      const u = -HALF + 44, v = geo.ext(k).self / 2;
      const x = CX + d.x * u + r.x * v, y = CY + d.y * u + r.y * v;
      g.globalAlpha = 0.55 + 0.45 * Math.sin(state.pulse * 8);
      g.fillStyle = '#e5484d';
      roundRect(g, x - 15, y - 9, 30, 18, 4); g.fill();
      g.globalAlpha = 1;
      g.fillStyle = '#fff';
      g.font = '700 11px "Overpass Mono", ui-monospace, monospace';
      g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText('+' + sp.pending.length, x, y + 1);
    }
  }

  function render() {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#161b21';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    let sx = 0, sy = 0;
    if (state.shake > 0) {
      const amp = 7 * (state.shake / 0.5);
      sx = (Math.random() - 0.5) * amp * scale; sy = (Math.random() - 0.5) * amp * scale;
    }
    ctx.drawImage(background, sx, sy);
    ctx.setTransform(scale, 0, 0, scale, sx, sy);

    drawLamps(ctx);
    for (const c of state.cars) {
      const at = pointAt(c.path, c.s - c.len / 2);
      drawCarBody(ctx, at.x, at.y, at.angle, c, false);
    }
    for (const w of state.wrecks) {
      ctx.globalAlpha = w.t > WRECK_TIME - 0.8 ? (WRECK_TIME - w.t) / 0.8 : 1;
      drawCarBody(ctx, w.x, w.y, w.angle, w, true);
      ctx.globalAlpha = 1;
    }
    drawEffects(ctx);
    for (const c of state.cars) drawWaitRing(ctx, c);
    drawBacklog(ctx);
    drawStreetSigns(ctx);
  }

  // Green street-name plates at the map edges, over each street.
  function drawStreetSigns(g) {
    const names = streetNames();
    g.font = '800 12px Overpass, system-ui, sans-serif';
    const plate = (text, x, y, anchor) => {
      const w = g.measureText(text).width + 16, h = 20;
      const x0 = anchor === 'left' ? x : x - w / 2, y0 = y - h / 2;
      x = x0 + w / 2;
      g.fillStyle = 'rgba(0, 0, 0, 0.35)';
      roundRect(g, x0 + 2, y0 + 2, w, h, 3); g.fill();
      g.fillStyle = '#1d6b46';
      roundRect(g, x0, y0, w, h, 3); g.fill();
      g.strokeStyle = 'rgba(232, 241, 234, 0.8)';
      g.lineWidth = 1;
      roundRect(g, x0 + 2, y0 + 2, w - 4, h - 4, 2); g.stroke();
      g.fillStyle = '#f2f6f3';
      g.textAlign = 'center'; g.textBaseline = 'middle';
      g.fillText(text, x, y + 1);
    };
    plate(names.NS.toUpperCase(), CX, 16);
    plate(names.EW.toUpperCase(), 8, CY, 'left');
  }

  // ---- Controls ----
  // Each approach gets its own cluster of signal buttons, placed on the block
  // beside the waiting line, with arrows pointing the way those cars drive.
  const GLYPH = {
    T: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 17V4M5 9l5-5 5 5"/></svg>',
    L: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M14 17v-6a3 3 0 0 0-3-3H5M8.5 4.5 5 8l3.5 3.5"/></svg>',
  };
  const ROTATE = { N: 0, E: 90, S: 180, W: -90 };

  function streetNames() {
    const [ns, ew] = state.level.street.split(' & ');
    return { NS: ns, EW: ew };
  }

  function buildControls() {
    const names = streetNames();
    const clusters = DIR_KEYS.map(k => {
      const { d, r } = DIRS[k];
      const e = geo.ext(k);
      // Corner of the block on the driver's right, just before the intersection.
      const u = -e.cross - SIDEWALK, v = e.self + SIDEWALK;
      const x = CX + d.x * u + r.x * v, y = CY + d.y * u + r.y * v;
      const ex = Math.sign(-d.x + r.x), ey = Math.sign(-d.y + r.y);
      const groups = [];
      for (const lamp of geo.lamps) {
        if (lamp.dir === k && !groups.includes(lamp.group)) groups.push(lamp.group);
      }
      groups.sort((a, b) => (state.groups[a].move === 'L' ? -1 : 1) - (state.groups[b].move === 'L' ? -1 : 1));
      const buttons = groups.map(i => {
        const g = state.groups[i];
        const what = g.move === 'L' ? 'left turn' : 'straight and right';
        return `<button class="map-sig" type="button" data-group="${i}" data-light="${g.state}"
            aria-label="${names[DIRS[k].road]} ${DIRS[k].name.toLowerCase()} ${what}, key ${i + 1}" title="${DIRS[k].name} ${what} (key ${i + 1})">
          <span class="arrow" style="transform: rotate(${ROTATE[k]}deg)">${GLYPH[g.move]}</span>
          <span class="key" aria-hidden="true">${i + 1}</span>
        </button>`;
      }).join('');
      return `<div class="cluster" data-x="${ex > 0 ? 'right' : 'left'}" data-y="${ey > 0 ? 'down' : 'up'}"
          style="left: ${(x / W) * 100}%; top: ${(y / H) * 100}%">
        <span class="cluster-name">${DIRS[k].name}</span>
        <div class="cluster-buttons">${buttons}</div>
      </div>`;
    });
    ui.signals.innerHTML = clusters.join('');
    ui.signalButtons = [...ui.signals.querySelectorAll('.map-sig')];
  }

  function isUnsafe(i) {
    for (const j of geo.conflicts[i]) {
      const o = state.groups[j];
      if (o.state !== 'red' || o.busy > 0) return true;
    }
    return false;
  }

  // ---- HUD ----
  const fmtTime = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;

  function updateHud() {
    const lvl = state.level;
    const fp = state.freeplay;
    ui.level.textContent = fp ? 'Freeplay' : `${state.levelIndex + 1}. ${lvl.name}`;
    ui.post.textContent = lvl.street;
    ui.cleared.textContent = fp ? String(state.cleared) : `${Math.min(state.cleared, lvl.goal)} / ${lvl.goal}`;
    ui.goalFill.style.width = fp ? '0%' : Math.min(100, (state.cleared / lvl.goal) * 100) + '%';
    ui.crashes.textContent = hasLimits() ? `${state.crashes} / ${MAX_CRASHES}` : String(state.crashes);
    ui.crashes.dataset.level = state.crashes === 0 ? 'ok' : !hasLimits() || state.crashes < MAX_CRASHES - 1 ? 'warn' : 'bad';
    ui.freeplayBar.hidden = !fp;
    if (fp) ui.liveDensityValue.textContent = densityName(fp.density);
    ui.time.textContent = fmtTime(state.t);
    const p = Math.ceil(state.patience);
    ui.patienceFill.style.width = state.patience + '%';
    ui.patienceValue.textContent = p + '%';
    ui.patienceBar.setAttribute('aria-valuenow', p);
    ui.patienceBar.dataset.level = p > 55 ? 'ok' : p > 25 ? 'warn' : 'bad';

    const live = state.mode === 'running' && state.failAt === null;
    const unsafe = state.groups.map((g, i) => live && g.state === 'red' && isUnsafe(i));
    for (const btn of ui.signalButtons) {
      const i = Number(btn.dataset.group);
      const g = state.groups[i];
      btn.dataset.light = g.state;
      btn.dataset.unsafe = unsafe[i] ? 'true' : 'false';
      btn.dataset.hover = state.hover === i ? 'true' : 'false';
      btn.disabled = !live || g.state === 'yellow';
    }

    ui.rush.hidden = !state.rush || state.mode !== 'running';
    if (state.rush) ui.rush.textContent = `Rush: ${DIRS[state.rush.dir].name.toLowerCase()} traffic`;
    ui.pauseBtn.disabled = state.mode !== 'running' && state.mode !== 'paused';
    ui.pauseBtn.textContent = state.mode === 'paused' ? 'Resume' : 'Pause';
  }

  // ---- Screens ----
  function showCard(html) {
    ui.card.innerHTML = html;
    ui.overlay.hidden = false;
    const primary = ui.card.querySelector('.primary');
    if (primary) primary.focus({ preventScroll: true });
  }
  const hideCard = () => { ui.overlay.hidden = true; };

  function levelSummary(lvl) {
    const lanes = s => s.length === 1 ? '1 lane' : `${s.length} lanes`;
    return `${lanes(lvl.lanes.NS)} on Main St, ${lanes(lvl.lanes.EW)} on the cross street, ${lvl.groups.length} switches`;
  }

  function showLevelSelect() {
    if (state.mode === 'running') state.mode = 'paused';
    const rows = LEVELS.map((lvl, i) => {
      const locked = i + 1 > progress.unlocked;
      const best = progress.best[i];
      const status = locked ? 'Locked' : best !== undefined ? `Done in ${fmtTime(best)}` : 'Open';
      return `<button class="level-row" type="button" data-action="pick" data-level="${i}" ${locked ? 'disabled' : ''}>
        <span class="level-num">${i + 1}</span>
        <span class="level-info"><span class="level-name">${lvl.name}</span><span class="level-desc">${levelSummary(lvl)}</span></span>
        <span class="level-status" data-done="${best !== undefined}">${status}</span>
      </button>`;
    }).join('');
    const free = `<button class="level-row freeplay-row" type="button" data-action="freeplay-setup">
        <span class="level-num">∞</span>
        <span class="level-info"><span class="level-name">Freeplay</span><span class="level-desc">Any map, your traffic density, no goal</span></span>
        <span class="level-status">Open</span>
      </button>`;
    const back = state.mode === 'paused' ? '<div class="card-actions"><button type="button" data-action="resume">Back to shift</button></div>' : '';
    showCard(`<h2>Choose a shift</h2><p class="muted">Finish a level to unlock the next one. Freeplay is always open.</p><div class="level-list">${rows}${free}</div>${back}`);
  }

  // ---- Freeplay ----
  const DENSITY_NAMES = ['Quiet', 'Quiet', 'Light', 'Light', 'Normal', 'Normal', 'Heavy', 'Heavy', 'Gridlock', 'Gridlock'];
  const densityName = d => `${DENSITY_NAMES[d - 1]} (${d})`;

  function loadFreeplaySettings() {
    try {
      const f = JSON.parse(localStorage.getItem('intersection-freeplay'));
      if (f && LEVELS[f.map] && f.density >= 1 && f.density <= 10) {
        return { map: f.map, density: f.density, rush: !!f.rush, limits: !!f.limits };
      }
    } catch { /* storage unavailable */ }
    return { map: 1, density: 5, rush: true, limits: false };
  }
  function saveFreeplaySettings(f) {
    try { localStorage.setItem('intersection-freeplay', JSON.stringify(f)); } catch { /* storage unavailable */ }
  }

  // Density 5 matches the busiest point of that map's campaign level.
  function densityRates(base, density) {
    const k = density / 5;
    return { NS: [base.rate.NS[1] * k, base.rate.NS[1] * k], EW: [base.rate.EW[1] * k, base.rate.EW[1] * k] };
  }

  function freeplayLevel(f) {
    const base = LEVELS[f.map];
    return { ...base, name: 'Freeplay', goal: Infinity, rate: densityRates(base, f.density), rush: f.rush };
  }

  function setupFreeplay(f, preview) {
    state = newState(f.map, freeplayLevel(f), f);
    prefill();
    buildControls();
    resize();
    ui.liveDensity.value = f.density;
    if (!preview) startLevel();
  }

  function mapSummary(lvl) {
    return `${lvl.lanes.NS.length} × ${lvl.lanes.EW.length} lanes · ${lvl.groups.length} switches`;
  }

  function showFreeplaySetup() {
    const f = state.freeplay ? { ...state.freeplay } : loadFreeplaySettings();
    if (!state.freeplay || state.freeplay.map !== f.map || state.mode === 'lost') setupFreeplay(f, true);
    else if (state.mode === 'running') state.mode = 'paused';
    const maps = LEVELS.map((lvl, i) => `
      <label class="map-option">
        <input type="radio" name="fp-map" id="fp-map-${i}" value="${i}" ${i === f.map ? 'checked' : ''}>
        <span class="level-info"><span class="level-name">${lvl.name}</span><span class="level-desc">${mapSummary(lvl)}</span></span>
      </label>`).join('');
    showCard(`
      <p class="eyebrow">Freeplay</p>
      <h2>Set up your intersection</h2>
      <fieldset class="field"><legend class="label">Map</legend><div class="map-list">${maps}</div></fieldset>
      <div class="field">
        <label class="label" for="fp-density">Traffic density</label>
        <div class="range-row">
          <input type="range" id="fp-density" min="1" max="10" step="1" value="${f.density}">
          <output id="fp-density-value" for="fp-density">${densityName(f.density)}</output>
        </div>
      </div>
      <label class="check"><input type="checkbox" id="fp-rush" ${f.rush ? 'checked' : ''}> Rush-hour surges</label>
      <label class="check"><input type="checkbox" id="fp-limits" ${f.limits ? 'checked' : ''}> End the game after ${MAX_CRASHES} crashes or when patience runs out</label>
      <div class="card-actions">
        <button class="primary" type="button" data-action="freeplay-start">Start freeplay</button>
        <button type="button" data-action="levels">All levels</button>
      </div>`);
  }

  function readFreeplayForm() {
    const checked = ui.card.querySelector('input[name="fp-map"]:checked');
    return {
      map: checked ? Number(checked.value) : 0,
      density: Number(ui.card.querySelector('#fp-density').value),
      rush: ui.card.querySelector('#fp-rush').checked,
      limits: ui.card.querySelector('#fp-limits').checked,
    };
  }

  ui.card.addEventListener('input', e => {
    if (e.target.id === 'fp-density') {
      ui.card.querySelector('#fp-density-value').textContent = densityName(Number(e.target.value));
    }
  });
  ui.card.addEventListener('change', e => {
    // Show the chosen map behind the setup card.
    if (e.target.name === 'fp-map') setupFreeplay(readFreeplayForm(), true);
  });

  ui.liveDensity.addEventListener('input', () => {
    const f = state.freeplay;
    if (!f) return;
    f.density = Number(ui.liveDensity.value);
    state.level.rate = densityRates(LEVELS[f.map], f.density);
    saveFreeplaySettings(f);
  });

  function loadLevel(i) {
    state = newState(i);
    prefill();
    buildControls();
    resize();
    showIntro();
  }

  function showIntro() {
    const lvl = state.level;
    showCard(`
      <p class="eyebrow">Level ${state.levelIndex + 1} · ${lvl.street}</p>
      <h2>${lvl.name}</h2>
      <p>${lvl.intro}</p>
      <p class="muted">${lvl.tip}</p>
      <p class="goal">Clear <strong>${lvl.goal}</strong> cars. ${MAX_CRASHES} crashes or an empty patience meter ends the shift.</p>
      <div class="card-actions">
        <button class="primary" type="button" data-action="start">Start shift</button>
        <button type="button" data-action="levels">All levels</button>
      </div>`);
  }

  function startLevel() {
    state.mode = 'running';
    hideCard();
  }

  function winLevel() {
    state.mode = 'won';
    const i = state.levelIndex;
    const prev = progress.best[i];
    if (prev === undefined || state.t < prev) progress.best[i] = state.t;
    progress.unlocked = Math.max(progress.unlocked, Math.min(LEVELS.length, i + 2));
    saveProgress();
    const hasNext = i + 1 < LEVELS.length;
    showCard(`
      <p class="eyebrow">Level ${i + 1} complete</p>
      <h2>${hasNext ? 'Intersection cleared' : 'You ran every intersection'}</h2>
      <p>You moved <strong>${state.cleared}</strong> cars in <strong>${fmtTime(state.t)}</strong> with <strong>${state.crashes}</strong> ${state.crashes === 1 ? 'crash' : 'crashes'}.</p>
      ${hasNext ? `<p class="muted">Next: ${LEVELS[i + 1].name}. ${levelSummary(LEVELS[i + 1])}.</p>` : '<p class="muted">Every level is unlocked. Try to beat your times.</p>'}
      <div class="card-actions">
        ${hasNext ? '<button class="primary" type="button" data-action="next">Next level</button>' : ''}
        <button ${hasNext ? '' : 'class="primary"'} type="button" data-action="retry">Replay</button>
        <button type="button" data-action="levels">All levels</button>
      </div>`);
  }

  function loseLevel() {
    state.mode = 'lost';
    showCard(`
      <p class="eyebrow">${state.freeplay ? 'Freeplay' : `Level ${state.levelIndex + 1}`} · ${state.level.street}</p>
      <h2>Shift over</h2>
      <p>${state.failReason}</p>
      <p class="muted">${state.freeplay ? `You cleared ${state.cleared} cars` : `You cleared ${state.cleared} of ${state.level.goal} cars`} in ${fmtTime(state.t)}.</p>
      <div class="card-actions">
        <button class="primary" type="button" data-action="retry">Try again</button>
        ${state.freeplay ? '<button type="button" data-action="freeplay-setup">Change settings</button>' : ''}
        <button type="button" data-action="levels">All levels</button>
      </div>`);
  }

  function togglePause() {
    if (state.mode === 'running') {
      state.mode = 'paused';
      showCard(`<h2>Paused</h2><p class="muted">Traffic is frozen.</p>
        <div class="card-actions">
          <button class="primary" type="button" data-action="resume">Resume</button>
          ${state.freeplay ? '<button type="button" data-action="freeplay-setup">Change settings</button>' : ''}
          <button type="button" data-action="retry">${state.freeplay ? 'Restart' : 'Restart level'}</button>
          <button type="button" data-action="levels">All levels</button>
        </div>`);
    } else if (state.mode === 'paused') {
      state.mode = 'running';
      hideCard();
    }
  }

  ui.card.addEventListener('click', e => {
    const btn = e.target.closest('button[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;
    if (action === 'start') startLevel();
    else if (action === 'levels') showLevelSelect();
    else if (action === 'pick') loadLevel(Number(btn.dataset.level));
    else if (action === 'next') loadLevel(state.levelIndex + 1);
    else if (action === 'retry') { if (state.freeplay) setupFreeplay(state.freeplay, false); else loadLevel(state.levelIndex); }
    else if (action === 'freeplay-setup') showFreeplaySetup();
    else if (action === 'freeplay-start') {
      const f = readFreeplayForm();
      saveFreeplaySettings(f);
      setupFreeplay(f, false);
    }
    else if (action === 'resume') togglePause();
  });

  ui.signals.addEventListener('click', e => {
    const btn = e.target.closest('button[data-group]');
    if (btn) toggleGroup(Number(btn.dataset.group));
  });
  const setHover = e => {
    const btn = e.target.closest && e.target.closest('button[data-group]');
    state.hover = btn ? Number(btn.dataset.group) : -1;
  };
  ui.signals.addEventListener('pointerover', setHover);
  ui.signals.addEventListener('pointerleave', () => { state.hover = -1; });
  ui.signals.addEventListener('focusin', setHover);
  ui.signals.addEventListener('focusout', () => { state.hover = -1; });

  ui.pauseBtn.addEventListener('click', togglePause);
  ui.levelsBtn.addEventListener('click', showLevelSelect);

  // Tapping a lamp on the road toggles its signal group.
  canvas.addEventListener('pointerdown', e => {
    const rect = canvas.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * W;
    const y = ((e.clientY - rect.top) / rect.height) * H;
    let best = null, bestD = 16;
    for (const lamp of geo.lamps) {
      const d = Math.hypot(lamp.x - x, lamp.y - y);
      if (d < bestD) { best = lamp; bestD = d; }
    }
    if (best) { e.preventDefault(); toggleGroup(best.group); }
  });

  window.addEventListener('keydown', e => {
    if (e.code === 'KeyP' || e.code === 'Escape') { togglePause(); return; }
    const m = /^Digit([1-9])$/.exec(e.code);
    if (m) { e.preventDefault(); toggleGroup(Number(m[1]) - 1); }
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
    if (state.mode === 'running') step(dt, false);
    else updateEffects(dt);
    render();
    updateHud();
    requestAnimationFrame(frame);
  }

  const startAt = Math.min(progress.unlocked, LEVELS.length) - 1;
  state = newState(startAt);
  prefill();
  buildControls();
  resize();
  if (progress.unlocked > 1) showLevelSelect(); else showIntro();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(resize);
  requestAnimationFrame(frame);
})();
