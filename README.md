# Intersection Control

A small browser game where you run the traffic lights at a city intersection.

Main St (north–south) crosses 1st Ave (east–west). Each street has two lanes, one in each direction. Only one street can have green at a time.

## How to play

Open `index.html` in a browser. No build step or server is needed.

- **Switch the lights:** tap the intersection, click **Switch lights**, or press <kbd>Space</kbd>. The green street goes yellow, then all-red, then the other street gets green.
- **Pause:** <kbd>P</kbd> or <kbd>Esc</kbd>.
- Drivers stopped for more than 8 seconds start honking (red `!`) and drain the city's patience. When a queue backs up off the edge of the map, a red `+N` badge appears and patience drains faster.
- Every car you get through refills a little patience. Traffic gets heavier over time, and rush-hour surges hit one approach at a time.
- The shift ends when patience reaches zero. Your score is the number of cars cleared.

## Files

- `index.html` — page layout and HUD
- `style.css` — styling
- `game.js` — simulation (signals, car following, spawning) and canvas rendering

## Ideas for next steps

- Turn lanes and protected left-turn arrows
- Pedestrians on the crosswalks
- Emergency vehicles that need a clear path
- Red-light runners and crash detection
- More intersections along the block
