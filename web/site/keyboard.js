/* oxlint-disable eslint/no-await-in-loop -- the hero is a timeline: each await is the pause before the next keystroke */
const ROWS = [
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
  ["shift", "z", "x", "c", "v", "b", "n", "m", "delete"],
  ["mic", "123", "emoji", "space", "return"],
];

const ICONS = {
  shift:
    '<svg viewBox="0 0 24 24"><path d="M12 3.8 3.6 12.6h4.8v6.6h7.2v-6.6h4.8z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
  grid: '<svg viewBox="0 0 24 24"><rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/></svg>',
  gif: '<svg viewBox="0 0 28 24"><rect x="2" y="5" width="24" height="14" rx="4" fill="none" stroke="currentColor" stroke-width="1.7"/><text x="14" y="15.6" text-anchor="middle" font-size="9" font-weight="800" font-family="Helvetica, Arial, sans-serif" fill="currentColor">GIF</text></svg>',
  delete:
    '<svg viewBox="0 0 24 24"><path d="M8.5 5H20a1.5 1.5 0 0 1 1.5 1.5v11A1.5 1.5 0 0 1 20 19H8.5L2.5 12z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="m11 9 6 6m0-6-6 6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  return:
    '<svg viewBox="0 0 24 24"><path d="M19 5v6a3 3 0 0 1-3 3H6m0 0 4-4m-4 4 4 4" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  emoji:
    '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5" fill="currentColor"/><circle cx="9" cy="10" r="1.2" fill="var(--kb-bg)"/><circle cx="15" cy="10" r="1.2" fill="var(--kb-bg)"/><path d="M8.5 14q3.5 3.2 7 0" fill="none" stroke="var(--kb-bg)" stroke-width="1.5" stroke-linecap="round"/></svg>',
  clip: '<svg viewBox="0 0 24 24"><rect x="5.5" y="4.5" width="13" height="16" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="9" y="2.8" width="6" height="3.4" rx="1.2" fill="currentColor"/><path d="M9 11h6M9 14.5h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  mic: '<svg viewBox="0 0 24 24"><path d="M4 10v4M8 7v10M12 4v16M16 7v10M20 10v4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
};

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
  "fast on-device dictation, gif + emoji search, clipboard history",
  "built on my iphone duo. it's my daily driver",
  "sooner or later everything is gonna be OSS",
  "bring your own integration. no more keyboard switching",
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

export const mountKeyboard = (root) => {
  const field = root.querySelector("[data-field]");
  const thread = root.querySelector("[data-thread]");
  const kb = root.querySelector(".kb");
  const keys = new Map();
  let text = "";
  let shift = false;
  let numbers = false;
  let auto = !reduced;
  let generation = 0;

  kb.innerHTML = `<div class="bar"><span class="bar-tool">${ICONS.grid}</span><span class="bar-tool gif">${ICONS.gif}</span><span class="bar-tool">${ICONS.clip}</span><div class="sugg"><button type="button" tabindex="-1"></button><button type="button" tabindex="-1"></button><button type="button" tabindex="-1"></button></div><div class="wave" aria-hidden="true">${"<i></i>".repeat(18)}</div></div>${ROWS.map(
    (row, r) =>
      `<div class="row r${r}">${row
        .map((k) => {
          const fn = k.length > 1 && k !== "space";

          return `<span class="k${fn ? " fn" : ""} k-${k}" data-k="${k}"><i class="face">${keyLabel(k)}</i></span>`;
        })
        .join("")}</div>`,
  ).join("")}<div class="pop" aria-hidden="true"><i></i></div>`;

  for (const el of kb.querySelectorAll("[data-k]")) {
    keys.set(el.dataset.k, el);
  }

  const pop = kb.querySelector(".pop");
  const sugg = [...kb.querySelectorAll(".sugg button")];
  const mic = keys.get("mic");

  const fit = () => {
    const w = kb.clientWidth;
    const pt = w / 390;
    const letter = keys.get("q").offsetWidth / pt;
    kb.style.setProperty("--pt", `${pt}px`);
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
      const kr = el.getBoundingClientRect();
      const br = kb.getBoundingClientRect();
      pop.style.left = `${kr.left - br.left + kr.width / 2}px`;
      pop.style.top = `${kr.top - br.top}px`;
      pop.style.setProperty("--w", `${kr.width}px`);
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
    await sleep(reduced ? 300 : 1900);
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
    if (!visible.now || event.metaKey || event.ctrlKey || event.altKey) {
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
