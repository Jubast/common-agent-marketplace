# Chief

A lightweight supervisor for Claude Code: dispatches work to isolated builder/researcher agents over the herdr or Orca backend, tracks a plain-markdown backlog, and supervises them with a near-zero-token watch loop. (Verbatim from `.claude-plugin/plugin.json`'s `description` - see "Maintaining these docs" below.)

Scoped down hard from bigger multi-agent supervisors on purpose: **Claude Code only**, **herdr or Orca backend only** (configurable via `.chief/config/backend`, default `herdr`), one delivery mode (branch + you approve every merge - no auto-merge). Every script is meant to be short enough to read start to finish.

Inspired by [Firstmate](https://github.com/kunchenguid/firstmate), which does the same job across many more harnesses, backends, and delivery modes - Chief keeps its core ideas (isolated worktrees per task, an intent/spec brief split, a closed status vocabulary, a durable steering inbox, refuse-before-discard teardown, and a near-zero-token Stop-hook watch loop) while cutting everything scoped to that broader generality.

## Layout

- `bin/` - the lifecycle scripts, split into `bin/` (`chief-spawn`, `chief-watch`, `chief-teardown`, `chief-backlog`, `chief-setup`, `chief-agents`), `bin/task/` (`chief-control`, `chief-crew-state`, `chief-send`, `chief-promote`), and `bin/pr/` (`chief-pr-open`, `chief-pr-update`, `chief-pr-state`, `chief-pr-review`, `chief-pr-approve`, `chief-pr-merge`); and `bin/lib/` (`paths.sh`/`home.sh`/`meta.sh`/`lock.sh`/`brief.sh` helpers, `bin/lib/agents/` with the loader and selector `agent.sh` (a task's adapter from its meta; profile selection from `.chief/config/agents`) and the adapters `{claude,codex,copilot}.sh` - the agent's launch command, screen texts and folder pre-trust - `git-sync.sh` - best-effort freshening of a project's default-branch checkout against origin, used by spawn/pr-merge/teardown - `worktree.sh` - the guard that tells a spawned builder's own session apart from the operator-facing one - `bin/lib/backends/` with the loader `backend.sh` and its adapters `{herdr,orca,mock}.sh`, and `bin/lib/pr-providers/` with the loader `pr-provider.sh` and its adapters `{github,gitlab,azuredevops,mock}.sh`).
- `templates/` - a brief template (`brief-<role>.md`) and a per-task lifecycle checklist (`lifecycle-<role>.md`) per worker role (`builder`, `researcher`, `brainstormer`) rendered into `state/<id>.lifecycle` at spawn time, mirroring `skills/dispatch/SKILL.md`'s own steps so Chief can recover in-flight progress after a context compaction.
- `skills/using-chief` - the identity/job-description skill, force-injected every session via the `SessionStart` hook so Chief always knows its role without being asked.
- `skills/setup` - one-time CHIEF_HOME config (backend choice + gitignoring `.chief/`); only relevant before `.chief/config/backend` exists, which the `SessionStart` digest flags explicitly.
- `skills/dispatch` - the operator-facing entry point; load this to hand off work.
- `skills/reviewer` - a short fixed review checklist, run before merging.
- `hooks/` - `SessionStart` (injects `using-chief`, a configuration status line, and a backlog/in-flight digest) and `Stop` (the token-saving watch arm). Both stand down entirely inside a spawned builder's own worktree - see `worktree.sh`.

Runtime state lives at `.chief/` under `CHIEF_HOME` - by default the outermost git root enclosing wherever the Chief session runs, so the operator's top-level workspace even when run from inside a project or one of its worktrees; never inside a project (`state/`, `data/`, `config/`, `worktrees/`) - created on first use, not part of the plugin package. `chief-setup.sh` gitignores it for you.

Spawn syncs the project's default branch from origin (best-effort), then creates the task worktree and launches the worker in it (agent command from `agents/<agent>.sh`, brief as first prompt). With herdr, each task is its own linked-worktree workspace grouped under the project's primary workspace; with Orca, the project is registered on first spawn (`orca repo add`) and each task is an Orca-created worktree nested under the project's main worktree, running the agent in a terminal created with `terminal create --command` (Orca picks the path). Teardown closes the task's terminals and removes the worktree (and, on Orca, its worktree entry).

## Agents

Workers run on `claude` (default), `codex` or `copilot`, unattended, on herdr and Orca alike. **`codex` and `copilot` have no folder-trust handling:** if their CLI asks to trust a new worktree, the spawn stalls and fails as "not ready" (only `claude` is pre-trusted, see below). Which agent a task gets:

1. `chief-spawn.sh ... --agent <agent[:model]>` and/or `--model <model>` win. `--model` alone overrides only the model of the profile the config selects.
2. Else `.chief/config/agents`, if present:

   ```
   strategy = weighted          # first (default) | round-robin | random | weighted
   claude:opus   weight=3
   codex:gpt-5   weight=2
   copilot       args="--banner" weight=1                  # weight defaults to 1

   [builder]                    # optional pool (and strategy) for builders
   claude:opus args="--verbose"

   [researcher]                 # and for researchers; a missing section uses the global pool
   strategy = round-robin
   claude:haiku
   codex:gpt-5-mini

   [brainstormer]               # and for brainstormers, typically a strong agent
   claude:opus
   ```

   Sections are the worker roles: `[builder]`, `[researcher]`, `[brainstormer]`, plus `[reviewer]` (valid, but that worker is not spawnable yet); any other name is an error. `#` starts a comment. Per entry, `weight=`, `args=` and `command=` may come in any order. `first` takes the first entry; `round-robin` rotates (cursor in `state/agent-cursor-<role>`, updated under a lock so parallel spawns differ); `weighted` draws by `weight=`; `random` is `weighted` with equal weights.
3. Else `claude` with its default model.

The choice is recorded in the task's meta (`agent`, `model`, `args`, `command`) and reused by relaunch; `chief-crew-state.sh`, `chief-backlog.sh list|show` (in-flight) and the session digest show `[agent: <agent>[:<model>]]`. Spawn fails before creating anything for an unknown agent, a malformed profile or weight, a missing CLI, or a bad `command=` / `args=` / model combination below. Models are passed to the agent unvalidated.

A profile's `args="..."` (or `--args "..."` on spawn, which replaces the configured ones) adds CLI arguments after the adapter's own unattended and model flags, on herdr and Orca alike, e.g. `claude:opus args="--verbose --add-dir /x"`. `args=` and `command=` values are split on whitespace and may only use letters, digits, spaces and `. _ / @ : = + , -` (no quotes or shell characters), so both backends read them the same way. `weight=` is a whole number from 0 to 1000 (0 = never picked by `weighted`; a pool where every weight is 0 is an error).

`command="..."` instead replaces the whole launch line (a wrapper, another binary path), so it cannot be combined with a model or `args=` (put them in the command). Orca runs it as given. herdr starts the agent's own executable (`--kind`), so the command must start with it (`claude`, `/usr/local/bin/claude`) and only its arguments are used; for another executable use `args=` or the Orca backend. An explicit `--agent` drops the configured `args` and `command`.

A role with no section of its own runs the global pool, which may be an expensive agent: give `[builder]` its own section. `chief-agents.sh` prints the agent each role would get now (read-only; a weighted or random pool is listed, not picked) and marks a role that falls back with `(global fallback)`. Spawn prints the chosen `agent:` too.

`CHIEF_AGENT` and `.chief/config/agent` (the old single-agent selection) are gone; `.chief/config/agents` replaces them.

The launch line each worker runs is the adapter's `agent_command` in `bin/lib/agents/<name>.sh` (executable, unattended flag, `--model`, then `args=`), unless the task has a `command=`; spawn prints it as `launch: ...`. Adding an agent is one `bin/lib/agents/<name>.sh` implementing the contract in `agents/agent.sh`. Differences to know:

- Folder trust is pre-accepted for `claude` only (see below); for `codex` and `copilot` a trust prompt, if shown, stalls the spawn as "not ready".
- The worker brief is agent-neutral (status file, turn-ended file, review checklist by path), but `claude` workers also get this repo's plugins and skills from their own config; `codex` and `copilot` do not, so project conventions come from `AGENTS.md` and the brief alone.
- Approval/sandbox: `claude --dangerously-skip-permissions`, `codex --dangerously-bypass-approvals-and-sandbox`, `copilot --allow-all`.
- Claude workers inherit the `CLAUDE_CONFIG_DIR` note below.

## Handoff

`chief-spawn.sh <id> <project> --mode <role> --from <src> ...` starts a **successor** of a done researcher (or brainstormer) with a non-empty `data/<src>/report.md`: a fresh worktree on a synced default branch, a brief with the `from=` lineage (oldest first) and the source's report appended under `# Prior work`, `from=<src>` in meta. Targets are `builder`, `researcher` or `brainstormer`, never the source's own role; builders and reviewers are never sources. The successor gets the **target role's** configured agent, never the source's; `--agent` carries one over explicitly. The source is left untouched.

`--dry-run` validates everything and prints `agent:` and `launch:` (or the pool for a weighted/random strategy) without creating anything or advancing a cursor, so a go-ahead can name the exact agent. `chief-promote.sh <src> --to <role> --branch <name> --intent "..." [--as <new-id>] [--keep-source] [--dry-run] [spawn flags]` is a thin wrapper: the successor is `<src>-<role>` unless `--as` (file it in the backlog first), then the source is torn down unless `--keep-source`; its report survives under `data/`.

## Brainstormer

An explicit-only worker (`--mode brainstormer`): Chief spawns one only when the operator asks to brainstorm. It is the one worker that talks to the operator, directly in its own pane; Chief never relays the conversation. It narrows an idea into a one-page, self-contained spec in `data/<id>/report.md` (goal, scope, acceptance criteria, decisions with rationale and rejected options, open questions) and reports `done` only after the operator confirms it in the pane. Its brief is agent-neutral and depends on no skill. A done spec hands off like a researcher's report (builder or researcher), and a researcher can hand off to a brainstormer.

- **Attach hint.** A backend may define the optional `backend_attach_hint <id>` (see `backend.sh`). Spawn prints the result as `attach: ...` and stores it as `attach=`; `chief-crew-state.sh` and the session digest repeat it while the brainstormer runs. herdr: `herdr workspace focus <workspace>`, verified against a live herdr. Orca: the worktree and terminal to open, tested against the fake `orca` only (unverified live). mock: `tail -f` of its log.
- **Idle policy.** An idle brainstormer with a non-terminal last status reads `working · awaiting operator in pane` instead of `stale`, until `CHIEF_INTERACTIVE_STALE_AFTER_SECS` (default 14400 = 4h) passes without a turn; then it reads `stale`. `done`, `failed` and `blocked` surface immediately.

## Folder trust

Each backend pre-accepts the agent's folder-trust dialog before a worker starts, via `agent_prepare` (also on relaunch) in `bin/lib/agents/claude.sh`: it sets `hasTrustDialogAccepted` in `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json` for the task's exact worktree (claude does not inherit trust from a parent directory), under a lock, never touching `$HOME`. Teardown and spawn rollback call `agent_release`, which removes only flags Chief set. There is no screen-scrape fallback, so a skipped or failed pre-trust shows as a warning and the spawn fails as "not ready".

- Chief and the worker's claude must resolve the same `.claude.json`. Herdr panes inherit the herdr server's environment, so start both with the same `CLAUDE_CONFIG_DIR`.
- `CHIEF_NO_PRETRUST=1` opts out. Use it only if you trust folders another way; spawns will otherwise stall at the trust dialog.
- Orca picks its own worktree path, so it is trusted right after `orca worktree create`, before the agent starts.

## Status

Core lifecycle (backlog, spawn, send, control/relaunch, crew-state, watch, teardown, merge, handoff) is implemented and tested end-to-end against a mock backend. The **herdr adapter** (`bin/lib/backends/herdr.sh`) is verified against a live herdr 0.9.0 install - spawn/capture/busy/send/kill/relaunch all exercised end to end with a real `claude` turn in `tests/chief/test-backend-herdr.sh` (opt-in, `CHIEF_TEST_HERDR=1`). The **Orca adapter** (`bin/lib/backends/orca.sh`) follows the same flow - bypass-permissions launch, spawn rollback, relaunch, teardown - verified live in `tests/chief/test-backend-orca.sh` (opt-in, `CHIEF_TEST_ORCA=1`; adapter functions plus the real spawn/send/control/crew-state/teardown scripts) and against a fake `orca` CLI in `tests/chief/test-backend-orca-mock.sh`.

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
