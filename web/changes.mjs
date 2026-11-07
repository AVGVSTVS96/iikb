// The page's record of the work: how many commits, since when, and the newest changes from their Changelog trailers.
import { execFileSync } from "node:child_process";

const git = (...args) => execFileSync("git", args, { encoding: "utf8" }).trim();
const log = git("log", "--format=%h%x1f%cI%x1f%(trailers:key=Changelog,valueonly,separator=%x1e)%x1d")
  .split("\x1d")
  .map((entry) => entry.trim().split("\x1f"))
  .filter(([sha]) => sha);

const changes = log
  .flatMap(([sha, at, trailers]) => (trailers ?? "").split("\x1e").map((text) => ({ sha, at, text: text.trim().replace(/\.$/, "") })))
  .filter((change) => change.text)
  .slice(0, 24);

const [head] = log;
const first = log.at(-1);
console.log(JSON.stringify({ commits: log.length, since: first[1], head: { sha: head[0], at: head[1] }, changes }, null, 2));
