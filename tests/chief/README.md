# Chief plugin tests

Functional/integration tests of Chief's own bash scripts. Everything except
`test-backend-herdr.sh` runs against the `mock` backend
(`plugins/chief/bin/lib/chief-backend-mock.sh`, a throwaway background
process standing in for a real terminal session) with no `claude` CLI
invocation - zero model tokens, safe to run anywhere including outside a
devcontainer. `test-backend-herdr.sh` is the one exception: it opts into a
real herdr install and a real (trivial) claude turn - see below.

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
| `test-backend-herdr.sh` | `chief-backend-herdr.sh` against a REAL herdr install and a real (trivial) claude turn: spawn, capture, busy, send, kill, relaunch. **Not zero-cost** - opt in with `CHIEF_TEST_HERDR=1`; skips cleanly otherwise. See below. |

## The herdr backend test is different from the rest

`test-backend-herdr.sh` is the one file here that isn't free: it needs `herdr`
and `claude` on PATH, a headless `herdr server`, and spends a small number of
real tokens on one trivial prompt per claude turn it starts. It's skipped by
default (even under `run-tests.sh`) unless you opt in:

```bash
CHIEF_TEST_HERDR=1 bash tests/chief/test-backend-herdr.sh
```

`chief-backend-herdr.sh` itself is verified against a live herdr 0.9.0
install (no longer a draft) - see the adapter file's own header comments for
the real CLI shape (`herdr workspace`/`worktree`/`pane`/`agent`, not
`herdr session ...`) and two confirmed-live quirks it works around: Claude
Code's own first-run "trust this folder?" dialog on every fresh worktree,
and `herdr agent prompt --wait` occasionally reporting `agent_prompt_stalled`
right after that dialog closes even when the text was genuinely delivered.

## What's deliberately NOT here (needs the devcontainer instead)

- **The Orca adapter** (`chief-backend-orca.sh`) - still an unverified draft; its header lists exactly what to confirm against a live Orca instance.
- **Skill-behavior tests** (does Claude actually follow `using-chief`/`dispatch`/`reviewer`/`setup` correctly when loaded) - that's `tests/claude-code/test-using-chief.sh`, `test-dispatch.sh`, `test-reviewer.sh`, and `test-chief-setup.sh`, which invoke the real `claude` CLI and cost real tokens.
