# GridlockCore

The game's rules and traffic simulation in plain Swift (no UI), being ported from `game.js`
for the fully native app (Stage 2 in `docs/native-plan.md`). Because it has no UI it builds and
tests anywhere; the **Core** GitHub workflow runs `swift test` on every change to `core/`
without making a TestFlight build.

| Path | What it is |
|---|---|
| `Sources/GridlockCore/Resources/levels.json` | the seven levels, exported from `game.js` (one source for both) |
| `Sources/GridlockCore/Geometry.swift` | lanes, the box, crosswalks, the paths cars take, lamps, signal conflicts |
| `Sources/GridlockCore/Simulation.swift`, `Entities.swift` | a shift: signals, spawning and traffic flow, driving, merges, yellow-light decisions, pedestrians, emergencies, crashes, score and patience |
| `Sources/GridlockCore/Random.swift` | the seeded dice (mulberry32), the same generator the JavaScript tests use |
| `Tests/GridlockCoreTests/Fixtures/` | the JavaScript game's own output, which the Swift code must match: every level's geometry, and seven seeded shifts played by a scripted player, second by second |
| `tools/export-fixtures.js` | regenerates `levels.json` and the fixtures from `game.js` |

Regenerate after changing levels or geometry in `game.js`: `node core/tools/export-fixtures.js`.
