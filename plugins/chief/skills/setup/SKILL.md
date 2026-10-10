---
name: setup
description: Use when Chief has not been configured yet at CHIEF_HOME (no .chief/config/backend at the operator's workspace root) - walks the operator through the one-time setup of choosing a backend, the workers' agents, and gitignoring runtime state. This is a one-time step for the whole CHIEF_HOME, not something to repeat inside each project you dispatch into. Do not use once Chief is already configured; dispatch owns everything after that.
---

# Chief: setup

Only needed once per `CHIEF_HOME` - the operator's single shared home, typically their top-level workspace root, not each individual project you dispatch into - when `.chief/config/backend` doesn't exist there yet.

All commands live in `${CLAUDE_PLUGIN_ROOT}/bin/`.

1. Ask the operator which backend to use: `herdr` or `orca`. Skip this if they already said.
2. Run `${CLAUDE_PLUGIN_ROOT}/bin/chief-setup.sh --backend <choice>`. It writes the config, checks the tool is on PATH, and adds `.chief/` to `.gitignore` if missing - safe to re-run.
3. If it warns the backend isn't on PATH, tell the operator plainly - dispatching won't work until it's installed (and for Orca, actually running; the PATH check can't confirm that part).
4. Ask which agent[:model] the dispatched workers should run, for builders and for scouts: `claude` (default), `codex` or `copilot`, e.g. `claude:opus`. Optional per profile: `weight=N`, `args="..."` (extra CLI arguments), `command="..."` (replaces the launch command). One profile each, or a pool with a strategy (`first`, `round-robin`, `random`, `weighted`). Skip it if they decline: with no `.chief/config/agents`, workers run `claude`.
5. Write `.chief/config/agents` (format and example: the plugin README's "Agents" section), with `[builder]` and `[scout]` sections for separate pools and the global lines above them for a shared one. Only dispatched workers are configurable; the agent of this Chief session is set by the operator themselves, there is no option for it.
6. Done. From here on, use `dispatch` for actual work.
