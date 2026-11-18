// WARNING: since iOS 26.5 a script's label.click() plays no switch haptic, so a real tap lands on a label holding the switch: https://github.com/WebKit/WebKit/commit/fc1ef83eae
export const haptics = (surface) => {
  const touch = matchMedia("(pointer: coarse)").matches;
  const bySwitch = touch && "switch" in HTMLInputElement.prototype;
  const byVibrate = touch && !bySwitch && "vibrate" in navigator;

  const label = Object.assign(document.createElement("label"), {
    className: "haptic",
    hidden: true,
  });

  label.setAttribute("aria-hidden", "true");
  label.innerHTML = `<input type="checkbox" switch>`;
  surface.append(label);
  let on = false;
  let note = "This browser can’t play haptics.";

  if (bySwitch) {
    note =
      "A web page can only play the haptic as your finger lifts off a key, not as it lands like Apple’s keyboard.";
  } else if (byVibrate) {
    note = "";
  }

  return {
    available: bySwitch || byVibrate,
    note,
    get enabled() {
      return on;
    },
    set enabled(value) {
      on = value;
      label.hidden = !(on && bySwitch);
    },
    get needsClicks() {
      return on && bySwitch;
    },
    keyDown() {
      if (on && byVibrate) {
        navigator.vibrate(10);
      }
    },
  };
};
