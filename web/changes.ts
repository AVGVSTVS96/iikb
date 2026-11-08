const FIELD = "\u001F";
const COMMIT = "\u001D";
const TRAILER = "\u001E";
const NEWEST_CHANGES = 24;

const log = Bun.spawnSync(
  ["git", "log", "--format=%h%x1f%cI%x1f%(trailers:key=Changelog,valueonly,separator=%x1e)%x1d"],
  { stderr: "inherit" },
);

if (!log.success) {
  throw new Error(`git log failed with ${log.exitCode}`);
}

const commits = log.stdout
  .toString()
  .split(COMMIT)
  .map((entry) => {
    const [sha = "", at = "", trailers = ""] = entry.trim().split(FIELD);

    return { sha, at, trailers };
  })
  .filter(({ sha }) => sha !== "");

const head = commits.at(0);
const first = commits.at(-1);

if (!head || !first) {
  throw new Error("git log found no commits");
}

const changes = commits
  .flatMap(({ sha, at, trailers }) =>
    trailers.split(TRAILER).map((text) => ({
      sha,
      at,
      text: text.trim().replace(/\.$/u, "").replaceAll("'", "’"),
    })),
  )
  .filter(({ text }) => text !== "")
  .slice(0, NEWEST_CHANGES);

console.log(
  JSON.stringify(
    { commits: commits.length, since: first.at, head: { sha: head.sha, at: head.at }, changes },
    null,
    2,
  ),
);
