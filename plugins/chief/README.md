# Chief

A lightweight supervisor for coding agents (Claude Code, Codex CLI, Copilot CLI): dispatches work to isolated builder/researcher/reviewer/brainstormer agents over the herdr, Orca or hc (herdr-core) backend, tracks a plain-markdown backlog, and supervises them with a near-zero-token watch loop. (Verbatim from `.claude-plugin/plugin.json`'s `description` - see "Maintaining these docs" below.)

Scoped down hard from bigger multi-agent supervisors on purpose: **Chief itself on Claude Code, Codex CLI or Copilot CLI** (see Harnesses), **herdr, Orca or hc (herdr-core) backend only** (configurable via `.chief/config/backend`, default `herdr`), one delivery mode (branch + you approve every merge - no auto-merge). Every script is meant to be short enough to read start to finish.

Inspired by [Firstmate](https://github.com/kunchenguid/firstmate), which does the same job across many more harnesses, backends, and delivery modes - Chief keeps its core ideas (isolated worktrees per task, an intent/spec brief split, a closed status vocabulary, a durable steering inbox, refuse-before-discard teardown, and a near-zero-token Stop-hook watch loop) while cutting everything scoped to that broader generality.

## Harnesses

Chief's own (operator-facing) session runs on any of three CLIs; they differ only in how identity is injected and how the idle session is woken. Workers are independent of this (see Agents).

| | Claude Code | Codex CLI | Copilot CLI |
|---|---|---|---|
| Identity | `SessionStart` hook, nested `hookSpecificOutput` | `hooks/hooks.codex.json` `SessionStart`, same output | `hooks/hooks.json` `SessionStart`, top-level `additionalContext` (the nested form is ignored) |
| Wake | `Stop` hook with `asyncRewake` (`stop-watch-claude.sh`) | async `Stop` hook, then `codex queue` (`stop-watch-codex.sh`) | extension calling `session.send` (`extensions/chief-watch/extension.mjs`) |
| Needs | nothing | Chief's hooks trusted in `/hooks`, again when an update changes them; a `codex` with `queue` | `experimental` on: launch with `--experimental` or `/settings experimental on` |
| Tested | 2.1.312 | codex-cli 0.162.1 | 1.0.107 |

`session-start.sh` tells them apart by `COPILOT_CLI`, else `PLUGIN_ROOT` (Codex or Copilot; Claude Code never sets it), else Claude Code. `stop-watch-claude.sh` exits when `PLUGIN_ROOT` is set, since Copilot also loads `hooks.json`. `stop-watch-codex.sh` queues only while a Codex TUI runs in the session's cwd (Linux `/proc`; elsewhere it always queues). `chief-setup.sh` warns about a `codex` without `queue` and about Copilot with `experimental` off.

## Layout

- `bin/` - the lifecycle scripts, split into `bin/` (`chief-spawn`, `chief-watch`, `chief-teardown`, `chief-backlog`, `chief-setup`, `chief-agents`), `bin/task/` (`chief-control`, `chief-crew-state`, `chief-send`, `chief-promote`, `chief-review`); and `bin/lib/` (`paths.sh`/`home.sh`/`meta.sh`/`lock.sh`/`brief.sh`/`meta-extensions.sh` helpers, `bin/lib/agents/` with the loader and selector `agent.sh` (a task's adapter from its meta; profile selection from `.chief/config/agents`) and the adapters `{claude,codex,copilot}.sh` - the agent's launch command, screen texts and folder pre-trust - `git-sync.sh` - best-effort freshening of a project's default-branch checkout against origin, used by spawn/teardown - `worktree.sh` - the guard that tells a spawned builder's own session apart from the operator-facing one - `bin/lib/backends/` with the loader `backend.sh` and its adapters `{herdr,orca,hc}.sh` and the screen helpers `screen.sh` they share).
- `templates/` - a brief template (`brief-<role>.md`) and a per-task lifecycle checklist (`lifecycle-<role>.md`) per worker role (`builder`, `researcher`, `reviewer`, `brainstormer`) rendered into `tasks/<id>/lifecycle` at spawn time, mirroring `skills/dispatch/SKILL.md`'s own steps so Chief can recover in-flight progress after a context compaction.
- `skills/using-chief` - the identity/job-description skill, force-injected every session via the `SessionStart` hook so Chief always knows its role without being asked.
- `skills/setup` - one-time CHIEF_HOME config (backend choice + gitignoring `.chief/`); only relevant before `.chief/config/backend` exists, which the `SessionStart` digest flags explicitly.
- `skills/dispatch` - the operator-facing entry point; load this to hand off work.
- `hooks/` - `SessionStart` (injects `using-chief`, a configuration status line and a backlog/in-flight digest) and `Stop` (the token-saving watch arm): `hooks.json` for Claude Code and Copilot, `hooks.codex.json` for Codex (named by `.codex-plugin/plugin.json`). `chief-watch.sh` wakes you once per state change (the delivered line is the task's `notify-baseline`; a stale alert's idle counter and the trailing metadata tags don't count as a change); one watcher runs per `CHIEF_HOME`, the newest takes over via `state/watch.owner`. `watch-reason.sh` is its shared entry behind each wake adapter, and all of them stand down in a spawned builder's own worktree (`worktree.sh`).
- `extensions/chief-watch/` - Copilot's wake adapter.

Runtime state lives at `.chief/` under `CHIEF_HOME` - by default the outermost git root enclosing wherever the Chief session runs, so the operator's top-level workspace even when run from inside a project or one of its worktrees; never inside a project - created on first use, not part of the plugin package. `chief-setup.sh` gitignores it for you. Layout (see `bin/lib/paths.sh`): `tasks/<id>/` is one folder per task (`meta`, `status`, `inbox/`, `lifecycle`, `turn-ended`, `brief.md`, `report.md`, `evidence/`); teardown moves it to `archive/<id>/`. `state/` holds only global machine state (locks, agent cursors, trust-owned, the watcher heartbeat and `watch.owner`). `backlog.md`, `config/` and `worktrees/<id>` complete it.

Spawn syncs the project's default branch from origin (best-effort), then creates the task worktree and launches the worker in it (agent command from `agents/<agent>.sh`, brief as first prompt). A spawn or relaunch succeeds (`spawned:` / `relaunched:`) only once the worker's first turn was observed started; otherwise it fails non-zero and rolls back. With hc, the task worktree is made with `git worktree add` and the agent runs in one hc terminal named and labelled `chief.task=<id>` (found by that label, never by the endpoint's address; `herdr.space`/`herdr.tab` labels make the Herdr app show it as a space of its own); the first `hc` call starts the core if none runs, and its terminals inherit that core's environment, so start it (`hc server start`) from a clean login shell, not from a Chief session. With herdr, each task is its own linked-worktree workspace grouped under the project's primary workspace; with Orca, the project is registered on first spawn (`orca repo add`) and each task is an Orca-created worktree nested under the project's main worktree, running the agent in a terminal created with `terminal create --command` (Orca picks the path). Teardown closes the task's terminals and removes the worktree (and, on Orca, its worktree entry). On herdr, the last teardown of a project also closes its primary workspace, but only if herdr created it for one of Chief's spawns (marked in herdr) and it is still one idle shell pane; a workspace you opened, worked in, or that predates this behaviour is left open.

## Naming

Task ids read `<role>-<topic>`, at most 20 chars (`build-rate-limit`, `res-auth-flow`; prefixes `build-`, `res-`, `spec-`, `rev-`); a reviewer is `<builder-id>-rv` and a successor replaces the source's prefix. The one id is the backlog id, task folder, worktree, herdr workspace label and agent name, Orca worktree name and hc terminal name and label. It must match `^[a-z][a-z0-9-]*$`, be at most 32 chars (herdr's agent-name and hc's terminal-name limit) and not look like an hc address (`t7`, `t1b`); `chief-backlog.sh add` and `chief-spawn.sh` reject others and print a valid suggestion. `chief-backlog.sh show <id>` prints a task's workspace, branch, worktree, brief and report paths.

## Agents

Workers run on `claude` (default), `codex` or `copilot`, on every backend; all but the brainstormer run unattended. **`codex` and `copilot` have no folder-trust handling:** if their CLI asks to trust a new worktree, the spawn stalls and fails as "not ready" (only `claude` is pre-trusted, see below). Which agent a task gets:

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

   [reviewer]                   # and for reviewers
   strategy = all               # chief-review.sh runs one reviewer per entry
   mode = sequential            # reviewer only: parallel (default) | sequential | first | ask
   copilot
   claude:sonnet

   [brainstormer]               # and for brainstormers
   claude:opus
   ```

   Sections are the worker roles: `[builder]`, `[researcher]`, `[reviewer]`, `[brainstormer]`; any other name is an error. `#` starts a comment. Per entry, `weight=`, `args=` and `command=` may come in any order. `first` takes the first entry; `round-robin` rotates (cursor in `state/agent-cursor-<role>`, updated under a lock so parallel spawns differ); `weighted` draws by `weight=`; `random` is `weighted` with equal weights. `all` and `mode` are for `[reviewer]`: see the review loop.
3. Else `claude` with its default model.

The choice is recorded in the task's meta (`agent`, `model`, `args`, `command`) and reused by relaunch; `chief-crew-state.sh`, `chief-backlog.sh list|show` (in-flight) and the session digest show `[agent: <agent>[:<model>]]`. Spawn fails before creating anything for an unknown agent, a malformed profile or weight, a missing CLI, or a bad `command=` / `args=` / model combination below. Models are passed to the agent unvalidated.

A profile's `args="..."` (or `--args "..."` on spawn, which replaces the configured ones) adds CLI arguments after the adapter's own unattended and model flags, on every backend, e.g. `claude:opus args="--verbose --add-dir /x"`. `args=` and `command=` values are split on whitespace and may only use letters, digits, spaces and `. _ / @ : = + , -` (no quotes or shell characters), so every backend reads them the same way. `weight=` is a whole number from 0 to 1000 (0 = never picked by `weighted`; a pool where every weight is 0 is an error).

`command="..."` instead replaces the whole launch line (a wrapper, another binary path), so it cannot be combined with a model or `args=` (put them in the command). Orca and hc run it as given. herdr starts the agent's own executable (`--kind`), so the command must start with it (`claude`, `/usr/local/bin/claude`) and only its arguments are used; for another executable use `args=`, or the Orca or hc backend. An explicit `--agent` drops the configured `args` and `command`.

A role with no section of its own runs the global pool. `chief-agents.sh` prints the agent each role would get now (read-only; a weighted or random pool is listed, not picked) and marks a role that falls back with `(global fallback)`. Spawn prints the chosen `agent:` too.

The launch line each worker runs is the adapter's `agent_command` in `bin/lib/agents/<name>.sh` (executable, unattended flag, `--model`, then `args=`), unless the task has a `command=`; spawn prints it as `launch: ...`. Adding an agent is one `bin/lib/agents/<name>.sh` implementing the contract in `agents/agent.sh`. Differences to know:

- Folder trust is pre-accepted for `claude` only (see below); for `codex` and `copilot` a trust prompt, if shown, stalls the spawn as "not ready".
- The worker brief is agent-neutral (status file and turn-ended file by path), but `claude` workers also get this repo's plugins and skills from their own config; `codex` and `copilot` do not, so project conventions come from `AGENTS.md` and the brief alone.
- Approval/sandbox: `claude --dangerously-skip-permissions`, `codex --dangerously-bypass-approvals-and-sandbox`, `copilot --allow-all`.
- Claude workers inherit the `CLAUDE_CONFIG_DIR` note below.

`.chief/config/definition-of-done` (optional) lists items the workers must meet, as markdown bullets:

- Items before any header, or under `[all]`, go to every role; `[builder]`, `[researcher]`, `[reviewer]` and `[brainstormer]` sections go to that role only. An unknown section warns and is ignored.
- Projects add their own as a `## Definition of done` section in `AGENTS.md`/`CLAUDE.md`, with optional `### <Role>` and `### All` subheadings (items outside any subheading go to every role). The workers read it; Chief does not parse it.
- The role's items are appended to the `# Definition of done` section at the end of its brief. Workers record one evidence line per item in their report (the reviewer under `Notes`); the reviewer also verifies the builder's.
- Keep it to a handful of checkable items; backtick a command for a mechanical item.

## Handoff

`chief-spawn.sh <id> <project> --mode <role> --from <src> ...` starts a **successor** of a done researcher (or brainstormer) with a non-empty `tasks/<src>/report.md`: a fresh worktree on a synced default branch, a brief with the `from=` lineage (oldest first) and the source's report appended under `# Prior work`, `from=<src>` in meta. Targets are `builder`, `researcher` or `brainstormer`, never the source's own role; builders and reviewers are never sources. The successor gets the **target role's** configured agent, never the source's; `--agent` carries one over explicitly. The source is left untouched.

`--dry-run` validates everything and prints `agent:` and `launch:` (or the pool for a weighted/random strategy) without creating anything or advancing a cursor, so a go-ahead can name the exact agent. `chief-promote.sh <src> --to <role> --branch <name> --intent "..." [--as <new-id>] [--keep-source] [--dry-run] [spawn flags]` is a thin wrapper: the successor's id is the source's with its role prefix replaced (`res-auth-flow` -> `build-auth-flow`) unless `--as` (file it in the backlog first; `--dry-run` prints `id:`), then the source is torn down unless `--keep-source`; its folder, with the report, survives under `archive/`.

## Review

The operator decides, per builder, whether it is reviewed; Chief asks after every builder `done` and never starts a review itself (unless told "review everything this session"). `chief-review.sh <builder> [--mode parallel|sequential|first] [--only <n>[,<n>...]]` needs the builder's last status `done`, a clean worktree and a commit ahead of the default branch.

- **Round 1** files backlog item `<builder>-rv` and spawns a reviewer (`--mode reviewer`, branch `chore/<builder>-rv`, the `[reviewer]` pool). Its spec pins the builder's HEAD SHA, names the branch and base, points at the builder's brief and `done` line. Meta links: `for=<builder>` on the reviewer, `reviewer=` and `review_round=` on the builder.
- **Several reviewers:** under `strategy = all`, round 1 spawns `<builder>-rv-1`, `-2`... (one per pool entry, in file order; all or none) and later rounds re-arm each live one. The watcher wakes Chief only when no sibling is still working; a failed, stale or torn-down one never holds the others.
- **Run modes:** `mode` in `[reviewer]` (default `parallel`), or `--mode` for one review, picks which pool entries a review arms. `parallel`: as above (the whole pool under `strategy = all`, else the strategy's single pick, `<builder>-rv`). `first`: entry 1 only. `sequential`: one entry per run, starting at entry 1; the script prints the next command and Chief runs it only on PASS, so the first non-PASS stops the review and a new commit starts again at entry 1. `ask`: Chief asks the operator for the mode and entries at every review and passes `--mode`/`--only`; the script itself refuses it.
  - `--only 2,3` arms those entries (numbers in file order) instead, under any mode but `first`; `sequential` takes one.
  - A reviewer records its pool entry (`pick=`, 0: the strategy chose) and `armed=<round>@<sha>`. A run re-arms the entry's live reviewer, spawns one for an entry with none, and skips a torn-down one. Ids are numbered, so entries on one model but different agents stay distinct.
  - Nothing waits or gates: a run starts reviewers and returns, so an interrupted run leaves its started reviewers linked, and every finished reviewer still wakes Chief.
- **Later rounds** re-arm the same reviewer: its `report.md` is archived as `report.round-<R>.md` for the round R it last ran, the round message goes to its inbox, the backlog item returns to in-flight, and `working: round N requested` is appended to its status. A new commit, or a re-run of an entry that already reviewed the commit, is a new round; the next entry of a sequential run is not. The same commit is refused while the reviewer is working.
- **The reviewer** resets its scratch worktree, detaches at the pinned SHA and reviews the full `base...sha` diff every round against the 9-item checklist in its brief, then verifies earlier findings. It writes `report.md` (`Verdict`, `Target`, `Blocking`, `Suggestions`, `Checklist`, `Prior findings`) and ends with `done: round N PASS @<sha7>` or `done: round N FAIL (<n> blocking) @<sha7>`; `failed` means the review could not be completed. It never posts, pushes or merges. A builder's `done` line starts with its short commit SHA, so every re-report is a new line to the watcher.
- **Chief** presents the verdict, holds the reviewer, and on the operator's yes sends the findings to the builder; the builder fixes them with new commits and reports `done` again. Findings go to a PR only when the operator asks.
- **Teardown** (including `--abandon`) removes only the local branch and worktree, never the remote branch. A builder's teardown also discards its reviewer once the builder's own teardown succeeds; a refused builder leaves it alone. A reviewer can be torn down alone; that ends review of that builder, and a manual `--mode reviewer` spawn is the way to review it again. `chief-crew-state.sh` and the session digest show `[for: <builder>]` / `[reviewer: <id>]`.

A reviewer on any branch, with no builder: `chief-spawn.sh <id> <project> --mode reviewer --branch chore/<name> --intent "..." --spec "<branch, pinned SHA, base, intent>"`.

## Brainstormer

An explicit-only worker (`--mode brainstormer`), spawned only when the operator asks to brainstorm. It talks to the operator directly in its own pane; Chief never relays the conversation. It writes a one-page, self-contained spec to `tasks/<id>/report.md` (goal, scope, acceptance criteria, decisions with rationale and rejected options, open questions) and reports `done` only after the operator confirms it there. Its brief is agent-neutral and depends on no skill. A done spec hands off like a researcher's report, and a researcher can hand off to a brainstormer.

- **Attach hint.** A backend may define the optional `backend_attach_hint <id>` (see `backend.sh`). Spawn and `chief-control.sh relaunch` print it as `attach: ...` and store `attach=`; `chief-crew-state.sh` and the session digest repeat it while the brainstormer runs. herdr: `herdr workspace focus <workspace>` (verified live). Orca: the worktree and terminal to open (the hint text is tested, opening it needs the Orca UI). hc: `hc attach <id>` (tested only as text; it needs a TTY).
- **Idle.** An idle brainstormer with a non-terminal last status reads `working · awaiting operator in pane`, never `stale`. `done`, `failed`, `blocked` and `needs-decision` surface immediately.

## Folder trust

Each backend pre-accepts the agent's folder-trust dialog before a worker starts, via `agent_prepare` (also on relaunch) in `bin/lib/agents/claude.sh`: it sets `hasTrustDialogAccepted` in `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json` for the task's exact worktree (claude does not inherit trust from a parent directory), under a lock, never touching `$HOME`. Teardown and spawn rollback call `agent_release`, which removes only flags Chief set. Pre-trust is lossy: a concurrently starting claude can rewrite `.claude.json` and drop the entry. The herdr and hc backends therefore read the screen after starting the agent and, if the dialog for the worktree Chief just created is showing, accepts it once (`agent_trust_keys`); a dialog for any other folder, or for an agent without trust keys, fails the spawn as "not ready" with the last screen lines. Orca has no such fallback.

- Chief and the worker's claude should resolve the same `.claude.json` (herdr panes and hc terminals inherit the server's or core's environment, so start both with the same `CLAUDE_CONFIG_DIR`); on herdr and hc a mismatch costs the pre-trust fast path, not the spawn.
- `CHIEF_NO_PRETRUST=1` opts out. Use it only if you trust folders another way; on Orca spawns will otherwise stall at the trust dialog.
- Orca picks its own worktree path, so it is trusted right after `orca worktree create`, before the agent starts.

## Gating finishing actions

Chief runs the finishing actions itself with the host CLI (`gh`, `az`, `glab`) after the operator's go-ahead; no script wraps them. To make the harness stop before each one, add `ask` rules to your own `settings.json` (a plugin cannot ship them):

```json
{ "permissions": { "ask": [
  "Bash(gh pr create *)", "Bash(gh pr merge *)", "Bash(gh pr review *)",
  "Bash(az repos pr create *)", "Bash(az repos pr update *)",
  "Bash(glab mr create *)", "Bash(glab mr merge *)", "Bash(git push *)" ] } }
```

Best-effort only: forms like `git -C . push` or `sh -c '...'` do not match. GitHub branch protection (required reviews and checks) is the server-side backstop.

## Status

Core lifecycle (backlog, spawn, send, control/relaunch, crew-state, watch, teardown, handoff) is implemented and tested end-to-end on a real herdr (`tests/chief/{unit,workflow,backends,harness}/*.bats`, with a zero-cost stand-in agent; `unit/hook-harness.bats` covers the Codex and Copilot adapters with fake CLIs; `tests/chief/live/` holds the opt-in tests with real CLIs and tokens, including Chief itself on Claude Code, Codex and Copilot). The **Orca adapter** (`bin/lib/backends/orca.sh`) follows the same flow - bypass-permissions launch, spawn rollback, relaunch, teardown - and is tested on a real headless Orca in `tests/chief/backends/orca.bats`. The **hc adapter** (`bin/lib/backends/hc.sh`, hc 0.1.20) is tested on a real core in `tests/chief/backends/hc.bats`; its app-side behaviour (the Herdr app adopting the labelled terminals) and a real `claude` are not yet checked. The **copilot adapter**'s screen needles and a real researcher spawn are checked against the real Copilot CLI in `tests/chief/live/copilot-spawn.bats`.

## Maintaining these docs

One owner per fact - don't restate one doc's content in another:

- Public pitch and current status -> this file (`README.md`) only.
- Agent operating contract and hard rules -> `skills/using-chief/SKILL.md`
  only; never restated here.
- Step-by-step process for one workflow -> that step's own `SKILL.md`
  (`skills/dispatch`, `skills/setup`).
- Stable architecture and extension points (backend adapters) -> a future `plugins/chief/ARCHITECTURE.md`, created once the
  "Layout" section above actually needs to split out, not pre-emptively.

This plugin's one-line pitch lives in `.claude-plugin/plugin.json`'s
`description`; this file's opening line quotes it verbatim rather than
paraphrasing it, so there's exactly one wording to keep current.
