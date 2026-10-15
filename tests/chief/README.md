# Chief plugin tests

Functional/integration tests of Chief's own bash scripts. Most files run
against the `mock` backend (`plugins/chief/bin/lib/backends/mock.sh`, a
throwaway background process standing in for a real terminal session) - no
`claude` CLI, zero tokens, safe anywhere. `test-backend-orca-mock.sh` is
also zero-cost: it unit-tests `backends/orca.sh` against a fake `orca`
CLI stub, and `test-backend-herdr-mock.sh` does the same for
`backends/herdr.sh` against a fake `herdr` fed screens captured from a live
herdr and Claude Code (`fixtures/herdr/`), so herdr's rendering quirks - the
trust dialog, the `[Pasted text #N +M lines]` placeholder, the bare shell line
before the TUI renders - are real, not hand-written. `test-backend-herdr.sh`
and `test-backend-orca.sh` are the two exceptions: each opts into a real
herdr/orca install and a real claude turn - see below.

## Cleanup

Tests that use the mock backend set their cleanup with `harness_trap` (`lib/harness.sh`): on EXIT/INT/TERM/HUP it kills the `chief-mock-*` workers the test started (found via the pid log `mock.sh` appends to, never by name), then runs the test's own cleanup. `run-tests.sh` counts `chief-mock-*` processes before and after the sweep and fails if any are new.

## Running

```bash
./tests/chief/run-tests.sh          # everything
bash tests/chief/test-lifecycle.sh  # a single file
```

Requires `git` and `bash`; `python3` is used where available to validate
JSON output (skipped gracefully if absent).

## What's covered

| File | Covers |
|---|---|
| `test-static.sh` | Every script parses (`bash -n`), every JSON file is valid, executable bits are correct |
| `test-meta.sh` | `meta.sh` key=value read/write helpers, and the task folder resolver and archive |
| `test-lock.sh` | `lock.sh` mutex: acquire/release/timeout/stale-lock reclaim |
| `test-backlog.sh` | `chief-backlog.sh`: add/status/note/hold/done/list/next/show, error cases, and that `status <id> in-flight` restores a held/spawned task's meta status back to `working` |
| `test-git-sync.sh` | `git-sync.sh`'s `chief_sync_default_branch`: fast-forwards the default branch from origin only when checked out on it with a clean tree, otherwise skips - and never fails its caller, including with no origin remote or a diverged history |
| `test-worktree-guard.sh` | `chief_is_linked_worktree` - main checkout vs. a linked worktree vs. a non-git dir |
| `test-crew-state.sh` | `chief-crew-state.sh`'s state classification across all six states, plus a brainstormer's awaiting-operator idle rule (never stale) and attach hint |
| `test-naming.sh` | Where-lines (`backlog show`) and herdr's workspace label and its cleanup (fake `herdr`) |
| `test-send.sh` | `chief-send.sh`: durable inbox numbering, handled-file awareness, key sends |
| `test-control.sh` | `chief-control.sh`: interrupt (agent keeps running), exit, relaunch with checkpoint note |
| `test-setup.sh` | `chief-setup.sh`: backend config, idempotent gitignore, no-git-repo case |
| `test-hooks.sh` | `session-start.sh` and `stop-watch-arm.sh`'s own bash logic across fresh/configured/in-flight/builder-worktree scenarios |
| `test-lifecycle.sh` | The full happy path: backlog → spawn → simulated work → crew-state → teardown-refuses-before-merge → merge → teardown-succeeds |
| `test-spawn-cleanup.sh` | `chief-spawn.sh`'s required `--branch` (nothing left behind when missing), rollback on a failed/malformed `backend_spawn` (`backend_spawn_cleanup`, no orphaned worktree/branch/meta) an interrupted spawn's `status=spawning` stub (crew-state, watch, teardown), and the atomic spawn lock, against the mock backend's `CHIEF_MOCK_SPAWN_FAIL`/`CHIEF_MOCK_SPAWN_MALFORMED` injectors |
| `test-project-workspace.sh` | The spawn/teardown flow on the mock backend: origin sync before the worktree exists, and no `.chief` ever created inside a project (default `CHIEF_HOME` from a project or its worktree) |
| `test-agent.sh` / `test-agent-claude.sh` / `test-agent-adapters.sh` | The agent loader (per-task adapter from meta, command override, unknown agent), the claude adapter (contract, pre-trust in `.claude.json`), and the codex/copilot adapters (flags, model flag, CLI check, herdr's start args) |
| `test-agent-select.sh` | `.chief/config/agents`: every strategy (round-robin persistence and parallel safety, weighted with an injected random), per-role pools, `peek`, comments, malformed config |
| `test-agents.sh` | `chief-agents.sh`: the effective agent per role, the `(global fallback)` marker, read-only |
| `test-handoff.sh` | `chief-spawn.sh --from` / `--dry-run` and `chief-promote.sh`: every role pair and rejection, the target role's agent (not the source's), `--agent` carry-over, lineage brief and framing, `from=`, source untouched, `--dry-run` without side effects |
| `test-brainstormer.sh` | The brainstormer brief (explicit confirmation before `done`, out-of-scope list, no skill dependency, spec skeleton) and lifecycle, and `chief-spawn.sh` printing and recording `attach=` for it only |
| `test-review.sh` | `chief-review.sh` (round 1 links and pinned SHA, round 2 archive/send/`working:` line/in-flight, every gate, stale or missing SHA, same-SHA refusal), the teardown cascade (done, refused, hand-removed worktree, reviewer alone), the builder/reviewer link in crew-state and the digest, watch (differing reviewer `done` wakes, identical suppressed), and the reviewer brief and builder lifecycle content |
| `test-backend-herdr-mock.sh` | `backends/herdr.sh` against a fake `herdr` CLI and live-captured screen fixtures: screen-based start readiness (shell-only, late TUI, `agent start` rc ignored), the folder-trust dialog (accepted once for Chief's own worktree, never for another folder or an agent without trust keys), `blocked` is not a started turn, stall recovery (Enter only over a landed placeholder or raw text, wait for a queued or already-submitted brief, one resend only when the box is empty and the TUI rendered, never over a shell-only screen), and `chief-spawn.sh` / `backend_relaunch` failing non-zero with rollback and no `spawned:` unless a turn started. Zero cost. |
| `test-backend-herdr.sh` | `backends/herdr.sh` against a REAL herdr install and a real (trivial) claude turn: spawn, pane read, busy, send, kill, relaunch, and the live-input-line check against real pane rendering (a placeholder-hint box and text genuinely in flight). **Not zero-cost** - opt in with `CHIEF_TEST_HERDR=1`; skips cleanly otherwise. See below. |
| `test-backend-orca-mock.sh` | `backends/orca.sh`'s argument-building and JSON-parsing against a fake `orca` CLI stub: spawn via `worktree create` + `terminal create --command` + `terminal send` (repo registration, parent-worktree nesting, pre-trust, ready-screen check, rollback on every failure), `backend_spawn_cleanup` rollback, pane read, busy, send, kill, `backend_teardown`, relaunch, and the real `chief-spawn`/`send`/`control`/`teardown` scripts end to end on the orca backend (herdr-parity flow). Zero cost. |
| `test-backend-orca.sh` | `backends/orca.sh` against a REAL live Orca instance and real (trivial) claude turns, on a scratch repo: spawn (incl. repo registration and parent-worktree nesting), pane read, busy, send, kill, relaunch, `backend_teardown`, `backend_spawn_cleanup`, then the real `chief-spawn`/`send`/`control` (interrupt, relaunch)/`crew-state`/`teardown` scripts end to end. **Not zero-cost** - opt in with `CHIEF_TEST_ORCA=1`; skips cleanly otherwise. See below. |

## The herdr and orca backend tests are different from the rest

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

## What's deliberately NOT here (needs the devcontainer instead)

- **Skill-behavior tests** (does Claude actually follow `using-chief`/`dispatch`/`setup` correctly when loaded) - that's `tests/claude-code/test-using-chief.sh`, `test-dispatch.sh`, and `test-chief-setup.sh`, which invoke the real `claude` CLI and cost real tokens.
