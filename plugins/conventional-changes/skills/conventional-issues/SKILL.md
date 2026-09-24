---
name: conventional-issues
description: File or update an issue with a conventional title and a structured description. Use when the user wants to open, create, or update an issue, task, or ticket, or invokes an issue-creation or issue-update command.
---

# Filing or Updating an Issue

## Important Rules

- Describe the outcome, not the mechanism.
- Tool and platform choice (`gh issue create`, Jira, Linear, Azure Boards,
  GitLab issues, a plain markdown backlog, etc.) is the agent's call — this
  skill only specifies the content.

## Workflow

### 1. Write the Title

Format: `type(optional scope): summary`

| Type | When |
|------|------|
| `bug` | Something is broken or behaves unexpectedly |
| `feature` | New capability or enhancement request |
| `chore` | Maintenance, tooling, dependency, or cleanup work |
| `docs` | Documentation-only work |
| `spike` | Time-boxed research or investigation |

Examples:
- `bug: checkout form allows duplicate submissions on double-click`
- `feature: add dark mode toggle to settings page`
- `spike: evaluate websocket libraries for live updates`

If the project's issue template or `CLAUDE.md`/`AGENTS.md` already defines
its own title convention (a type prefix, a label taxonomy, a platform
issue-type field), follow that instead.

### 2. Write the Description

Check for an existing template first, in this priority order:
1. A platform-native issue template — GitHub's `.github/ISSUE_TEMPLATE/`,
   GitLab's `.gitlab/issue_templates/`, an Azure Boards work item template,
   a Jira issue type scheme, a Linear template, etc.
2. Repo conventions in `CLAUDE.md` / `AGENTS.md`.
3. Otherwise, use this structure:

```markdown
## Context / Problem

1-3 sentences on what's wrong or missing, and why it matters.

## Repro

Steps to reproduce, if this describes a defect. Omit for feature/chore work.

1. ...
2. ...
3. Observed: ... / Expected: ...

## Environment

OS, version/commit, browser/runtime, etc. Omit if not relevant.

## Acceptance Criteria

- [ ] Criterion the work must satisfy to be considered done
- [ ] Another criterion

## Suggestions

Optional: a known approach or fix. Omit if there isn't one.

## Related

- Related to #12
- Blocks #45
```
