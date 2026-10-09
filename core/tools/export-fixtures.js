// Exports the reference data the Swift engine is checked against, from the
// current JavaScript game: the levels (shared data, loaded by the engine) and
// every level's computed geometry. Run from the repo root:
//   node core/tools/export-fixtures.js
// Needs Playwright with Chromium (the game runs in a real page).
const fs = require('fs');
const path = require('path');
const { chromium } = require(process.env.PLAYWRIGHT || '/opt/node22/lib/node_modules/playwright');

const root = path.resolve(__dirname, '..', '..');
const hook = 'let state; window.__core = { LEVELS, buildGeometry };\n';

(async () => {
  const src = fs.readFileSync(path.join(root, 'game.js'), 'utf8');
  if (!src.includes('let state;\n')) throw new Error('game.js changed: hook point not found');
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.route('**/fonts.googleapis.com/**', r => r.abort());
  await page.route('**/game.js', r => r.fulfill({ contentType: 'text/javascript', body: src.replace('let state;\n', hook) }));
  await page.goto('file://' + path.join(root, 'index.html'));
  const out = await page.evaluate(() => {
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
    return { levels: LEVELS, geometry };
  });
  await browser.close();
  fs.writeFileSync(path.join(__dirname, '..', 'Sources/GridlockCore/Resources/levels.json'), JSON.stringify(out.levels, null, 1) + '\n');
  fs.writeFileSync(path.join(__dirname, '..', 'Tests/GridlockCoreTests/Fixtures/geometry.json'), JSON.stringify(out.geometry) + '\n');
  console.log(`exported ${out.levels.length} levels, ${out.geometry.reduce((n, g) => n + g.paths.length, 0)} paths`);
})();
