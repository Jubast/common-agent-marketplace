# Chief plugin tests

Functional/integration tests of Chief's own bash scripts.

- **`*.bats`** run against a real herdr (see "Real herdr with a stand-in
  agent" below), or, tagged `orca`, a real headless Orca (see "Real headless
  Orca"), always with a zero-cost stand-in agent. `fixtures/herdr/` holds
  screens captured from a live herdr and Claude Code, the reference for the
  stand-in.
- **`manual/`** holds the opt-in tests that run real herdr and agent CLIs and
  spend real tokens: `test-backend-herdr-real.sh`, `test-backend-copilot.sh`
  and `test-backend-copilot-brief.sh` (see below). They use the small assertion
  helpers in `manual/lib/harness.sh` and are never run by `run-tests.sh`.

## Real herdr with a stand-in agent (`*.bats`)

Tests run against a real, headless `herdr server` - one per test, with
its own `HOME`/`XDG_*` and socket, stopped in `teardown` (`lib/common.bash`).
The agent in its panes is `fixtures/standin/claude`, a Claude-Code-shaped TUI
that costs no tokens; the server's `PATH` holds only the stand-ins, and
`chief_zero_cost_guard` aborts if a real `claude`/`codex`/`copilot` could be
found. Panes inherit the server's environment, not the test's: configure the
stand-in through files under `$STANDIN_DIR` (`standin_mode`, `standin_hold`),
never exported variables (modes: `exit`, `never-ready`, `late`, `trust`,
`lose-enter`, `drop`, `slow-work`; see the header of `fixtures/standin/claude`).
Where a real herdr reply cannot be provoked, `herdr_fault` swaps one named
call's reply (`fixtures/faulty/herdr`, a wrapper that otherwise runs the real
herdr). Use `eventually` for anything asynchronous, never a bare `sleep`.

`tests/chief/ci/install-herdr.sh` installs the pinned herdr into
`tests/.cache/bin`, which the suite prefers over the herdr on `PATH`.

## Real headless Orca (`test-backend-orca.bats`)

One `orca-ide serve` per file (`lib/orca.bash`: Xvfb, own `HOME`/`XDG_CONFIG_HOME`,
port 0, scrubbed env), so its tests run serially; `teardown_file` kills the
server, Xvfb, Orca's pty daemon and the stand-ins by working directory. Orca
adds the login shell's `PATH` to its panes, so the stand-ins go first through
the isolated `HOME`'s `.bashrc`, and a test checks in a pane that `claude`,
`codex` and `copilot` resolve to them. Orca cannot see a stand-in's hooks, so
each prompt it sends takes ~8 s; the file stays small (~5 min). It needs
`tests/chief/ci/install-orca.sh` (or `orca-ide` on `PATH`) and Xvfb plus the
Electron libraries listed in `.github/workflows/tests.yml`; without them the
file skips, unless `CHIEF_TEST_REQUIRE_BACKENDS=1` (set by the CI job) makes
that a failure. CI runs it as `chief-orca` (`run-tests.sh --only-orca`); the
herdr job runs `--no-orca`. A plain `run-tests.sh --jobs N` runs the Orca file
alongside the herdr files; on a small machine use `--no-orca`, then `--only-orca`.

## Running

```bash
./tests/chief/run-tests.sh          # everything
```

`*.bats` files run on [bats-core](https://github.com/bats-core/bats-core) pinned
in `tests/package.json` (bats 1.14.0, bats-assert, bats-support, bats-file;
`run-tests.sh` runs `npm ci` on first use, so Node and npm are needed). Options:
`run-tests.sh [--jobs N] [--junit DIR] [--no-orca | --only-orca] [bats args...]`. `--jobs` needs GNU
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
| `test-backlog.bats` | `chief-backlog.sh`: add/status/note/hold/done/list/next/show, error cases, and that `status <id> in-flight` restores a held/spawned task's meta status back to `working` |
| `test-git-sync.bats` | `git-sync.sh`'s `chief_sync_default_branch`: fast-forwards the default branch from origin only when checked out on it with a clean tree, otherwise skips - and never fails its caller, including with no origin remote or a diverged history |
| `test-worktree-guard.bats` | `chief_is_linked_worktree` - main checkout vs. a linked worktree vs. a non-git dir |
| `test-crew-state.bats` | `chief-crew-state.sh`'s state classification across all six states, plus a brainstormer's awaiting-operator idle rule (never stale) and attach hint |
| `test-naming.bats` | Where-lines (`backlog show`), herdr's workspace label and its cleanup against a real herdr, task id checks and composition |
| `test-send.bats` | `chief-send.sh` on a real herdr: durable inbox numbering, handled-file awareness, key sends, the doorbell line |
| `test-watch.bats` | `chief-watch.sh` on a real herdr: notify-once per state change (done, resumed, brainstormer, stale, agent and reviewer tags), one watcher per home, and `chief_notify_line` |
| `test-zero-cost.bats` | The zero-cost guard refuses a server PATH holding a real agent CLI |
| `test-standin.bats` | The stand-in agent's modes (`hold`, `exit`, `never-ready`, kill) on a real herdr |
| `test-control.bats` | `chief-control.sh`: interrupt (agent keeps running), exit, relaunch with checkpoint note |
| `test-setup.bats` | `chief-setup.sh`: backend config, idempotent gitignore, no-git-repo case |
| `test-hooks.bats` | `session-start.sh` and `stop-watch-arm.sh`'s own bash logic across fresh/configured/in-flight/builder-worktree scenarios |
| `test-lifecycle.bats` | The full happy path: backlog → spawn → simulated work → crew-state → teardown-refuses-before-merge → merge → teardown-succeeds |
| `test-brief.bats` | `brief.sh`'s `chief_brief_strip_section`: a checkpoint section is stripped to EOF or to the next heading, repeats collapse to one, an absent section is a no-op |
| `test-spawn.bats` | `chief-spawn.sh` on a real herdr: brief rendering with embedded newlines and sed-delimiter characters, pre-trust, agent selection (`--agent`, `--model`, `--args`, config pools and `command=`), the agent and launch lines, every pre-backend failure leaving nothing behind, invalid ids |
| `test-teardown.bats` | `chief-teardown.sh` on a real herdr: a researcher or brainstormer discards unconditionally, a builder needs a landed branch or `--abandon` (merge and squash checks), the remote branch is always kept, the reviewer cascade, un-trusting the worktree |
| `test-spawn-cleanup.bats` | `chief-spawn.sh`'s required `--branch` (nothing left behind when missing), rollback on a failed or malformed `backend_spawn` (`backend_spawn_cleanup`, no orphaned worktree/branch/meta) an interrupted spawn's `status=spawning` stub (crew-state, watch, teardown), and the atomic spawn lock, on a real herdr, failed by the stand-in's `never-ready` mode and by `herdr_fault` (a wrapper around the real herdr that fails one named call) |
| `test-project-workspace.bats` | The spawn/teardown flow on a real herdr: origin sync before the worktree exists, and no `.chief` ever created inside a project (default `CHIEF_HOME` from a project or its worktree) |
| `test-agent.bats` / `test-agent-claude.bats` / `test-agent-adapters.bats` | The agent loader (per-task adapter from meta, command override, unknown agent), the claude adapter (contract, pre-trust in `.claude.json`), and the codex/copilot adapters (flags, model flag, CLI check, herdr's start args) |
| `test-agent-select.bats` | `.chief/config/agents`: every strategy (round-robin persistence and parallel safety, weighted with an injected random), per-role pools, `peek`, comments, malformed config |
| `test-agents.bats` | `chief-agents.sh`: the effective agent per role, the `(global fallback)` marker, read-only |
| `test-handoff.bats` | `chief-spawn.sh --from` / `--dry-run` and `chief-promote.sh`: every role pair and rejection, the target role's agent (not the source's), `--agent` carry-over, lineage brief and framing, `from=`, source untouched, `--dry-run` without side effects |
| `test-brainstormer.bats` | The brainstormer brief (explicit confirmation before `done`, out-of-scope list, no skill dependency, spec skeleton) and lifecycle, and `chief-spawn.sh` printing and recording `attach=` for it only |
| `test-review.bats` | `chief-review.sh` (round 1 links and pinned SHA, round 2 archive/send/`working:` line/in-flight, every gate, stale or missing SHA, same-SHA refusal), the teardown cascade (done, refused, hand-removed worktree, reviewer alone), the builder/reviewer link in crew-state and the digest, watch (differing reviewer `done` wakes, identical suppressed), and the reviewer brief and builder lifecycle content |
| `test-backend-herdr.bats` | `backends/herdr.sh` against a real herdr and the stand-in agent: screen-based start readiness (never-rendering pane, late TUI, `agent start` errors from `herdr_fault`), the folder-trust dialog (accepted once for Chief's own worktree, never for another folder), `blocked` is not a started turn, stall recovery (a bare Enter only over landed text, wait for an already-submitted brief, one resend only when the box is empty), `chief-spawn.sh` / `backend_relaunch` failing with rollback unless a turn started, and spawn, busy, send, kill and relaunch end to end. Zero cost. Not covered: copilot's inline brief echo and a TUI not rendered at prompt time. |
| `manual/test-backend-herdr-real.sh` | The same adapter against a REAL herdr and a real (trivial) claude turn, for real Claude rendering the stand-in only imitates. **Not zero-cost** - opt in with `CHIEF_TEST_HERDR=1`; skips cleanly otherwise. Not run by `run-tests.sh`. |
| `manual/test-backend-copilot.sh` | The copilot adapter against the REAL Copilot CLI, on its own isolated herdr server: ready text vs. the real idle footer, the folder-trust dialog and banner screens, the paste placeholder and input marker, then a real `chief-spawn.sh --agent copilot --mode researcher` on a throwaway repo through a status line, a report and teardown. **Not zero-cost** - opt in with `CHIEF_TEST_COPILOT=1`; skips cleanly otherwise. See below. |
| `manual/test-backend-copilot-brief.sh` | Issue #90 against the REAL Copilot CLI (same isolation as `test-backend-copilot.sh`): real `chief-spawn.sh --agent copilot` spawns with a brief-sized prompt must send one `herdr agent prompt` and produce one `user.message` in Copilot's `events.jsonl`; fails if no attempt hit herdr's `agent_prompt_stalled`. **Not zero-cost** - opt in with `CHIEF_TEST_COPILOT_BRIEF=1`; skips cleanly otherwise. See below. |
| `test-backend-orca.bats` | `backends/orca.sh` against a real headless Orca and the stand-in agent: spawn (repo registration, nesting under the main worktree, pre-trust, launch args), the registration, worktree-create and never-ready failures with their rollback, a lost or unsubmitted prompt, busy/send/kill/relaunch, `backend_spawn_cleanup`, teardown, and the real lifecycle scripts (spawn, send, interrupt, relaunch, teardown, brainstormer attach hint, rollback) |

## The herdr and copilot backend tests that use real agents

`manual/test-backend-herdr-real.sh` isn't free: it needs `herdr` + a headless
`herdr server` plus `claude` on PATH, and spends a small number of real tokens
per claude turn it starts. It skips by default (even under `run-tests.sh`)
unless you opt in:

```bash
CHIEF_TEST_HERDR=1 bash tests/chief/manual/test-backend-herdr-real.sh
```

`backends/herdr.sh` is verified against a live herdr 0.9.1 install -
see its header for the real CLI shape and two confirmed quirks: Claude
Code's first-run "trust this folder?" dialog, and `herdr agent prompt
--wait` reporting `agent_prompt_stalled` for distinct situations (text
delivered but Enter didn't register, text never delivered, TUI not yet
rendered) that `_chief_herdr_recover` tells apart from the screen.

### The copilot test

```bash
CHIEF_TEST_COPILOT=1 bash tests/chief/manual/test-backend-copilot.sh
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
CHIEF_TEST_COPILOT_BRIEF=1 bash tests/chief/manual/test-backend-copilot-brief.sh
```

Same prerequisites and isolation as the copilot test (shared in
`manual/lib/copilot-isolation.sh`). **Cost: one research turn per attempt**, with
`CHIEF_TEST_COPILOT_BRIEF_ATTEMPTS` attempts (default 3). The bug needs herdr to
report `agent_prompt_stalled` although copilot took the brief, which happens on
some runs only, so the test fails when no attempt stalled instead of passing
without having exercised the recovery.

## What's deliberately NOT here (needs the devcontainer instead)

- **Skill-behavior tests** (does Claude actually follow `using-chief`/`dispatch`/`setup` correctly when loaded) - that's `tests/claude-code/test-using-chief.sh`, `test-dispatch.sh`, and `test-chief-setup.sh`, which invoke the real `claude` CLI and cost real tokens.
