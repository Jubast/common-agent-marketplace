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

- [`convert-pdf-to-md`](plugins/convert-pdf-to-md/) — converts PDF
  documents into Markdown so their contents can be accurately analyzed,
  summarized, searched, or extracted from.
- [`clean-code`](plugins/clean-code/) — helps AI agents design, write, and
  review C#/.NET code following the principles in Robert C. Martin's Clean
  Code, translated into .NET idiom.
- [`clean-architecture`](plugins/clean-architecture/) — helps AI agents
  design, write, and review C#/.NET code and solution structure
  following the principles in Robert C. Martin's Clean Architecture,
  translated into .NET idiom.

## Adding a plugin

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Repo layout

```
common-agent-marketplace/
├── .claude-plugin/
│   └── marketplace.json      # lists every plugin in this repo
├── plugins/
│   └── <plugin-name>/        # one directory per plugin
├── CONTRIBUTING.md
└── LICENSE
```
