const flat = (fill, pressed, label) => ({
  top: fill,
  bottom: fill,
  pressedTop: pressed,
  pressedBottom: pressed,
  label,
});

const host = {
  dark: { bg: "#212121", key: flat("#2f2f2f", "#6b6b6b", "#ffffff"), bar: "#ffffff" },
  light: {
    bg: "#d3d5db",
    key: { ...flat("#ffffff", "#abb0ba", "#000000"), drop: "0 1px 0 rgb(0 0 0 / .28)" },
    bar: "#000000",
  },
};

const classic = {
  letter: {
    top: "#f5f5f5",
    bottom: "#c3c5c9",
    pressedTop: "#c4c7cd",
    pressedBottom: "#acb0b8",
    label: "#000000",
    labelShadow: "0 1px 0 #ffffff",
    rim: ["rgb(255 255 255 / .3)", 0.85, 0.2],
    drop: "0 1px 1px rgb(0 0 0 / .3)",
  },
  function: {
    top: "#9ea6af",
    bottom: "#6d737c",
    pressedTop: "#80868f",
    pressedBottom: "#5a5f68",
    label: "#ffffff",
    labelShadow: "0 -1px 0 rgb(0 0 0 / .55)",
    rim: ["rgb(255 255 255 / .18)", 0.85, 0.2],
    drop: "0 1px 1px rgb(0 0 0 / .3)",
  },
};

export const themes = {
  standard: {
    title: "Default",
    dark: { letter: host.dark.key },
    light: { letter: host.light.key },
  },
  clear: {
    title: "Clear",
    dark: { letter: flat("transparent", "rgb(255 255 255 / .16)", "#ffffff") },
    light: { letter: flat("transparent", "rgb(0 0 0 / .16)", "#000000") },
  },
  physical: {
    title: "Physical",
    dark: {
      letter: {
        top: "#0b0b0b",
        bottom: "#050505",
        pressedTop: "#3a3a3c",
        pressedBottom: "#343436",
        label: "#ffffff",
        rim: ["rgb(255 255 255 / .15)", 1 / 3, 0.25],
      },
    },
    light: {
      letter: {
        ...flat("#f8f8f8", "#c4c6cc", "#2c2c2c"),
        rim: ["rgb(255 255 255 / .6)", 1 / 3, 0.1],
      },
    },
  },
  mechanical: {
    title: "Mechanical",
    dark: {
      letter: {
        top: "#171717",
        bottom: "#202020",
        pressedTop: "#111111",
        pressedBottom: "#181818",
        label: "#ffffff",
        keycap: {
          sides: ["#171717 0%", "#0e0e0e 80%", "#0d0d0d 100%"],
          glow: "rgb(255 255 255 / .12)",
        },
      },
    },
    light: {
      letter: {
        top: "#fafafa",
        bottom: "#e5e5e5",
        pressedTop: "#e8e8e8",
        pressedBottom: "#d6d6d6",
        label: "#2a2a29",
        keycap: { sides: ["#e0e0e0 0%", "#dbdbdb 100%"], glow: "rgb(255 255 255 / .23)" },
      },
    },
  },
  classic: {
    title: "iOS 5",
    dark: classic,
    light: classic,
  },
};

export const themeNames = Object.keys(themes);

export const paint = (name, scheme) => {
  const theme = themes[name] ?? themes.standard;
  const look = theme[scheme];

  return { ...host[scheme], letter: look.letter, function: look.function ?? look.letter };
};

const keyVars = (prefix, key) => ({
  [`--${prefix}-top`]: key.top,
  [`--${prefix}-bottom`]: key.bottom,
  [`--${prefix}-ptop`]: key.pressedTop,
  [`--${prefix}-pbottom`]: key.pressedBottom,
  [`--${prefix}-label`]: key.label,
  [`--${prefix}-lshadow`]: key.labelShadow ?? "none",
  [`--${prefix}-drop`]: key.drop ?? "none",
  [`--${prefix}-rim`]: key.rim ? key.rim[0] : "transparent",
  [`--${prefix}-rim-fade`]: key.rim ? `${key.rim[2] * 100}%` : "0%",
  [`--${prefix}-sides`]: key.keycap
    ? `radial-gradient(60% 55% at 50% 0%, ${key.keycap.glow}, transparent), linear-gradient(${key.keycap.sides.join(",")})`
    : "transparent",
  [`--${prefix}-cap`]: key.keycap ? "1" : "0",
});

export const cssVars = (name, scheme) => {
  const p = paint(name, scheme);

  return {
    "--kb-bg": p.bg,
    "--kb-bar": p.bar,
    ...keyVars("l", p.letter),
    ...keyVars("f", p.function),
  };
};
