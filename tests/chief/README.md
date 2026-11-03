# Chief plugin tests

Functional/integration tests of Chief's own bash scripts. The `*.bats` files
run against a real herdr with a zero-cost stand-in agent (see "Real herdr with
a stand-in agent" below); the remaining legacy `*.sh` files are being converted
and mostly run against the `mock` backend (`plugins/chief/bin/lib/backends/mock.sh`, a
throwaway background process standing in for a real terminal session) - no
`claude` CLI, zero tokens, safe anywhere. `test-backend-orca-mock.sh` is
also zero-cost: it unit-tests `backends/orca.sh` against a fake `orca`
CLI stub, and `test-backend-herdr-mock.sh` does the same for
`backends/herdr.sh` against a fake `herdr` fed screens captured from a live
herdr and Claude Code (`fixtures/herdr/`), so herdr's rendering quirks - the
trust dialog, the `[Pasted text #N +M lines]` placeholder, the bare shell line
before the TUI renders - are real, not hand-written. `test-backend-herdr.sh`,
`test-backend-orca.sh`, `test-backend-copilot.sh` and
`test-backend-copilot-brief.sh` are the exceptions: each
opts into a real herdr/orca install and a real agent turn - see below.

## Real herdr with a stand-in agent (`*.bats`)

Converted tests run against a real, headless `herdr server` - one per test, with
its own `HOME`/`XDG_*` and socket, stopped in `teardown` (`lib/common.bash`).
The agent in its panes is `fixtures/standin/claude`, a Claude-Code-shaped TUI
that costs no tokens; the server's `PATH` holds only the stand-ins, and
`chief_zero_cost_guard` aborts if a real `claude`/`codex`/`copilot` could be
found. Panes inherit the server's environment, not the test's: configure the
stand-in through files under `$STANDIN_DIR` (`standin_mode`, `standin_hold`),
never exported variables. Use `eventually` for anything asynchronous, never a
bare `sleep`. Never source `lib/harness.sh` in a `.bats` file.

`tests/chief/ci/install-herdr.sh` installs the pinned herdr into
`tests/.cache/bin`, which the suite prefers over the herdr on `PATH`.

## Cleanup

Tests that use the mock backend set their cleanup with `harness_trap` (`lib/harness.sh`): on EXIT/INT/TERM/HUP it kills the `chief-mock-*` workers the test started (found via the pid log `mock.sh` appends to, never by name), then runs the test's own cleanup. `mock.sh` also logs each worker pid to `run-tests.sh`'s run-wide `CHIEF_MOCK_RUN_LOG` at spawn time; the runner fails if any logged worker is still alive after the sweep. Workers from other runs are never in that log, so they are ignored.

## Running

```bash
./tests/chief/run-tests.sh          # everything
bash tests/chief/test-lifecycle.sh  # a single legacy .sh file
```

`*.bats` files run on [bats-core](https://github.com/bats-core/bats-core) pinned
in `tests/package.json` (bats 1.14.0, bats-assert, bats-support, bats-file;
`run-tests.sh` runs `npm ci` on first use, so Node and npm are needed). Options:
`run-tests.sh [--jobs N] [--junit DIR] [bats args...]`. `--jobs` needs GNU
`parallel` (required locally; without it the run is serial and slow); `--junit`
writes `DIR/report.xml`. Tests tagged `manual` are skipped. A single bats file:

```bash
BATS_LIB_PATH=$PWD/tests/node_modules tests/node_modules/.bin/bats tests/chief/test-lock.bats
```

Requires `git` and `bash`; `python3` is used where available to validate
JSON output (skipped gracefully if absent).

## What's covered

| File | Covers |
|---|---|
| `test-static.bats` | Every script parses (`bash -n`), every JSON file is valid, executable bits are correct |
| `test-meta.bats` | `meta.sh` key=value read/write helpers, and the task folder resolver and archive |
| `test-lock.bats` | `lock.sh` mutex: acquire/release/timeout/stale-lock reclaim |
| `test-backlog.sh` | `chief-backlog.sh`: add/status/note/hold/done/list/next/show, error cases, and that `status <id> in-flight` restores a held/spawned task's meta status back to `working` |
| `test-git-sync.bats` | `git-sync.sh`'s `chief_sync_default_branch`: fast-forwards the default branch from origin only when checked out on it with a clean tree, otherwise skips - and never fails its caller, including with no origin remote or a diverged history |
| `test-worktree-guard.bats` | `chief_is_linked_worktree` - main checkout vs. a linked worktree vs. a non-git dir |
| `test-crew-state.sh` | `chief-crew-state.sh`'s state classification across all six states, plus a brainstormer's awaiting-operator idle rule (never stale) and attach hint |
| `test-naming.sh` | Where-lines (`backlog show`) and herdr's workspace label and its cleanup (fake `herdr`) |
| `test-send.bats` | `chief-send.sh` on a real herdr: durable inbox numbering, handled-file awareness, key sends, the doorbell line |
| `test-watch.bats` | `chief-watch.sh` on a real herdr: notify-once per state change (done, resumed, brainstormer, stale, agent and reviewer tags), one watcher per home, and `chief_notify_line` |
| `test-zero-cost.bats` | The zero-cost guard refuses a server PATH holding a real agent CLI |
| `test-standin.bats` | The stand-in agent's modes (`hold`, `exit`, `never-ready`, kill) on a real herdr |
| `test-control.sh` | `chief-control.sh`: interrupt (agent keeps running), exit, relaunch with checkpoint note |
| `test-setup.bats` | `chief-setup.sh`: backend config, idempotent gitignore, no-git-repo case |
| `test-hooks.sh` | `session-start.sh` and `stop-watch-arm.sh`'s own bash logic across fresh/configured/in-flight/builder-worktree scenarios |
| `test-lifecycle.sh` | The full happy path: backlog → spawn → simulated work → crew-state → teardown-refuses-before-merge → merge → teardown-succeeds |
| `test-spawn-cleanup.sh` | `chief-spawn.sh`'s required `--branch` (nothing left behind when missing), rollback on a failed/malformed `backend_spawn` (`backend_spawn_cleanup`, no orphaned worktree/branch/meta) an interrupted spawn's `status=spawning` stub (crew-state, watch, teardown), and the atomic spawn lock, against the mock backend's `CHIEF_MOCK_SPAWN_FAIL`/`CHIEF_MOCK_SPAWN_MALFORMED` injectors |
| `test-project-workspace.sh` | The spawn/teardown flow on the mock backend: origin sync before the worktree exists, and no `.chief` ever created inside a project (default `CHIEF_HOME` from a project or its worktree) |
| `test-agent.bats` / `test-agent-claude.bats` / `test-agent-adapters.bats` | The agent loader (per-task adapter from meta, command override, unknown agent), the claude adapter (contract, pre-trust in `.claude.json`), and the codex/copilot adapters (flags, model flag, CLI check, herdr's start args) |
| `test-agent-select.bats` | `.chief/config/agents`: every strategy (round-robin persistence and parallel safety, weighted with an injected random), per-role pools, `peek`, comments, malformed config |
| `test-agents.bats` | `chief-agents.sh`: the effective agent per role, the `(global fallback)` marker, read-only |
| `test-handoff.sh` | `chief-spawn.sh --from` / `--dry-run` and `chief-promote.sh`: every role pair and rejection, the target role's agent (not the source's), `--agent` carry-over, lineage brief and framing, `from=`, source untouched, `--dry-run` without side effects |
| `test-brainstormer.sh` | The brainstormer brief (explicit confirmation before `done`, out-of-scope list, no skill dependency, spec skeleton) and lifecycle, and `chief-spawn.sh` printing and recording `attach=` for it only |
| `test-review.sh` | `chief-review.sh` (round 1 links and pinned SHA, round 2 archive/send/`working:` line/in-flight, every gate, stale or missing SHA, same-SHA refusal), the teardown cascade (done, refused, hand-removed worktree, reviewer alone), the builder/reviewer link in crew-state and the digest, watch (differing reviewer `done` wakes, identical suppressed), and the reviewer brief and builder lifecycle content |
| `test-leak-check.sh` | `run-tests.sh`'s mock-worker leak check: only workers logged in this run's `CHIEF_MOCK_RUN_LOG` are reported (alive or not), foreign `chief-mock-*` processes are ignored, and the runner fails on a leak |
| `test-backend-herdr-mock.sh` | `backends/herdr.sh` against a fake `herdr` CLI and live-captured screen fixtures: screen-based start readiness (shell-only, late TUI, `agent start` rc ignored), the folder-trust dialog (accepted once for Chief's own worktree, never for another folder or an agent without trust keys), `blocked` is not a started turn, stall recovery (Enter only over a landed placeholder or raw text, wait for a queued or already-submitted brief, one resend only when the box is empty, the TUI rendered and the screen is unchanged since the send, never over a shell-only screen or an agent that echoed the brief inline), and `chief-spawn.sh` / `backend_relaunch` failing non-zero with rollback and no `spawned:` unless a turn started. Zero cost. |
| `test-backend-herdr.sh` | `backends/herdr.sh` against a REAL herdr install and a real (trivial) claude turn: spawn, pane read, busy, send, kill, relaunch, and the live-input-line check against real pane rendering (a placeholder-hint box and text genuinely in flight). **Not zero-cost** - opt in with `CHIEF_TEST_HERDR=1`; skips cleanly otherwise. See below. |
| `test-backend-copilot.sh` | The copilot adapter against the REAL Copilot CLI, on its own isolated herdr server: ready text vs. the real idle footer, the folder-trust dialog and banner screens, the paste placeholder and input marker, then a real `chief-spawn.sh --agent copilot --mode researcher` on a throwaway repo through a status line, a report and teardown. **Not zero-cost** - opt in with `CHIEF_TEST_COPILOT=1`; skips cleanly otherwise. See below. |
| `test-backend-copilot-brief.sh` | Issue #90 against the REAL Copilot CLI (same isolation as `test-backend-copilot.sh`): real `chief-spawn.sh --agent copilot` spawns with a brief-sized prompt must send one `herdr agent prompt` and produce one `user.message` in Copilot's `events.jsonl`; fails if no attempt hit herdr's `agent_prompt_stalled`. **Not zero-cost** - opt in with `CHIEF_TEST_COPILOT_BRIEF=1`; skips cleanly otherwise. See below. |
| `test-backend-orca-mock.sh` | `backends/orca.sh`'s argument-building and JSON-parsing against a fake `orca` CLI stub: spawn via `worktree create` + `terminal create --command` + `terminal send` (repo registration, parent-worktree nesting, pre-trust, ready-screen check, rollback on every failure), `backend_spawn_cleanup` rollback, pane read, busy, send, kill, `backend_teardown`, relaunch, and the real `chief-spawn`/`send`/`control`/`teardown` scripts end to end on the orca backend (herdr-parity flow). Zero cost. |
| `test-backend-orca.sh` | `backends/orca.sh` against a REAL live Orca instance and real (trivial) claude turns, on a scratch repo: spawn (incl. repo registration and parent-worktree nesting), pane read, busy, send, kill, relaunch, `backend_teardown`, `backend_spawn_cleanup`, then the real `chief-spawn`/`send`/`control` (interrupt, relaunch)/`crew-state`/`teardown` scripts end to end. **Not zero-cost** - opt in with `CHIEF_TEST_ORCA=1`; skips cleanly otherwise. See below. |

## The herdr, orca and copilot backend tests are different from the rest

`test-backend-herdr.sh` and `test-backend-orca.sh` aren't free: each needs
its real backend reachable (`herdr` + a headless `herdr server`, or `orca`
talking to a live Orca runtime) plus `claude` on PATH, and spends a small
number of real tokens per claude turn it starts. Both skip by default
(even under `run-tests.sh`) unless you opt in:

```bash
CHIEF_TEST_HERDR=1 bash tests/chief/test-backend-herdr.sh
CHIEF_TEST_ORCA=1  bash tests/chief/test-backend-orca.sh
```

`backends/herdr.sh` is verified against a live herdr 0.9.1 install -
see its header for the real CLI shape and two confirmed quirks: Claude
Code's first-run "trust this folder?" dialog, and `herdr agent prompt
--wait` reporting `agent_prompt_stalled` for distinct situations (text
delivered but Enter didn't register, text never delivered, TUI not yet
rendered) that `_chief_herdr_recover` tells apart from the screen.

`backends/orca.sh` runs on a throwaway scratch repo like herdr's: `backend_spawn`
registers it with Orca (`orca repo add`) and tasks nest under its main
worktree. Spawn, relaunch, teardown, spawn rollback and the real lifecycle scripts are all exercised live.
The test snapshots Orca before the run (repos, every repo's worktrees,
terminals, projects, project setups, `~/orca/workspaces`) and asserts the same
snapshot afterwards, plus no mention of the scratch repo in `orca-data.json`
and no `/tmp/orca-claude-statusline-last-*` file left for its panes. Cleanup
runs on EXIT/INT/TERM/HUP, is idempotent, and touches only the scratch repo it
registered itself (via `orca worktree rm` / `orca project setup-delete`; never
by editing `orca-data.json`) and the claude transcript/session dirs of its own
worktrees.

### The copilot test

```bash
CHIEF_TEST_COPILOT=1 bash tests/chief/test-backend-copilot.sh
```

Needs `herdr`, `copilot`, `jq`, `ss` and a copilot login in `~/.copilot/config.json`
(or `$COPILOT_HOME`); skips cleanly without any of them. **Cost: one research
turn per run** (the spawned worker's brief); everything else, including the
paste check, is free local screen reading. It fails without retrying on a rate
or quota message.

It never touches your herdr: it runs in a scrubbed environment (no `HERDR_*`),
with its own `HOME`/`XDG_*` in a temp dir and its own herdr server and socket,
and aborts before any herdr call or copilot run unless it proves the socket
differs from the default and the caller's, its server pid differs from the
default server's, and its workspace list is empty.
`CHIEF_TEST_COPILOT_GUARD_ONLY=1` runs that guard alone. Only the login is
copied into the temp `HOME` (plus trust for the throwaway repo); it is deleted
on EXIT/INT/TERM/HUP along with the temp dir, and only the test's own server is
stopped. Copilot has no folder-trust handling, so the spawn repo is pre-trusted
in the temp config; an untrusted folder stalls at copilot's trust dialog.

### The copilot brief test

```bash
CHIEF_TEST_COPILOT_BRIEF=1 bash tests/chief/test-backend-copilot-brief.sh
```

Same prerequisites and isolation as the copilot test (shared in
`lib/copilot-isolation.sh`). **Cost: one research turn per attempt**, with
`CHIEF_TEST_COPILOT_BRIEF_ATTEMPTS` attempts (default 3). The bug needs herdr to
report `agent_prompt_stalled` although copilot took the brief, which happens on
some runs only, so the test fails when no attempt stalled instead of passing
without having exercised the recovery.

## What's deliberately NOT here (needs the devcontainer instead)

- **Skill-behavior tests** (does Claude actually follow `using-chief`/`dispatch`/`setup` correctly when loaded) - that's `tests/claude-code/test-using-chief.sh`, `test-dispatch.sh`, and `test-chief-setup.sh`, which invoke the real `claude` CLI and cost real tokens.
