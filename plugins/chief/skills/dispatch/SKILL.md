---
name: dispatch
description: Use when the user wants to hand off a piece of work to an isolated agent instead of doing it inline - dispatching a task, spawning a builder/researcher/brainstormer, checking on in-flight work, steering, or merging/tearing down finished work, once CHIEF_HOME (the operator's one shared home, not one per project) is configured (or where the user asks to set it up).
---

# Chief: dispatch

Chief runs isolated worker agents ("builders" for code changes, "researchers" for investigation-only reports) in their own git worktree, tracks them in a plain-markdown backlog, and supervises them at near-zero token cost between your turns. You are the operator's single point of contact for this; you do not do the dispatched work yourself once you've handed it off.

All commands live in ${CLAUDE_PLUGIN_ROOT}/bin/. Runtime state lives in `.chief/` at `CHIEF_HOME` - resolved from the git root of wherever the Chief session itself runs, typically the operator's top-level workspace, *not* inside any individual `<project-dir>` you dispatch into (created on first use). One `CHIEF_HOME` dispatches into many `<project-dir>` targets; don't run `chief:setup` separately inside each project you plan to dispatch to.

## Deciding builder vs researcher vs brainstormer

- **builder** (default): the deliverable is a code change on a branch. Use for anything with clear enough intent to implement.
- **researcher**: the deliverable is a written report only - no commit, no push. Use only when the operator explicitly wants a separate investigation/design artifact, or genuine uncertainty about *what* to build would make implementing now wasteful.

- **brainstormer**: the deliverable is a spec, shaped in live conversation between the operator and the worker. **Explicit-only:** spawn one only when the operator explicitly asks to brainstorm. Never choose it, default to it, or offer it instead of asking a clarifying question.

Don't launch a researcher to resolve ordinary ambiguity - ask one concise question instead. Reserve researchers for uncertainty big enough to change the outcome.

## The lifecycle

Every task's `state/<id>.lifecycle` (rendered by `chief-spawn.sh`) is the checklist for everything below, filing through teardown - each line names the step and, for review/landing, the exact action to take. Check off each line the moment you complete it - don't batch it. Read the file before acting on an in-flight task, always, not just after a compaction, so you work from its checked state, not memory.

1. **File it.**
   `${CLAUDE_PLUGIN_ROOT}/bin/chief-backlog.sh add <id> "<short title>"`
   Pick a short id yourself (e.g. `t-001`, or a slug like `rate-limit`).

2. **Spawn.**
   `${CLAUDE_PLUGIN_ROOT}/bin/chief-spawn.sh <id> <project-dir> --mode builder|researcher|brainstormer --branch "<type>/<short-kebab-description>" --intent "<the operator's own ask, close to verbatim>" --spec "<your build instructions, only what the intent requires>"`
   `--branch` is required - always pass it, named per the `conventional-branches` scheme (`<type>/<short-kebab-case-description>`) and a new name; spawn errors otherwise.
   The worker's agent and model come from the role's pool in `.chief/config/agents` (then the global pool) unless the operator names one: then add `--agent <agent[:model]>` and/or `--model <model>`. Spawn prints the chosen `agent:`; `${CLAUDE_PLUGIN_ROOT}/bin/chief-agents.sh` lists the agent each role would get now, marking a role that falls back to the global pool.
   Keep `--intent` narrow - it becomes the acceptance criteria. Keep `--spec` to only what's needed; a generalization or extra hardening nobody asked for is a note for later, not something to build now.
   This creates an isolated worktree+branch, renders the brief, and launches the builder. It also marks the backlog item in-flight if it exists.
   Returns once the builder's first turn has started (typically seconds) - it doesn't wait for that turn to finish. Still run it in the background (e.g. `run_in_background` on the Bash tool, or your host's equivalent) rather than the foreground as good practice.

3. **It runs on its own.** `${CLAUDE_PLUGIN_ROOT}/bin/chief-watch.sh` (armed by a Stop hook, zero model cost) polls it between your turns and only interrupts you when it's finished, failed, blocked, or needs a decision. On `blocked` or `needs-decision`, run `${CLAUDE_PLUGIN_ROOT}/bin/chief-backlog.sh hold <id> "<why, one line>"`.

4. **Check on it anytime:**
   `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-crew-state.sh <id>` - deterministic current state (working/done/blocked/needs-decision/failed/stale) plus a `[mode: builder|researcher|brainstormer]` tag. An idle brainstormer reads `working · awaiting operator in pane` (not stale) until `CHIEF_INTERACTIVE_STALE_AFTER_SECS`, default 4h, then `stale`: ask the operator whether to keep it.

5. **Steer it if needed:**
   `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-send.sh <id> "<instruction>"` - delivered through a durable inbox the builder acknowledges; safe to send mid-task. If the item is `held`, move it back with `${CLAUDE_PLUGIN_ROOT}/bin/chief-backlog.sh status <id> in-flight` once you've sent the unblocking instruction.

6. **If it's stuck**, escalate cheapest first:
   - `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-control.sh <id> interrupt` (nudge; it keeps running) + a corrective `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-send.sh`
   - `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-control.sh <id> relaunch --note "<progress so far>"` only if genuinely wedged - the replacement gets the same worktree and commits but none of the conversation, so the note is all it has. Same backend round-trip as spawn (step 2) - run it in the background too.

7. **Review and report** - your `state/<id>.lifecycle` has the exact next actions (review, report, hold).

## After the operator responds

Do exactly what they decide, nothing more:

- **Not satisfied** - move the task back to in-flight (`${CLAUDE_PLUGIN_ROOT}/bin/chief-backlog.sh status <id> in-flight`) before sending further instructions, then `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-send.sh <id> "<instruction>"` back to the builder, or send the researcher to investigate further.
- **Ready to land** (builder only) - compose a conventional-commit-style title and a structured body yourself (the same way this project's own PR conventions - a `conventional-pull-requests`-style skill if installed, or its CLAUDE.md/AGENTS.md rules - would produce), then `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-open.sh <id> --confirm --title "<title>" --body "<body>"` to push and open a PR/MR. `--title`/`--body` are required - you must compose them yourself, there is no auto-derived fallback.
- **Accepted** - builder: `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-merge.sh <id> --confirm` (merges the open PR, defaults to squash). Researcher or brainstormer to be built on: see "Handing off" below.
- **Accepted as-is** (researcher or brainstormer) - `${CLAUDE_PLUGIN_ROOT}/bin/chief-backlog.sh done <id>` then `${CLAUDE_PLUGIN_ROOT}/bin/chief-teardown.sh <id>` discards the worktree; the report at `.chief/data/<id>/report.md` survives.

`${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-open.sh`, `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-update.sh`, and `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-merge.sh` all require `--confirm` - pass it only once the operator has explicitly said so in this conversation.

## The brainstormer

Spawn it as in step 2 (`--mode brainstormer`, `--intent` = the operator's idea). Spawn prints `attach: ...`: tell the operator that line so they can attach and talk to it directly. Then step back: you never relay the conversation or answer for the operator, and the brainstormer's questions go in its pane, not through `needs-decision`. Its end result is a spec in `report.md` (goal, scope, acceptance criteria, decisions with rationale); it reports `done` only after the operator confirms it there. Later `crew-state` and the session digest repeat the `[attach: ...]` hint while it runs.

## Handing off a researcher or brainstormer

A done researcher or brainstormer with a report can be followed by a **successor** - a new worker in a fresh worktree whose brief carries the report (earlier stages are linked). Targets: a builder (the usual end of a brainstormer's spec), a researcher (a brainstormer's open question to spike), or, from a researcher, a brainstormer (findings into a spec). Never the source's own role. A brainstormer's spec reaches the successor as operator-approved and authoritative; a researcher's report as context. The report is the whole handoff, so skim it first and send the source back (`chief-send.sh`) to fix a thin one - it must stand alone for an agent that saw none of the conversation.

The successor runs the **target role's** configured agent, not the source's, so a strong brainstormer does not make an expensive builder. Carrying the source's agent over takes an explicit `--agent`, which runs the successor on that model - say so in the go-ahead.

1. Propose the branch (`conventional-branches` scheme) and preview the agent: `${CLAUDE_PLUGIN_ROOT}/bin/chief-spawn.sh <new-id> <project-dir> --mode <builder|researcher|brainstormer> --from <id> --branch "<type>/<short-kebab-description>" --intent "<ask>" --dry-run` prints the exact `agent:` and `launch:` (a weighted or random pool is printed as the pool - the pick happens at spawn). It creates nothing.
2. Ask the operator's go-ahead naming that agent and branch, and that the source's session ends (a brainstormer's pane closes; its report survives under `.chief/data/<id>/`).
3. On the go-ahead, file `<new-id>` (`chief-backlog.sh add`), then `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-promote.sh <id> --to <role> --as <new-id> --branch "<branch>" --intent "<ask>" [--spec "<instructions>"]` - a wrapper that runs `chief-spawn.sh --from` and then tears the source down. `--keep-source` leaves it running; `--dry-run` previews. Same backend round-trip as spawn (step 2) - run it in the background too.

## Once a PR is open

- **A follow-up commit lands** - push it and, if the PR's description no longer matches, refresh it: `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-update.sh <id> --confirm [--title "<title>"] [--body "<body>"]`. Always pushes the branch's new commits; `--title`/`--body` are optional here - omit both for a plain push-only update. Requires `--confirm` the same way `chief-pr-open.sh` does.
- **Check it** - `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-state.sh <id>` for its current state (open/draft/mergeable/checks).
- **Review it** - `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-review.sh <id> --comment "<text>"` or `--request-changes "<text>"`. Add `--file <path> --line <N>` to a `--comment` call to attach it to a specific line instead of posting top-level (only valid with `--comment`, not `--request-changes`).
- **Approve it** - `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-approve.sh <id>`.
- **Merge it** - `${CLAUDE_PLUGIN_ROOT}/bin/pr/chief-pr-merge.sh <id> --confirm`. Defaults to `--squash` - the recommended strategy, and applied uniformly by this script itself rather than left to each provider's own default (GitHub already defaults to squash; GitLab and Azure DevOps default to a plain merge). Pass `--merge` or `--rebase` explicitly only if the operator asks for one of those instead.
- **Abandon** - `${CLAUDE_PLUGIN_ROOT}/bin/task/chief-control.sh <id> exit` stops the worker without discarding its worktree or commits. To discard the work too, `${CLAUDE_PLUGIN_ROOT}/bin/chief-teardown.sh <id> --abandon` force-discards it even though nothing landed - only on the operator's explicit instruction.
- **Landed** - `${CLAUDE_PLUGIN_ROOT}/bin/chief-backlog.sh done <id>` (if not already), then `${CLAUDE_PLUGIN_ROOT}/bin/chief-teardown.sh <id>`. Without `--abandon`, teardown refuses unless the branch is reachable from the default branch.

## Backlog reference

`${CLAUDE_PLUGIN_ROOT}/bin/chief-backlog.sh add|status|note|hold|done|list|next|show <id> ...` - one markdown file (`.chief/data/backlog.md`), statuses are `queued|in-flight|held|done`. Use `hold <id> "<reason>"` for anything that needs an operator decision before it can proceed.

## What NOT to do

- Don't spawn a worker agent to answer something you can check yourself with a quick, read-only look - dispatch is for changes and real investigation, not a single lookup. Any actual change to a project, however small, still goes to a worker agent.
- Don't invent scope in `--spec` beyond what `--intent` asks for.
