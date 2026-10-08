# Intersection Control

A browser game where you run the traffic signals at a city intersection. Open `index.html` in a browser; there is no build step.

## How to play

The game opens on a Pixel City main menu: a night street in chunky pixel art and retro arcade fonts, with a skyline, cars driving past and a traffic light swaying on its wire that cycles green, amber and red. The version and, in the iPhone app, the build number sit in the top left corner (e.g. "1.0 · Build 9") with your stars in the top right. The menu is an arcade-style list with a blinking ▶ cursor (arrow keys move it): Play (your next shift, or resume one in progress), Freeplay, Levels, Records (stars and best scores), Settings and How to play.

Settings has switches for turn signals, the waiting counts on each corner, the busiest-corner marker, emergency vehicles in shifts, big signal buttons, colour-blind signal shapes, screen shake, CRT scanlines and haptics (a tap you feel each time you switch a light: lighter for green, firmer for a stop, on the iPhone app and phones that support vibration), all remembered between visits, plus resetting freeplay bests or all progress.

Every shift and freeplay run starts on empty streets that fill up over the first 45 seconds or so. From then on traffic is never a constant stream: the overall flow swells and eases over a minute or two, cars arrive in bunches as if released by the lights up the road, and every minute or so there's a quiet spell (announced as "Traffic easing off") or, in livelier traffic, a surge ("Wave of traffic coming"). Drivers stuck in a long queue off the map sometimes give up and take another route.

In a shift, a band at the top shows the score, combo, cars cleared, crashes, time and city patience. The signal buttons sit on the map itself, in a set per direction of traffic placed on the corner right beside that queue. Each button turns its signal green, or sends a green one through yellow to red. Arrows show where those cars go; walking-figure buttons are Walk signals. Number keys <kbd>1</kbd>–<kbd>9</kbd> and <kbd>0</kbd> (number row or keypad) work the buttons too, and tapping a lamp at a stop line does the same.

Each set is also a **monitor**: its label shows how many cars and people are waiting there (including cars backed up off the map) and the longest wait in seconds, turning amber and then red as drivers near the end of their patience. The busiest direction gets a steady yellow outline and a **★ Busiest** tag (it only moves once another corner has been clearly busier for a moment), and each button shows how many are waiting for that signal.

The signals don't protect you. If two conflicting groups are green, or you turn one green while the other's cars are still clearing the box, cars crash. A red **!** on a button means turning it green right now would cross moving traffic.

- Clear the level's goal number of cars to win and unlock the next level.
- Three crashes end the shift.
- Drivers who wait too long start honking and drain the city's patience. Empty patience ends the shift.
- <kbd>P</kbd> or <kbd>Esc</kbd> pauses.

## Drivers

Every car gets a driver with its own habits:

- **Commuters** (most drivers) cruise at a normal speed. **Speeders** are faster, quicker off the line and follow closer. **Cautious** drivers are slower, react later and leave bigger gaps. **Trucks** are slow to accelerate.
- Everyone takes a moment to react when the light turns green or the car ahead pulls away.
- No two drivers drive quite alike: each takes corners at their own pace (speeders cut them quick, trucks and cautious drivers ease round), keeps their own gap when stopped and their own following distance on the move, accelerates a little differently, and drifts a few percent around their cruising speed. A line of turning cars spreads out and bunches up instead of moving like a train.
- **Yellow lights are each driver's call.** Every driver has their own nerve: cautious drivers and most truckers stop, commuters vary, speeders often go for it. When the light turns yellow, a driver who's close enough, or bold enough, keeps going, sometimes from a crawl or reaching the line just as it turns red, so the junction can take a moment to clear. Anyone who has decided to go counts as traffic in the box, so the red **!** on conflicting buttons stays up until they're through: wait for it before you switch.
- **Turn signals,** only where they tell you something: a car in a lane that can go more than one way (say straight or right) blinks its turn as it nears the line, and a car whose lane ends signals the merge. Cars in dedicated turn lanes don't bother; the arrows on the road already say where they're going.
- **Merges** work like a zipper: a car whose lane ends eases off beside traffic in the next lane and slips in behind it, or goes first when it's clearly ahead.
- **Yellow-light racers** (10% of drivers) wear an amber lightning bolt and outline from the moment they appear. When their light turns yellow, they speed up to beat it instead of stopping. They count as traffic in the box, so the red **!** still covers them. If one misjudges and can still stop when the light turns red, it gives up and stops.
- **Mistakes:** some drivers are distracted at green (a … bubble), some stall (hazard lights), and some tailgaters tap the car ahead in the queue ("BUMP", hazard lights on both). These delays never cost patience and never count as crashes.

## Emergency vehicles

From level 3 on (and in freeplay, unless you switch them off), an ambulance, fire engine or police car needs to get straight through every minute or so. A banner announces it a few seconds ahead with where it's coming from ("Ambulance from the south · clear Northbound!"), a flashing red-and-blue marker at the edge of the map shows where it will appear and which way it will drive, and that direction's signal set flashes red and blue with a white ring on the buttons that give it a green.

The vehicle waits at a red light like anyone else, so it's on you: stop the cross traffic and give its lane the green. The clock only runs while it's actually stopped at the lights: if its lane is already moving, there's no countdown at all. Once it comes to a stop, a ring around it counts down 8 seconds plus a little for each car queued ahead of it, and only runs down while it's standing still. Get it across the stop line without the ring running out for a **+50** bonus. Let the ring run out and you lose **120 points** (and 12% patience in a shift), again for every further 10 seconds it sits stopped. Wrecking it costs the same on top of the crash.

## Score, combos and stars

- Every car you clear scores 10 points, times your combo. The combo grows by ×0.5 for every 10 cars in a row cleared without anyone starting to honk, up to ×3. A honking driver or pedestrian, a crash, or a held-up emergency vehicle resets it, and the "Streak lost" message says which (a honking driver is also marked HONK! on the map). How to play includes a key to the marks on the map: the busiest corner's yellow outline and ★, the waiting count and longest wait under each set, the numbers on the buttons, the red **!**, the lightning bolt and the siren ring.
- **Green Wave:** switch a signal off after it has sent at least 4 cars through and nobody is left waiting in its lanes, and you get 5 bonus points per car.
- Crashes cost 100 points and hitting a pedestrian costs 150.
- Each level awards up to three stars: clear the goal, finish with no crashes, and never let city patience drop below 50%. Stars and your best score show in the level list; stars you've earned stay earned.
- Result screens show cars per minute, average wait and longest wait. In freeplay, your best score and best cars per minute are kept for each map and density; if you change the density mid-run, the run counts for the lightest density you played at. Calm and Wild runs keep their own bests.

## Pedestrians

From level 3 on, people walk in along the sidewalks and wait at the corners. Each crosswalk has a Walk button (a walking figure on a rounded-square button) beside the nearest waiting cars. On Walk they cross; when you switch it off, the hand flashes for a few seconds so the last walkers can finish.

- Turning drivers stop for people in the crosswalk.
- Straight-through traffic on green does not. Giving Walk across a street whose straight traffic is moving gets someone hit, which counts as a crash. The red **!** warns you before you do it.
- People look before stepping off the curb and wait for a car stopped in their way. Waiting too long makes them lose patience, the same as drivers.

## Road layouts

Levels mix up the streets instead of only adding lanes:

- **One-way streets:** every lane heads the same way, and some turns are impossible.
- **T-junctions:** one road ends, so its drivers can only turn left or right.
- **Lane drops:** fewer lanes leave the intersection than arrive. The outer lane tapers into the next after the box, and drivers zipper-merge: whoever is ahead goes first.
- **Divided roads:** a planted median separates the two directions, which widens the box and lengthens left turns.
- **Don't block the box:** drivers won't enter the intersection unless there's room on the far side, so a backed-up merge can hold up a green light.

## Levels

| # | Name | Layout | Switches |
|---|------|--------|----------|
| 1 | First Shift | 1 lane each way | 2 |
| 2 | Turn Lanes | Left-turn lanes | 4 |
| 3 | Crosswalks | Left-turn lanes, pedestrians; tree canopies hang over the outer lanes | 6 |
| 4 | One Way | Two-way Main St, three-lane one-way avenue; road works and long building shadows | 5 |
| 5 | Harbor Merge | T-junction on the waterfront at night (headlights and streetlights only); Main St drops to one lane northbound | 5 |
| 6 | Split Phases | Directions controlled separately; 3rd Ave is a divided boulevard with a planted median and drops a lane both ways | 8 |
| 7 | Downtown Rush | Every direction and turn separately; Main St drops a lane northbound; an overpass hides part of the queue | 10 |

Progress and best times are saved in the browser. Number keys <kbd>1</kbd>–<kbd>9</kbd> and <kbd>0</kbd>, on the number row or the numeric keypad, work the switches in order.

## Freeplay

Pick **Freeplay** at the bottom of the level list to play any of the seven maps with no goal. Choose the traffic density (1 Quiet to 10 Gridlock; 5 matches that map's level at its busiest, and Gridlock sends nearly four times as many cars on average) and the traffic flow, which sets how much it swings around that average:

| Flow | What it's like |
|---|---|
| Calm | Gentle swings and the odd quiet spell |
| Lively (default) | Waves and bunches, quiet spells and some surges |
| Wild | Big surges and sudden lulls, more often |

Quiet spells drop to around the map's normal traffic even on Gridlock, so a jammed junction gets a chance to clear. You also choose whether rush-hour surges happen, whether pedestrians cross, and whether it's night (freeplay starts at night unless you untick it). There is no patience meter and crashes never end the game, so you can run it however you like. A density slider under the map changes traffic straight away while you play (with a readout of what the flow is doing: building up, picking up, easing off, quiet spell or surge), and your settings are remembered. On a phone held sideways the readout sits beside the map. On phones and tablets the screen is filled edge to edge: the readout sits right under the status bar, a dock at the bottom (goal and patience, or the freeplay traffic controls) runs down to the home indicator and takes up any spare height, and held upright the map shows a taller slice of the junction, zoomed in as far as each map allows. Signal buttons are 44pt finger targets; on maps with wide roads they stack in a column on a tall screen, and only shrink when nothing else fits. Held sideways, the readout and dock sit to the left of a full-height map.

## How it works

`game.js` builds each level's lane paths (straight lines, plus quarter-ellipse curves for turns) and works out which signal groups conflict by checking where those paths come close. Cars follow the car ahead in their approach lane and exit lane, slow for turns, and on yellow either stop or clear the intersection if they are too close to stop. They do not yield to cross traffic, so a collision check between cars in the box creates crashes, with wrecks, sparks, debris, smoke and screen shake.

- `index.html` — page layout and HUD
- `style.css` — styling
- `game.js` — levels, geometry, simulation and canvas rendering

## Ideas for next steps

- Emergency vehicles that need a clear path
- Permissive left turns (yield on a green ball)
- A second intersection down the block with timing between the two
