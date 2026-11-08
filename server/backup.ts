#!/usr/bin/env bun
import { mkdir, readdir, rename, rm, stat, utimes } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { parseArgs } from "node:util";

import { z } from "zod";

import { keystroke } from "./keystroke.ts";

const GIVEN_BACK = ["mac", "personal"];

export const Held = z.record(z.string(), z.tuple([z.number(), z.number()]));

export type Held = z.infer<typeof Held>;

const held = async (mirror: string): Promise<Held> => {
  const entries = await readdir(mirror, { recursive: true, withFileTypes: true }).catch(() => []);

  const files = entries
    .filter((entry) => entry.isFile())
    .map((entry) => path.join(entry.parentPath, entry.name));

  const listed = await Promise.all(
    files.map(async (file) => {
      const { size, mtimeMs } = await stat(file);
      const sizeAndTime: Held[string] = [size, Math.floor(mtimeMs / 1000)];

      return [path.relative(mirror, file).split(path.sep).join("/"), sizeAndTime] as const;
    }),
  );

  return Object.fromEntries(listed);
};

const same = async (a: string, b: string) => {
  const [one, other] = [Bun.file(a), Bun.file(b)];

  return (
    one.size === other.size &&
    Buffer.from(await one.arrayBuffer()).equals(Buffer.from(await other.arrayBuffer()))
  );
};

const two = (n: number) => String(n).padStart(2, "0");

const versionStamp = (date: Date) =>
  `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}T${two(date.getHours())}${two(date.getMinutes())}${two(date.getSeconds())}`;

const freeVersion = async (versions: string, time: string, name: string) => {
  for (let n = 0; ; n += 1) {
    const version = path.join(
      versions,
      n === 0 ? time : `${time}.${String(n).padStart(3, "0")}`,
      name,
    );

    // oxlint-disable-next-line eslint/no-await-in-loop -- each folder is tried only once the one before it is taken
    if (!(await Bun.file(version).exists())) {
      return version;
    }
  }
};

const status = (code: number) => new Response(null, { status: code });

const giveBack = async (shared: string, name: string) => {
  const file = path.join(shared, name);
  const sent = Bun.file(file);

  const inGiven = GIVEN_BACK.some((folder) =>
    file.startsWith(path.join(shared, folder) + path.sep),
  );

  if (!inGiven || !(await sent.exists())) {
    return status(404);
  }

  const { mtimeMs } = await stat(file);

  return new Response(sent, { headers: { "last-modified": new Date(mtimeMs).toUTCString() } });
};

interface Replacing {
  readonly own: string;
  readonly name: string;
  readonly file: string;
  readonly incoming: string;
  readonly now: () => Date;
}

const keepReplaced = async ({ own, name, file, incoming, now }: Replacing) => {
  if (!(await Bun.file(file).exists())) {
    return;
  }

  if (await same(file, incoming)) {
    await rm(incoming);

    return;
  }

  const version = await freeVersion(path.join(own, "versions"), versionStamp(now()), name);
  await mkdir(path.dirname(version), { recursive: true });
  await rename(file, version);
};

export const backup =
  (dir: string, token: string, now = () => new Date()) =>
  async (request: Request): Promise<Response> => {
    if (request.headers.get("authorization") !== `Bearer ${token}`) {
      return status(401);
    }

    const device = request.headers.get("x-device") ?? "iPhone";

    if (!/^[A-Za-z]+$/u.test(device)) {
      return status(400);
    }

    const shared = path.join(dir, "mirror");
    const own = device === "iPhone" ? dir : `${dir.replace(/\/+$/u, "")}-${device.toLowerCase()}`;
    const mirror = path.join(own, "mirror");

    const name = decodeURIComponent(new URL(request.url).pathname).replace(
      /^\/+(?:backup\/*)?/u,
      "",
    );

    if (request.method === "GET" && name === "") {
      const gives = Object.entries(await held(shared)).filter(([file]) =>
        GIVEN_BACK.some((folder) => file.startsWith(`${folder}/`)),
      );

      return Response.json(
        { ...(await held(mirror)), ...Object.fromEntries(gives) },
        { headers: { "x-device": device } },
      );
    }

    if (request.method === "GET" && name === "iphone/typing-stats.json") {
      return Response.json(await keystroke(shared));
    }

    if (request.method === "GET") {
      return await giveBack(shared, name);
    }

    const file = path.join(mirror, name);
    const modified = Number(request.headers.get("x-modified"));

    if (
      request.method !== "PUT" ||
      !file.startsWith(mirror + path.sep) ||
      !Number.isSafeInteger(modified)
    ) {
      return status(400);
    }

    const incoming = path.join(own, "incoming", crypto.randomUUID());

    await mkdir(path.dirname(incoming), { recursive: true });
    await Bun.write(incoming, request);
    await keepReplaced({ own, name, file, incoming, now });

    if (await Bun.file(incoming).exists()) {
      await mkdir(path.dirname(file), { recursive: true });
      await rename(incoming, file);
    }

    await utimes(file, modified, modified);

    return status(204);
  };

if (import.meta.main) {
  const { values } = parseArgs({
    options: {
      port: { type: "string", default: "2592" },
      dir: { type: "string", default: path.join(homedir(), ".local/share/iikb/backup") },
    },
  });

  const token = process.env.BACKUP_TOKEN ?? "";

  if (token === "") {
    throw new Error("BACKUP_TOKEN is unset");
  }

  Bun.serve({
    hostname: "127.0.0.1",
    port: Number(values.port),
    maxRequestBodySize: Number.MAX_SAFE_INTEGER,
    fetch: backup(values.dir, token),
  });
}
