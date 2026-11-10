/* oxlint-disable eslint/no-await-in-loop -- the hero is a timeline: each await is the pause before the next keystroke */
import { ICONS } from "./icons.js";

const ROWS = [
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
  ["shift", "z", "x", "c", "v", "b", "n", "m", "delete"],
  ["123", "emoji", "space", "return"],
];

const WORDS =
  `the to and a i you it is that of in for on my this be it's with your have we just can so but not are
all at what if me was do get like i'm out about one up know how now no will they more be there time keyboard keys
iikb ios open source best world fast on-device dictation gif emoji search clipboard history built iphone duo daily
driver sooner later everything gonna oss transcription styles customize extension extensions extensible system
themes theme smart suggestions data sources meet bring your own integration typing type thumbs learns tap taps
build building building today tonight tomorrow love really much make making macbook maybe minute message meeting
send see soon sure still something swipe space switch shipped shipping ship commits commit check perfection
perfect pure trust try it iterating quickly guys`.split(/\s+/u);

const NEXT = {
  the: ["best", "keyboard", "world"],
  best: ["open", "iOS", "keyboard"],
  open: ["source"],
  source: ["iOS"],
  ios: ["keyboard"],
  in: ["the"],
  my: ["daily", "iphone", "keyboard"],
  on: ["my", "the"],
  is: ["gonna", "my", "the"],
  gonna: ["be"],
  be: ["oss", "the"],
  it: ["is", "out"],
  "it's": ["my", "on"],
  and: ["emoji", "the"],
};

export const LINES = [
  "meet iikb, the best open source iOS keyboard in the world",
  "it learns where your thumbs really land",
  "dictation on device. free, no word limit",
  "clipboard, gifs, emoji and chats, one tap away",
  "sooner or later everything is gonna be OSS",
];

const LETTERS = "qwertyuiopasdfghjklzxcvbnm";

const NUMBERS = [
  ..."1234567890".split(""),
  "-",
  "/",
  ":",
  ";",
  "(",
  ")",
  "$",
  "&",
  "@",
  ".",
  ",",
  "?",
  "!",
  "’",
  '"',
  "+",
];

const NUMBER = Object.fromEntries(LETTERS.split("").map((k, i) => [k, NUMBERS[i]]));
const EMOJI = ["🔥", "⚡", "🎯", "🧠", "🤌", "🚀", "✨", "🫡"];

const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

const sleep = async (ms) => {
  const { promise, resolve } = Promise.withResolvers();

  setTimeout(() => {
    resolve();
  }, ms);
  await promise;
};

const keyLabel = (k) => {
  if (k.length === 1 || k === "123") {
    return k;
  }

  return k === "space" ? "<small>iikb</small>" : (ICONS[k] ?? "");
};

export const mountKeyboard = (root, { active = () => root.isConnected } = {}) => {
  const field = root.querySelector("[data-field]");
  const thread = root.querySelector("[data-thread]");
  const kb = root.querySelector(".kb");
  const keys = new Map();
  let text = "";
  let shift = false;
  let numbers = false;
  let auto = !reduced;
  let generation = 0;

  kb.innerHTML = `<div class="bar"><span class="bar-btn">${ICONS.grid}</span><div class="sugg"><button type="button" tabindex="-1"></button><button type="button" tabindex="-1"></button><button type="button" tabindex="-1"></button></div><span class="bar-btn k-mic" data-mic>${ICONS.mic}</span><div class="rec" aria-hidden="true"><span class="bar-btn">${ICONS.close}</span><span class="pill"><b data-clock>0:00</b><span class="wave">${"<i></i>".repeat(16)}</span><i class="stop"></i></span></div></div>${ROWS.map(
    (row, r) =>
      `<div class="row r${r}">${row
        .map((k) => {
          const fn = k.length > 1 && k !== "space";

          return `<span class="k${fn ? " fn" : ""} k-${k}" data-k="${k}"><i class="face">${keyLabel(k)}</i></span>`;
        })
        .join("")}</div>`,
  ).join(
    "",
  )}<div class="sys"><span>${ICONS.globe}</span><span>${ICONS.dictation}</span></div><div class="pop" aria-hidden="true"><i></i></div>`;

  for (const el of kb.querySelectorAll("[data-k]")) {
    keys.set(el.dataset.k, el);
  }

  const pop = kb.querySelector(".pop");
  const sugg = [...kb.querySelectorAll(".sugg button")];
  const mic = kb.querySelector("[data-mic]");
  const clock = kb.querySelector("[data-clock]");

  const fit = () => {
    const pt = Number.parseFloat(getComputedStyle(kb).getPropertyValue("--pt")) || 1;
    const letter = keys.get("q").offsetWidth / pt;
    kb.style.setProperty("--r", `${(3.9 + 0.143 * letter) * pt}px`);
    kb.style.setProperty("--kh", `${keys.get("q").offsetHeight}px`);
  };

  new ResizeObserver(fit).observe(kb);

  const out = (k) => {
    if (numbers) {
      return NUMBER[k];
    }

    return shift ? k.toUpperCase() : k;
  };

  const setNumbers = (on) => {
    numbers = on;
    kb.classList.toggle("numbers", on);

    for (const k of LETTERS) {
      keys.get(k).firstChild.textContent = on ? NUMBER[k] : k;
    }

    keys.get("123").firstChild.textContent = on ? "ABC" : "123";
    keys.get("shift").firstChild.innerHTML = on ? "#+=" : ICONS.shift;
  };

  const render = () => {
    field.querySelector("span").textContent = text;
    field.scrollTop = field.scrollHeight;
    field.classList.toggle("empty", !text);
    const word = /[\w'+-]*$/u.exec(text)[0].toLowerCase();
    let list;

    if (word) {
      const found = WORDS.filter((w) => w.startsWith(word) && w !== word).slice(0, 2);
      list = [`“${word}”`, ...found];
    } else {
      const last = (/[\w'-]+$/u.exec(text.trim())?.[0] ?? "").toLowerCase();
      list = NEXT[last] ?? (text ? ["the", "I", "and"] : ["I", "The", "I'm"]);
    }

    while (list.length < 3) {
      list.push(["the", "and", "to"][list.length]);
    }

    const order = [list[1], list[0], list[2]];

    for (const [i, b] of sugg.entries()) {
      b.textContent = order[i] ?? "";
      b.classList.toggle("lead", i === 1);
    }

    kb.classList.toggle("shifted", shift);
  };

  const press = (k, ms = 110) => {
    const el = keys.get(k);

    if (!el) {
      return;
    }

    el.classList.add("down");

    if (k.length === 1) {
      pop.firstChild.textContent = out(k);
      const pt = Number.parseFloat(getComputedStyle(kb).getPropertyValue("--pt")) || 1;
      const width = Math.min(el.offsetWidth * 1.5, el.offsetWidth + 22 * pt);
      const center = el.offsetLeft + el.offsetWidth / 2;
      const edge = width / 2 + 2 * pt;
      pop.style.left = `${Math.min(Math.max(center, edge), kb.offsetWidth - edge)}px`;
      pop.style.top = `${el.offsetTop}px`;
      pop.style.width = `${width}px`;
      pop.classList.add("on");
    }

    clearTimeout(el._up);
    el._up = setTimeout(() => {
      el.classList.remove("down");
      pop.classList.remove("on");
    }, ms);
    root.dispatchEvent(new CustomEvent("keypress", { detail: k }));
  };

  const send = () => {
    if (!text.trim()) {
      return;
    }

    const bubble = document.createElement("p");
    bubble.textContent = text.trim();
    thread.append(bubble);

    while (thread.children.length > 3) {
      thread.firstElementChild.remove();
    }

    text = "";
    shift = true;

    if (numbers) {
      setNumbers(false);
    }

    render();
  };

  const type = (k) => {
    if (k === "delete") {
      text = text.slice(0, -1);
    } else if (k === "space") {
      text += " ";
    } else if (k === "return") {
      send();
    } else if (k === "shift") {
      shift = !shift;
      render();

      return;
    } else if (k === "123") {
      setNumbers(!numbers);

      return;
    } else if (k === "emoji") {
      text += EMOJI[Math.floor(Math.random() * EMOJI.length)];
    } else if (k.length === 1) {
      text += out(k);
      shift = false;
    }

    render();
  };

  const takeOver = () => {
    if (!auto) {
      return;
    }

    auto = false;
    generation += 1;
    text = "";
    thread.replaceChildren();
    shift = true;
    root.classList.add("yours");
    render();
  };

  const autoType = async () => {
    const mine = generation;
    const stillMine = () => auto && mine === generation;
    let n = 0;
    await sleep(700);

    while (stillMine()) {
      const line = LINES[n % LINES.length];
      n += 1;

      for (const ch of line) {
        if (!stillMine()) {
          return;
        }

        const lower = ch.toLowerCase();

        if (ch !== lower) {
          press("shift");
          shift = true;
          render();
          await sleep(140);
        }

        if (ch === " ") {
          press("space", 95);
        } else if (keys.has(lower)) {
          press(lower, 95);
        }

        text += ch;
        shift = false;
        render();
        await sleep(ch === " " ? 120 + Math.random() * 90 : 55 + Math.random() * 70);
      }

      await sleep(900);

      if (!stillMine()) {
        return;
      }

      press("return", 140);
      send();
      shift = false;
      render();
      await sleep(1100);
    }
  };

  const dictate = async (words = "Running late, but I’ll be there by 3:30pm. Save me a seat") => {
    takeOver();
    send();
    setNumbers(false);
    kb.classList.add("listening");
    mic.setAttribute("aria-pressed", "true");
    clock.textContent = "0:00";
    await sleep(reduced ? 300 : 1000);
    clock.textContent = "0:01";
    await sleep(reduced ? 0 : 900);
    kb.classList.remove("listening");
    kb.classList.add("writing");
    await sleep(reduced ? 100 : 450);
    kb.classList.remove("writing");
    mic.setAttribute("aria-pressed", "false");
    text = words;
    shift = false;
    render();
  };

  kb.addEventListener("pointerdown", (event) => {
    if (event.target.closest(".k-mic")) {
      event.preventDefault();
      void dictate();

      return;
    }

    const b = event.target.closest(".sugg button");

    if (b) {
      event.preventDefault();
      takeOver();
      const word = b.textContent.replaceAll(/[“”]/gu, "");
      text = `${text.replace(/[\w'+-]*$/u, "")}${word} `;
      render();

      return;
    }

    const el = event.target.closest("[data-k]");

    if (!el) {
      return;
    }

    event.preventDefault();
    takeOver();
    press(el.dataset.k);
    type(el.dataset.k);
  });

  const visible = { now: false };
  new IntersectionObserver(([entry]) => {
    visible.now = entry.isIntersecting;
  }).observe(kb);
  addEventListener("keydown", (event) => {
    if (!visible.now || !active() || event.metaKey || event.ctrlKey || event.altKey) {
      return;
    }

    if (event.target.closest?.("input, textarea, [contenteditable]")) {
      return;
    }

    const map = { " ": "space", Backspace: "delete", Enter: "return" };
    const k = map[event.key] ?? (event.key.length === 1 ? event.key : null);

    if (!k) {
      return;
    }

    const lower = k.length === 1 ? k.toLowerCase() : k;

    if (k.length === 1 && !/[a-z]/iu.test(k) && !/[.,'!?+:-]/u.test(k)) {
      return;
    }

    event.preventDefault();
    takeOver();

    if (numbers) {
      setNumbers(false);
    }

    if (keys.has(lower)) {
      press(lower);
    }

    if (k.length === 1) {
      text += k;
      shift = false;
      render();
    } else {
      type(k);
    }
  });

  root.dictate = dictate;

  if (reduced) {
    [text] = LINES;
    render();
  } else {
    render();
    void autoType();
  }

  fit();

  return { press, dictate };
};
