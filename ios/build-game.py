#!/usr/bin/env python3
"""Copies the game (index.html, style.css, game.js) into the app as TrafficSim/game/,
with the fonts loaded from the app bundle instead of Google Fonts so it works offline."""
import os, re, shutil
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, '..')
dst = os.path.join(here, 'TrafficSim', 'game')
if os.path.exists(dst): shutil.rmtree(dst)
os.makedirs(dst)
html = open(os.path.join(root, 'index.html'), encoding='utf-8').read()
html = re.sub(r'<link rel="preconnect" href="https://fonts\.g[^"]*"[^>]*>\n?', '', html)
html, n = re.subn(r'<link rel="stylesheet" href="https://fonts\.googleapis\.com[^"]*">', '<link rel="stylesheet" href="fonts/fonts.css">', html)
assert n == 1, 'Google Fonts link not found in index.html'
html = html.replace('<html lang="en">', '<html lang="en" class="native">', 1)
open(os.path.join(dst, 'index.html'), 'w', encoding='utf-8').write(html)
for f in ('style.css', 'game.js'):
    shutil.copy(os.path.join(root, f), dst)
shutil.copytree(os.path.join(here, 'fonts'), os.path.join(dst, 'fonts'))
print('game copied into TrafficSim/game')
