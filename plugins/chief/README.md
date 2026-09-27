# Chief

A lightweight supervisor for Claude Code: dispatches work to isolated builder/scout agents over the herdr or Orca backend, tracks a plain-markdown backlog, and supervises them with a near-zero-token watch loop. (Verbatim from `.claude-plugin/plugin.json`'s `description` - see "Maintaining these docs" below.)

Scoped down hard from bigger multi-agent supervisors on purpose: **Claude Code only**, **herdr or Orca backend only** (configurable via `.chief/config/backend`, default `herdr`), one delivery mode (branch + you approve every merge - no auto-merge). Every script is meant to be short enough to read start to finish.

Inspired by [Firstmate](https://github.com/kunchenguid/firstmate), which does the same job across many more harnesses, backends, and delivery modes - Chief keeps its core ideas (isolated worktrees per task, an intent/spec brief split, a closed status vocabulary, a durable steering inbox, refuse-before-discard teardown, and a near-zero-token Stop-hook watch loop) while cutting everything scoped to that broader generality.

## Layout

- `bin/` - the lifecycle scripts (`chief-spawn`, `chief-send`, `chief-control`, `chief-crew-state`, `chief-watch`, `chief-teardown`, `chief-local-merge`, `chief-promote`, `chief-backlog`, `chief-setup`), the PR/MR lifecycle scripts (`chief-pr-open`, `chief-pr-state`, `chief-pr-review`, `chief-pr-approve`, `chief-pr-merge`), and `bin/lib/` (path/meta/lock helpers, the backend adapters, the PR provider dispatcher `chief-pr-provider.sh` and its adapters `chief-pr-provider-{mock,github,gitlab,azuredevops}.sh`, and `chief-worktree.sh` - the guard that tells a spawned builder's own session apart from the operator-facing one).
- `templates/` - the two brief templates (`brief-ship.md`, `brief-scout.md`).
- `skills/using-chief` - the identity/job-description skill, force-injected every session via the `SessionStart` hook so Chief always knows its role without being asked.
- `skills/setup` - one-time CHIEF_HOME config (backend choice + gitignoring `.chief/`); only relevant before `.chief/config/backend` exists, which the `SessionStart` digest flags explicitly.
- `skills/dispatch` - the operator-facing entry point; load this to hand off work.
- `skills/reviewer` - a short fixed review checklist, run before merging.
- `hooks/` - `SessionStart` (injects `using-chief`, a configuration status line, and a backlog/in-flight digest) and `Stop` (the token-saving watch arm). Both stand down entirely inside a spawned builder's own worktree - see `chief-worktree.sh`.

Runtime state lives at `.chief/` under `CHIEF_HOME` - the git root of wherever the Chief session itself runs, typically the operator's top-level workspace, not each project it dispatches into (`state/`, `data/`, `config/`, `worktrees/`) - created on first use, not part of the plugin package. `chief-setup.sh` gitignores it for you.

## Status

Core lifecycle (backlog, spawn, send, control/relaunch, crew-state, watch, teardown, merge, promote) is implemented and tested end-to-end against a mock backend. The **herdr adapter** (`bin/lib/chief-backend-herdr.sh`) is verified against a live herdr 0.9.0 install - spawn/capture/busy/send/kill/relaunch all exercised end to end with a real `claude` turn in `tests/chief/test-backend-herdr.sh` (opt-in, `CHIEF_TEST_HERDR=1`). The **Orca adapter** (`bin/lib/chief-backend-orca.sh`) has spawn confirmed live in `tests/chief/test-backend-orca.sh` (opt-in, `CHIEF_TEST_ORCA=1`); **relaunch has a known live issue** - see the adapter's header comment.

PR provider adapters: **GitHub** is implemented and tested against a fake `gh` CLI, including inline (file:line) review comments. **GitLab and Azure DevOps are fully implemented but their `pr_review_line` (inline comments) is an unverified draft**, same status as the Orca backend - built from each provider's documented API shape, not run against a live `glab`/`az` install; each adapter's header comment lists exactly what needs confirming.

## Maintaining these docs

One owner per fact - don't restate one doc's content in another:

- Public pitch and current status -> this file (`README.md`) only.
- Agent operating contract and hard rules -> `skills/using-chief/SKILL.md`
  only; never restated here.
- Step-by-step process for one workflow -> that step's own `SKILL.md`
  (`skills/dispatch`, `skills/reviewer`, `skills/setup`).
- Stable architecture and extension points (backend adapters, PR-provider
  adapters) -> a future `plugins/chief/ARCHITECTURE.md`, created once the
  "Layout" section above actually needs to split out, not pre-emptively.

This plugin's one-line pitch lives in `.claude-plugin/plugin.json`'s
`description`; this file's opening line quotes it verbatim rather than
paraphrasing it, so there's exactly one wording to keep current.
