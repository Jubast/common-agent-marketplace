// Copilot's wake adapter (needs experimental on). Runs hooks/watch-reason.sh and
// wakes the session with session.send; a send mid-turn is queued by Copilot.
import { joinSession } from "@github/copilot-sdk/extension";
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const WATCH = join(dirname(fileURLToPath(import.meta.url)), "../../hooks/watch-reason.sh");
const IDLE_MS = 30000;
const STAND_DOWN = 3;

let child;
const stop = () => { try { process.kill(-child.pid); } catch {} };
process.on("exit", stop);
for (const sig of ["SIGTERM", "SIGINT", "SIGHUP"]) process.on(sig, () => process.exit(0));

// A detached child, so stop() also ends the chief-watch.sh under it.
const watch = () => new Promise((resolve) => {
  let out = "";
  child = spawn(WATCH, [process.cwd()], { detached: true, stdio: ["ignore", "pipe", "ignore"] });
  child.stdout.on("data", (d) => { out += d; });
  child.on("error", () => resolve({ code: 1, out: "" }));
  child.on("close", (code) => resolve({ code, out: out.trim() }));
});

const session = await joinSession({});
for (;;) {
  const { code, out } = await watch();
  if (code === STAND_DOWN) break;
  if (out) await session.send({ prompt: `chief watcher: ${out}` });
  else await new Promise((r) => setTimeout(r, IDLE_MS));
}
