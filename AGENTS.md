# AGENTS.md

Instructions for agents working in this repo. `CLAUDE.md` is a symlink to this
file; edit `AGENTS.md`. See [ARCHITECTURE.md](ARCHITECTURE.md) for how the pieces
fit together and [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor workflow.

## What this repo is

A plugin marketplace for Claude Code; its manifests and skills are also read by
GitHub Copilot CLI. Most plugins are skills, some with a `SessionStart` hook.
`chief` is the only plugin with substantial bash code and CI.

## Scope

- Each `plugins/<name>/` is self-contained: its own manifest, skills, hooks and
  README. Don't make one plugin depend on another's files.
- `docs/superpowers/` and `.claude/` are gitignored local state. Don't commit them.

## Working rules

- **Commits, branches and PRs** follow
  [Commits and PRs](CONTRIBUTING.md#commits-and-prs).
- **No AI attribution** in commits or PRs: no `Co-Authored-By`, no "Generated
  with" line, no trailers.
- **Never bump `version` or `metadata.version`, and never tag by hand**, in a
  feature or fix PR. The one exception is a new plugin's initial `version`. See
  [Marketplace versions](CONTRIBUTING.md#marketplace-versions).
- **Chief tests** follow [tests/chief/README.md](tests/chief/README.md): the
  zero-cost stand-in agent, `eventually` instead of `sleep`, pinned exit codes.
  Never run `tests/chief/live/` unless asked.
- **Don't run `tests/claude-code/` or `tests/marketplace/` unprompted.** They
  drive the real CLIs and cost tokens.
- Never read or expose secrets.

## Docs that must stay in sync

- A plugin's description appears in its `plugin.json`, its `marketplace.json`
  entry and the root [README.md](README.md) plugin list. For chief it is also the
  first line of [plugins/chief/README.md](plugins/chief/README.md), verbatim.
- A plugin's `version` is the same in its `plugin.json` and its
  `marketplace.json` entry. For chief,
  `plugins/chief/.codex-plugin/plugin.json` carries that version too.
- A new chief backend, agent or CI job touches
  [plugins/chief/README.md](plugins/chief/README.md),
  [tests/chief/README.md](tests/chief/README.md),
  [docs/testing.md](docs/testing.md), the CI sentence in
  [CONTRIBUTING.md](CONTRIBUTING.md#tooling),
  [skills/setup/SKILL.md](plugins/chief/skills/setup/SKILL.md) and
  [tests.yml](.github/workflows/tests.yml).
- Chief's brief templates are pinned by
  [tests/chief/unit/templates.bats](tests/chief/unit/templates.bats).

## Verify

```bash
tests/chief/run-tests.sh tests/chief/unit   # chief changes; no backend, no agent
python3 -m json.tool <manifest>             # every manifest you touched
```

## Definition of done

### All

- No changes unrelated to the task.
- Every doc listed under "Docs that must stay in sync" that the change affects
  is updated.

### Builder

- `tests/chief/run-tests.sh tests/chief/unit` passes when `plugins/chief/` or
  `tests/chief/` changed.
- `python3 -m json.tool` parses every manifest the change touched.

### Reviewer

- The builder's commands above were re-run, not taken from the report.
- No `version`, `metadata.version` or tag changed outside a release PR, except
  a new plugin's initial `version`.
