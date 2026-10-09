# Gridlock: going fully native

Goal: Gridlock is a regular iPhone and iPad app, not a browser game. Done in stages so each one
ships to TestFlight on its own and nothing is half-finished in between.

Constraint: Xcode can't run in the cloud workspace, so Swift only gets compiled by the TestFlight
workflow on GitHub (macOS runner). Every stage ends with a push the owner approves, and a build
that fails is fixed before the next stage starts.

## Stage 0: bug fixes (done, builds 14–15)
Four review agents (simulation, UI/layout, game flow/saving, iOS/performance) found bugs; the
confirmed fixes are in. Their feedback and feature ideas are kept in `docs/ideas.md`.

## Stage 1: native app around the game
The game screen keeps the existing engine (web view, bundled and offline); everything else becomes
native SwiftUI in the Pixel City style (Press Start 2P and VT323 registered as app fonts).

- **1a. Bridge and native menu.** A typed message channel between Swift and the game
  (start level, freeplay, pause/resume, settings, progress, events such as level won/lost).
  Native main menu (night street, swaying light, arcade list, version label). In the app the
  web menu is never shown.
- **1b. Native screens.** Levels, Records, Settings (UserDefaults is the source of truth, pushed
  into the game), How to play, Freeplay setup.
- **1c. In-game overlays.** Pause, results and level intro as native sheets over the game.
- **1d. Sound and Game Center.** Native sound effects (AVAudioEngine), Game Center leaderboards and
  achievements (the owner creates them in App Store Connect). Retire the web link.

## Stage 2: Swift + SpriteKit game engine
Port the engine so no web view is left. The rules and simulation live in `core/` (GridlockCore),
a UI-free Swift package that GitHub builds and tests on every change without a TestFlight build. Each step is checked against the JS version with the same
seeds and scripted players before it replaces anything.

- **2a. Model.** Levels, geometry (lanes, paths, conflicts, crosswalks, overpass), constants.
- **2b. Simulation.** Cars, drivers (nerve, headway, merges), pedestrians, flow waves, emergencies,
  patience, scoring.
- **2c. Rendering.** SpriteKit scene: roads, cars, signals, night lighting, popups, banners.
- **2d. Controls and HUD.** Signal buttons on the map, HUD and dock in SwiftUI.
- **2e. Switch over.** Remove the web view and the bundled web files.

## Status
| Stage | State |
|---|---|
| 0 | done |
| 1a–1c | done (build 16) |
| 1d | done (build 17); Game Center needs the App Store Connect setup in ios/README.md |
| 2a | built: `core/` package, levels shared as JSON, geometry checked against the JS game |
| 2b | done: the simulation in `core/` plays seven seeded shifts identically to the JS game, second by second (Core run 2) |
| 2c | done: `GridlockRender` draws the board with Core Graphics; CI snapshots match the JS game's own renders level by level (fetched from the `ci-snapshots` branch) |
| 2d–2e | built: native game screen (board, signal sets, HUD, dock) and engine host; progress imported once from the web version; Settings → Classic engine switches back to compare (build 19) |
