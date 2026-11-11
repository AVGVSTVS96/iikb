# Which screens changed between two runs of scripts/parity with the clock stopped (IIKB_NOW): each <screen>.png in
# <after> against the same in <before>, pixel for pixel but for what a run can't hold still, which each shot's outline
# (<screen>.json, from UITests/ParityShots) places: GIF tiles, whose pictures are KLIPY's and play, and dictation's bar
# mid-recording, each with the glass around it that picks up its colors (LIVE), the caret blinking in a text field, with
# its ghost in the glass below, and the swipe shot mid-trail (UNHELD). A pixel counts as changed when a channel moves
# more than the glass's faint tint does. Each change is named by the elements whose frame or label differs where it is.
# Writes <out>/report.md, a line per changed screen, and <out>/<screen>.png, before | after | after with the change in
# red; prints the report.
# uv run --with pillow --with numpy --with scipy scripts/screens.py <before> <after> <out>
import filecmp
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

CHANGED = 16  # of 255
GLASS = 20  # points around what moves, which the glass near it picks up
CARET = 8  # points: a narrower mark inside a text field is its caret
# On a screen shot without an outline (the app's pages, through simctl), what the outline would place is told by size:
# a mark this narrow is a caret, one this small each way a spinner.
NARROW, SMALL = 3, 16
LIVE = {'dictation-': 'iikb.mic'}
UNHELD = ('keyboard-swipe-',)


def outline(folder, screen):
    path = os.path.join(folder, screen + '.json')
    if not os.path.exists(path):
        return []
    with open(path) as file:
        return json.load(file)


def held(screen, elements, scale, shape):
    live = [element for start, element in LIVE.items() if screen.startswith(start)]
    mask = np.zeros(shape, bool)
    for element in elements:
        if element['id'] in live or element['id'].startswith('iikb.gif.'):
            x, y, w, h = element['frame']
            x0, y0 = (max(round((v - GLASS) * scale), 0) for v in (x, y))
            x1, y1 = (round((v + GLASS) * scale) for v in (x + w, y + h))
            mask[y0:y1, x0:x1] = True
    return mask


def inputs(elements):
    return [element['frame'] for element in elements if element['input']]


def inside(box, frame):
    x, y, w, h = frame
    return box[0] >= x and box[1] >= y and box[2] <= x + w and box[3] <= y + h


def overlaps(box, frame):
    x, y, w, h = frame
    return box[0] < x + w and box[2] > x and box[1] < y + h and box[3] > y


def named(element):
    return element['id'] or element['label']


def changes(before, after, box):
    """The elements in the box that moved, resized, changed their text, came or went, by identifier or label."""

    def index(elements):
        found = {}
        for element in elements:
            if named(element) and overlaps(box, element['frame']):
                found.setdefault(named(element), element)
        return found

    old, new = index(before), index(after)
    said = []
    for name, element in new.items():
        if name not in old:
            said.append(f'{name!r} appeared')
            continue
        (x0, y0, w0, h0), (x1, y1, w1, h1) = old[name]['frame'], element['frame']
        parts = []
        if (x0, y0) != (x1, y1):
            parts.append(f'moved {x1 - x0:+g},{y1 - y0:+g}pt')
        if (w0, h0) != (w1, h1):
            parts.append(f'{w0:g}x{h0:g} to {w1:g}x{h1:g}pt')
        if old[name]['label'] != element['label'] and element['id']:
            parts.append(f'reads {element["label"]!r}, was {old[name]["label"]!r}')
        if parts:
            said.append(f'{name!r} ' + ', '.join(parts))
    said += [f'{name!r} gone' for name in old if name not in new]
    return said


def compare(before, after, screen, width):
    """The changed regions, each its box in points and what changed in it, and the pictures; no regions when the
    screen is the same."""
    if screen.startswith(UNHELD) or filecmp.cmp(os.path.join(before, screen + '.png'), os.path.join(after, screen + '.png'), shallow=False):
        return [], None
    a = np.asarray(Image.open(os.path.join(before, screen + '.png')).convert('RGB')).astype(np.int16)
    b = np.asarray(Image.open(os.path.join(after, screen + '.png')).convert('RGB')).astype(np.int16)
    elements_a, elements_b = outline(before, screen), outline(after, screen)
    if a.shape != b.shape:
        return [((0, 0, b.shape[1], b.shape[0]), [f'size {a.shape[1]}x{a.shape[0]} to {b.shape[1]}x{b.shape[0]}px'])], None
    scale = b.shape[1] / (width or b.shape[1])
    differs = np.abs(a - b).max(axis=2) > CHANGED
    differs &= ~(held(screen, elements_a, scale, differs.shape) | held(screen, elements_b, scale, differs.shape))
    fields = inputs(elements_a) + inputs(elements_b)
    marks, _ = ndimage.label(differs)
    for rows, columns in ndimage.find_objects(marks):
        box = tuple(v / scale for v in (columns.start, rows.start, columns.stop, rows.stop))
        if box[2] - box[0] <= CARET and any(inside(box, frame) for frame in fields):
            differs[rows, columns] = False
    if not differs.any():
        return [], None
    labels, _ = ndimage.label(ndimage.maximum_filter(differs, size=round(8 * scale) + 1))
    regions = []
    for found, (rows, columns) in enumerate(ndimage.find_objects(labels), 1):
        pixels = differs[rows, columns]
        own = pixels & (labels[rows, columns] == found)
        if not own.any():
            continue
        ys, xs = np.nonzero(own)
        box = (
            (columns.start + xs.min()) / scale,
            (rows.start + ys.min()) / scale,
            (columns.start + xs.max() + 1) / scale,
            (rows.start + ys.max() + 1) / scale,
        )
        w, h = box[2] - box[0], box[3] - box[1]
        if not (elements_a or elements_b) and (w <= NARROW or max(w, h) <= SMALL):
            pixels[own] = False
            continue
        regions.append((box, changes(elements_a, elements_b, box)))
    return regions, (a, b, differs)


def picture(images, path):
    a, b, differs = images
    marked = b.copy()
    marked[differs] = (marked[differs] * 0.3 + np.array([255, 0, 0]) * 0.7).astype(np.int16)
    gap = np.full((a.shape[0], 24, 3), 128, np.int16)
    strip = np.concatenate([a, gap, b, gap, marked], axis=1).clip(0, 255).astype(np.uint8)
    image = Image.fromarray(strip)
    image.reduce(2).save(path)


def main(before, after, out):
    os.makedirs(out, exist_ok=True)
    screens = lambda folder: {name[:-4] for name in os.listdir(folder) if name.endswith('.png')}
    old, new = screens(before), screens(after)
    lines = [f'- {screen}: new' for screen in sorted(new - old)]
    lines += [f'- {screen}: gone' for screen in sorted(old - new)]
    # The screen's width in points, from any shot's outline (its first element is the app's window).
    width = next((outline(folder, name)[0]['frame'][2] for folder in (after, before) for name in sorted(screens(folder))
                  if outline(folder, name)), None)
    for screen in sorted(old & new):
        regions, images = compare(before, after, screen, width)
        if not regions:
            continue
        if images:
            picture(images, os.path.join(out, screen + '.png'))
        said = list(dict.fromkeys(change for _, found in regions for change in found))
        where = ', '.join(f'{x0:.0f},{y0:.0f} {x1 - x0:.0f}x{y1 - y0:.0f}pt' for (x0, y0, x1, y1), _ in regions[:4])
        lines.append(f'- {screen}: {where}' + (f'; {"; ".join(said[:6])}' if said else ''))
    head = f'{len(lines)} of {len(new | old)} screens changed' if lines else f'All {len(new)} screens the same'
    report = '\n'.join([head, *lines]) + '\n'
    with open(os.path.join(out, 'report.md'), 'w') as file:
        file.write(report)
    print(report, end='')


if __name__ == '__main__':
    main(*sys.argv[1:4])
