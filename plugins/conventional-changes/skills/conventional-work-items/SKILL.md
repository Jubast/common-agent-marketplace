---
name: conventional-work-items
description: File or update an issue (any tracked work item) with a conventional title and a structured description. Use when the user wants to open, create, or update an issue, task, ticket, or work item (PBI, user story, epic, bug), or invokes an issue-creation or issue-update command.
---

# Filing or Updating a Work Item

## Important Rules

- Describe the outcome, not the mechanism.
- Tool and platform choice (`gh issue create`, Jira, Linear, Azure Boards,
  GitLab issues, a plain markdown backlog, etc.) is your call — this skill
  only specifies the content.
- Relate work items through the tracker's links (step 5).

## Workflow

### 1. Determine the Type Model

Use the work-item types the tracker offers (its type list, or the type of an
existing item), narrowed by any in `CLAUDE.md` / `AGENTS.md`. If it has none,
or you can't determine them, use the flat model: a plain issue with no types.
Use only types that exist.

### 2. Pick the Role

Map the tracker's types onto a role and pick the one that matches the request.
Tell the user the chosen type.

| Role | Typical tracker names |
|------|-----------------------|
| container | Epic, Feature, Initiative |
| deliverable | PBI, User Story, Story, Requirement |
| unit of work | Task, Sub-task |
| defect | Bug, Incident |
| investigation | Spike |
| plain issue | Issue |

Names vary by tracker: pick by what the item is, not its name. One request is
a deliverable; a grouping of child items is a container. If several types
fit, take the closest; if none fits, use the most general one. In the flat
model the role is always plain issue.

### 3. Write the Title

Use the first that applies:
1. A title convention in the project's template or `CLAUDE.md` / `AGENTS.md`.
2. The tracker has a type field: write the summary only, with no type prefix.
3. Otherwise (flat model): `type(optional scope): summary`.

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

### 4. Write the Description

Use the first of these that exists for the chosen role:
1. A project template for that type:
   - GitHub: `.github/ISSUE_TEMPLATE/`
   - GitLab: `.gitlab/issue_templates/`
   - Azure Boards, Jira, Linear keep templates in the tool; use one if you
     can read it.
   - Any platform: `.work-items/templates/<role>.md`, named like this
     skill's `templates/` files.
2. Conventions in `CLAUDE.md` / `AGENTS.md`.
3. This skill's `templates/<role>.md` (`plain-issue`, `unit-of-work`, ...).
   Read only the file for the chosen role.

Replace the guidance text; drop sections that don't apply. If the tracker has
a field for a section (e.g. Acceptance Criteria, Repro Steps), put that
content in the field, not under a heading.

### 5. Relate to Other Items

Relate work items with the tracker's native links (parent, child, blocking,
related, duplicate), only to items the user named or you created. If you
can't set a link, tell the user which are missing. If the tracker has no link
type for a relation, put one line in the description using its reference
syntax. Create child items only when the user asks or project conventions
require it.

Closing keywords (`Closes #N`) belong in commits and pull requests, not here.
