# Feedback and feature ideas (to revisit after the native switch)

Collected from four review agents (simulation, screens and layout, game flow and saving, iOS
and performance) after build 14. The bugs they found are already fixed; this is what's left to
decide on.

## Feedback on the game

**Difficulty and pacing**
- Level 6 is the sharpest difficulty jump. A well-played test bot lost about half its runs, mostly
  to patience drained by left-turn lanes waiting 60–170 s.
- About 1 in 5 cars runs a yellow under frequent switching, so the box stays busy and careful play
  means a lot of all-red waiting. Fits the theme; newer players may find it slow.
- Going all-red always clears a jam within a minute (good).

**Scoring and progression**
- Stars (out of 21) are counted but unlock nothing.
- The win card says "Try to beat your times", but best times are tracked and never shown.
- Stars ignore score, so a 3-star clear with a low score feels finished; replays have little pull.
- Losing records nothing: no "best: 27/30" to show progress on a near miss.
- Any single honk resets the streak, so ×3 is almost unreachable at high traffic. Dropping one
  step instead of resetting may feel fairer.
- Freeplay bests are filed under the lightest density played in a run, which isn't explained.

**Screens**
- The look holds up from iPhone SE to iPad; busiest, emergency and colour-blind states read well.
- In landscape about two-thirds of the left column is empty, while signal buttons shrink to
  30–36 px on levels 6–7 (below 44 pt on the hardest levels).
- How to play says counts sit "under" each set of buttons; for the top corners they sit above.
- "New best!" and the 8 px HUD labels (CRASHES, PATIENCE) are small on phones.
- Some pixel-font text isn't a multiple of 8 px, so it renders soft; the smallest labels are
  hard to read.

## Feature ideas

| Idea | What it is | Notes |
|---|---|---|
| Daily challenge | Same map, seed and traffic for everyone each day; best per day; shareable result | `seeded()` RNG already exists |
| Survival mode | Freeplay with patience and crash limits; density ramps up; score = time survived | Reuses `hasLimits` and live density |
| Star rewards | Stars unlock night/rain variants of campaign maps or a bonus shift | Gives the 21 stars a purpose |
| Game Center | Leaderboards per map and density; achievements for stars and no-crash shifts | Planned in Stage 1d |
| Sound | Pixel beeps for switching, crash thud, siren; mute switch | Planned in Stage 1d |
| iCloud save | Mirror progress to iCloud so it survives a reinstall | Also guards against WebKit storage eviction |
| First-run guide | Level 1 points at a button ("tap to go green") and the patience bar | Instead of relying on the long How to play |
| Shift heatmap | After a shift, show where cars waited longest and where crashes happened | Wait and crash data already exist |
| Per-level stats | Best time, best cars/min, fewest crashes, last attempt in Records | |
| Shift modifiers | Optional handicaps ("no left arrows", "ambulance every 30 s") with score multipliers | Replay value |
| Pedestrian push buttons | Waiting walkers show on the Walk button; all-walk scramble phase earns a bonus | |
| Flashing yellow left | Permissive left turns that yield to oncoming traffic | Uses existing yield logic |
| Emergency pre-emption bonus | Extra points for greening the lane before the vehicle slows | Makes the 5 s warning a skill moment |
| "What's blocking" hint | Highlight the cars keeping a red "!" busy | Helps learn when it's safe |
| Rush tag on the corner | Show rush on the affected corner's label instead of a floating pill | Removes a class of overlap bugs |
| Large text setting | Bump pixel labels to 16 px multiples, next to Big buttons | |
| Landscape side panel | Use the empty column for per-corner wait bars | |
| Home-screen widget | "Shift N · ★ x/21 · best score", tap to resume | Needs an App Group |
| Low Power Mode | 30 fps and no night lighting when the phone is in Low Power Mode | |

## Small leftovers noted in review
- Esc can't close the level list after a win or loss when no shift is suspended.
- Very old saves (unlocked + best only) show finished levels as "Open" with no stars.
- An emergency whose lane is backed up past the map edge waits in "warn" with the countdown at 0s
  (no penalty, so harmless, but confusing).
- The game doesn't pause on interruptions that don't hide the app (Control Center, call banner).
- Re-running a TestFlight workflow reuses the run number, so Apple rejects it as a duplicate build.
