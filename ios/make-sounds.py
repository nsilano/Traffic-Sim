#!/usr/bin/env python3
"""Makes the app's chiptune sound effects (TrafficSim/Sounds/*.wav).

Square and triangle waves with short fades, like an old arcade cabinet. Run it again after
changing a sound; the files it writes are checked in, so the build doesn't need it.
"""
import math, random, struct, wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).parent / 'TrafficSim' / 'Sounds'


def tone(freq, ms, vol=0.35, shape='square', slide=None):
    """One note; slide makes the pitch glide to another frequency."""
    n = int(RATE * ms / 1000)
    out, phase = [], 0.0
    for i in range(n):
        f = freq if slide is None else freq + (slide - freq) * i / n
        phase += f / RATE
        p = phase % 1
        if shape == 'square':
            v = 1.0 if p < 0.5 else -1.0
        elif shape == 'triangle':
            v = 4 * abs(p - 0.5) - 1
        else:  # noise
            v = random.uniform(-1, 1)
        # 4 ms fade in and a fade out over the last quarter, so nothing clicks.
        env = min(1, i / (RATE * 0.004)) * min(1, (n - i) / (n * 0.25 + 1))
        out.append(v * vol * env)
    return out


def rest(ms):
    return [0.0] * int(RATE * ms / 1000)


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def notes(seq, ms, vol=0.3, shape='square'):
    out = []
    for f in seq:
        out += tone(f, ms, vol, shape) if f else rest(ms)
    return out


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 32000)) for s in samples))


random.seed(7)
C5, E5, G5, C6, E6, G6 = 523, 659, 784, 1047, 1319, 1568
write('tap', tone(1400, 22, 0.18))                                   # menu choice
write('go', tone(660, 70, 0.28, slide=990))                          # a light turns green
write('stop', tone(520, 80, 0.26, slide=350))                        # a light goes to yellow
crash = [s * math.exp(-i / (RATE * 0.12)) for i, s in enumerate(tone(0, 420, 0.6, 'noise'))]
write('crash', mix(crash, tone(110, 260, 0.5, 'triangle', slide=45)))
write('siren', notes([760, 960] * 3, 140, 0.18))                     # emergency announced
write('clear', notes([C5, E5, G5, C6], 55, 0.25))                    # emergency got through
write('held', tone(300, 320, 0.3, slide=140))                        # emergency held up
write('combo', notes([G5, C6], 60, 0.22))                            # combo went up
write('wave', notes([C5, E5, G5, C6, E6], 45, 0.22, 'triangle'))     # green wave bonus
write('streak', notes([E5, C5], 90, 0.22))                           # streak lost
write('win', notes([C5, E5, G5, C6, 0, G5, C6, E6, G6], 95, 0.26))
write('lose', notes([G5, E5, C5, 0, 392, 330, 262], 120, 0.26, 'triangle'))
