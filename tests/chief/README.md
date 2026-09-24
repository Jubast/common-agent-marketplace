# Chief plugin tests

Functional/integration tests of Chief's own bash scripts. Most files run
against the `mock` backend (`plugins/chief/bin/lib/chief-backend-mock.sh`, a
throwaway background process standing in for a real terminal session) - no
`claude` CLI, zero tokens, safe anywhere. `test-backend-orca-mock.sh` is
also zero-cost: it unit-tests `chief-backend-orca.sh` against a fake `orca`
CLI stub. `test-backend-herdr.sh` and `test-backend-orca.sh` are the two
exceptions: each opts into a real herdr/orca install and a real claude turn
- see below.

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
| `test-meta.sh` | `chief-meta.sh` key=value read/write helpers |
| `test-lock.sh` | `chief-lock.sh` mutex: acquire/release/timeout/stale-lock reclaim |
| `test-backlog.sh` | `chief-backlog.sh`: add/status/note/hold/done/list/next/show, error cases |
| `test-worktree-guard.sh` | `chief_is_linked_worktree` - main checkout vs. a linked worktree vs. a non-git dir |
| `test-crew-state.sh` | `chief-crew-state.sh`'s state classification across all six states |
| `test-send.sh` | `chief-send.sh`: durable inbox numbering, handled-file awareness, key sends |
| `test-control.sh` | `chief-control.sh`: interrupt (agent keeps running), exit, relaunch with checkpoint note |
| `test-setup.sh` | `chief-setup.sh`: backend config, idempotent gitignore, no-git-repo case |
| `test-hooks.sh` | `session-start.sh` and `stop-watch-arm.sh`'s own bash logic across fresh/configured/in-flight/builder-worktree scenarios |
| `test-lifecycle.sh` | The full happy path: backlog → spawn → simulated work → crew-state → teardown-refuses-before-merge → merge → teardown-succeeds |
| `test-spawn-cleanup.sh` | `chief-spawn.sh`'s rollback on a failed/malformed `backend_spawn` (`backend_spawn_cleanup`, no orphaned worktree/branch/meta) and the atomic spawn lock, against the mock backend's `CHIEF_MOCK_SPAWN_FAIL`/`CHIEF_MOCK_SPAWN_MALFORMED` injectors |
| `test-backend-herdr.sh` | `chief-backend-herdr.sh` against a REAL herdr install and a real (trivial) claude turn: spawn, capture, busy, send, kill, relaunch. **Not zero-cost** - opt in with `CHIEF_TEST_HERDR=1`; skips cleanly otherwise. See below. |
| `test-backend-orca-mock.sh` | `chief-backend-orca.sh`'s argument-building and JSON-parsing against a fake `orca` CLI stub: spawn, capture, busy, send, kill, relaunch. Zero cost. |
| `test-backend-orca.sh` | `chief-backend-orca.sh` against a REAL live Orca instance and a real (trivial) claude turn, targeting this repo itself: spawn, capture, busy, send, kill, relaunch. **Not zero-cost** - opt in with `CHIEF_TEST_ORCA=1`; skips cleanly otherwise. See below. |

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

`chief-backend-herdr.sh` is verified against a live herdr 0.9.0 install -
see its header for the real CLI shape and two confirmed quirks: Claude
Code's first-run "trust this folder?" dialog, and `herdr agent prompt
--wait` occasionally reporting `agent_prompt_stalled` on a genuinely
delivered prompt.

`chief-backend-orca.sh` targets this repo itself as the project, since
`orca` only resolves a worktree selector for one it created via `orca
worktree create` - never a plain `git worktree add`, so the project has to
already be in `orca repo list`; a throwaway temp repo can't satisfy that.
Spawn (worktree creation, the branch rename, launch, reply capture,
busy/idle, send, kill) is confirmed working end to end live. Relaunch has
a known issue - see the adapter's own header.

## What's deliberately NOT here (needs the devcontainer instead)

- **Skill-behavior tests** (does Claude actually follow `using-chief`/`dispatch`/`reviewer`/`setup` correctly when loaded) - that's `tests/claude-code/test-using-chief.sh`, `test-dispatch.sh`, `test-reviewer.sh`, and `test-chief-setup.sh`, which invoke the real `claude` CLI and cost real tokens.
