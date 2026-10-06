# Intersection Control

A browser game where you run the traffic signals at a city intersection. Open `index.html` in a browser; there is no build step.

## How to play

Each direction of traffic has its signal buttons on the map, on the block right beside its waiting line. The arrow on each button points the way those cars will drive: straight (right turns go with straight), or a left turn. Tap a red button to turn it green, and tap a green one to send it through yellow to red. Green street-name signs and a compass show which street is which. Number keys <kbd>1</kbd>–<kbd>8</kbd> work too, and tapping a lamp at a stop line does the same thing.

On the early levels one switch controls both directions of a street, so the buttons on both sides of the intersection change together.

The signals don't protect you. If two conflicting groups are green, or you turn one green while the other's cars are still clearing the box, cars crash. A red **!** on a button means turning it green right now would cross moving traffic.

- Clear the level's goal number of cars to win and unlock the next level.
- Three crashes end the shift.
- Drivers who wait too long start honking (red `!`) and drain the city's patience. Queues backing up off the map (red `+N`) drain it faster. Empty patience ends the shift.
- <kbd>P</kbd> or <kbd>Esc</kbd> pauses.

## Drivers

Every car gets a driver with its own habits:

- **Commuters** (most drivers) cruise at a normal speed. **Speeders** are faster, quicker off the line and follow closer. **Cautious** drivers are slower, react later and leave bigger gaps. **Trucks** are slow to accelerate.
- Everyone takes a moment to react when the light turns green or the car ahead pulls away.
- **Yellow-light racers** (10% of drivers) wear an amber lightning bolt and outline from the moment they appear. When their light turns yellow, they speed up to beat it instead of stopping. They count as traffic in the box, so the red **!** still covers them. If one misjudges and can still stop when the light turns red, it gives up and stops.
- **Mistakes:** some drivers are distracted at green (a … bubble), some stall (hazard lights), and some tailgaters tap the car ahead in the queue ("BUMP", hazard lights on both). These delays never cost patience and never count as crashes.

## Levels

| # | Name | Lanes per direction (Main St / cross street) | Switches |
|---|------|------|------|
| 1 | First Shift | 1 / 1 | Main St, 1st Ave |
| 2 | Turn Lanes | left + 1 / left + 1 | Straight and left arrow for each street |
| 3 | Main St Widens | left + 2 / left + 1 | Same four, heavier Main St traffic |
| 4 | Split Phases | left + 2 / left + 2 | Northbound and southbound controlled separately, rush-hour surges |
| 5 | Downtown Rush | left + 3 / left + 2 | Every direction and turn separately (8 switches) |

Progress and best times are saved in the browser.

## Freeplay

Pick **Freeplay** at the bottom of the level list to play any of the five maps with no goal. Choose the traffic density (1 Quiet to 10 Gridlock; 5 matches that map's level at its busiest) and whether rush-hour surges happen. There is no patience meter and crashes never end the game, so you can run it however you like. A density slider under the map changes traffic while you play, and your settings are remembered.

## How it works

`game.js` builds each level's lane paths (straight lines, plus quarter-ellipse curves for turns) and works out which signal groups conflict by checking where those paths come close. Cars follow the car ahead in their approach lane and exit lane, slow for turns, and on yellow either stop or clear the intersection if they are too close to stop. They do not yield to cross traffic, so a collision check between cars in the box creates crashes, with wrecks, sparks, debris, smoke and screen shake.

- `index.html` — page layout and HUD
- `style.css` — styling
- `game.js` — levels, geometry, simulation and canvas rendering

## Ideas for next steps

- Pedestrians and walk signals
- Emergency vehicles that need a clear path
- Permissive left turns (yield on a green ball)
- A second intersection down the block with timing between the two
