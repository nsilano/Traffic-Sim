# Gridlock for iPhone and iPad

A small native app that runs the game full screen and offline. The game itself is still
`index.html`, `style.css` and `game.js` at the root of the repo; the app bundles a copy of them with the fonts.

## How it gets to TestFlight

`.github/workflows/testflight.yml` builds the app on a GitHub-hosted Mac (Xcode 26) and uploads it to
TestFlight. It runs on every push to the default branch (or `main`) that changes the game or this folder, and from
GitHub → Actions → TestFlight → *Run workflow*.

It needs four repository secrets (Settings → Secrets and variables → Actions):

| Name | Value |
|---|---|
| `TEAM_ID` | Team ID, developer.apple.com → Membership details |
| `ASC_KEY_ID` | Key ID of an App Store Connect API key with **Admin** access |
| `ASC_ISSUER_ID` | Issuer ID from the App Store Connect API page |
| `ASC_KEY` | the whole contents of that key's `.p8` file |

The bundle ID in `project.yml` must match the app record in App Store Connect.
Each run uses the GitHub run number as the build number. To change the name under the icon,
edit `CFBundleDisplayName` in `project.yml`.

## What is in here

| Path | What it is |
|---|---|
| `TrafficSim/TrafficSimApp.swift` | the app: the game full screen, with the native main menu over it while you're on the menu |
| `TrafficSim/GameView.swift` | the web view that runs the bundled game offline |
| `TrafficSim/GameBridge.swift` | the link between the app and the game: menu choices go in, menu state and haptic taps come out |
| `TrafficSim/MenuView.swift` | the native Pixel City main menu (SwiftUI) |
| `TrafficSim/Screens.swift` | native Levels, Records, Settings, Freeplay setup and How to play screens |
| `TrafficSim/GameCardView.swift` | native level intro, pause and results cards over the live game |
| `TrafficSim/SoundPlayer.swift`, `TrafficSim/Sounds/` | chiptune sound effects; `make-sounds.py` regenerates the WAVs |
| `TrafficSim/GameCenter.swift` | Game Center sign-in, leaderboards and achievements |
| `TrafficSim/Fonts/` | Press Start 2P and VT323 as app fonts for the native screens |
| `TrafficSim/Assets.xcassets` | app icon and launch colour |
| `fonts/` | Press Start 2P, VT323, Archivo and IBM Plex Mono (SIL Open Font License) so the app works offline |
| `build-game.py` | copies the game into the app and points it at the local fonts |
| `project.yml` | XcodeGen spec for the Xcode project |

Progress, stars and best scores are kept on the device between launches.

## Game Center

The app signs the player in to Game Center, posts scores and unlocks achievements on its own. For
that to work, set these up once in App Store Connect (My Apps → the app → **Services → Game Center**;
add Game Center to the app version too, under the version's **Game Center** section). The IDs must
match exactly.

**Leaderboards** (Classic, High score first, Integer):

| Leaderboard ID | Name |
|---|---|
| `com.nicsilano.gridlock.campaign` | Campaign score (best scores of all levels added up) |
| `com.nicsilano.gridlock.stars` | Stars |
| `com.nicsilano.gridlock.freeplay` | Freeplay best |

**Achievements** (100 points between them works well, e.g. 10/20/20/30/20):

| Achievement ID | Name | Earned when |
|---|---|---|
| `com.nicsilano.gridlock.first-shift` | First Shift | level 1 is finished |
| `com.nicsilano.gridlock.perfect-shift` | Perfect Shift | any level gets all three stars |
| `com.nicsilano.gridlock.every-shift` | Every Intersection | all seven levels are finished |
| `com.nicsilano.gridlock.all-stars` | Gridlock Legend | all 21 stars |
| `com.nicsilano.gridlock.freeplay-5000` | Rush Hour Hero | 5,000 points in one freeplay run |

Until they exist, Game Center quietly ignores the reports. TestFlight builds use Game Center's
sandbox, so test scores don't reach the live leaderboards.
