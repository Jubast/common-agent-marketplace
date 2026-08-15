# Common Agent Marketplace — Scaffold Design

Date: 2026-08-15

## Purpose

`common-agent-marketplace` is a repo for hosting multiple independent plugins
(skills + agents) under a single marketplace, usable from both Claude Code and
GitHub Copilot CLI.

Both tools read the same "Open Plugin Spec" `marketplace.json` /
`plugin.json` manifest shape, and Copilot CLI explicitly accepts the
`.claude-plugin/` directory as a valid manifest location (alongside its own
`.github/plugin/`) — see
[GitHub Copilot CLI plugin marketplace docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-marketplace)
and the
[CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference).
So the manifests and skills built here are genuinely dual-platform, not just
Claude Code with a promise of future Copilot support. Agents are the one
component kept Claude-Code-only for now — see "Copilot CLI compatibility"
below for why.

## Structure

```
common-agent-marketplace/
├── .claude-plugin/
│   └── marketplace.json          # lists all plugins, points to ./plugins/<name>/
├── plugins/
│   └── example-plugin/           # working example + copy-paste template
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── skills/
│       │   └── example-skill/
│       │       └── SKILL.md
│       ├── agents/
│       │   └── example-reviewer.md
│       └── README.md
├── README.md
├── CONTRIBUTING.md
├── LICENSE
└── .gitignore
```

## Copilot CLI compatibility

What's shared vs. platform-specific, and why:

- **`marketplace.json` and `plugin.json` — shared, unmodified.** Both fields
  sets match: `name`, `owner`/`author`, `description`, `version`, `plugins`
  array with `name`/`source`/`description`, etc. Copilot CLI's manifest
  lookup order includes `.claude-plugin/marketplace.json` and
  `.claude-plugin/plugin.json` directly, so the files Claude Code already
  reads need no duplication or adapter step.
- **Skills — shared, unmodified.** Both platforms read `skills/NAME/SKILL.md`
  with the same YAML frontmatter (`name`, `description`) and Markdown body.
- **Agents — Claude Code format only, by design.** Claude Code scans *every*
  `*.md` file in `agents/`. Copilot CLI scans only files named `*.agent.md`,
  also (by default) inside `agents/`. Since a `.agent.md` file still matches
  `*.md`, putting a Copilot-formatted agent file in the same `agents/`
  directory means Claude Code would attempt to load it too — and its
  frontmatter (`tools` as a YAML array, no `model` field) doesn't match what
  Claude Code's own agent frontmatter expects. There's no documented,
  verified way to keep the two from colliding in one shared directory, so
  this scaffold ships agents in Claude Code's format only. Adding a
  Copilot-formatted sibling agent is a follow-up once Copilot CLI agent
  loading can be tested directly, not something to guess at here.

## Components

### `.claude-plugin/marketplace.json`

Marketplace manifest, shared by both platforms (see above). Fields:
`name: common-agent-marketplace`, `description`,
`owner: { name: Jubast, email: 30406814+Jubast@users.noreply.github.com }`
(pulled from the local `git config --global user.name`/`user.email`), and a
`plugins` array with one entry for `example-plugin`
(`source: ./plugins/example-plugin/`).

### `plugins/example-plugin/`

A minimal, clearly-labeled template plugin that is also a working example:

- `.claude-plugin/plugin.json` — plugin manifest (`name`, `description`,
  `version`, `author`, `license`, `keywords`), same shape as
  `plugin.json` in sibling repos (rockstar-prompter, GodotPrompter) and
  directly readable by Copilot CLI from the same path. `author` uses the
  same `git config` name/email as the marketplace `owner` above.
- `skills/example-skill/SKILL.md` — a skill with YAML frontmatter
  (`name`, `description`) and a body demonstrating the standard sections
  (purpose, when to use, process, output). Content is a genuinely minimal
  but functional skill, not a stub.
- `agents/example-reviewer.md` — an agent with YAML frontmatter (`name`,
  `description` with usage examples, `model: inherit`) and a body
  demonstrating process/output-format conventions, mirroring the shape of
  agents in `GodotPrompter/agents/*.md`.
- `README.md` — explains what the example plugin demonstrates and how to
  copy it to start a new plugin.

New plugins are added by copying `plugins/example-plugin/`, renaming it,
editing its `plugin.json`, and adding an entry to the root
`marketplace.json`.

### Root docs

- `README.md` — what the marketplace is, how a user installs it in Claude
  Code (`/plugin marketplace add <repo>`) and in Copilot CLI
  (`copilot plugin marketplace add <repo>`), how to browse/install individual
  plugins, and repo layout.
- `CONTRIBUTING.md` — steps to add a new plugin, skill/agent authoring
  conventions, and the agents compatibility note from "Copilot CLI
  compatibility" above.
- `LICENSE` — MIT.
- `.gitignore` — standard OS/editor/node ignores.

## Explicitly out of scope

- No CI workflow, devcontainer, pre-commit config, or test harness — there is
  no generation/adapter step yet to validate, so tooling would have nothing
  to check. Add these when a real validation need appears.
- No Copilot-formatted agent file (`agents/*.agent.md`) — deferred per the
  "Copilot CLI compatibility" section above; this is the only piece of the
  scaffold that is Claude-Code-only.
- No `.github/instructions/`, `.github/prompts/`, or `.github/chatmodes/`
  files — those are VS Code Copilot Chat customization formats, a separate
  concern from Copilot CLI plugins, and out of scope here.
- No second example plugin — one is enough to demonstrate the pattern.

## Testing / verification

This is static scaffolding (JSON + Markdown, no executable code). Verification
is: `marketplace.json` and `plugin.json` are valid JSON, the paths they
reference exist, and the example skill/agent files are well-formed per the
frontmatter conventions observed in sibling repos.
