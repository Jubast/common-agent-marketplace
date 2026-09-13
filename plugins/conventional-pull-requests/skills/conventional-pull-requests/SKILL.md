---
name: conventional-pull-requests
description: Open a pull request (or merge request) with a conventional-commit-style title and a structured, review-ready body. Gathers the branch's commits and diff against the base branch, drafts the title/body, and creates it with the project's own PR/MR tooling. Use when the user wants to open or create a pull request, or invokes a PR-creation command.
---

# Creating a Pull Request

Package the branch's changes into a pull request (or merge request) that's
easy to review, with a conventional-commit-style title and a structured
body — regardless of which hosting platform or CLI the project uses (GitHub
`gh`, GitLab `glab`, Bitbucket, or otherwise).

## 0. Check for Project-Specific Conventions

Look for repo-specific PR conventions before applying the defaults below:
- `.github/PULL_REQUEST_TEMPLATE.md` (or `.github/PULL_REQUEST_TEMPLATE/`)
- `.gitlab/merge_request_templates/`
- `CONTRIBUTING.md` in the project root
- `CLAUDE.md` / `AGENTS.md` in the project root
- `.claude/CLAUDE.md`

If a PR/MR template exists, fill it in rather than freelancing the body's
section layout. If any of these files specify title format, required
sections, which CLI to use, or other conventions, follow them —
project-specific rules override the defaults below.

## 1. Identify the Hosting Platform and Base Branch

Check the remote to figure out which platform and CLI to use
(`git remote get-url origin`), and don't assume GitHub/`gh` by default:
use whatever the project already relies on (look for existing usage of
`gh`, `glab`, or similar in scripts, CI config, or CONTRIBUTING.md).

Find what branch this one will merge into (e.g. `git remote show origin`,
or check for a tracked upstream). Default to `main` if nothing more
specific is configured.

## 2. Prepare the Branch

```bash
git fetch origin
git log <base>..HEAD --oneline
git diff <base>...HEAD --stat
```

Make sure the branch is pushed and up to date before opening the PR/MR.

## 3. Gather the Change Set

Understand everything the PR will contain, the same way you'd gather commits
for `conventional-commits`:
- `git log <base>..HEAD` to see the commits already made on this branch
  (if the branch was committed with `conventional-commits`, these are
  already conventionally typed and are your best signal for the PR's type
  and scope)
- `git diff <base>...HEAD` to see the full accumulated change set
- `git status` to confirm the working tree is clean (uncommitted changes
  won't be part of the PR)

If there are uncommitted changes, point this out — don't silently leave them
out of the PR.

## 4. Write the Title

Format: `type(optional scope): description`

| Type | When |
|------|------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Changes that do not affect the meaning of the code (formatting, semicolons, etc) |
| `refactor` | A code change that neither fixes a bug nor adds a feature |
| `perf` | A code change that improves performance |
| `test` | Adding missing tests or correcting existing tests |
| `build` | Changes that affect the build system or external dependencies |
| `ci` | Changes to CI configuration files and scripts |
| `chore` | Other changes that don't modify src or test files |

Pick the type that best represents the overall change (if commits span
multiple types, choose the one that best characterizes the PR as a whole —
usually the most impactful one, not a mechanical concatenation).

Breaking changes get an exclamation mark after the type/scope, for example:
`feat!:` or `feat(api)!:`.

Use imperative mood in the description ("add feature" not "added feature").

Examples:
- `feat: add dark mode toggle to settings page`
- `fix(checkout): prevent duplicate form submissions`
- `refactor!: extract auth middleware into shared module`

## 5. Write the Body

Structure the body with clear sections. Absent a repo-specific template, use:

```markdown
## Summary

[1-3 sentences on what this PR does and why]

Closes #123

## Changes

- [Bullet list of the key changes, grouped logically]

## Test plan

- [How this was verified — tests run, manual checks, etc.]

## Breaking changes

[Only include this section if there are breaking changes. Describe what
breaks and how to migrate.]
```

Base the content on the actual diff and commit log from step 3 — don't
speculate about changes that aren't there. Link related issues (`Closes
#123`, `Fixes #456`) if the project tracks them.

## 6. Self-Review

Before creating the PR/MR:
- Read through the diff yourself
- Remove debug code (stray `console.log`/`print`, `TODO`s, commented-out code)
- Run the project's existing test/lint/typecheck commands if configured, and
  confirm they pass
- Check for files that shouldn't be committed (`.env`, secrets, lockfile
  conflicts)

## 7. Create the Pull Request

Announce the title and body, then create it immediately with whatever CLI
the project uses — don't wait for approval before creating it. For example,
with `gh`:

```bash
git push -u origin HEAD
gh pr create --title "type(scope): description" --body "$(cat <<'EOF'
## Summary

...

## Changes

- ...

## Test plan

- ...
EOF
)"
```

Or with `glab` (`glab mr create --title "..." --description "..."`), or
whatever equivalent the project already relies on.

If the user gives feedback after the PR/MR is created (wrong title, missing
section, wrong scope, etc.), incorporate it — edit it in place (`gh pr
edit`, `glab mr update`, etc.) — but don't hold up creation on upfront
approval.

---

## Important Rules

- NEVER add a "Generated by", "Generated with Claude Code", "Co-Authored-By",
  session-link, or any other AI-attribution or signoff line anywhere in the
  PR/MR title or body — it must read as if written entirely by the human
  author. This is a hard requirement from the plugin's author, not a
  suggestion.
- Never assume GitHub/`gh` by default — use whatever hosting platform and
  CLI the project already relies on.
- Keep the title concise but descriptive
- Use imperative mood in the title's description
- Scope is optional but helpful for larger codebases
- Breaking changes should include an exclamation mark after the type/scope, for example: `feat!:` or `feat(api)!:`
- Follow a repo-specific PR/MR template or contribution guide when one exists, over the default section layout above
