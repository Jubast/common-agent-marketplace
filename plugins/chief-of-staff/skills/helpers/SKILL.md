---
name: helpers
description: How Chief spawns, messages, watches and tears down worker agents. Load before touching a worker.
user-invocable: false
---

# Chief helpers

## Backend

Workers run in terminals of the backend named by `$CHIEF_BACKEND` (`herdr` or
`orca`; unset: ask the operator). Load its skill for the commands:
`chief-of-staff:herdr` or `chief-of-staff:orca`. The backend's own skill
(`herdr --skill`, `using-orca`) covers anything else.

## Layout

- `<chief-plugin-dir>`: two levels above this skill's base directory.
- `<chief-home>`: `$CHIEF_HOME`, default `.chief/` in the directory this
  session started in.
- `<dir>` = `<chief-home>/<id>/`, one per worker:
  - `brief.md`: what the worker reads first.
  - `status`: the worker appends `<state>: <one line>`; the last line counts.
  - `report.md`: the worker's report. Read it, not the worker's terminal.
  - `meta`: your notes to find the worker again: role, project, branch,
    worktree and the backend's handle.

## Spawn

1. Pick an `<id>` (kebab-case, e.g. `fix-login-timeout`) and a branch in the
   project's conventions (e.g. `fix/login-timeout`). A researcher gets a
   branch too; it pushes nothing.
2. Write `<dir>/brief.md`: `# Ask` (the operator's ask, plus context the
   worker can't find), `# Paths` (branch, status file, report path), then
   the rules from `<chief-plugin-dir>/templates/<role>.md`.
3. Create the worktree and start the worker as the backend skill says, with:
   `claude "Read <dir>/brief.md and follow it." --dangerously-skip-permissions --add-dir <dir>`
4. Write `<dir>/meta`, then watch.

## Send

Write the message to `<dir>/msg-<n>.md` and type one line into the worker's
terminal: `Chief: read <dir>/msg-<n>.md and act on it.` Then watch again.

## Watch

Run as a background command; it costs no tokens and exits on a final state:

```bash
until tail -n1 <dir>/status | grep -Eq '^(done|blocked|failed):'; do sleep 15; done; tail -n1 <dir>/status
```

If it runs far longer than the task should, look at the worker's screen.

## Teardown

Once the outcome is reported and the operator has no follow-up:

1. Stop, unless the operator says to discard, if either prints anything:
   `git -C <worktree> status --porcelain` or
   `git -C <worktree> log --oneline HEAD --not --exclude=<branch> --branches --remotes`.
2. Close the terminal and remove the worktree and branch as the backend
   skill says.
3. Move `<dir>` to `<chief-home>/archive/`.
