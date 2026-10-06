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
  const MIN_COMMIT_SPEED = 45;   // slower cars always stop for a yellow

  // Driver types: top speed range, acceleration, following gap, reaction time.
  const DRIVERS = {
    commuter: { maxV: [92, 115], accel: 150, gap: 8, react: [0.25, 0.6] },
    speeder: { maxV: [128, 150], accel: 215, gap: 5, react: [0.15, 0.35] },
    cautious: { maxV: [70, 88], accel: 110, gap: 12, react: [0.5, 0.95] },
    truck: { maxV: [72, 86], accel: 95, gap: 10, react: [0.4, 0.7] },
  };
  const BEATER_SHARE = 0.1;      // drivers who speed up to beat a yellow
  const BEATER_BOOST = 1.3;      // their top speed while racing a yellow
  // Share of drivers with each bad habit. Their mistakes never count against the player.
  const HABITS = { distracted: 0.08, stall: 0.03, tailgate: 0.015 };
  const MISTAKE_KINDS = new Set(['distracted', 'stall', 'bump']);
  const DRAIN_PER_ANGRY = 1.1;   // patience lost per second per honking driver
  const MAX_DRAIN = 6;           // cap on patience lost per second
  // Scoring
  const CAR_POINTS = 10;         // per car cleared, times the combo multiplier
  const COMBO_STEP = 10;         // cars in a row (with no one honking) per +0.5x
  const MAX_COMBO = 3;
  const WAVE_MIN = 4;            // cars through one green to earn a Green Wave
  const WAVE_POINTS = 5;         // bonus per car in the wave
  const CRASH_PENALTY = 100;
  const PED_HIT_PENALTY = 150;
  const STAR_PATIENCE = 50;      // third star: patience never drops below this
  const DRAIN_PER_BLOCKED = 4;   // per second per approach backed up off-screen
  const REFILL_PER_CAR = 1.6;
  const CRASH_PATIENCE = 12;
  const MAX_CRASHES = 3;
  const CONFLICT_DIST = 15;      // path centrelines closer than this can collide
  const WRECK_TIME = 5;
  const MERGE_START = 40;        // where a dropped lane starts to taper, past the box
  const MERGE_LEN = 110;         // length of the taper
  const WALK_CLEAR_TIME = 5;     // flashing don't-walk before a crosswalk turns red
  const PED_PATIENCE = 1.5;      // seconds a pedestrian waits for a car in their way
  const MIN_HIT_SPEED = 10;      // slower contact with a pedestrian isn't a hit
  const PED_COLORS = ['#e8c07a', '#c45a4a', '#5a7fb8', '#7a5aa8', '#4f9a6a', '#d0d4d8', '#2e3338', '#d98a3a'];

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
  // `lanes` lists each direction's approach lanes, inner lane first:
  // L = left turn, T = straight, R = right turn; combined like 'TR' or 'LT'.
  // A road can be given once for both directions (`NS`, `EW`) or per
  // direction (`N`, `S`, `E`, `W`); an empty list means no traffic comes
  // that way (a one-way street or a T-junction).
  // `out` is how many lanes a direction keeps after the intersection. Fewer
  // than it arrives with means the outer lanes merge after the box.
  // Signal groups: `move` 'T' (straight and right), 'L' (left) or 'A' (all).
  // `walks` are pedestrian signals; `legs` names crosswalks by the direction
  // of traffic that arrives over them.
  const LEVELS = [
    {
      name: 'First Shift', street: 'Main St & 1st Ave', desc: '1 lane each way · 2 switches',
      lanes: { NS: ['TR'], EW: ['TR'] },
      groups: [
        { label: 'Main St', dirs: ['N', 'S'], move: 'T' },
        { label: '1st Ave', dirs: ['E', 'W'], move: 'T' },
      ],
      goal: 20, rate: { NS: [0.13, 0.2], EW: [0.13, 0.2] }, left: 0, right: 0.15, angry: 9, rush: false,
      intro: 'The signal buttons sit next to the cars they control, and the arrows show which way those cars go. Turn one street red before you turn the other green. If both are green, cars will crash.',
      tip: 'After you switch a street off, wait for the yellow to end and for the last cars to clear the box. Cars with an amber lightning bolt speed up to beat a yellow, so watch for them before you switch.',
    },
    {
      name: 'Turn Lanes', street: 'Main St & 1st Ave', desc: 'Left-turn lanes · 4 switches',
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
      name: 'Crosswalks', street: 'Main St & 1st Ave', desc: 'Pedestrians · 6 switches',
      lanes: { NS: ['L', 'TR'], EW: ['L', 'TR'] },
      groups: [
        { label: 'Main St', dirs: ['N', 'S'], move: 'T' },
        { label: 'Main St', dirs: ['N', 'S'], move: 'L' },
        { label: '1st Ave', dirs: ['E', 'W'], move: 'T' },
        { label: '1st Ave', dirs: ['E', 'W'], move: 'L' },
      ],
      walks: [
        { label: 'Main St', legs: ['N', 'S'] },
        { label: '1st Ave', legs: ['E', 'W'] },
      ],
      peds: 0.05,
      goal: 35, rate: { NS: [0.14, 0.22], EW: [0.14, 0.22] }, left: 0.3, right: 0.12, angry: 15, rush: false,
      intro: 'People now wait at the corners. Each crosswalk has a Walk button with a walking figure. Turning cars stop for people in the crosswalk, but straight-through traffic on green does not.',
      tip: 'Let people cross a street while that street is red. Walk across Main St runs safely with 1st Ave straight traffic, and the flashing don’t-walk gives the last walkers time to finish.',
    },
    {
      name: 'One Way', street: 'Main St & 2nd Ave', desc: 'One-way avenue · 5 switches',
      lanes: { N: ['L', 'T', 'T'], S: ['T', 'T', 'TR'], E: [], W: ['L', 'T', 'TR'] },
      groups: [
        { label: 'Main St', dirs: ['N', 'S'], move: 'T' },
        { label: 'Main St', dirs: ['N'], move: 'L' },
        { label: '2nd Ave', dirs: ['W'], move: 'A' },
      ],
      walks: [
        { label: 'Main St', legs: ['N', 'S'] },
        { label: '2nd Ave', legs: ['E', 'W'] },
      ],
      peds: 0.05,
      goal: 45, rate: { NS: [0.18, 0.28], EW: [0.26, 0.36] }, left: 0.25, right: 0.15, angry: 15, rush: false,
      intro: '2nd Ave is a one-way street heading west, with three lanes that all move on one switch. Northbound Main St can turn left onto it; southbound can only turn right.',
      tip: 'The avenue carries the most traffic. Its left turns cut across southbound Main St, so the avenue and Main St can never run together.',
    },
    {
      name: 'Harbor Merge', street: 'Main St & Harbor Rd', desc: 'T-junction, lane drop · 5 switches',
      lanes: { N: ['T', 'TR'], S: ['L', 'T'], E: [], W: ['L', 'R'] },
      out: { N: 1, S: 2, E: 1, W: 0 },
      groups: [
        { label: 'Main St', dirs: ['N', 'S'], move: 'T' },
        { label: 'Main St', dirs: ['S'], move: 'L' },
        { label: 'Harbor Rd', dirs: ['W'], move: 'A' },
      ],
      walks: [
        { label: 'Main St', legs: ['N', 'S'] },
        { label: 'Harbor Rd', legs: ['W'] },
      ],
      peds: 0.05,
      goal: 45, rate: { NS: [0.2, 0.3], EW: [0.2, 0.3] }, left: 0.35, right: 0.12, angry: 15, rush: false,
      intro: 'Harbor Rd ends at Main St, so its drivers can only turn. North of the junction, Main St drops to one lane: the two northbound lanes and cars turning right off Harbor Rd all merge.',
      tip: 'When the merge backs up, drivers will not enter the junction until there is room on the other side. Long greens for northbound traffic stop helping once the merge is full.',
    },
    {
      name: 'Split Phases', street: 'Main St & 3rd Ave', desc: 'Split control, lane drops · 8 switches',
      lanes: { NS: ['L', 'T', 'TR'], EW: ['L', 'T', 'TR'] },
      out: { E: 2, W: 2 },
      groups: [
        { label: 'Northbound', dirs: ['N'], move: 'T' },
        { label: 'Northbound', dirs: ['N'], move: 'L' },
        { label: 'Southbound', dirs: ['S'], move: 'T' },
        { label: 'Southbound', dirs: ['S'], move: 'L' },
        { label: '3rd Ave', dirs: ['E', 'W'], move: 'T' },
        { label: '3rd Ave', dirs: ['E', 'W'], move: 'L' },
      ],
      walks: [
        { label: 'Main St', legs: ['N', 'S'] },
        { label: '3rd Ave', legs: ['E', 'W'] },
      ],
      peds: 0.06,
      goal: 60, rate: { NS: [0.24, 0.34], EW: [0.18, 0.26] }, left: 0.28, right: 0.12, angry: 16, rush: true,
      intro: 'Northbound and southbound Main St have separate controls. 3rd Ave loses a lane on both sides of the junction, so its traffic merges right after crossing. Rush-hour surges start here.',
      tip: 'Northbound straight with northbound left is safe. Northbound left with southbound straight is not.',
    },
    {
      name: 'Downtown Rush', street: 'Main St & Broadway', desc: 'Everything at once · 10 switches',
      lanes: { NS: ['L', 'T', 'T', 'TR'], EW: ['L', 'T', 'TR'] },
      out: { N: 3 },
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
      walks: [
        { label: 'Main St', legs: ['N', 'S'] },
        { label: 'Broadway', legs: ['E', 'W'] },
      ],
      peds: 0.07,
      goal: 80, rate: { NS: [0.3, 0.42], EW: [0.22, 0.3] }, left: 0.28, right: 0.12, angry: 16, rush: true,
      intro: 'Every direction and turn has its own signal, people cross on both streets, and northbound Main St drops a lane past the junction.',
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
  const OPP = { N: 'S', S: 'N', E: 'W', W: 'E' };

  function buildGeometry(level) {
    const lanes = {}, out = {};
    for (const k of DIR_KEYS) {
      lanes[k] = level.lanes[k] ?? level.lanes[DIRS[k].road] ?? [];
      out[k] = level.out?.[k] ?? lanes[k].length;
    }
    // Width of the half of a road that carries direction k (its lanes in the box).
    const halfOf = k => Math.max(lanes[k].length, out[k]) * LANE_W;
    // Box extents seen from approach k: `near` edge it enters, `far` edge it
    // leaves by, and how far the box reaches to the driver's right and left.
    const ext = k => ({ near: halfOf(RIGHT_OF[k]), far: halfOf(LEFT_OF[k]), right: halfOf(k), left: halfOf(OPP[k]) });
    // The road leg that traffic heading k arrives over.
    const legRight = k => lanes[k].length * LANE_W;
    const legLeft = k => (out[OPP[k]] > 0 ? halfOf(OPP[k]) : 0);
    const hasLeg = k => legRight(k) > 0 || legLeft(k) > 0;
    const box = { x0: CX - halfOf('S'), x1: CX + halfOf('N'), y0: CY - halfOf('W'), y1: CY + halfOf('E') };

    const g = { lanes, out, halfOf, ext, legRight, legLeft, hasLeg, box };
    const carGroups = level.groups;
    const groupFor = (k, move) => carGroups.findIndex(gr => gr.dirs.includes(k) && (gr.move === 'A' || (gr.move === 'L') === (move === 'L')));

    // Crosswalks, one per road leg that has a walk signal.
    g.crosswalks = [];
    (level.walks || []).forEach((w, wi) => {
      for (const k of w.legs) {
        if (!hasLeg(k)) continue;
        g.crosswalks.push({
          leg: k, group: carGroups.length + wi,
          uc: -ext(k).near - CROSSWALK / 2,
          road0: -legLeft(k), road1: legRight(k),
        });
      }
    });

    g.paths = [];
    g.lamps = [];
    for (const k of DIR_KEYS) {
      lanes[k].forEach((laneSpec, i) => {
        for (const move of laneSpec.split('')) {
          const p = buildPath(g, k, i, move);
          if (!p) continue;
          p.group = groupFor(k, move);
          g.paths.push(p);
        }
        const { d, r } = DIRS[k];
        const u = -ext(k).near - CROSSWALK - STOP_GAP + 9, v = LANE_W * (i + 0.5);
        const kind = laneSpec === 'L' ? 'L' : 'T';
        g.lamps.push({
          dir: k, lane: i, u, v, kind,
          x: CX + d.x * u + r.x * v, y: CY + d.y * u + r.y * v,
          group: groupFor(k, laneSpec[0]),
        });
      });
    }
    for (const p of g.paths) p.crossings = pathCrossings(p, g.crosswalks);
    g.conflicts = computeConflicts(level, g);
    return g;
  }

  // Point on crosswalk `cw` at distance v across the road (and u along it).
  function cwPoint(cw, v, du = 0) {
    const { d, r } = DIRS[cw.leg];
    const u = cw.uc + du;
    return { x: CX + d.x * u + r.x * v, y: CY + d.y * u + r.y * v };
  }

  function buildPath(g, k, i, move) {
    const { d, r } = DIRS[k];
    const e = g.ext(k);
    const off = LANE_W * (i + 0.5);
    const P = (u, v) => ({ x: CX + d.x * u + r.x * v, y: CY + d.y * u + r.y * v });
    const pts = [P(-(HALF + PAD), off), P(-e.near, off)];
    let exitDir, boxLane;
    const STEPS = 24;
    if (move === 'T') {
      exitDir = k; boxLane = i;
      if (g.out[k] === 0) return null;
      pts.push(P(e.far, off));
    } else if (move === 'L') {
      exitDir = LEFT_OF[k]; boxLane = 0;
      if (g.out[exitDir] === 0) return null;
      // Quarter ellipse around the far-left corner of the box.
      const a = off + e.left, b = LANE_W * 0.5 + e.near;
      for (let j = 1; j <= STEPS; j++) {
        const t = (j / STEPS) * Math.PI / 2;
        pts.push(P(-e.near + b * Math.sin(t), -e.left + a * Math.cos(t)));
      }
    } else {
      exitDir = RIGHT_OF[k];
      if (g.out[exitDir] === 0) return null;
      boxLane = g.out[exitDir] - 1;
      // Curve around the near-right corner into the outer lane.
      const offX = LANE_W * (boxLane + 0.5);
      const a = e.right - off, b = e.near - offX;
      for (let j = 1; j <= STEPS; j++) {
        const t = (j / STEPS) * Math.PI / 2;
        pts.push(P(-e.near + b * Math.sin(t), e.right - a * Math.cos(t)));
      }
    }
    const jEnd = pts.length - 1;
    const exitLane = Math.min(boxLane, g.out[exitDir] - 1);
    const ed = DIRS[exitDir].d, er = DIRS[exitDir].r;
    const remain = HALF + PAD - g.ext(exitDir).far;
    const X = pts[jEnd];
    const shift = LANE_W * (exitLane - boxLane);
    if (shift) {
      // Lane ends after the box: taper across into the next lane.
      pts.push({ x: X.x + ed.x * MERGE_START, y: X.y + ed.y * MERGE_START });
      for (let m = 1; m <= 12; m++) {
        const t = m / 12, sm = t * t * (3 - 2 * t);
        const along = MERGE_START + MERGE_LEN * t;
        pts.push({ x: X.x + ed.x * along + er.x * shift * sm, y: X.y + ed.y * along + er.y * shift * sm });
      }
    }
    pts.push({ x: X.x + ed.x * remain + er.x * shift, y: X.y + ed.y * remain + er.y * shift });

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
      exitKey: exitDir + exitLane,   // lane the car ends up in
      boxKey: exitDir + boxLane,     // lane the car is in right after the box
      merges: !!shift,
      mergeS: cum[jEnd] + MERGE_START,
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

  // Stretches of a path that run over each crosswalk.
  function pathCrossings(p, crosswalks) {
    const out = [];
    for (const cw of crosswalks) {
      const { d, r } = DIRS[cw.leg];
      let s0 = null, s1 = null;
      for (let s = p.stopS; s <= p.exitStart + CROSSWALK + 30; s += 2) {
        const pt = pointAt(p, s);
        const u = (pt.x - CX) * d.x + (pt.y - CY) * d.y, v = (pt.x - CX) * r.x + (pt.y - CY) * r.y;
        if (Math.abs(u - cw.uc) <= CROSSWALK / 2 + 1 && v >= cw.road0 - 2 && v <= cw.road1 + 2) {
          if (s0 === null) s0 = s;
          s1 = s;
        }
      }
      if (s0 !== null) out.push({ cw, s0, s1 });
    }
    return out;
  }

  // Two signal groups conflict if their paths come close inside the box. A
  // walk signal conflicts with straight-through traffic over its crosswalk;
  // turning drivers stop for people, so they are not a conflict.
  function computeConflicts(level, g) {
    const nGroups = level.groups.length + (level.walks || []).length;
    const conflicts = Array.from({ length: nGroups }, () => new Set());
    const link = (a, b) => { conflicts[a].add(b); conflicts[b].add(a); };
    const paths = g.paths;
    const samples = paths.map(p => {
      const pts = [];
      for (let s = p.A - 2; s <= p.exitStart + 12; s += 3) pts.push(pointAt(p, s));
      return pts;
    });
    for (let i = 0; i < paths.length; i++) {
      for (let j = i + 1; j < paths.length; j++) {
        const p = paths[i], q = paths[j];
        if (p.group === q.group || p.laneKey === q.laneKey || conflicts[p.group].has(q.group)) continue;
        let hit = p.exitKey === q.exitKey && p.boxKey === q.boxKey;
        for (const a of samples[i]) {
          if (hit) break;
          for (const b of samples[j]) if (dist(a, b) < CONFLICT_DIST) { hit = true; break; }
        }
        if (hit) link(p.group, q.group);
      }
    }
    for (const p of paths) {
      if (p.move !== 'T') continue;
      for (const c of p.crossings) link(p.group, c.cw.group);
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
    score: el('stat-score'), combo: el('stat-combo'), scoreBox: el('score-box'), fpBest: el('fp-best'),
    freeplayBar: el('freeplay-bar'), patienceRow: el('patience-row'), liveDensity: el('live-density'), liveDensityValue: el('live-density-value'),
  };

  // ---- Progress (per browser, optional) ----
  function loadProgress() {
    try {
      const p = JSON.parse(localStorage.getItem('intersection-progress'));
      if (p && Number.isInteger(p.unlocked)) {
        const best = {};
        for (const [k, v] of Object.entries(p.best || {})) if (Number.isFinite(v) && v >= 0) best[k] = v;
        const stars = {}, scores = {};
        for (const [k, v] of Object.entries(p.stars || {})) if (Array.isArray(v) && v.length === 3) stars[k] = v.map(Boolean);
        for (const [k, v] of Object.entries(p.scores || {})) if (Number.isFinite(v) && v >= 0) scores[k] = v;
        return { unlocked: Math.min(LEVELS.length, Math.max(1, p.unlocked)), best, stars, scores };
      }
    } catch { /* storage unavailable */ }
    return { unlocked: 1, best: {}, stars: {}, scores: {} };
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
    // People arrive at both ends of every crosswalk.
    const pedSpawners = [];
    geo.crosswalks.forEach(cw => { for (const dir of [1, -1]) pedSpawners.push({ cw, dir, timer: Math.random() * 6 }); });
    return {
      levelIndex, level, freeplay,
      mode: 'intro', // intro | running | paused | won | lost
      t: 0, cleared: 0, crashes: 0, patience: 100,
      groups: [
        ...level.groups.map((g, i) => ({ ...g, kind: 'car', state: i === 0 ? 'green' : 'red', timer: 0, cycle: 0, busy: 0, passed: 0 })),
        ...(level.walks || []).map(w => ({ ...w, kind: 'walk', state: 'red', timer: 0, cycle: 0, busy: 0 })),
      ],
      cars: [], peds: [], wrecks: [], particles: [], flashes: [],
      spawners, pedSpawners,
      rush: null, nextRush: 25,
      shake: 0, pulse: 0,
      failAt: null, failReason: '',
      hover: -1,
      score: 0, streak: 0, mult: 1, minPatience: 100, waitSum: 0, worstWait: 0,
      popups: [], banners: [], bestShown: false,
    };
  }

  function prefill() {
    for (let i = 0; i < 350; i++) step(0.02, true);
    state.t = 0; state.cleared = 0; state.patience = 100;
    state.particles = []; state.flashes = []; state.popups = []; state.banners = [];
    state.score = 0; state.streak = 0; state.mult = 1; state.minPatience = 100; state.waitSum = 0; state.worstWait = 0;
    for (const g of state.groups) g.passed = 0;
    for (const c of state.cars) c.wait = 0;
    for (const p of state.peds) p.wait = 0;
  }

  // ---- Signals ----
  function toggleGroup(i) {
    if (state.mode !== 'running' || state.failAt !== null) return;
    const g = state.groups[i];
    if (!g) return;
    if (g.state === 'green') { greenWave(i); g.state = 'yellow'; g.timer = 0; g.cycle++; }
    else if (g.state === 'red') { g.state = 'green'; g.passed = 0; }
  }

  function updateGroups(dt) {
    for (const g of state.groups) {
      if (g.state !== 'yellow') continue;
      g.timer += dt;
      if (g.timer >= (g.kind === 'walk' ? WALK_CLEAR_TIME : YELLOW_TIME)) g.state = 'red';
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
    const has = m => geo.paths.some(p => p.dir === k && p.move === m);
    if (!has('T')) return has('L') && (!has('R') || Math.random() < 0.5) ? 'L' : 'R';
    if (has('L') && Math.random() < state.level.left) return 'L';
    return has('R') && Math.random() < state.level.right ? 'R' : 'T';
  }

  const between = ([a, b]) => a + Math.random() * (b - a);

  function makeCar(path) {
    const truck = Math.random() < 0.12;
    const r = Math.random();
    const type = truck ? 'truck' : r < 0.2 ? 'speeder' : r < 0.35 ? 'cautious' : 'commuter';
    const prof = DRIVERS[type];
    // A few drivers have a bad habit that shows up now and then.
    const h = Math.random();
    const habit = h < HABITS.distracted ? 'distracted'
      : h < HABITS.distracted + HABITS.stall ? 'stall'
      : h < HABITS.distracted + HABITS.stall + HABITS.tailgate ? 'tailgate' : null;
    return {
      path, s: 0, v: 0,
      len: truck ? 38 : 22 + Math.random() * 6,
      wid: truck ? 17 : 14,
      color: truck ? pick(TRUCK_COLORS) : pick(CAR_COLORS),
      truck, type,
      maxV: between(prof.maxV), accel: prof.accel, gapPref: prof.gap, react: between(prof.react),
      beater: Math.random() < BEATER_SHARE, racing: false,
      habit, bumped: false,
      wait: 0, commit: -1, decided: -1,
      hold: 0, holdKind: null, stoppedFor: 0, starting: false,
    };
  }

  function updateSpawns(dt, tails) {
    for (const k of DIR_KEYS) {
      if (!geo.lanes[k].length) continue;
      const sp = state.spawners[k];
      sp.timer -= dt;
      if (sp.timer <= 0) {
        if (sp.pending.length < 20) sp.pending.push(pickMove(k));
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
      state.rush = { dir: pick(DIR_KEYS.filter(k => geo.lanes[k].length)), until: state.t + 12 };
      state.nextRush = state.t + 22 + Math.random() * 10;
    }
  }

  // ---- Driving ----
  function updateCars(dt) {
    // Index cars by the approach lane and exit lane they share with others.
    const byLane = {}, byExit = {}, byBox = {};
    for (const c of state.cars) {
      (byLane[c.path.laneKey] ||= []).push(c);
      (byExit[c.path.exitKey] ||= []).push(c);
      (byBox[c.path.boxKey] ||= []).push(c);
    }
    // Crosswalks with someone on the road right now.
    const pedsOnRoad = new Set();
    for (const ped of state.peds) if (ped.state === 'crossing' && ped.v > ped.cw.road0 - 4 && ped.v < ped.cw.road1 + 4) pedsOnRoad.add(ped.cw);

    // Lanes held up by a driver's own mistake: nobody there loses patience.
    const mistakeLanes = new Set();
    for (const c of state.cars) if (c.hold > 0 && MISTAKE_KINDS.has(c.holdKind)) mistakeLanes.add(c.path.laneKey);

    for (const c of state.cars) {
      const p = c.path;
      if (c.racing && c.s > p.exitStart) c.racing = false;
      let vMax = c.racing ? c.maxV * BEATER_BOOST : c.maxV;

      // Slow down for the turn.
      const tv = TURN_SPEED[p.move];
      // Stay at turning speed until past the crosswalk on the far side.
      if (tv && c.s < p.exitStart + CROSSWALK + c.len) vMax = Math.min(vMax, Math.sqrt(tv * tv + 2 * BRAKE * Math.max(0, p.A - c.s)));

      // Gap to whoever is ahead in the same approach lane or exit lane.
      let gap = Infinity, lead = null;
      for (const o of byLane[p.laneKey]) {
        if (o === c || o.s <= c.s) continue;
        // A car that went a different way (a turn from a shared lane) stops
        // mattering only once its body is clear of this car's path.
        if (o.path !== p && o.s - o.len >= p.A + 2 && !inTheWay(c, o)) continue;
        const gl = o.s - o.len - c.s;
        if (gl < gap) { gap = gl; lead = o; }
      }
      const ec = c.s - p.exitStart;
      const cWaitingToMerge = p.merges && c.s < p.mergeS;
      for (const o of byExit[p.exitKey]) {
        if (o === c) continue;
        const eo = o.s - o.path.exitStart;
        const oWaitingToMerge = o.path.merges && o.s < o.path.mergeS;
        if (o.path !== p) {
          // Merging: the car whose lane ends goes only when the lane beside
          // it is clear; until then, cars in that lane ignore it.
          if (cWaitingToMerge && !oWaitingToMerge) {
            const alongside = eo > ec - c.len - 12;
            if (alongside && eo - o.len < p.mergeS - p.exitStart + 6) gap = Math.min(gap, p.mergeS - c.s);
            continue;
          }
          if (oWaitingToMerge && !cWaitingToMerge) continue;
        }
        if (eo <= ec || (o.path !== p && eo <= 0)) continue;
        gap = Math.min(gap, eo - o.len - ec);
      }
      // Turning drivers stop short of a crosswalk while anyone is crossing it.
      if (p.move !== 'T' && pedsOnRoad.size) {
        for (const x of p.crossings) {
          if (!pedsOnRoad.has(x.cw) || c.s >= x.s0 - 6 || x.s0 - c.s > 90) continue;
          if ((c.v * c.v) / (2 * HARD_BRAKE) <= x.s0 - c.s - 7) gap = Math.min(gap, x.s0 - 7 - c.s + c.gapPref);
        }
      }
      // Nobody drives into a person right beside or ahead of them: turning
      // drivers always check, and so does anyone creeping along in a queue.
      // Straight-through traffic at speed does not, which is the player's risk.
      if (pedsOnRoad.size && (p.move !== 'T' || c.v < 25) && pedNear(c)) gap = Math.min(gap, c.gapPref);
      // Stop short of wrecks on the road ahead.
      if (state.wrecks.length && c.s < p.len) {
        for (const w of state.wrecks) {
          for (let q = 6; q <= 72; q += 6) {
            if (dist(pointAt(p, c.s + q), w) < 16) { gap = Math.min(gap, q - 10); break; }
          }
        }
      }
      // Mistake: a tailgater comes up on a stopped queue too fast and taps it.
      let tailgating = false;
      if (c.habit === 'tailgate' && !c.bumped && lead && lead.v < 3 && lead.s <= lead.path.stopS
          && gap < 70 && c.v > 25 && c.s < p.stopS - 4) {
        if (c.willBump === undefined) c.willBump = Math.random() < 0.35;
        // Only a low-speed tap: above walking pace the driver still brakes.
        tailgating = c.willBump && c.v < 45;
        if (tailgating && gap <= 1) { bump(c, lead); continue; }
      }
      if (!tailgating) vMax = Math.min(vMax, Math.sqrt(2 * BRAKE * Math.max(0, gap - c.gapPref)));

      // Obey the signal while still before the stop line.
      let mustStop = false;
      const g = state.groups[p.group];
      if (c.s <= p.stopS) {
        const d = p.stopS - c.s;
        let hold = false;
        if (g.state === 'red') {
          hold = c.commit !== g.cycle;
          // A car that committed on yellow but ended up stopped short of the
          // line (behind a wreck or a stopped car) gives up and waits for green.
          if (!hold && c.v < 2) { hold = true; c.commit = -1; c.racing = false; }
          if (!hold && c.racing && (c.v * c.v) / (2 * HARD_BRAKE) <= d) { hold = true; c.racing = false; }
        } else if (g.state === 'yellow' && c.commit !== g.cycle) {
          // Only a car at speed that is too close to stop goes through on
          // yellow. A slow car (one just pulling away from the line) stops,
          // otherwise it crawls across the box long after the light is red.
          const tooClose = (c.v * c.v) / (2 * HARD_BRAKE) > d;
          if (tooClose && c.v >= MIN_COMMIT_SPEED) c.commit = g.cycle;
          else if (c.decided !== g.cycle) {
            // Yellow-light racers floor it if they can reach the line before red.
            c.decided = g.cycle;
            const left = YELLOW_TIME - g.timer;
            const reach = ((c.v + c.maxV * BEATER_BOOST) / 2) * left * 0.8;
            if (c.beater && c.v > 30 && d < reach && !(state.wrecks.length && wreckOnPath(c))) {
              c.commit = g.cycle;
              c.racing = true;
            } else hold = true;
          } else hold = true;
        }
        // Don't enter the box when a wreck blocks the way through it, or when
        // the lane on the far side is backed up to the box.
        if (!hold && state.wrecks.length && wreckOnPath(c)) hold = true;
        if (!hold && c.commit !== g.cycle && exitBlocked(c, byBox[p.boxKey])) hold = true;
        if (hold) {
          mustStop = true;
          vMax = Math.min(vMax, Math.sqrt(2 * BRAKE * d));
        }
      }

      // Pulling away from a stop takes a moment; some drivers take longer.
      if (c.v < 1) c.stoppedFor += dt;
      else if (c.v > 5) { c.stoppedFor = 0; c.starting = false; }
      if (c.v < 1 && c.stoppedFor > 0.3 && vMax > 5 && c.hold <= 0 && !c.starting) {
        c.starting = true;
        c.hold = c.react; c.holdKind = 'react';
        if (c.habit === 'distracted' && Math.random() < 0.6) {
          c.hold += 1.2 + Math.random() * 1.5; c.holdKind = 'distracted';
        } else if (c.habit === 'stall' && Math.random() < 0.5) {
          c.hold += 2 + Math.random() * 1.5; c.holdKind = 'stall';
        }
      }
      if (c.hold > 0) {
        c.hold -= dt;
        vMax = 0;
        if (c.hold <= 0) c.holdKind = null;
      }

      const accel = c.racing ? c.accel * 1.6 : c.accel;
      if (c.v < vMax) c.v = Math.min(vMax, c.v + accel * dt);
      else c.v = Math.max(vMax, c.v - HARD_BRAKE * 1.5 * dt);
      const before = c.s;
      c.s += c.v * dt;
      if (mustStop && before <= p.stopS && c.s > p.stopS) { c.s = p.stopS; c.v = 0; }
      if (before <= p.stopS && c.s > p.stopS && g.state === 'green') g.passed++;

      if (c.v < 4 && c.s <= p.stopS + 1 && !mistakeLanes.has(p.laneKey)) c.wait += dt;
    }

    // Cars that left the map count as cleared.
    const keep = [];
    for (const c of state.cars) {
      if (c.s - c.len > c.path.len) carCleared(c);
      else keep.push(c);
    }
    state.cars = keep;
  }

  function pedNear(c) {
    const mid = pointAt(c.path, c.s - c.len / 2);
    let body = null;
    for (const ped of state.peds) {
      if (ped.state !== 'crossing') continue;
      const at = cwPoint(ped.cw, ped.v, ped.du);
      if (dist(at, mid) > c.len / 2 + 30) continue;
      body ||= bodyCircles(c);
      if (body.some(b => dist(at, b) < b.r + 8)) return true;
      for (let q = 0; q <= 18; q += 6) {
        if (dist(pointAt(c.path, c.s + q), at) < c.wid / 2 + 7) return true;
      }
    }
    return false;
  }

  // Is car o's body within reach of the stretch of road just ahead of c?
  function inTheWay(c, o) {
    const oc = bodyCircles(o);
    for (let q = 2; q <= 20; q += 6) {
      const pt = pointAt(c.path, c.s + q);
      if (oc.some(b => dist(pt, b) < b.r + c.wid / 2)) return true;
    }
    return false;
  }

  // A low-speed tap in the queue: both drivers stop to check. Never counted as a crash.
  function bump(c, lead) {
    c.s = lead.s - lead.len - 3;
    c.v = 0;
    c.bumped = true;
    for (const car of [c, lead]) { car.hold = Math.max(car.hold, 2.5); car.holdKind = 'bump'; car.starting = true; }
    const at = pointAt(c.path, c.s);
    for (let i = 0; i < 3; i++) {
      const ang = Math.random() * Math.PI * 2, sp = 30 + Math.random() * 40;
      state.particles.push({ kind: 'spark', x: at.x, y: at.y, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp, life: 0, max: 0.2 + Math.random() * 0.25 });
    }
    state.flashes.push({ x: at.x, y: at.y, t: 0, kind: 'bump' });
  }

  function exitBlocked(c, cars) {
    for (const o of cars || []) {
      if (o === c) continue;
      const eo = o.s - o.path.exitStart;
      if (eo > 0 && eo - o.len < c.len + 6 && o.v < 15) return true;
    }
    return false;
  }

  function wreckOnPath(c) {
    const p = c.path;
    for (let s = p.stopS; s <= p.exitStart + 30; s += 8) {
      const pt = pointAt(p, s);
      for (const w of state.wrecks) if (dist(pt, w) < 18) return true;
    }
    return false;
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

  // ---- Scoring ----
  const fmtNum = n => Math.round(n).toLocaleString('en-US');

  function addPoints(n, at, color) {
    state.score = Math.max(0, state.score + n);
    if (at) state.popups.push({ x: at.x, y: at.y, text: (n > 0 ? '+' : '') + fmtNum(n), color, t: 0, big: Math.abs(n) >= 40 });
    if (n > 0) pulseScore();
    checkFreeplayBest();
  }

  function banner(text, color) {
    state.banners.push({ text, color, t: 0 });
    if (state.banners.length > 3) state.banners.shift();
  }

  function carCleared(c) {
    state.cleared++;
    state.patience = Math.min(100, state.patience + REFILL_PER_CAR);
    state.waitSum += c.wait;
    state.worstWait = Math.max(state.worstWait, c.wait);
    state.streak++;
    const mult = Math.min(MAX_COMBO, 1 + 0.5 * Math.floor(state.streak / COMBO_STEP));
    if (mult > state.mult) banner(`${state.streak} in a row · ×${mult}`, '#f2a91f');
    state.mult = mult;
    // Points float up where the car leaves the map.
    addPoints(Math.round(CAR_POINTS * state.mult), pointAt(c.path, c.path.len - PAD - 22), '#f2f6f3');
  }

  function breakStreak() {
    if (state.streak >= COMBO_STEP) banner('Streak lost', '#ff8a8d');
    state.streak = 0;
    state.mult = 1;
  }

  // Switching a group off after it emptied its whole queue earns a bonus.
  function greenWave(i) {
    const g = state.groups[i];
    if (g.kind !== 'car' || g.passed < WAVE_MIN || state.mode !== 'running') return;
    const waiting = state.cars.some(c => c.path.group === i && c.s <= c.path.stopS && c.s > c.path.stopS - 140);
    if (waiting) return;
    const bonus = g.passed * WAVE_POINTS;
    const lamp = geo.lamps.find(l => l.group === i);
    addPoints(bonus, lamp ? { x: lamp.x, y: lamp.y - 12 } : null, '#30c070');
    banner(`Green wave · ${g.passed} cars · +${bonus}`, '#30c070');
  }

  // ---- Personal bests ----
  const fpKey = f => `${f.map}-${f.density}`;
  function loadFreeplayBests() {
    try {
      const b = JSON.parse(localStorage.getItem('intersection-freeplay-bests'));
      if (b && typeof b === 'object') return b;
    } catch { /* storage unavailable */ }
    return {};
  }
  const freeplayBests = loadFreeplayBests();
  let bestsDirty = false;
  function saveFreeplayBests() {
    if (!bestsDirty) return;
    bestsDirty = false;
    try { localStorage.setItem('intersection-freeplay-bests', JSON.stringify(freeplayBests)); } catch { /* storage unavailable */ }
  }
  function currentFreeplayBest() {
    const b = state.freeplay && freeplayBests[fpKey(state.freeplay)];
    return { score: Number.isFinite(b?.score) ? b.score : 0, cpm: Number.isFinite(b?.cpm) ? b.cpm : 0 };
  }
  function checkFreeplayBest() {
    if (!state.freeplay || state.mode !== 'running') return;
    const key = fpKey(state.freeplay);
    const best = currentFreeplayBest();
    const entry = freeplayBests[key] ||= {};
    if (state.score > best.score) {
      if (best.score > 0 && !state.bestShown) { state.bestShown = true; banner('New best score!', '#f2a91f'); }
      entry.score = state.score; bestsDirty = true;
    }
    if (state.t >= 60) {
      const cpm = carsPerMinute();
      if (cpm > best.cpm) { entry.cpm = Math.round(cpm * 10) / 10; bestsDirty = true; }
    }
  }
  setInterval(saveFreeplayBests, 2000);

  const carsPerMinute = () => (state.t > 0 ? (state.cleared / state.t) * 60 : 0);
  const avgWait = () => (state.cleared ? state.waitSum / state.cleared : 0);
  function statsLine() {
    return `${carsPerMinute().toFixed(1)} cars/min · average wait ${avgWait().toFixed(1)} s · longest wait ${state.worstWait.toFixed(1)} s`;
  }

  // Stars: clear the goal, no crashes, patience never below STAR_PATIENCE.
  function starsEarned() {
    return [state.cleared >= state.level.goal, state.crashes === 0, state.minPatience >= STAR_PATIENCE];
  }
  const STAR_GOALS = ['Clear the goal', 'No crashes', `Patience never below ${STAR_PATIENCE}%`];
  function starRow(stars, animate) {
    return `<span class="stars${animate ? ' animate' : ''}" aria-label="${stars.filter(Boolean).length} of 3 stars">${
      stars.map((on, i) => `<span class="star" data-on="${on}" style="--i:${i}">★</span>`).join('')}</span>`;
  }

  // ---- Pedestrians ----
  function updatePeds(dt) {
    const rate = state.level.peds || 0;
    if (rate) {
      for (const sp of state.pedSpawners) {
        sp.timer -= dt;
        if (sp.timer > 0) continue;
        sp.timer = expRand(1 / rate);
        const waiting = state.peds.filter(p => p.cw === sp.cw && p.dir === sp.dir && p.state === 'waiting').length;
        if (waiting >= 6) continue;
        const start = sp.dir > 0 ? sp.cw.road0 - 9 : sp.cw.road1 + 9;
        state.peds.push({
          cw: sp.cw, dir: sp.dir, v: start, start,
          du: (Math.random() - 0.5) * (CROSSWALK - 10), back: waiting * 5 + Math.random() * 3,
          speed: 26 + Math.random() * 16, color: pick(PED_COLORS),
          state: 'waiting', wait: 0, phase: Math.random() * 6, paused: 0,
        });
      }
    }
    for (const ped of state.peds) {
      const g = state.groups[ped.cw.group];
      if (ped.state === 'waiting') {
        if (g.state === 'green' && !carsInTheWay(ped)) ped.state = 'crossing';
        else ped.wait += dt;
      } else {
        // Hurry once the hand starts flashing.
        // Wait for a car in the way, but only briefly: after that, squeeze
        // past it. This way a person and a driver never wait on each other forever.
        if (carAhead(ped) && ped.paused < PED_PATIENCE) {
          ped.paused += dt;
        } else {
          if (!carAhead(ped)) ped.paused = 0;
          ped.v += ped.dir * ped.speed * (g.state === 'green' ? 1 : 1.5) * dt;
          ped.phase += dt * 10;
        }
      }
    }
    state.peds = state.peds.filter(p => !(p.state === 'crossing' && (p.dir > 0 ? p.v > p.cw.road1 + 10 : p.v < p.cw.road0 - 10)));
  }

  // People look before stepping off the curb: they wait for any car that is
  // moving across the crosswalk or will reach it in the next second. Cars
  // standing still (waiting at the stop line) don't stop them.
  function carsInTheWay(ped) {
    const cw = ped.cw;
    for (const c of state.cars) {
      if (c.v < 3 || Math.abs(c.s - c.path.A) > 160) continue;
      for (const t of [0, 0.35, 0.7, 1]) {
        const ahead = c.s + c.v * t;
        for (const f of [0, 0.5, 1]) {
          const pt = pointAt(c.path, ahead - c.len * f);
          if (onCrosswalk(cw, pt, 3)) return true;
        }
      }
    }
    return false;
  }

  function onCrosswalk(cw, pt, pad) {
    const { d, r } = DIRS[cw.leg];
    const u = (pt.x - CX) * d.x + (pt.y - CY) * d.y, v = (pt.x - CX) * r.x + (pt.y - CY) * r.y;
    return Math.abs(u - cw.uc) <= CROSSWALK / 2 + pad && v >= cw.road0 - pad && v <= cw.road1 + pad;
  }

  // A crossing pedestrian stops short of a car in their way.
  function carAhead(ped) {
    const next = cwPoint(ped.cw, ped.v + ped.dir * 7, ped.du);
    for (const c of state.cars) {
      if (dist(next, pointAt(c.path, c.s - c.len / 2)) > 30) continue;
      if (bodyCircles(c).some(b => dist(next, b) < b.r + 4)) return true;
    }
    return false;
  }

  function detectPedHits() {
    for (const ped of state.peds) {
      if (ped.state !== 'crossing' || ped.v < ped.cw.road0 - 2 || ped.v > ped.cw.road1 + 2) continue;
      const at = cwPoint(ped.cw, ped.v, ped.du);
      for (const c of state.cars) {
        // Only a moving car hits someone; brushing past a stopped one doesn't count.
        if (c.v < MIN_HIT_SPEED || dist(at, pointAt(c.path, c.s - c.len / 2)) > 30) continue;
        if (bodyCircles(c).some(b => dist(at, b) < b.r + 3.5)) { pedHit(ped, c, at); break; }
      }
    }
    state.peds = state.peds.filter(p => !p.hit);
  }

  function pedHit(ped, car, at) {
    ped.hit = true;
    car.v = 0;
    car.hold = 3; car.holdKind = 'hit'; car.starting = true;
    for (let i = 0; i < 12; i++) {
      const ang = Math.random() * Math.PI * 2, sp = 40 + Math.random() * 90;
      state.particles.push({ kind: 'spark', x: at.x, y: at.y, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp, life: 0, max: 0.3 + Math.random() * 0.3 });
    }
    state.flashes.push({ x: at.x, y: at.y, t: 0, kind: 'hit' });
    registerCrash('Someone was hit in a crosswalk.', at, PED_HIT_PENALTY);
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
    registerCrash('', mid, CRASH_PENALTY);
  }

  function registerCrash(note, at, penalty) {
    breakStreak();
    addPoints(-penalty, at ? { x: at.x, y: at.y - 18 } : null, '#ff8a8d');
    state.shake = reducedMotion ? 0 : 0.5;
    state.crashes++;
    state.patience = Math.max(0, state.patience - CRASH_PATIENCE);
    if (hasLimits() && state.crashes >= MAX_CRASHES && state.failAt === null) {
      state.failAt = state.t + 1.8;
      state.failReason = `${MAX_CRASHES} crashes. ${note ? note + ' ' : ''}The city pulled you off signal duty.`;
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
    for (const p of state.popups) p.t += dt;
    state.popups = state.popups.filter(p => p.t < (p.big ? 1.4 : 0.9));
    if (state.banners.length) {
      state.banners[0].t += dt;
      if (state.banners[0].t > 1.8) state.banners.shift();
    }
    state.shake = Math.max(0, state.shake - dt);
  }

  // ---- Patience, busy groups, win/lose ----
  const hasLimits = () => !state.freeplay; // freeplay never ends the game
  const isAngry = c => c.wait > state.level.angry && c.s <= c.path.stopS + 1;

  function updateStatus(dt) {
    for (const g of state.groups) g.busy = 0;
    let angry = 0;
    for (const c of state.cars) {
      const p = c.path;
      const grp = state.groups[p.group];
      const committed = c.commit === grp.cycle && grp.state !== 'green';
      if ((c.s > p.stopS + 0.5 || c.racing || committed) && c.s - c.len < p.exitStart) grp.busy++;
      if (isAngry(c)) {
        angry++;
        if (!c.honked) { c.honked = true; breakStreak(); }
      }
    }
    for (const ped of state.peds) {
      if (ped.state === 'crossing' && ped.v > ped.cw.road0 - 4 && ped.v < ped.cw.road1 + 4) state.groups[ped.cw.group].busy++;
      if (ped.state === 'waiting' && ped.wait > state.level.angry) {
        angry++;
        if (!ped.honked) { ped.honked = true; breakStreak(); }
      }
    }
    let blocked = 0;
    for (const k of DIR_KEYS) if (state.spawners[k].blockedFor > 1) blocked++;
    const drain = Math.min(MAX_DRAIN, angry * DRAIN_PER_ANGRY + blocked * DRAIN_PER_BLOCKED);
    state.patience = Math.max(0, state.patience - drain * dt);
    state.minPatience = Math.min(state.minPatience, state.patience);
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
    updatePeds(dt);
    if (!quiet) {
      detectCrashes();
      detectPedHits();
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
    const b = geo.box;

    g.fillStyle = '#9da5ad';
    g.fillRect(0, 0, W, H);

    const left = b.x0 - SIDEWALK, right = b.x1 + SIDEWALK;
    const top = b.y0 - SIDEWALK, bottom = b.y1 + SIDEWALK;
    drawBuildings(g, 0, 0, left, top, rnd);
    drawBuildings(g, right, 0, W - right, top, rnd);
    drawPark(g, 0, bottom, left, H - bottom, rnd);
    drawBuildings(g, right, bottom, W - right, H - bottom, rnd);
    // Where a leg is missing (a T-junction), the block continues across.
    if (!geo.hasLeg('E')) drawBuildings(g, 0, top, left, bottom - top, rnd);
    if (!geo.hasLeg('W')) drawBuildings(g, right, top, W - right, bottom - top, rnd);
    if (!geo.hasLeg('S')) drawBuildings(g, left, 0, right - left, top, rnd);
    if (!geo.hasLeg('N')) drawBuildings(g, left, bottom, right - left, H - bottom, rnd);
    drawCompass(g, 26, H - 30);

    g.fillStyle = '#3a4048';
    g.fillRect(b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0);
    for (const k of DIR_KEYS) {
      if (!geo.hasLeg(k)) continue;
      g.save();
      approachFrame(g, k);
      legShape(g, k);
      g.fill();
      g.restore();
    }

    g.strokeStyle = '#c7ccd1';
    g.lineWidth = 2;
    for (const k of DIR_KEYS) {
      g.save();
      approachFrame(g, k);
      const e = geo.ext(k);
      if (geo.hasLeg(k)) {
        const { far, near, R, L0, L1, m0, m1 } = legDims(k);
        g.beginPath(); g.moveTo(near, R + 1); g.lineTo(far, R + 1); g.stroke();
        g.beginPath(); g.moveTo(far, -L1 - 1); g.lineTo(m1, -L1 - 1); g.lineTo(m0, -L0 - 1); g.lineTo(near, -L0 - 1); g.stroke();
      } else {
        // Curb across the end of the box where no road continues.
        g.beginPath(); g.moveTo(-e.near - 1, -e.left); g.lineTo(-e.near - 1, e.right); g.stroke();
      }
      g.restore();
    }

    for (const k of DIR_KEYS) {
      if (!geo.hasLeg(k)) continue;
      g.save();
      approachFrame(g, k);
      drawLegMarkings(g, k);
      g.restore();
    }
  }

  // Outline of the road leg that traffic heading k arrives over, in k's frame.
  function legDims(k) {
    const e = geo.ext(k);
    const near = -e.near;
    return {
      far: -(HALF + PAD), near,
      R: geo.legRight(k), L0: geo.legLeft(k),
      L1: geo.out[OPP[k]] * LANE_W,
      m0: near - MERGE_START, m1: near - MERGE_START - MERGE_LEN,
    };
  }

  function legShape(g, k) {
    const { far, near, R, L0, L1, m0, m1 } = legDims(k);
    g.beginPath();
    g.moveTo(near + 1, R); g.lineTo(far, R); g.lineTo(far, -L1);
    g.lineTo(m1, -L1); g.lineTo(m0, -L0); g.lineTo(near + 1, -L0);
    g.closePath();
  }

  function drawLegMarkings(g, k) {
    const { far, near, R, L0, m0, m1 } = legDims(k);
    const spec = geo.lanes[k];
    const uStop = near - CROSSWALK - STOP_GAP;
    const outOpp = geo.out[OPP[k]];
    const exitLanes = Math.round(L0 / LANE_W);

    // Double yellow centre line on two-way legs.
    if (R > 0 && L0 > 0) {
      const end = spec.length ? uStop + 4 : near - CROSSWALK - 2;
      g.fillStyle = '#e3b23c';
      g.fillRect(far, -2.5, end - far, 1.6);
      g.fillRect(far, 0.9, end - far, 1.6);
    }

    g.fillStyle = '#eef0ea';
    // Lane lines on the approach: solid beside a turn lane, dashed between through lanes.
    for (let j = 1; j < spec.length; j++) {
      const v = LANE_W * j - 1;
      const turnLane = spec[j - 1] === 'L';
      if (turnLane) g.fillRect(uStop - 150, v, 150, 2);
      for (let u = far; u < (turnLane ? uStop - 150 : uStop); u += 24) g.fillRect(u, v, 12, 2);
    }
    // Lane lines on the way out; a dropped lane's line stops where it tapers away.
    for (let j = 1; j < exitLanes; j++) {
      const start = j < outOpp ? far : m1 + MERGE_LEN * 0.35;
      for (let u = start; u < near - CROSSWALK - 2; u += 24) g.fillRect(u, -LANE_W * j - 1, 12, 2);
    }
    // Merge arrows in lanes that end.
    g.strokeStyle = 'rgba(238, 240, 234, 0.85)';
    g.lineWidth = 2.5;
    for (let j = Math.max(outOpp, 1); j < exitLanes; j++) {
      const v = -LANE_W * (j + 0.5), u0 = m0 + 4;
      g.beginPath(); g.moveTo(u0, v); g.lineTo(u0 - 16, v); g.lineTo(u0 - 32, v + 10); g.stroke();
      g.beginPath(); g.moveTo(u0 - 37, v + 13); g.lineTo(u0 - 26, v + 12.5); g.lineTo(u0 - 31, v + 5); g.closePath(); g.fill();
    }

    // Stop line and crosswalk.
    if (spec.length) g.fillRect(uStop + 1, 2, 4, R - 2);
    for (let v = -L0 + 3; v < R - 3; v += 8) g.fillRect(near - CROSSWALK + 2, v, CROSSWALK - 4, 4);

    g.fillStyle = 'rgba(238, 240, 234, 0.85)';
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
    const L = spec.includes('L'), T = spec.includes('T'), R = spec.includes('R');
    const branch = T ? u - 2 : u + 4;
    g.beginPath(); g.moveTo(u - 12, v); g.lineTo(T ? u + 8 : branch, v); g.stroke();
    if (T) head(u + 8, v, 1, 0);
    if (L) { g.beginPath(); g.moveTo(branch, v); g.lineTo(branch, v - 6); g.stroke(); head(branch, v - 6, 0, -1); }
    if (R) { g.beginPath(); g.moveTo(branch, v); g.lineTo(branch, v + 6); g.stroke(); head(branch, v + 6, 0, 1); }
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

  function drawWalkSignals(g) {
    for (const cw of geo.crosswalks) {
      const st = state.groups[cw.group].state;
      if (state.hover === cw.group) {
        g.save();
        approachFrame(g, cw.leg);
        g.fillStyle = 'rgba(242, 169, 31, 0.3)';
        g.fillRect(cw.uc - CROSSWALK / 2, cw.road0, CROSSWALK, cw.road1 - cw.road0);
        g.restore();
      }
      for (const v of [cw.road0 - 8, cw.road1 + 8]) {
        const at = cwPoint(cw, v, -(CROSSWALK / 2 + 9));
        g.fillStyle = '#15181c';
        roundRect(g, at.x - 6, at.y - 6, 12, 12, 3); g.fill();
        if (st === 'green') {
          // Walking figure.
          g.strokeStyle = '#f2f6f3'; g.fillStyle = '#f2f6f3'; g.lineWidth = 1.4;
          g.beginPath(); g.arc(at.x + 0.5, at.y - 3.3, 1.3, 0, Math.PI * 2); g.fill();
          g.beginPath();
          g.moveTo(at.x, at.y - 1.5); g.lineTo(at.x - 0.6, at.y + 1.5);
          g.lineTo(at.x - 2.4, at.y + 4.2); g.moveTo(at.x - 0.6, at.y + 1.5); g.lineTo(at.x + 1.6, at.y + 4.2);
          g.moveTo(at.x - 2.6, at.y + 0.2); g.lineTo(at.x, at.y - 1.2); g.lineTo(at.x + 2.6, at.y + 0.6);
          g.stroke();
        } else if (st === 'red' || Math.sin(state.pulse * 9) > 0) {
          // Raised hand.
          g.fillStyle = '#f08a3c';
          roundRect(g, at.x - 2.6, at.y - 3, 5.2, 6.2, 1.8); g.fill();
        }
      }
    }
  }

  function drawPeds(g) {
    const showAngry = !state.freeplay;
    for (const ped of state.peds) {
      const crossing = ped.state === 'crossing';
      const at = crossing ? cwPoint(ped.cw, ped.v, ped.du) : cwPoint(ped.cw, ped.start - ped.dir * ped.back, ped.du * 0.7);
      const { d, r } = DIRS[ped.cw.leg];
      // Facing across the road.
      const ang = Math.atan2(r.y * ped.dir, r.x * ped.dir);
      g.save();
      g.translate(at.x, at.y);
      g.rotate(ang);
      if (crossing) {
        const swing = Math.sin(ped.phase) * 2.2;
        g.strokeStyle = '#2a2622'; g.lineWidth = 2;
        g.beginPath(); g.moveTo(0, -1.8); g.lineTo(swing * 1.3, -1.8); g.moveTo(0, 1.8); g.lineTo(-swing * 1.3, 1.8); g.stroke();
      }
      g.fillStyle = 'rgba(0, 0, 0, 0.3)';
      g.beginPath(); g.ellipse(1, 1, 3.3, 5, 0, 0, Math.PI * 2); g.fill();
      g.fillStyle = ped.color;
      g.beginPath(); g.ellipse(0, 0, 3.3, 5, 0, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#3a2e26';
      g.beginPath(); g.arc(0.3, 0, 2.4, 0, Math.PI * 2); g.fill();
      g.restore();
      if (showAngry && !crossing && ped.wait > state.level.angry && Math.sin(state.pulse * 10) > -0.3) {
        g.fillStyle = '#ff4d4f';
        g.font = '800 10px Overpass, system-ui, sans-serif';
        g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText('!', at.x, at.y - 8);
      }
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

  // Badges that tell the player what a driver is up to.
  function drawDriverMarks(g, c) {
    const p = c.path;
    const at = pointAt(p, c.s - c.len / 2);
    const fwd = { x: Math.cos(at.angle), y: Math.sin(at.angle) };
    const side = { x: -fwd.y, y: fwd.x };

    // Yellow-light racer: an amber lightning bolt riding with the car until it clears the box.
    if (c.beater && c.s < p.exitStart + c.len) {
      if (c.racing) {
        // Speed streaks behind the car.
        g.strokeStyle = 'rgba(242, 169, 31, 0.8)';
        g.lineWidth = 1.6;
        for (const o of [-5, 0, 5]) {
          const bx = at.x - fwd.x * (c.len / 2 + 3) + side.x * o, by = at.y - fwd.y * (c.len / 2 + 3) + side.y * o;
          const ln = 8 + Math.random() * 8;
          g.beginPath(); g.moveTo(bx, by); g.lineTo(bx - fwd.x * ln, by - fwd.y * ln); g.stroke();
        }
      }
      const pulse = c.racing ? 1 : 0.7 + 0.3 * Math.sin(state.pulse * 6);
      // Amber outline around the car body.
      g.save();
      g.translate(at.x, at.y); g.rotate(at.angle);
      g.strokeStyle = `rgba(242, 169, 31, ${pulse})`;
      g.lineWidth = 2;
      roundRect(g, -c.len / 2 - 3, -c.wid / 2 - 3, c.len + 6, c.wid + 6, 6); g.stroke();
      g.restore();
      // Lightning badge on the driver's side.
      const bx = at.x + side.x * -(c.wid / 2 + 10), by = at.y + side.y * -(c.wid / 2 + 10);
      g.fillStyle = '#161b21';
      g.beginPath(); g.arc(bx, by, 8.5, 0, Math.PI * 2); g.fill();
      g.strokeStyle = `rgba(242, 169, 31, ${pulse})`;
      g.lineWidth = 1.5;
      g.stroke();
      g.fillStyle = `rgba(242, 169, 31, ${pulse})`;
      g.beginPath();
      g.moveTo(bx + 1.4, by - 6); g.lineTo(bx - 3.6, by + 0.7); g.lineTo(bx - 0.3, by + 0.7);
      g.lineTo(bx - 1.4, by + 6); g.lineTo(bx + 3.6, by - 0.7); g.lineTo(bx + 0.3, by - 0.7);
      g.closePath(); g.fill();
    }

    if (c.hold <= 0) return;
    if (c.holdKind === 'distracted') {
      // A thought bubble: eyes off the road.
      const x = at.x + side.x * -(c.wid / 2 + 12), y = at.y + side.y * -(c.wid / 2 + 12) - 4;
      g.fillStyle = 'rgba(0, 0, 0, 0.35)';
      roundRect(g, x - 11, y - 6, 24, 15, 7); g.fill();
      g.fillStyle = '#e8edf2';
      roundRect(g, x - 12, y - 8, 24, 15, 7); g.fill();
      g.beginPath(); g.arc(x - 6, y + 9, 2.2, 0, Math.PI * 2); g.fill();
      g.fillStyle = '#161b21';
      for (const dx of [-5, 0, 5]) { g.beginPath(); g.arc(x + dx, y - 0.5, 1.7, 0, Math.PI * 2); g.fill(); }
    } else if ((c.holdKind === 'stall' || c.holdKind === 'bump' || c.holdKind === 'hit') && Math.sin(state.pulse * 12) > 0) {
      // Hazard lights at all four corners.
      g.fillStyle = '#ffb02e';
      for (const f of [-1, 1]) for (const sd of [-1, 1]) {
        const x = at.x + fwd.x * f * (c.len / 2 - 1) + side.x * sd * (c.wid / 2 - 1);
        const y = at.y + fwd.y * f * (c.len / 2 - 1) + side.y * sd * (c.wid / 2 - 1);
        g.beginPath(); g.arc(x, y, 3.2, 0, Math.PI * 2); g.fill();
      }
    }
  }

  function drawWaitRing(g, c) {
    if (state.freeplay) return; // no patience in freeplay
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
      const isBump = fl.kind === 'bump';
      const label = fl.kind === 'hit' ? 'PEDESTRIAN HIT' : isBump ? 'BUMP' : 'CRASH';
      if (!isBump && fl.t < 0.3) {
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
      g.font = `800 ${label === 'CRASH' ? 22 : label === 'BUMP' ? 10 : 15}px Overpass, system-ui, sans-serif`;
      g.textAlign = 'center'; g.textBaseline = 'middle';
      g.lineWidth = 4;
      g.strokeStyle = '#161b21';
      g.strokeText(label, 0, 0);
      g.fillStyle = isBump ? '#f2a91f' : '#e5484d';
      g.fillText(label, 0, 0);
      g.restore();
    }
  }

  function drawBacklog(g) {
    for (const k of DIR_KEYS) {
      const sp = state.spawners[k];
      if (sp.blockedFor <= 1 || !sp.pending.length) continue;
      const { d, r } = DIRS[k];
      const u = -HALF + 44, v = geo.legRight(k) / 2;
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
    drawWalkSignals(ctx);
    drawPeds(ctx);
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
    for (const c of state.cars) drawDriverMarks(ctx, c);
    for (const c of state.cars) drawWaitRing(ctx, c);
    drawBacklog(ctx);
    drawStreetSigns(ctx);
    drawScorePopups(ctx);
  }

  function drawScorePopups(g) {
    g.textAlign = 'center'; g.textBaseline = 'middle';
    for (const p of state.popups) {
      const life = p.big ? 1.4 : 0.9;
      const k = p.t / life;
      g.globalAlpha = k < 0.7 ? 1 : 1 - (k - 0.7) / 0.3;
      g.font = `800 ${p.big ? 15 : 11}px Overpass, system-ui, sans-serif`;
      const y = p.y - 6 - k * 22;
      g.lineWidth = 3; g.strokeStyle = 'rgba(22, 27, 33, 0.9)';
      g.strokeText(p.text, p.x, y);
      g.fillStyle = p.color;
      g.fillText(p.text, p.x, y);
    }
    g.globalAlpha = 1;
    const b = state.banners[0];
    if (b) {
      const pop = Math.min(1, b.t / 0.18);
      const alpha = b.t > 1.4 ? 1 - (b.t - 1.4) / 0.4 : 1;
      g.save();
      g.globalAlpha = Math.max(0, alpha);
      g.translate(CX, 70);
      g.scale(0.7 + 0.3 * pop, 0.7 + 0.3 * pop);
      g.font = '800 17px Overpass, system-ui, sans-serif';
      const w = g.measureText(b.text).width + 28;
      g.fillStyle = 'rgba(22, 27, 33, 0.88)';
      roundRect(g, -w / 2, -16, w, 32, 16); g.fill();
      g.strokeStyle = b.color; g.lineWidth = 2;
      roundRect(g, -w / 2, -16, w, 32, 16); g.stroke();
      g.fillStyle = b.color;
      g.fillText(b.text, 0, 1);
      g.restore();
    }
  }

  // Green street-name plates at the map edges, over each street.
  function drawStreetSigns(g) {
    const names = streetNames();
    g.font = '800 12px Overpass, system-ui, sans-serif';
    const plate = (text, x, y, anchor) => {
      const w = g.measureText(text).width + 16, h = 20;
      const x0 = anchor === 'left' ? x : anchor === 'right' ? x - w : x - w / 2, y0 = y - h / 2;
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
    const b = geo.box;
    plate(names.NS.toUpperCase(), (b.x0 + b.x1) / 2, geo.hasLeg('S') ? 16 : H - 16);
    if (geo.hasLeg('E')) plate(names.EW.toUpperCase(), 8, (b.y0 + b.y1) / 2, 'left');
    else plate(names.EW.toUpperCase(), W - 8, (b.y0 + b.y1) / 2, 'right');
  }

  // ---- Controls ----
  // Each approach gets its own cluster of signal buttons, placed on the block
  // beside the waiting line, with arrows pointing the way those cars drive.
  const GLYPH = {
    T: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 17V4M5 9l5-5 5 5"/></svg>',
    L: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M14 17v-6a3 3 0 0 0-3-3H5M8.5 4.5 5 8l3.5 3.5"/></svg>',
    A: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M12 17V4M8 8l4-4 4 4M12 13H6M8.5 10.5 6 13l2.5 2.5"/></svg>',
    walk: '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="11.5" cy="3.6" r="1.9" fill="currentColor" stroke="none"/><path d="M10.5 7.5 9 12.5l-3 5M9 12.5l3.5 2 1 3.5M6 10.5l4.5-3 3 3.5 3 1"/></svg>',
  };
  const keyLabel = i => String((i + 1) % 10);
  const ROTATE = { N: 0, E: 90, S: 180, W: -90 };

  function streetNames() {
    const [ns, ew] = state.level.street.split(' & ');
    return { NS: ns, EW: ew };
  }

  function buildControls() {
    const names = streetNames();
    const approaches = DIR_KEYS.filter(k => geo.lanes[k].length);
    // Walk buttons go with the approach whose corner touches that crosswalk.
    const walksAt = Object.fromEntries(approaches.map(k => [k, []]));
    for (const cw of geo.crosswalks) {
      if (walksAt[cw.leg] && !walksAt[cw.leg].includes(cw.group)) walksAt[cw.leg].push(cw.group);
    }
    state.groups.forEach((g, i) => {
      if (g.kind !== 'walk' || approaches.some(k => walksAt[k].includes(i))) return;
      if (approaches.length) walksAt[approaches[0]].push(i);
    });

    const clusters = approaches.map(k => {
      const { d, r } = DIRS[k];
      const e = geo.ext(k);
      // Corner of the block on the driver's right, just before the intersection.
      const u = -e.near - SIDEWALK, v = geo.legRight(k) + SIDEWALK;
      const x = CX + d.x * u + r.x * v, y = CY + d.y * u + r.y * v;
      const ex = Math.sign(-d.x + r.x), ey = Math.sign(-d.y + r.y);
      const groups = [];
      for (const lamp of geo.lamps) {
        if (lamp.dir === k && !groups.includes(lamp.group)) groups.push(lamp.group);
      }
      groups.sort((a, b) => (state.groups[a].move === 'L' ? -1 : 1) - (state.groups[b].move === 'L' ? -1 : 1));
      const carButtons = groups.map(i => {
        const g = state.groups[i];
        const what = g.move === 'L' ? 'left turn' : g.move === 'A' ? 'all lanes' : 'straight and right';
        return `<button class="map-sig" type="button" data-group="${i}" data-light="${g.state}"
            aria-label="${names[DIRS[k].road]} ${DIRS[k].name.toLowerCase()} ${what}, key ${keyLabel(i)}" title="${DIRS[k].name} ${what} (key ${keyLabel(i)})">
          <span class="arrow" style="transform: rotate(${ROTATE[k]}deg)">${GLYPH[g.move]}</span>
          <span class="key" aria-hidden="true">${keyLabel(i)}</span>
        </button>`;
      });
      const walkButtons = walksAt[k].map(i => {
        const g = state.groups[i];
        return `<button class="map-sig walk" type="button" data-group="${i}" data-light="${g.state}"
            aria-label="Walk across ${g.label}, key ${keyLabel(i)}" title="Walk across ${g.label} (key ${keyLabel(i)})">
          <span class="arrow">${GLYPH.walk}</span>
          <span class="key" aria-hidden="true">${keyLabel(i)}</span>
        </button>`;
      });
      return `<div class="cluster" data-x="${ex > 0 ? 'right' : 'left'}" data-y="${ey > 0 ? 'down' : 'up'}"
          style="left: ${(x / W) * 100}%; top: ${(y / H) * 100}%">
        <span class="cluster-name">${DIRS[k].name}</span>
        <div class="cluster-buttons">${carButtons.join('')}${walkButtons.join('')}</div>
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
    ui.freeplayBar.hidden = !fp || !ui.overlay.hidden;
    ui.patienceRow.hidden = !!fp;
    if (fp) ui.liveDensityValue.textContent = densityName(fp.density);
    ui.time.textContent = fmtTime(state.t);
    ui.score.textContent = fmtNum(state.score);
    ui.combo.hidden = state.mult <= 1;
    ui.combo.textContent = `×${state.mult}`;
    if (fp) {
      const best = currentFreeplayBest();
      ui.fpBest.textContent = `${carsPerMinute().toFixed(1)}/min · best ${fmtNum(best.score)} pts, ${best.cpm.toFixed(1)}/min`;
    }
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

  function pulseScore() {
    ui.scoreBox.classList.remove('pop');
    void ui.scoreBox.offsetWidth; // restart the animation
    ui.scoreBox.classList.add('pop');
  }

  // ---- Screens ----
  function showCard(html) {
    ui.card.innerHTML = html;
    ui.overlay.hidden = false;
    const primary = ui.card.querySelector('.primary');
    if (primary) primary.focus({ preventScroll: true });
  }
  const hideCard = () => { ui.overlay.hidden = true; };

  const levelSummary = lvl => lvl.desc;

  // A shift in progress is kept while the player browses the level list or
  // freeplay settings, so "Back to shift" can return to it.
  let suspended = null;
  function suspendCurrent() {
    if (suspended || (state.mode !== 'running' && state.mode !== 'paused')) return;
    state.mode = 'paused';
    suspended = { state, geo };
  }
  function resumeSuspended() {
    ({ state, geo } = suspended);
    suspended = null;
    buildControls();
    resize();
    if (state.freeplay) ui.liveDensity.value = state.freeplay.density;
    state.mode = 'running';
    hideCard();
  }
  const backButton = () => (suspended ? '<button type="button" data-action="back">Back to shift</button>' : '');

  function showLevelSelect() {
    suspendCurrent();
    const rows = LEVELS.map((lvl, i) => {
      const locked = i + 1 > progress.unlocked;
      const best = progress.best[i];
      const stars = progress.stars[i];
      const status = locked ? 'Locked'
        : stars ? `${starRow(stars)}<span class="level-score">${fmtNum(progress.scores[i] || 0)}</span>`
        : 'Open';
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
    const back = suspended ? `<div class="card-actions">${backButton()}</div>` : '';
    showCard(`<h2>Choose a shift</h2><p class="muted">Finish a level to unlock the next one. Freeplay is always open.</p><div class="level-list">${rows}${free}</div>${back}`);
  }

  // ---- Freeplay ----
  const DENSITY_NAMES = ['Quiet', 'Quiet', 'Light', 'Light', 'Normal', 'Normal', 'Heavy', 'Heavy', 'Gridlock', 'Gridlock'];
  const densityName = d => `${DENSITY_NAMES[d - 1]} (${d})`;

  function loadFreeplaySettings() {
    try {
      const f = JSON.parse(localStorage.getItem('intersection-freeplay'));
      if (f && Number.isInteger(f.map) && LEVELS[f.map] && Number.isInteger(f.density) && f.density >= 1 && f.density <= 10) {
        return { map: f.map, density: f.density, rush: !!f.rush, peds: f.peds !== false };
      }
    } catch { /* storage unavailable */ }
    return { map: 2, density: 5, rush: true, peds: true };
  }
  function saveFreeplaySettings(f) {
    try { localStorage.setItem('intersection-freeplay', JSON.stringify(f)); } catch { /* storage unavailable */ }
  }

  // Density 5 matches the busiest point of that map's campaign level; above
  // that traffic climbs steeply, to nearly four times as many cars at 10.
  const densityFactor = d => (d <= 5 ? d / 5 : 1 + (d - 5) * 0.55);

  function densityRates(base, density) {
    const k = densityFactor(density);
    return { NS: [base.rate.NS[1] * k, base.rate.NS[1] * k], EW: [base.rate.EW[1] * k, base.rate.EW[1] * k] };
  }

  function freeplayLevel(f) {
    const base = LEVELS[f.map];
    const lvl = { ...base, name: 'Freeplay', goal: Infinity, rate: densityRates(base, f.density), rush: f.rush };
    if (!f.peds) { lvl.walks = []; lvl.peds = 0; }
    else if (!base.walks) {
      const [ns, ew] = base.street.split(' & ');
      lvl.walks = [{ label: ns, legs: ['N', 'S'] }, { label: ew, legs: ['E', 'W'] }];
    }
    lvl.basePeds = f.peds ? (base.peds || 0.05) : 0;
    lvl.peds = lvl.basePeds * Math.min(2, densityFactor(f.density));
    return lvl;
  }

  function setupFreeplay(f, preview) {
    state = newState(f.map, freeplayLevel(f), f);
    prefill();
    buildControls();
    resize();
    ui.liveDensity.value = f.density;
    if (!preview) startLevel();
  }

  const mapSummary = lvl => lvl.desc;

  function showFreeplaySetup() {
    const f = state.freeplay ? { ...state.freeplay } : loadFreeplaySettings();
    suspendCurrent();
    setupFreeplay(f, true);
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
      <label class="check"><input type="checkbox" id="fp-peds" ${f.peds ? 'checked' : ''}> Pedestrians</label>
      <p class="muted">No goal, no patience meter, and crashes never end the game.</p>
      <div class="card-actions">
        <button class="primary" type="button" data-action="freeplay-start">Start freeplay</button>
        ${backButton()}
        <button type="button" data-action="levels">All levels</button>
      </div>`);
  }

  function readFreeplayForm() {
    const checked = ui.card.querySelector('input[name="fp-map"]:checked');
    return {
      map: checked ? Number(checked.value) : 0,
      density: Number(ui.card.querySelector('#fp-density').value),
      rush: ui.card.querySelector('#fp-rush').checked,
      peds: ui.card.querySelector('#fp-peds').checked,
    };
  }

  ui.card.addEventListener('input', e => {
    if (e.target.id === 'fp-density') {
      ui.card.querySelector('#fp-density-value').textContent = densityName(Number(e.target.value));
    }
  });
  ui.card.addEventListener('change', e => {
    // Preview the chosen settings behind the setup card.
    if (e.target.name === 'fp-map' || /^fp-(density|rush|peds)$/.test(e.target.id)) setupFreeplay(readFreeplayForm(), true);
  });

  ui.liveDensity.addEventListener('input', () => {
    const f = state.freeplay;
    if (!f) return;
    f.density = Number(ui.liveDensity.value);
    state.level.rate = densityRates(LEVELS[f.map], f.density);
    state.level.peds = state.level.basePeds * Math.min(2, densityFactor(f.density));
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
      <ul class="star-goals">${STAR_GOALS.map((g, j) => `<li><span class="star" data-on="${!!progress.stars[state.levelIndex]?.[j]}">★</span>${g}</li>`).join('')}</ul>
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
    const stars = starsEarned();
    const had = progress.stars[i] || [false, false, false];
    progress.stars[i] = had.map((h, j) => h || stars[j]);
    const prevScore = progress.scores[i] || 0;
    const newBest = state.score > prevScore;
    if (newBest) progress.scores[i] = state.score;
    saveProgress();
    const hasNext = i + 1 < LEVELS.length;
    const starNotes = STAR_GOALS.map((g, j) => `<li><span class="star" data-on="${stars[j]}">★</span>${g}</li>`).join('');
    showCard(`
      <p class="eyebrow">Level ${i + 1} complete</p>
      ${starRow(stars, true)}
      <h2>${hasNext ? 'Intersection cleared' : 'You ran every intersection'}</h2>
      <p class="final-score"><strong>${fmtNum(state.score)}</strong> points${newBest ? ' <span class="new-best">New best!</span>' : ` · best ${fmtNum(prevScore)}`}</p>
      <ul class="star-goals">${starNotes}</ul>
      <p>You moved <strong>${state.cleared}</strong> cars in <strong>${fmtTime(state.t)}</strong> with <strong>${state.crashes}</strong> ${state.crashes === 1 ? 'crash' : 'crashes'}.</p>
      <p class="muted">${statsLine()}</p>
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
      <p class="muted">${state.freeplay ? `You cleared ${state.cleared} cars` : `You cleared ${state.cleared} of ${state.level.goal} cars`} in ${fmtTime(state.t)}, scoring ${fmtNum(state.score)} points.</p>
      <p class="muted">${statsLine()}</p>
      <div class="card-actions">
        <button class="primary" type="button" data-action="retry">Try again</button>
        ${state.freeplay ? '<button type="button" data-action="freeplay-setup">Change settings</button>' : ''}
        <button type="button" data-action="levels">All levels</button>
      </div>`);
  }

  function togglePause() {
    if (state.mode === 'running') {
      state.mode = 'paused';
      showCard(`<h2>Paused</h2><p class="muted">Traffic is frozen. ${fmtNum(state.score)} points so far.</p>
        <p class="muted">${statsLine()}</p>
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
    else if (action === 'retry') {
      // Retry skips the intro and goes straight back to work.
      if (state.freeplay) setupFreeplay(state.freeplay, false);
      else { loadLevel(state.levelIndex); startLevel(); }
    }
    else if (action === 'freeplay-setup') showFreeplaySetup();
    else if (action === 'freeplay-start') {
      const f = readFreeplayForm();
      saveFreeplaySettings(f);
      setupFreeplay(f, false);
    }
    else if (action === 'resume') togglePause();
    else if (action === 'back') resumeSuspended();
    if (action !== 'levels' && action !== 'freeplay-setup' && action !== 'back' && action !== 'resume') suspended = null;
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
    let best = null, bestD = 22;
    for (const lamp of geo.lamps) {
      const d = Math.hypot(lamp.x - x, lamp.y - y);
      if (d < bestD) { best = lamp; bestD = d; }
    }
    if (best) { e.preventDefault(); toggleGroup(best.group); }
  });

  window.addEventListener('keydown', e => {
    if (e.repeat || e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.code === 'Escape' && suspended) { resumeSuspended(); return; }
    if (e.code === 'KeyP' || e.code === 'Escape') { togglePause(); return; }
    const m = /^Digit([0-9])$/.exec(e.code);
    if (m) { e.preventDefault(); toggleGroup((Number(m[1]) + 9) % 10); }
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
