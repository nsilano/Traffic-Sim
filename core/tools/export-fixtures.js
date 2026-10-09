// Exports the reference data the Swift engine is checked against, from the
// current JavaScript game: the levels (shared data, loaded by the engine) and
// every level's computed geometry. Run from the repo root:
//   node core/tools/export-fixtures.js
// Needs Playwright with Chromium (the game runs in a real page).
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PLAYWRIGHT || '/opt/node22/lib/node_modules/playwright');

const root = path.resolve(__dirname, '..', '..');
const hook = 'let state; window.__core = { LEVELS, buildGeometry, newState, prefill, step, toggleGroup, isUnsafe, ' +
  'get state() { return state; }, set state(v) { state = v; } };\n';

// The simulation runs: seeds, levels and how long. Each records a snapshot every second.
const RUNS = [0, 1, 2, 3, 4, 5, 6].map(level => ({ level, seed: 1000 + level, seconds: 150 }));

(async () => {
  const src = fs.readFileSync(path.join(root, 'game.js'), 'utf8');
  if (!src.includes('let state;\n')) throw new Error('game.js changed: hook point not found');
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.route('**/fonts.googleapis.com/**', r => r.abort());
  // No animation frames: drawing must not use up random numbers between steps.
  await page.addInitScript(() => { window.requestAnimationFrame = () => 0; });
  await page.route('**/game.js', r => r.fulfill({ contentType: 'text/javascript', body: src.replace('let state;\n', hook) }));
  await page.goto('file://' + path.join(root, 'index.html'));
  const out = await page.evaluate(runs => {
    const { LEVELS, buildGeometry } = window.__core;
    const r = x => Math.round(x * 1e6) / 1e6;
    const geometry = LEVELS.map(level => {
      const g = buildGeometry(level);
      return {
        box: { x0: r(g.box.x0), x1: r(g.box.x1), y0: r(g.box.y0), y1: r(g.box.y1) },
        crosswalks: g.crosswalks.map(c => ({ leg: c.leg, group: c.group, uc: r(c.uc), road0: r(c.road0), road1: r(c.road1) })),
        lamps: g.lamps.map(l => ({ dir: l.dir, lane: l.lane, kind: l.kind, group: l.group, x: r(l.x), y: r(l.y) })),
        paths: g.paths.map(p => ({
          dir: p.dir, lane: p.lane, move: p.move, group: p.group,
          pts: p.pts.map(q => [r(q.x), r(q.y)]), len: r(p.len), A: r(p.A), exitStart: r(p.exitStart), stopS: r(p.stopS),
          laneKey: p.laneKey, exitKey: p.exitKey, boxKey: p.boxKey, merges: p.merges, mergeSide: p.mergeSide,
          mergeS: r(p.mergeS), mergeAt: r(p.mergeAt),
          crossings: p.crossings.map(c => ({ cw: g.crosswalks.indexOf(c.cw), s0: r(c.s0), s1: r(c.s1) })),
        })),
        conflicts: g.conflicts.map(s => [...s].sort((a, b) => a - b)),
      };
    });
    // Same generator as GridlockCore's Random (mulberry32).
    const mulberry32 = a => () => {
      a |= 0; a = a + 0x6D2B79F5 | 0;
      let t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
    // A scripted player both versions run: it gives each car group a 7-second green in
    // turn, switching only when the next one is safe (see SimulationTests.swift).
    const core = window.__core;
    const simulation = runs.map(run => {
      Math.random = mulberry32(run.seed);
      core.state = core.newState(run.level);
      core.prefill();
      const st = core.state;
      st.mode = 'running';
      const carGroups = st.groups.filter(g => g.kind === 'car').length;
      let cur = 0, greenSince = 0;
      const frames = [];
      for (let f = 1; f <= run.seconds * 60; f++) {
        if (st.mode !== 'running') break;
        const g = st.groups[cur];
        if (g.state === 'green' && st.t - greenSince >= 7) core.toggleGroup(cur);
        if (!st.groups.some((x, i) => i < carGroups && x.state !== 'red')) {
          const next = (cur + 1) % carGroups;
          if (!core.isUnsafe(next)) { core.toggleGroup(next); cur = next; greenSince = st.t; }
        }
        core.step(1 / 60, false);
        if (f % 60 === 0) {
          frames.push({
            t: r(st.t), cars: st.cars.length, peds: st.peds.length, cleared: st.cleared, crashes: st.crashes,
            score: r(st.score), patience: r(st.patience), wrecks: st.wrecks.length,
            sumS: r(st.cars.reduce((n, c) => n + c.s, 0)), sumV: r(st.cars.reduce((n, c) => n + c.v, 0)),
            lastId: st.carSeq, emergency: st.emergency ? st.emergency.phase : null,
          });
        }
      }
      return { ...run, mode: st.mode, frames };
    });
    return { levels: LEVELS, geometry, simulation };
  }, RUNS);
  await browser.close();
  fs.writeFileSync(path.join(__dirname, '..', 'Sources/GridlockCore/Resources/levels.json'), JSON.stringify(out.levels, null, 1) + '\n');
  fs.writeFileSync(path.join(__dirname, '..', 'Tests/GridlockCoreTests/Fixtures/geometry.json'), JSON.stringify(out.geometry) + '\n');
  fs.writeFileSync(path.join(__dirname, '..', 'Tests/GridlockCoreTests/Fixtures/simulation.json'), JSON.stringify(out.simulation) + '\n');
  console.log(`simulation runs: ${out.simulation.map(s => `level ${s.level + 1}: ${s.frames.length}s, ${s.frames.at(-1).cleared} cleared, ${s.frames.at(-1).crashes} crashes, ${s.mode}`).join('; ')}`);
  console.log(`exported ${out.levels.length} levels, ${out.geometry.reduce((n, g) => n + g.paths.length, 0)} paths`);
})();
