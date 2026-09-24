---
name: setup
description: Use when Chief has not been configured yet in this project (no .chief/config/backend) - walks the operator through the one-time setup of choosing a backend and gitignoring runtime state. Do not use once Chief is already configured; dispatch owns everything after that.
---

# Chief: setup

Only needed once per project, when `.chief/config/backend` doesn't exist yet.

All commands live in `${CLAUDE_PLUGIN_ROOT}/bin/`.

1. Ask the operator which backend to use: `herdr` or `orca`. Skip this if they already said.
2. Run `${CLAUDE_PLUGIN_ROOT}/bin/chief-setup.sh --backend <choice>`. It writes the config, checks the tool is on PATH, and adds `.chief/` to `.gitignore` if missing - safe to re-run.
3. If it warns the backend isn't on PATH, tell the operator plainly - dispatching won't work until it's installed (and for Orca, actually running; the PATH check can't confirm that part).
4. Done. From here on, use `dispatch` for actual work.
