import { themes, themeNames, cssVars } from "./themes.js";
import { mountKeyboard } from "./keyboard.js";
import { mountWordmark } from "./wordmark.js";

const root = document.documentElement;
const dark = matchMedia("(prefers-color-scheme: dark)");
const scheme = () => (dark.matches ? "dark" : "light");
const setVars = (el, vars) => { for (const [k, v] of Object.entries(vars)) el.style.setProperty(k, v); };
const html = (s) => { const t = document.createElement("template"); t.innerHTML = s.trim(); return t.content.firstElementChild; };

// Theme: one for the whole page, kept between visits.
let theme = themeNames.includes(root.dataset.theme) ? root.dataset.theme : "standard";
const picks = document.querySelector(".theme-pick");
const cards = document.querySelector(".theme-cards");
const mini = `<div class="row"><span class="k"><i class="face">i</i></span><span class="k"><i class="face">i</i></span><span class="k"><i class="face">k</i></span><span class="k"><i class="face">b</i></span></div><div class="row"><span class="k fn k-123"><i class="face">123</i></span><span class="k k-space"><i class="face"></i></span><span class="k fn k-return"><i class="face"><svg viewBox="0 0 24 24"><path d="M19 5v6a3 3 0 0 1-3 3H6m0 0 4-4m-4 4 4 4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></i></span></div>`;
for (const name of themeNames) {
  picks.append(html(`<button type="button" role="radio" data-theme="${name}">${themes[name].title}</button>`));
  cards.append(html(`<button type="button" class="theme-card" role="radio" data-theme="${name}"><div class="mini kb-like">${mini}</div><div class="about"><b>${themes[name].title}</b></div></button>`));
}
const wordmark = mountWordmark(document.querySelector(".keycaps"), () => theme);
const applyTheme = (name, fromUser) => {
  theme = name;
  root.dataset.theme = name;
  setVars(root, cssVars(name, scheme()));
  for (const card of cards.children) setVars(card.querySelector(".mini"), cssVars(card.dataset.theme, scheme()));
  setVars(document.querySelector("[data-duo]"), cssVars(name, "dark"));
  for (const b of document.querySelectorAll("[data-theme][role=radio]")) b.setAttribute("aria-checked", String(b.dataset.theme === name));
  if (fromUser) { try { localStorage.setItem("iikb-theme", name); } catch {} wordmark.retheme(); }
};
for (const b of document.querySelectorAll("[data-theme][role=radio]")) b.addEventListener("click", () => applyTheme(b.dataset.theme, true));
dark.addEventListener("change", () => { applyTheme(theme); wordmark.retheme(); });
applyTheme(theme);

const demo = document.querySelector("[data-demo]");
const keyboard = mountKeyboard(demo);

// The Duo: folded, typing on its cover screen, it opens on its hinge and then turns as the page scrolls past it.
const stage = document.querySelector("[data-stage]");
const pin = stage.querySelector(".pin");
const hero = stage.querySelector(".hero-copy");
const slot = stage.querySelector("[data-slot]");
const duo = stage.querySelector("[data-duo]");
const rig = duo.querySelector("[data-rig]");
const lid = duo.querySelector("[data-lid]");
const dial = stage.querySelector("[data-dial]");
const W = 490, H = 702;
const poses = [
  { id: "folded", title: "folded", size: "466 × 678", at: 0 },
  { id: "open", title: "open", size: "951 × 669", at: 0.5 },
  { id: "turned", title: "turned", size: "669 × 951", at: 1 },
];
const clamp = (v) => Math.min(1, Math.max(0, v));
const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - (-2 * t + 2) ** 3 / 2);
const span = (p, a, b) => ease(clamp((p - a) / (b - a)));
const mix = (a, b, t) => a + (b - a) * t;
const progress = () => {
  const r = stage.getBoundingClientRect();
  return clamp(-r.top / Math.max(1, r.height - innerHeight));
};
for (const pose of poses) {
  const b = html(`<button type="button" role="tab" data-pose="${pose.id}"><b>${pose.title}</b><span>${pose.size}</span></button>`);
  b.addEventListener("click", () => {
    const top = stage.offsetTop + pose.at * (stage.offsetHeight - innerHeight);
    scrollTo({ top: pose.at ? top + 2 : 0 });
  });
  dial.append(b);
}
let aim = { x: 0, y: 0 }, lean = { x: 0, y: 0 }, live = false, raf = 0, shown = "";
addEventListener("pointermove", (e) => { if (e.pointerType === "mouse") aim = { x: e.clientX / innerWidth - 0.5, y: e.clientY / innerHeight - 0.5 }; }, { passive: true });
const frame = () => {
  raf = 0;
  const p = progress();
  const open = span(p, 0.1, 0.46), turn = span(p, 0.6, 0.9);
  lean.x += (aim.x - lean.x) * 0.08;
  lean.y += (aim.y - lean.y) * 0.08;
  const box = pin.getBoundingClientRect(), s = slot.getBoundingClientRect();
  const pad = innerWidth < 640 ? 16 : 40, room = { w: box.width - pad * 2, h: box.height - dial.offsetHeight - pad * 2 };
  // Fit what the Duo covers at this angle: one screen folded, two open, turned by the turn.
  const fit = { w: mix(s.width, room.w, open), h: mix(s.height, room.h, open) };
  const wide = mix(W, 2 * W, open), a = (Math.PI / 2) * turn, cos = Math.cos(a), sin = Math.sin(a);
  const scale = 0.94 * Math.min(fit.w / (wide * cos + H * sin), fit.h / (wide * sin + H * cos)) * (1 - 0.22 * Math.sin(Math.PI * open));
  const x = mix(s.left - box.left + s.width / 2, box.width / 2, open);
  const y = mix(s.top - box.top + s.height / 2, pad + room.h / 2, open);
  duo.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
  const narrow = innerWidth < 760;
  const rx = mix(narrow ? 6 : 9, 5, open) - lean.y * 8, ry = mix(narrow ? -14 : -22, -8, open) * (1 - turn * 0.6) + lean.x * 10;
  rig.style.transform = `perspective(3600px) rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${90 * turn}deg) translateX(${(W / 2) * (1 - open)}px)`;
  lid.style.transform = `rotateY(${-180 * (1 - open)}deg)`;
  duo.style.setProperty("--turn", turn < 0.5 ? 0 : 1);
  hero.style.opacity = 1 - span(p, 0.03, 0.22);
  hero.style.transform = `translateY(${-40 * span(p, 0.03, 0.22)}px)`;
  hero.inert = p > 0.15;
  const now = p < 0.28 ? "folded" : p < 0.75 ? "open" : "turned";
  if (now !== shown) { shown = now; for (const b of dial.children) b.setAttribute("aria-selected", String(b.dataset.pose === now)); }
  if (live && (Math.abs(aim.x - lean.x) > 0.001 || Math.abs(aim.y - lean.y) > 0.001)) raf = requestAnimationFrame(frame);
};
const wake = () => { if (!raf) raf = requestAnimationFrame(frame); };
new IntersectionObserver(([e]) => { live = e.isIntersecting; wake(); }).observe(stage);
addEventListener("scroll", wake, { passive: true });
addEventListener("resize", wake);
addEventListener("pointermove", wake, { passive: true });
wake();

// Writing styles: what one dictation becomes in each, by DictationStyle's rules.
const styles = [
  { id: "formal", title: "Formal", text: "Running late, but I’ll be there by 3:30pm. Save me a seat." },
  { id: "casual", title: "Casual", text: "Running late, but I’ll be there by 3:30pm. Save me a seat" },
  { id: "veryCasual", title: "Very casual", text: "running late but i’ll be there by 3:30pm. save me a seat" },
  { id: "excited", title: "Excited", text: "Running late, but I’ll be there by 3:30pm. Save me a seat!" },
];
const stylePick = document.querySelector(".style-pick");
const wrote = document.querySelector("[data-wrote]");
let style = styles[1];
const showStyle = (s) => {
  style = s;
  for (const b of stylePick.children) b.setAttribute("aria-selected", String(b.dataset.style === s.id));
  wrote.textContent = s.text;
};
for (const s of styles) {
  const b = html(`<button type="button" role="tab" data-style="${s.id}">${s.title}</button>`);
  b.addEventListener("click", () => showStyle(s));
  stylePick.append(b);
}
showStyle(style);
document.querySelector("[data-try]").addEventListener("click", () => {
  scrollTo({ top: stage.offsetTop, behavior: "smooth" });
  setTimeout(() => keyboard.dictate(style.text), 500);
});

// Numbers from copy/facts.json, the changelog from git (web/changes.mjs).
const get = (obj, path) => path.split(".").reduce((v, k) => v?.[k], obj);
const format = (v) => (typeof v === "number" ? v.toLocaleString("en-US") : v);
const [facts, changes] = await Promise.all([
  fetch("facts.json").then((r) => r.json()).catch(() => null),
  fetch("changes.json").then((r) => r.json()).catch(() => null),
]);
if (facts) for (const el of document.querySelectorAll("[data-fact]")) { const v = get(facts, el.dataset.fact); if (v != null) el.textContent = format(v); }

if (changes) {
  const day = (iso) => new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric" });
  document.querySelector('[data-change="commits"]').textContent = format(changes.commits);
  document.querySelector('[data-change="since"]').textContent = day(changes.since);
  const head = document.querySelector('[data-change="head"]');
  head.textContent = `main @ ${changes.head.sha} · ${day(changes.head.at)}`;
  head.href = `https://github.com/AVGVSTVS96/iikb/commit/${changes.head.sha}`;
  const ticker = document.querySelector("[data-ticker]");
  const list = ticker.querySelector("ol");
  for (const c of changes.changes) {
    const li = document.createElement("li");
    li.innerHTML = `<span></span><time></time><code></code>`;
    li.querySelector("span").textContent = c.text;
    li.querySelector("time").textContent = day(c.at);
    li.querySelector("code").textContent = c.sha;
    list.append(li);
  }
  const rows = [...list.children];
  let at = 2, timer = 0;
  const show = (i) => {
    at = (i + rows.length) % rows.length;
    const row = rows[0].offsetHeight;
    list.style.transform = `translateY(${(2 - at) * row}px)`;
    rows.forEach((li, n) => li.classList.toggle("now", n === at));
  };
  show(2);
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (!reduced) {
    new IntersectionObserver(([e]) => {
      clearInterval(timer);
      if (e.isIntersecting) timer = setInterval(() => show(at + 1), 2600);
    }, { threshold: 0.4 }).observe(ticker);
  }
  ticker.addEventListener("pointerenter", () => clearInterval(timer));
  ticker.addEventListener("click", (e) => { const li = e.target.closest("li"); if (li) show(rows.indexOf(li)); });
  new ResizeObserver(() => show(at)).observe(ticker);
}

// The accuracy chart: iikb against the nearest key plus Apple's spell checker, per 500 words.
const chart = document.getElementById("chart");
if (facts && chart) {
  const { iikbCurve, baselineCurve, blockWords } = facts.accuracy;
  const draw = () => {
    const width = chart.clientWidth;
    if (!width) return;
    const narrow = width < 520;
    const height = narrow ? 220 : 280;
    const left = 40, right = narrow ? 8 : 150, top = 12, bottom = 30;
    const x = (i) => left + (i / (iikbCurve.length - 1)) * (width - left - right);
    const y = (v) => top + ((100 - v) / 20) * (height - top - bottom);
    const path = (c) => c.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join("");
    const ticks = [80, 85, 90, 95, 100].map((v) => `<line class="grid-line" x1="${left}" x2="${width}" y1="${y(v)}" y2="${y(v)}"/><text class="tick" x="0" y="${y(v) + 4}">${v}%</text>`).join("");
    const labels = iikbCurve.map((_, i) => i).filter((i) => (narrow ? i % 4 === 1 : i % 2 === 1)).map((i) => `<text class="tick" x="${x(i)}" y="${height - 6}" text-anchor="middle">${((i + 1) * blockWords).toLocaleString("en-US")}</text>`).join("");
    const dots = (c, n) => c.map((v, i) => `<circle class="fade dot-${n}" cx="${x(i)}" cy="${y(v)}" r="3"/>`).join("");
    const last = iikbCurve.length - 1;
    const ends = narrow
      ? `<text class="end end-ours fade" x="${left + 4}" y="${y(iikbCurve[0]) - 10}">iikb</text><text class="end end-theirs fade" x="${left + 4}" y="${y(baselineCurve[0]) + 22}">nearest key + spell checker</text>`
      : `<text class="end end-ours fade" x="${x(last) + 12}" y="${y(iikbCurve[last]) + 4}">iikb</text><text class="end end-theirs fade" x="${x(last) + 12}" y="${y(baselineCurve[last]) - 4}">nearest key +</text><text class="end end-theirs fade" x="${x(last) + 12}" y="${y(baselineCurve[last]) + 12}">spell checker</text>`;
    chart.innerHTML = `<svg viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" aria-hidden="true">${ticks}${labels}<path class="series theirs draw" d="${path(baselineCurve)}"/><path class="series ours draw" d="${path(iikbCurve)}"/>${dots(baselineCurve, "theirs")}${dots(iikbCurve, "ours")}${ends}</svg>`;
    for (const line of chart.querySelectorAll(".ours.draw")) line.style.setProperty("--length", line.getTotalLength());
  };
  let drawn = 0;
  new ResizeObserver(() => { if (chart.clientWidth !== drawn) { drawn = chart.clientWidth; draw(); } }).observe(chart);
  new IntersectionObserver(([e], o) => { if (e.isIntersecting) { chart.classList.add("seen"); o.disconnect(); } }, { threshold: 0.35 }).observe(chart);
}
