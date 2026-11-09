import { z } from "zod";

export interface Chat {
  readonly id: string;
  readonly name: string;
  readonly line?: string;
  readonly pinned?: boolean;
}

export interface File {
  readonly name: string;
  readonly url: string;
  readonly type?: string;
}

export interface Message {
  readonly from: string;
  readonly text: string;
  readonly pending?: boolean;
  readonly files?: readonly File[];
}

export interface Messages {
  readonly version: string;
  readonly messages: readonly Message[];
}

export interface Chats {
  readonly name: string;
  readonly list: () => Promise<readonly Chat[]>;
  readonly read: (chat: string, after?: string) => Promise<Messages>;
  readonly send: (chat: string, text: string, id: string) => Promise<void>;
}

const SHOWN_LATEST_MESSAGES = 40;

const Sent = z.object({ text: z.string().trim().min(1), id: z.string() });

const status = (code: number) => new Response(null, { status: code });

const route = async (extension: Chats, request: Request, chat: string, after: string | null) => {
  if (request.method === "GET" && chat === "") {
    return Response.json({ name: extension.name, chats: await extension.list() });
  }

  if (request.method === "GET") {
    const { version, messages } = await extension.read(chat, after ?? undefined);

    return Response.json({ version, messages: messages.slice(-SHOWN_LATEST_MESSAGES) });
  }

  if (request.method !== "POST" || chat === "") {
    return status(405);
  }

  const sent = Sent.safeParse(await request.json().catch(() => null));

  if (!sent.success) {
    return new Response("Send { text, id }", { status: 400 });
  }

  await extension.send(chat, sent.data.text, sent.data.id);

  return status(204);
};

export const answer = async (extension: Chats, request: Request, token = ""): Promise<Response> => {
  if (token !== "" && request.headers.get("authorization") !== `Bearer ${token}`) {
    return status(401);
  }

  const url = new URL(request.url);

  try {
    return await route(
      extension,
      request,
      decodeURIComponent(url.pathname.slice(1)),
      url.searchParams.get("after"),
    );
  } catch (error) {
    return new Response(error instanceof Error ? error.message : String(error), { status: 502 });
  }
};

export const chats = (extension: Chats) => ({
  hostname: process.env.HOST ?? "127.0.0.1",
  port: Number(process.env.PORT ?? "2593"),
  idleTimeout: 60,
  fetch: async (request: Request) => await answer(extension, request, process.env.IIKB_TOKEN),
});
