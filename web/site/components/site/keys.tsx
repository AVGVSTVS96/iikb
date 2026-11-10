import { ICONS } from "@/lib/icons.js";
import { cssVars, themeNames } from "@/lib/themes.js";

const ROWS = [
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
  ["shift", "z", "x", "c", "v", "b", "n", "m", "delete"],
  ["123", "emoji", "space", "return"],
];

const icons = new Map<string, string>(Object.entries(ICONS));

const Face = ({ k }: { k: string }) => {
  if (k.length === 1 || k === "123") {
    return <i className="face">{k}</i>;
  }

  if (k === "space") {
    return (
      <i className="face">
        <small>iikb</small>
      </i>
    );
  }

  return <i className="face" dangerouslySetInnerHTML={{ __html: icons.get(k) ?? "" }} />;
};

export const Keys = ({ bar = true }: { bar?: boolean }) => (
  <div className="kb" aria-hidden="true">
    {bar ? (
      <div className="bar">
        <span className="bar-btn" dangerouslySetInnerHTML={{ __html: icons.get("grid") ?? "" }} />
        <div className="sugg">
          <button type="button" tabIndex={-1}>
            I
          </button>
          <button type="button" tabIndex={-1} className="lead">
            the
          </button>
          <button type="button" tabIndex={-1}>
            I’m
          </button>
        </div>
        <span className="bar-btn" dangerouslySetInnerHTML={{ __html: icons.get("mic") ?? "" }} />
      </div>
    ) : null}
    {ROWS.map((row, r) => (
      <div key={row[0]} className={`row r${r}`}>
        {row.map((k) => (
          <span key={k} className={`k${k.length > 1 && k !== "space" ? " fn" : ""} k-${k}`}>
            <Face k={k} />
          </span>
        ))}
      </div>
    ))}
    <div className="sys">
      <span dangerouslySetInnerHTML={{ __html: icons.get("globe") ?? "" }} />
      <span dangerouslySetInnerHTML={{ __html: icons.get("dictation") ?? "" }} />
    </div>
  </div>
);

const block = (selector: string, vars: Record<string, string>) =>
  `${selector}{${Object.entries(vars)
    .map(([k, v]) => `${k}:${v}`)
    .join(";")}}`;

const css = (scheme: "light" | "dark") =>
  [
    block(":root", cssVars("standard", scheme)),
    ...themeNames.map((name) => block(`[data-kb-theme="${name}"]`, cssVars(name, scheme))),
  ].join("");

export const ThemeStyles = () => (
  <style
    dangerouslySetInnerHTML={{
      __html: `${css("light")}@media (prefers-color-scheme: dark){${css("dark")}}`,
    }}
  />
);
