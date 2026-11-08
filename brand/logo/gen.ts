import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { Path, parse } from "opentype.js";

const here = import.meta.dirname;
const fonts = process.env.FONTS ?? path.join(here, "../../.scratch/fonts");
const bold = parse(readFileSync(path.join(fonts, "HelveticaNeue-Bold.ttf")).buffer);
const out = path.join(here, "out");

const INK = "#000";
const PAPER = "#fff";
const NAME = "iikb";
const TIGHT = -45;
const ICON_CORNER = 0.225;

const round = (n: number) => Math.round(n * 100) / 100;

interface Line {
  readonly size: number;
  readonly trackingPerMille: number;
  readonly x?: number;
  readonly y?: number;
}

const line = ({ size, trackingPerMille, x = 0, y = 0 }: Line) => {
  const glyphs = bold.stringToGlyphs(NAME);
  const scale = size / bold.unitsPerEm;
  const tracking = (trackingPerMille / 1000) * size;
  const outline = new Path();
  let pen = x;

  for (const [index, glyph] of glyphs.entries()) {
    outline.extend(glyph.getPath(pen, y, size));
    pen += (glyph.advanceWidth ?? 0) * scale + (index < glyphs.length - 1 ? tracking : 0);
  }

  return { d: outline.toPathData(2), box: outline.getBoundingBox() };
};

const svg = (width: number, height: number, body: string) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${round(width)} ${round(height)}" width="${round(width)}" height="${round(height)}">${body}</svg>\n`;

const wordmark = (color: string) => {
  const { d, box } = line({ size: 100, trackingPerMille: TIGHT });

  return svg(
    box.x2 - box.x1,
    box.y2 - box.y1,
    `<path transform="translate(${round(-box.x1)} ${round(-box.y1)})" fill="${color}" d="${d}"/>`,
  );
};

const flushBottomLeft = (size: number, marginShare: number) => {
  const margin = marginShare * size;
  const probe = line({ size: 100, trackingPerMille: TIGHT }).box;
  const type = (100 * (size - 2 * margin)) / (probe.x2 - probe.x1);
  const fit = line({ size: type, trackingPerMille: TIGHT }).box;

  return line({
    size: type,
    trackingPerMille: TIGHT,
    x: margin - fit.x1,
    y: size - margin - fit.y2,
  }).d;
};

interface Icon {
  readonly field: string;
  readonly color: string;
  readonly rounded?: boolean;
}

const icon = ({ field, color, rounded = false }: Icon, size = 1024) => {
  const corner = rounded ? ` rx="${size * ICON_CORNER}"` : "";

  return svg(
    size,
    size,
    `<rect width="${size}" height="${size}"${corner} fill="${field}"/><path fill="${color}" d="${flushBottomLeft(size, 0.13)}"/>`,
  );
};

const poster = (size = 1024) => {
  const type = 0.4 * size;
  const margin = 0.12 * size;
  const probe = line({ size: type, trackingPerMille: TIGHT }).box;

  const { d } = line({
    size: type,
    trackingPerMille: TIGHT,
    x: margin - probe.x1,
    y: size - margin,
  });

  return svg(
    size,
    size,
    `<rect width="${size}" height="${size}" rx="${size * ICON_CORNER}" fill="${INK}"/><path fill="${PAPER}" d="${d}"/>`,
  );
};

const spacebar = (size = 1024) => {
  const key = { x: 0.1 * size, y: 0.4 * size, w: 0.8 * size, h: 0.3 * size };
  const type = 0.13 * size;
  const probe = line({ size: type, trackingPerMille: -30 }).box;

  const { d } = line({
    size: type,
    trackingPerMille: -30,
    x: key.x + 0.06 * size - probe.x1,
    y: key.y + 0.06 * size - probe.y1,
  });

  return svg(
    size,
    size,
    `<rect width="${size}" height="${size}" rx="${size * ICON_CORNER}" fill="${INK}"/><rect x="${key.x}" y="${key.y}" width="${key.w}" height="${key.h}" rx="${0.06 * size}" fill="${PAPER}"/><path fill="${INK}" d="${d}"/>`,
  );
};

const favicon = (size = 64) => {
  const style = `<style>rect{fill:${INK}}path{fill:${PAPER}}@media (prefers-color-scheme:dark){rect{fill:${PAPER}}path{fill:${INK}}}</style>`;

  return svg(
    size,
    size,
    `${style}<rect width="${size}" height="${size}" rx="${size * 0.2}"/><path d="${flushBottomLeft(size, 0.09)}"/>`,
  );
};

const files = {
  "favicon.svg": favicon(),
  "direction-poster.svg": poster(),
  "direction-spacebar.svg": spacebar(),
  "wordmark-ink.svg": wordmark(INK),
  "wordmark-paper.svg": wordmark(PAPER),
  "icon.svg": icon({ field: INK, color: PAPER }),
  "icon-light.svg": icon({ field: PAPER, color: INK }),
  "icon-rounded.svg": icon({ field: INK, color: PAPER, rounded: true }),
};

mkdirSync(out, { recursive: true });

for (const [name, body] of Object.entries(files)) {
  writeFileSync(path.join(out, name), body);
}

console.log(Object.keys(files).join("\n"));
