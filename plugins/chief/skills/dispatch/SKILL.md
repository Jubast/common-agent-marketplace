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

3. **It runs on its own.** Between your turns, `chief-watch.sh` (armed by a Stop hook, at zero model cost) polls it in the background and only interrupts you when something needs attention - the task finished, failed, is blocked, or needs a decision.

4. **Check on it anytime:**
   `bin/chief-crew-state.sh <id>` - deterministic current state (working/done/blocked/needs-decision/failed/stale).

5. **Steer it if needed:**
   `bin/chief-send.sh <id> "<instruction>"` - delivered through a durable inbox the builder acknowledges; safe to send even while it's mid-task.

6. **If it's stuck**, escalate in order - cheapest first:
   - `bin/chief-control.sh <id> interrupt` (nudge; it keeps running) + a corrective `chief-send.sh`
   - `bin/chief-control.sh <id> relaunch --note "<progress so far>"` only if genuinely wedged (looping, unresponsive, truly dead) - the replacement gets the same worktree and commits but NONE of the conversation, so the note is the only thing carrying context forward. Write it accordingly.

7. **Review and report.** Once a task reports `done`:
   - If it's a ship, load the `reviewer` skill against its diff, then report the outcome to the operator plainly.
   - If it's a scout, relay its report as-is.

   That's the end of the lifecycle above for this task until the operator responds.

## After the operator responds

Whatever they decide, do exactly that and nothing more - never on your own initiative:

- **Not satisfied** - fix it: `bin/chief-send.sh <id> "<instruction>"` back to the builder, or send the scout to investigate further.
- **Ready to land** (ship only) - `bin/chief-pr-open.sh <id>` to push the branch and open a PR/MR for the operator to review. Skip this if they want a local-only merge instead.
- **Accepted** - for a ship: `bin/chief-merge.sh <id>` for a local fast-forward, or `bin/chief-pr-merge.sh <id>` to merge the open PR. For a scout: `bin/chief-promote.sh <id> --intent "<the operator's ask for the ship task>" [--spec "<build instructions>"]` - converts it to a ship task in place (same worktree, same branch, same running agent) and sends it the new instructions through its steering inbox; its findings become supporting context, not the deliverable.

## Once a PR is open

- **Check it** - `bin/chief-pr-state.sh <id>` for its current state (open/draft/mergeable/checks) across whichever provider it was opened against.
- **Review it** - `bin/chief-pr-review.sh <id> --comment "<text>"` to leave a comment, or `bin/chief-pr-review.sh <id> --request-changes "<text>"` to request changes.
- **Approve it** - `bin/chief-pr-approve.sh <id>`.
- **Merge it** - `bin/chief-pr-merge.sh <id>` (replaces chief-merge.sh's old `--pr` mode, which no longer exists).
- **Abandon** - `bin/chief-control.sh <id> exit` stops the worker without discarding its worktree or commits, in case it's needed later.
- **Landed** - clean up: `bin/chief-backlog.sh done <id>` (if not already updated), then `bin/chief-teardown.sh <id>`. Teardown refuses unless the branch is already reachable from the project's default branch - it will not discard unlanded work.

## Backlog reference

`bin/chief-backlog.sh add|status|note|hold|done|list|next|show <id> ...` - one markdown file (`.chief/data/backlog.md`), statuses are `queued|in-flight|held|done`. Use `hold <id> "<reason>"` for anything that needs an operator decision before it can proceed.

## What NOT to do

- Don't spawn a worker agent to answer something you can check yourself with a quick, read-only look - dispatch is for changes and real investigation, not a single lookup. Any actual change to a project, however small, still goes to a worker agent.
- Don't invent scope in `--spec` beyond what `--intent` asks for.
