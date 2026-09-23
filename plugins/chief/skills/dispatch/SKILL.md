---
name: dispatch
description: Use when the user wants to hand off a piece of work to an isolated agent instead of doing it inline - dispatching a task, spawning a builder/scout, checking on in-flight work, steering, or merging/tearing down finished work in a project that has a .chief/ home (or where the user asks to set one up).
---

# Chief: dispatch

Chief runs isolated worker agents ("builders" for code changes, "scouts" for investigation-only reports) in their own git worktree, tracks them in a plain-markdown backlog, and supervises them at near-zero token cost between your turns. You are the operator's single point of contact for this; you do not do the dispatched work yourself once you've handed it off.

All commands live in `${CLAUDE_PLUGIN_ROOT}/bin/`. Runtime state lives in `.chief/` at the project's git root (created on first use).

## Deciding ship vs scout

- **ship** (default): the deliverable is a code change on a branch. Use for anything with clear enough intent to implement.
- **scout**: the deliverable is a written report only - no commit, no push. Use only when the operator explicitly wants a separate investigation/design artifact, or genuine uncertainty about *what* to build would make implementing now wasteful.

Don't launch a scout to resolve ordinary ambiguity - ask one concise question instead. Reserve scouts for uncertainty big enough to change the outcome.

## The lifecycle

1. **File it.**
   `bin/chief-backlog.sh add <id> "<short title>"`
   Pick a short id yourself (e.g. `t-001`, or a slug like `rate-limit`).

2. **Spawn.**
   `bin/chief-spawn.sh <id> <project-dir> --mode ship|scout --intent "<the operator's own ask, close to verbatim>" --spec "<your build instructions, only what the intent requires>"`
   Keep `--intent` narrow - it becomes the acceptance criteria. Keep `--spec` to only what's needed; a generalization or extra hardening nobody asked for is a note for later, not something to build now.
   This creates an isolated worktree+branch, renders the brief, and launches the builder. It also marks the backlog item in-flight if it exists.

3. **It runs on its own.** `chief-watch.sh` (armed by a Stop hook, zero model cost) polls it between your turns and only interrupts you when it's finished, failed, blocked, or needs a decision. On `blocked` or `needs-decision`, run `bin/chief-backlog.sh hold <id> "<why, one line>"`.

4. **Check on it anytime:**
   `bin/chief-crew-state.sh <id>` - deterministic current state (working/done/blocked/needs-decision/failed/stale).

5. **Steer it if needed:**
   `bin/chief-send.sh <id> "<instruction>"` - delivered through a durable inbox the builder acknowledges; safe to send mid-task. If the item is `held`, move it back with `bin/chief-backlog.sh status <id> in-flight` once you've sent the unblocking instruction.

6. **If it's stuck**, escalate cheapest first:
   - `bin/chief-control.sh <id> interrupt` (nudge; it keeps running) + a corrective `chief-send.sh`
   - `bin/chief-control.sh <id> relaunch --note "<progress so far>"` only if genuinely wedged - the replacement gets the same worktree and commits but none of the conversation, so the note is all it has.

7. **Review and report.** Once a task reports `done`, check its current mode via `chief-crew-state.sh <id>`'s `[mode: ...]` tag (promotion can change it after spawn):
   - `ship` - load the `reviewer` skill against its diff, then report the outcome to the operator plainly.
   - `scout` - relay its report as-is.

   End of the lifecycle for this task until the operator responds.

## After the operator responds

Do exactly what they decide, nothing more:

- **Not satisfied** - `bin/chief-send.sh <id> "<instruction>"` back to the builder, or send the scout to investigate further.
- **Ready to land** (ship only) - compose a conventional-commit-style title and a structured body yourself (the same way this project's own PR conventions - a `conventional-pull-requests`-style skill if installed, or its CLAUDE.md/AGENTS.md rules - would produce), then `bin/chief-pr-open.sh <id> --confirm --title "<title>" --body "<body>"` to push and open a PR/MR. Always pass `--title`/`--body` explicitly; don't rely on the script's auto-derived fallback. Skip if they want a local-only merge.
- **Accepted** - ship: `bin/chief-local-merge.sh <id> --confirm` (local fast-forward) or `bin/chief-pr-merge.sh <id> --confirm` (merges the open PR, defaults to squash). Scout to become a ship: `bin/chief-promote.sh <id> --intent "<ask>" [--spec "<instructions>"]` - converts it in place; its findings become context, not the deliverable.
- **Accepted, no ship needed** (scout only) - `bin/chief-backlog.sh done <id>` then `bin/chief-teardown.sh <id>` discards the worktree; the report at `.chief/data/<id>/report.md` survives.

`chief-pr-open.sh`, `chief-local-merge.sh`, and `chief-pr-merge.sh` all require `--confirm` - pass it only once the operator has explicitly said so in this conversation.

## Once a PR is open

- **Check it** - `bin/chief-pr-state.sh <id>` for its current state (open/draft/mergeable/checks).
- **Review it** - `bin/chief-pr-review.sh <id> --comment "<text>"` or `--request-changes "<text>"`. Add `--file <path> --line <N>` to a `--comment` call to attach it to a specific line instead of posting top-level (only valid with `--comment`, not `--request-changes`).
- **Approve it** - `bin/chief-pr-approve.sh <id>`.
- **Merge it** - `bin/chief-pr-merge.sh <id> --confirm`. Defaults to `--squash` - the recommended strategy, and applied uniformly by this script itself rather than left to each provider's own default (GitHub already defaults to squash; GitLab and Azure DevOps default to a plain merge). Pass `--merge` or `--rebase` explicitly only if the operator asks for one of those instead.
- **Abandon** - `bin/chief-control.sh <id> exit` stops the worker without discarding its worktree or commits. To discard the work too, `bin/chief-teardown.sh <id> --abandon` force-discards it even though nothing landed - only on the operator's explicit instruction.
- **Landed** - `bin/chief-backlog.sh done <id>` (if not already), then `bin/chief-teardown.sh <id>`. Without `--abandon`, teardown refuses unless the branch is reachable from the default branch.

## Backlog reference

`bin/chief-backlog.sh add|status|note|hold|done|list|next|show <id> ...` - one markdown file (`.chief/data/backlog.md`), statuses are `queued|in-flight|held|done`. Use `hold <id> "<reason>"` for anything that needs an operator decision before it can proceed.

## What NOT to do

- Don't spawn a worker agent to answer something you can check yourself with a quick, read-only look - dispatch is for changes and real investigation, not a single lookup. Any actual change to a project, however small, still goes to a worker agent.
- Don't invent scope in `--spec` beyond what `--intent` asks for.
