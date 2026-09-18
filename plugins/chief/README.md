# Chief

A lightweight supervisor for Claude Code. Dispatches work to isolated worker agents ("builders" for code, "scouts" for investigation-only reports), tracks them in a plain-markdown backlog, and supervises them between your turns at near-zero token cost via a Stop-hook-armed background watch loop.

Scoped down hard from bigger multi-agent supervisors on purpose: **Claude Code only**, **herdr or Orca backend only** (configurable via `.chief/config/backend`, default `herdr`), one delivery mode (branch + you approve every merge - no auto-merge). Every script is meant to be short enough to read start to finish.

Inspired by [Firstmate](https://github.com/kunchenguid/firstmate), which does the same job across many more harnesses, backends, and delivery modes - Chief keeps its core ideas (isolated worktrees per task, an intent/spec brief split, a closed status vocabulary, a durable steering inbox, refuse-before-discard teardown, and a near-zero-token Stop-hook watch loop) while cutting everything scoped to that broader generality.

## Layout

- `bin/` - the lifecycle scripts (`chief-spawn`, `chief-send`, `chief-control`, `chief-crew-state`, `chief-watch`, `chief-teardown`, `chief-local-merge`, `chief-promote`, `chief-backlog`, `chief-setup`), the PR/MR lifecycle scripts (`chief-pr-open`, `chief-pr-state`, `chief-pr-review`, `chief-pr-approve`, `chief-pr-merge`), and `bin/lib/` (path/meta/lock helpers, the backend adapters, the PR provider dispatcher `chief-pr-provider.sh` and its adapters `chief-pr-provider-{mock,github,gitlab,azuredevops}.sh`, and `chief-worktree.sh` - the guard that tells a spawned builder's own session apart from the operator-facing one).
- `templates/` - the two brief templates (`brief-ship.md`, `brief-scout.md`).
- `skills/using-chief` - the identity/job-description skill, force-injected every session via the `SessionStart` hook so Chief always knows its role without being asked.
- `skills/setup` - one-time per-project config (backend choice + gitignoring `.chief/`); only relevant before `.chief/config/backend` exists, which the `SessionStart` digest flags explicitly.
- `skills/dispatch` - the operator-facing entry point; load this to hand off work.
- `skills/reviewer` - a short fixed review checklist, run before merging.
- `hooks/` - `SessionStart` (injects `using-chief`, a configuration status line, and a backlog/in-flight digest) and `Stop` (the token-saving watch arm). Both stand down entirely inside a spawned builder's own worktree - see `chief-worktree.sh`.

Runtime state lives at `.chief/` under the current project's git root (`state/`, `data/`, `config/`, `worktrees/`) - created on first use, not part of the plugin package. `chief-setup.sh` gitignores it for you.

## Status

Core lifecycle (backlog, spawn, send, control/relaunch, crew-state, watch, teardown, merge, promote) is implemented and tested end-to-end against a mock backend. The **herdr adapter** (`bin/lib/chief-backend-herdr.sh`) is verified against a live herdr 0.9.0 install - spawn/capture/busy/send/kill/relaunch all exercised end to end with a real `claude` turn in `tests/chief/test-backend-herdr.sh` (opt-in, `CHIEF_TEST_HERDR=1`). The **Orca adapter** (`bin/lib/chief-backend-orca.sh`) has spawn confirmed live in `tests/chief/test-backend-orca.sh` (opt-in, `CHIEF_TEST_ORCA=1`); **relaunch has a known live issue** - see the adapter's header comment.

PR provider adapters: **GitHub** is implemented and tested against a fake `gh` CLI, including inline (file:line) review comments. **GitLab and Azure DevOps are fully implemented but their `pr_review_line` (inline comments) is an unverified draft**, same status as the Orca backend - built from each provider's documented API shape, not run against a live `glab`/`az` install; each adapter's header comment lists exactly what needs confirming.
