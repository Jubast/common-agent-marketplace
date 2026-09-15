# Chief

A lightweight supervisor for Claude Code. Dispatches work to isolated worker agents ("builders" for code, "scouts" for investigation-only reports), tracks them in a plain-markdown backlog, and supervises them between your turns at near-zero token cost via a Stop-hook-armed background watch loop.

Scoped down hard from bigger multi-agent supervisors on purpose: **Claude Code only**, **herdr or Orca backend only** (configurable via `.chief/config/backend`, default `herdr`), one delivery mode (branch + you approve every merge - no auto-merge). Every script is meant to be short enough to read start to finish.

Inspired by [Firstmate](https://github.com/kunchenguid/firstmate), which does the same job across many more harnesses, backends, and delivery modes - Chief keeps its core ideas (isolated worktrees per task, an intent/spec brief split, a closed status vocabulary, a durable steering inbox, refuse-before-discard teardown, and a near-zero-token Stop-hook watch loop) while cutting everything scoped to that broader generality.

## Layout

- `bin/` - the lifecycle scripts (`chief-spawn`, `chief-send`, `chief-control`, `chief-crew-state`, `chief-watch`, `chief-teardown`, `chief-merge`, `chief-backlog`, `chief-setup`) and `bin/lib/` (path/meta/lock helpers, the backend adapters, and `chief-worktree.sh` - the guard that tells a spawned builder's own session apart from the operator-facing one).
- `templates/` - the two brief templates (`brief-ship.md`, `brief-scout.md`).
- `skills/using-chief` - the identity/job-description skill, force-injected every session via the `SessionStart` hook so Chief always knows its role without being asked.
- `skills/setup` - one-time per-project config (backend choice + gitignoring `.chief/`); only relevant before `.chief/config/backend` exists, which the `SessionStart` digest flags explicitly.
- `skills/dispatch` - the operator-facing entry point; load this to hand off work.
- `skills/reviewer` - a short fixed review checklist, run before merging.
- `hooks/` - `SessionStart` (injects `using-chief`, a configuration status line, and a backlog/in-flight digest) and `Stop` (the token-saving watch arm). Both stand down entirely inside a spawned builder's own worktree - see `chief-worktree.sh`.

Runtime state lives at `.chief/` under the current project's git root (`state/`, `data/`, `config/`, `worktrees/`) - created on first use, not part of the plugin package. `chief-setup.sh` gitignores it for you.

## Status

Core lifecycle (backlog, spawn, send, control/relaunch, crew-state, watch, teardown, merge) is implemented and tested end-to-end against a mock backend. The **herdr and Orca adapters are unverified drafts** (`bin/lib/chief-backend-herdr.sh`, `bin/lib/chief-backend-orca.sh`) - built from documented command fragments, not run against a live install. Each has a header comment listing exactly what needs confirming against the real CLI before it's trustworthy.
