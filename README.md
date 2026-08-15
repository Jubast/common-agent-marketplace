# common-agent-marketplace

A marketplace of plugins — skills and agents — for Claude Code and GitHub
Copilot CLI.

## What this is

Each plugin under `plugins/` is a self-contained directory with its own
manifest, skills, and agents. The root `.claude-plugin/marketplace.json`
lists every plugin and where to find it. Manifests and skills are read
directly by both Claude Code and Copilot CLI — see
[CONTRIBUTING.md](CONTRIBUTING.md) for exactly what's shared between the
two platforms and what isn't (agents, for now).

## Installing

**Claude Code:**

```
/plugin marketplace add <org>/<repo>
/plugin install <plugin-name>
```

**Copilot CLI:**

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install <plugin-name>
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)

## Available plugins

- [`example-plugin`](plugins/example-plugin/) — a minimal working example;
  copy it to start a new plugin.

## Adding a plugin

See the `example-skill` skill inside `example-plugin`
(`plugins/example-plugin/skills/example-skill/SKILL.md`), or read
[CONTRIBUTING.md](CONTRIBUTING.md).

## Repo layout

```
common-agent-marketplace/
├── .claude-plugin/
│   └── marketplace.json      # lists every plugin in this repo
├── plugins/
│   └── example-plugin/       # one directory per plugin
├── CONTRIBUTING.md
└── LICENSE
```
