const SOURCE = `import { chats } from "./iikb.ts";

export default chats({
  name: "notes",
  list: async () => [inbox],
  read: async (chat, after) => thread,
  send: async (chat, text) => save(text),
});`;

const TOKEN =
  /(?<string>"[^"]*")|\b(?<keyword>import|from|export|default|async)\b|\b(?<call>list|read|send)(?=:)/gu;

const tone = (m: RegExpExecArray) => {
  if (m.groups?.string !== undefined) {
    return "text-muted-foreground";
  }

  return m.groups?.keyword === undefined ? "text-pick" : "text-faint";
};

const highlight = (source: string) => {
  const out: { text: string; tone?: string }[] = [];
  let at = 0;

  for (const m of source.matchAll(TOKEN)) {
    out.push({ text: source.slice(at, m.index) }, { text: m[0], tone: tone(m) });
    at = m.index + m[0].length;
  }

  out.push({ text: source.slice(at) });

  return out;
};

export const Code = () => (
  <pre className="overflow-x-auto p-4 font-mono text-[12px] leading-[1.7] sm:text-[13px]">
    <code>
      {highlight(SOURCE).map((part, i) => (
        <span key={i} className={part.tone}>
          {part.text}
        </span>
      ))}
    </code>
  </pre>
);
