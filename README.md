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

## Score, combos and stars

- Every car you clear scores 10 points, times your combo. The combo grows by ×0.5 for every 10 cars in a row cleared without anyone starting to honk, up to ×3. A honking driver or pedestrian, or a crash, resets it.
- **Green Wave:** switch a signal off after it has sent at least 4 cars through and nobody is left waiting in its lanes, and you get 5 bonus points per car.
- Crashes cost 100 points and hitting a pedestrian costs 150.
- Each level awards up to three stars: clear the goal, finish with no crashes, and never let city patience drop below 50%. Stars and your best score show in the level list; stars you've earned stay earned.
- Result screens show cars per minute, average wait and longest wait. In freeplay, your best score and best cars per minute are kept for each map and density.

## Pedestrians

From level 3 on, people wait at the corners. Each crosswalk has a Walk button (a walking figure on a rounded-square button) beside the nearest waiting cars. On Walk they cross; when you switch it off, the hand flashes for a few seconds so the last walkers can finish.

- Turning drivers stop for people in the crosswalk.
- Straight-through traffic on green does not. Giving Walk across a street whose straight traffic is moving gets someone hit, which counts as a crash. The red **!** warns you before you do it.
- People look before stepping off the curb and wait for a car stopped in their way. Waiting too long makes them lose patience, the same as drivers.

## Road layouts

Levels mix up the streets instead of only adding lanes:

- **One-way streets:** every lane heads the same way, and some turns are impossible.
- **T-junctions:** one road ends, so its drivers can only turn left or right.
- **Lane drops:** fewer lanes leave the intersection than arrive. The outer lane tapers into the next after the box. Drivers already in the continuing lane go first, and merging drivers wait their turn.
- **Don't block the box:** drivers won't enter the intersection unless there's room on the far side, so a backed-up merge can hold up a green light.

## Levels

| # | Name | Layout | Switches |
|---|------|--------|----------|
| 1 | First Shift | 1 lane each way | 2 |
| 2 | Turn Lanes | Left-turn lanes | 4 |
| 3 | Crosswalks | Left-turn lanes, pedestrians | 6 |
| 4 | One Way | Two-way Main St, three-lane one-way avenue | 5 |
| 5 | Harbor Merge | T-junction; Main St drops to one lane northbound | 5 |
| 6 | Split Phases | Directions controlled separately; the avenue drops a lane both ways | 8 |
| 7 | Downtown Rush | Every direction and turn separately; Main St drops a lane northbound | 10 |

Progress and best times are saved in the browser. Number keys <kbd>1</kbd>–<kbd>9</kbd> and <kbd>0</kbd> work the switches in order.

## Freeplay

Pick **Freeplay** at the bottom of the level list to play any of the seven maps with no goal. Choose the traffic density (1 Quiet to 10 Gridlock; 5 matches that map's level at its busiest, and Gridlock sends nearly four times as many cars), whether rush-hour surges happen, and whether pedestrians cross. There is no patience meter and crashes never end the game, so you can run it however you like. A density slider under the map changes traffic while you play, and your settings are remembered.

## How it works

`game.js` builds each level's lane paths (straight lines, plus quarter-ellipse curves for turns) and works out which signal groups conflict by checking where those paths come close. Cars follow the car ahead in their approach lane and exit lane, slow for turns, and on yellow either stop or clear the intersection if they are too close to stop. They do not yield to cross traffic, so a collision check between cars in the box creates crashes, with wrecks, sparks, debris, smoke and screen shake.

- `index.html` — page layout and HUD
- `style.css` — styling
- `game.js` — levels, geometry, simulation and canvas rendering

## Ideas for next steps

- Emergency vehicles that need a clear path
- Permissive left turns (yield on a green ball)
- A second intersection down the block with timing between the two
