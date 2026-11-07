// The footer's iikb, set in keycaps: the wordmark sampled onto a grid, a key wherever it covers a cell, a small one where it
// grazes one. Keys near the pointer press and lean away, a tap scatters them, and they spring back, painted in the theme
// the page is set to.
import { paint } from "./themes.js";

const PATH = document.querySelector("#wordmark path").getAttribute("d");
const VIEW = { w: 147.2, h: 72.7 };
const columns = () => (innerWidth < 640 ? 36 : 62);
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

// Each cell's share of ink, from the wordmark drawn large and read back.
function cells(COLS) {
  const scale = 8;
  const cell = (VIEW.w / COLS) * scale;
  const rows = Math.ceil((VIEW.h * scale) / cell);
  const canvas = new OffscreenCanvas(Math.ceil(VIEW.w * scale), Math.ceil(rows * cell));
  const g = canvas.getContext("2d", { willReadFrequently: true });
  g.scale(scale, scale);
  g.translate(-5.8, 71.4);
  g.fill(new Path2D(PATH));
  const data = g.getImageData(0, 0, canvas.width, canvas.height).data;
  const out = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < COLS; c++) {
      let ink = 0;
      const n = 6;
      for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
          const x = Math.floor((c + (i + 0.5) / n) * cell);
          const y = Math.floor((r + (j + 0.5) / n) * cell);
          ink += data[(y * canvas.width + x) * 4 + 3] > 127 ? 1 : 0;
        }
      }
      ink /= n * n;
      if (ink > 0.3) out.push({ c, r, size: ink > 0.62 ? 1 : 0.5, ox: 0, oy: 0, vx: 0, vy: 0, press: 0, glow: 0 });
    }
  }
  return { list: out, rows, COLS };
}

// A keycap drawn once per theme, pressed or not, at the size the canvas draws it.
function keycap(key, size, pressed, dark) {
  const s = Math.max(4, Math.round(size));
  const canvas = new OffscreenCanvas(s, s + 2);
  const g = canvas.getContext("2d");
  const r = s * 0.24;
  const shape = (x, y, w, h, rr) => { g.beginPath(); g.roundRect(x, y, w, h, rr); };
  const top = pressed ? key.pressedTop : key.top;
  const bottom = pressed ? key.pressedBottom : key.bottom;
  const visible = top !== "transparent";
  if (key.drop) { g.fillStyle = "rgb(0 0 0 / .3)"; shape(0.5, 1.2, s - 1, s, r); g.fill(); }
  if (key.keycap) {
    const sides = g.createLinearGradient(0, 0, 0, s);
    for (const stop of key.keycap.sides) { const [color, at] = stop.split(" "); sides.addColorStop(parseFloat(at) / 100, color); }
    g.fillStyle = sides; shape(0, 0, s, s, r); g.fill();
    const glow = g.createRadialGradient(s / 2, 0, 0, s / 2, 0, s * 0.6);
    glow.addColorStop(0, key.keycap.glow); glow.addColorStop(1, "transparent");
    g.fillStyle = glow; shape(0, 0, s, s, r); g.fill();
    const face = g.createLinearGradient(0, s * 0.09, 0, s * 0.85);
    face.addColorStop(0, top); face.addColorStop(1, bottom);
    g.fillStyle = face; shape(s * 0.1, s * 0.09 + (pressed ? s * 0.03 : 0), s * 0.8, s * 0.76, r * 0.65); g.fill();
  } else if (visible) {
    const face = g.createLinearGradient(0, 0, 0, s);
    face.addColorStop(0, top); face.addColorStop(1, bottom);
    g.fillStyle = face; shape(0, 0, s, s, r); g.fill();
    if (!dark) { g.strokeStyle = "rgb(0 0 0 / .14)"; g.lineWidth = 1; shape(0.5, 0.5, s - 1, s - 1, r); g.stroke(); }
    if (key.rim) {
      g.save(); shape(0, 0, s, s, r); g.clip();
      const rim = g.createLinearGradient(0, 0, 0, s * Math.max(key.rim[2], 0.2));
      rim.addColorStop(0, key.rim[0]); rim.addColorStop(1, "transparent");
      g.strokeStyle = rim; g.lineWidth = Math.max(1, key.rim[1] * 3); g.stroke(); g.restore();
    }
  } else {
    // Clear keys have no face: only their outline shows, as a hairline.
    g.strokeStyle = dark ? (pressed ? "rgb(255 255 255 / .55)" : "rgb(255 255 255 / .2)") : (pressed ? "rgb(0 0 0 / .5)" : "rgb(0 0 0 / .2)");
    if (pressed) { g.fillStyle = dark ? "rgb(255 255 255 / .16)" : "rgb(0 0 0 / .16)"; shape(0, 0, s, s, r); g.fill(); }
    g.lineWidth = 1; shape(0.5, 0.5, s - 1, s - 1, r); g.stroke();
  }
  return canvas;
}

export function mountWordmark(canvas, getTheme) {
  const g = canvas.getContext("2d");
  let { list, rows, COLS } = cells(columns());
  canvas.dataset.ready = "";
  let width = 0, height = 0, ratio = 1, pitch = 0, sprites = null, pointer = null, frame = 0, seen = false;

  const scheme = () => (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const build = () => {
    const theme = getTheme();
    const look = scheme();
    const k = paint(theme, look).letter;
    const size = pitch * 0.86 * ratio;
    sprites = { up: keycap(k, size, false, look === "dark"), down: keycap(k, size, true, look === "dark"), small: keycap(k, size * 0.5, false, look === "dark"), smallDown: keycap(k, size * 0.5, true, look === "dark") };
  };

  const resize = () => {
    if (columns() !== COLS) ({ list, rows, COLS } = cells(columns()));
    const rect = canvas.getBoundingClientRect();
    ratio = Math.min(devicePixelRatio || 1, 2);
    width = rect.width;
    pitch = width / COLS;
    height = pitch * rows;
    canvas.style.height = `${height}px`;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round((height + pitch * 0.2) * ratio);
    build();
    draw();
  };

  const draw = () => {
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, canvas.width, canvas.height);
    const size = pitch * 0.86;
    for (const cell of list) {
      const small = cell.size < 1;
      const s = small ? size * 0.5 : size;
      const x = (cell.c * pitch + (pitch - s) / 2 + cell.ox) * ratio;
      const y = (cell.r * pitch + (pitch - s) / 2 + cell.oy + cell.press * pitch * 0.06) * ratio;
      const sprite = cell.press > 0.5 ? (small ? sprites.smallDown : sprites.down) : (small ? sprites.small : sprites.up);
      g.globalAlpha = small ? 0.75 : 1;
      g.drawImage(sprite, Math.round(x), Math.round(y));
    }
    g.globalAlpha = 1;
  };

  const step = () => {
    let moving = false;
    for (const cell of list) {
      const cx = (cell.c + 0.5) * pitch + cell.ox;
      const cy = (cell.r + 0.5) * pitch + cell.oy;
      let near = 0;
      if (pointer) {
        const dx = cx - pointer.x, dy = cy - pointer.y;
        const d = Math.hypot(dx, dy) || 0.001;
        const reach = pitch * 3.2;
        if (d < reach) {
          const f = (1 - d / reach) ** 2 * pitch * 0.09;
          cell.vx += (dx / d) * f;
          cell.vy += (dy / d) * f;
          near = 1 - d / reach;
        }
      }
      cell.vx = (cell.vx - cell.ox * 0.06) * 0.86;
      cell.vy = (cell.vy - cell.oy * 0.06) * 0.86;
      cell.ox += cell.vx;
      cell.oy += cell.vy;
      cell.press += ((near > 0.45 ? 1 : 0) - cell.press) * 0.35;
      if (Math.abs(cell.ox) + Math.abs(cell.oy) + Math.abs(cell.vx) + Math.abs(cell.vy) + cell.press > 0.02) moving = true;
      else cell.ox = cell.oy = cell.vx = cell.vy = cell.press = 0;
    }
    draw();
    frame = moving || pointer ? requestAnimationFrame(step) : 0;
  };
  const wake = () => { if (!frame && !reduced) frame = requestAnimationFrame(step); };

  const local = (event) => {
    const rect = canvas.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };

  // A tap scatters the keys around it, harder the closer they are.
  const burst = (at, power = 1) => {
    for (const cell of list) {
      const dx = (cell.c + 0.5) * pitch + cell.ox - at.x;
      const dy = (cell.r + 0.5) * pitch + cell.oy - at.y;
      const d = Math.hypot(dx, dy) || 0.001;
      const reach = pitch * 12;
      if (d > reach) continue;
      const f = (1 - d / reach) * pitch * 1.4 * power * (0.7 + Math.random() * 0.6);
      cell.vx += (dx / d) * f + (Math.random() - 0.5) * pitch * 0.2;
      cell.vy += (dy / d) * f + (Math.random() - 0.5) * pitch * 0.2;
    }
    wake();
  };

  new ResizeObserver(resize).observe(canvas);
  new IntersectionObserver(([entry]) => { seen = entry.isIntersecting; }).observe(canvas);
  if (!reduced) {
    canvas.addEventListener("pointermove", (event) => { pointer = local(event); wake(); });
    canvas.addEventListener("pointerleave", () => { pointer = null; });
    canvas.addEventListener("pointerdown", (event) => { burst(local(event)); if (event.pointerType !== "mouse") pointer = null; });
    // Typing while the footer shows presses a key of the wordmark, somewhere along it.
    addEventListener("keydown", (event) => {
      if (!seen || event.key.length !== 1 || event.metaKey || event.ctrlKey) return;
      const cell = list[Math.floor(Math.random() * list.length)];
      cell.press = 1;
      cell.vy += pitch * 0.25;
      wake();
    });
  }

  return {
    retheme() {
      if (!width) return;
      build();
      draw();
      if (!reduced) burst({ x: width / 2, y: height * 1.2 }, 0.35);
    },
  };
}
