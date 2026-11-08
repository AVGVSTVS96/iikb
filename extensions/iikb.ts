/**
 * An iikb extension: the keyboard draws a panel of chats, and the extension says what's in it (docs/extensions.md).
 *
 *   export default chats({ name, list, read, send })   // bun extensions/<name>.ts, IIKB_TOKEN=secret PORT=2593
 */

export interface Chat {
  readonly id: string;
  readonly name: string;
  /** What it's about or where it stands, under its name. */
  readonly line?: string;
  /** Pinned chats come first. */
  readonly pinned?: boolean;
}

export interface Message {
  /** `me`, or who else wrote it. */
  readonly from: string;
  readonly text: string;
  /** Sent, but not yet taken in by the other side. */
  readonly pending?: boolean;
}

export interface Messages {
  /** Changes whenever the messages do. */
  readonly version: string;
  readonly messages: ReadonlyArray<Message>;
}

export interface Chats {
  readonly name: string;
  list(): Promise<ReadonlyArray<Chat>>;
  /** The chat's messages; with `after`, once they're no longer at that version. */
  read(chat: string, after?: string): Promise<Messages>;
  /** `id` names the message, so a retry after a lost answer sends it once. */
  send(chat: string, text: string, id: string): Promise<void>;
}

/** The keyboard shows a chat's latest messages, so it gets only these. */
const SHOWN = 40;

export const chats = (extension: Chats) => ({
  hostname: process.env["HOST"] ?? "127.0.0.1",
  port: Number(process.env["PORT"] ?? 2593),
  idleTimeout: 60,
  fetch: (request: Request) => answer(extension, request, process.env["IIKB_TOKEN"]),
});

export const answer = async (extension: Chats, request: Request, token?: string): Promise<Response> => {
  if (token && request.headers.get("authorization") !== `Bearer ${token}`) return new Response(null, { status: 401 });
  const url = new URL(request.url);
  const chat = decodeURIComponent(url.pathname.slice(1));
  try {
    if (request.method === "GET" && !chat) return Response.json({ name: extension.name, chats: await extension.list() });
    if (request.method === "GET") {
      const { version, messages } = await extension.read(chat, url.searchParams.get("after") ?? undefined);
      return Response.json({ version, messages: messages.slice(-SHOWN) });
    }
    if (request.method === "POST" && chat) {
      const { text, id } = (await request.json()) as { text?: unknown; id?: unknown };
      if (typeof text !== "string" || !text.trim() || typeof id !== "string") return new Response("Send { text, id }", { status: 400 });
      await extension.send(chat, text.trim(), id);
      return new Response(null, { status: 204 });
    }
    return new Response(null, { status: 405 });
  } catch (error) {
    return new Response(error instanceof Error ? error.message : String(error), { status: 502 });
  }
};
