# Compares where iikb's rows of keys sit with the system keyboard's, from one `scripts/sim all <tag>` or `scripts/sim duo <tag>` run's
# dark shots, where every key stands apart from the backdrop (in light the bottom row runs into the system's bar below it).
# Letter rows are compared by top, height and outer edges; the bottom row by its return key's top and height only, since the system
# one holds keys a third-party keyboard can't have (mic, emoji). docs/design.md says where iikb moves rows off Apple's on purpose (the open Duo).
# uv run --with pillow --with numpy --with scipy scripts/shotdiff.py <tag>
import glob
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

RAW = os.path.join(os.path.dirname(__file__), '..', 'shots', 'raw')
# Pixels per point in a screenshot: the minis' panels are 1080 pixels across 375 points.
SCALES = {'ipad': 2, 'iphone-se': 2, 'iphone-13-mini': 1080 / 375}


def rows(path, scale):
    image = np.asarray(Image.open(path).convert('RGB')).astype(int)
    height, width, _ = image.shape
    # The backdrop between the keys isn't one color everywhere: try the commonest colors under the screen's middle, keeping
    # the one that tells the most rows, and the most keys, apart.
    colors, counts = np.unique(image[height // 2 :].reshape(-1, 3), axis=0, return_counts=True)
    return max((rows_on(image, scale, c) for c in colors[np.argsort(-counts)[:6]]),
               key=lambda r: (len(r), sum(k[4] for k in r)))


def rows_on(image, scale, background):
    height, width, _ = image.shape
    mask = np.abs(image - background).sum(axis=2) > 24
    mask[: height // 2] = False
    labels, _ = ndimage.label(mask)
    keys = []
    for ys, xs in ndimage.find_objects(labels):
        h, w = (ys.stop - ys.start) / scale, (xs.stop - xs.start) / scale
        if 25 < h < 90 and 20 < w < width / scale * 0.9:
            keys.append((ys.start / scale, ys.stop / scale, xs.start / scale, xs.stop / scale))
    found = []
    for key in sorted(keys):
        row = next((r for r in found if abs(r[0][0] - key[0]) < 3 and abs(r[0][1] - key[1]) < 3), None)
        row.append(key) if row else found.append([key])
    span = lambda r: max(k[3] for k in r) - min(k[2] for k in r)
    letters = [r for r in found if len(r) >= 3 and span(r) > width / scale * 0.6][:3]
    tall = letters[0][0][1] - letters[0][0][0] if letters else 0
    # The bottom row by its return key, the rightmost: the others run into the system's globe and mic under them.
    below = [k for k in keys if letters and 0 < k[0] - letters[-1][0][1] < tall and k[1] - k[0] < tall + 3]
    last = [[max(below, key=lambda k: (k[3], -k[0]))]] if below else []
    return [(np.median([k[0] for k in r]), np.median([k[1] for k in r]), min(k[2] for k in r), max(k[3] for k in r), len(r))
            for r in letters + last]


tag = sys.argv[1]
worst = 0.0
for reference in sorted(glob.glob(os.path.join(RAW, f'*{tag}-*system-dark.png')) +
                    glob.glob(os.path.join(RAW, 'duo', f'{tag}-*-system-dark.png'))):
    ours = reference.replace('-system-', '-iikb-')
    if not os.path.exists(ours):
        continue
    name = os.path.basename(reference).replace('-system-dark.png', '')
    scale = next((v for k, v in SCALES.items() if name.startswith(k)), 3)
    system, iikb_ = rows(reference, scale), rows(ours, scale)
    if min(len(system), len(iikb_)) < 3:
        print(f'{name:40} found {len(system)} rows, ours {len(iikb_)}')
        continue
    cells = []
    for i, (a, b) in enumerate(zip(system, iikb_)):
        edges = (a[2] - b[2], b[3] - a[3]) if i < 3 else (0, 0)
        top, tall = b[0] - a[0], (b[1] - b[0]) - (a[1] - a[0])
        worst = max(worst, abs(top), abs(tall), *map(abs, edges))
        cells.append(f'{top:+5.2f}/{tall:+5.2f}' + (f' ↔{edges[0]:+.2f},{edges[1]:+.2f}' if any(edges) else ''))
    print(f'{name:40} ' + ' | '.join(cells))
print(f'worst {worst:.2f}pt (each row: top/height off Apple\'s, ↔ how much wider its keys reach on the left and right)')
