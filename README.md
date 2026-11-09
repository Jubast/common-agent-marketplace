# common-agent-marketplace

A marketplace of plugins — skills and hooks — for Claude Code, with skills
also usable from GitHub Copilot CLI.

## What this is

Each plugin under `plugins/` is a self-contained directory with its own
manifest and skills, plus hooks where needed. The root
`.claude-plugin/marketplace.json` lists every plugin and where to find it.
Manifests and skills are read directly by both Claude Code and Copilot CLI;
no plugin ships agents yet, and `using-orca` relies on Claude Code hooks
(`chief` has its own adapters for Claude Code, Codex CLI and Copilot CLI).
See [CONTRIBUTING.md](CONTRIBUTING.md) for what's shared between the two
platforms and what isn't.

## Installing

**Claude Code:**

```
/plugin marketplace add Jubast/common-agent-marketplace
/plugin install <plugin-name>
```

**Copilot CLI:**

```
copilot plugin marketplace add Jubast/common-agent-marketplace
copilot plugin install <plugin-name>
```

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
- [`using-orca`](plugins/using-orca/) — teaches Claude Code to recognize
  and require the orca-cli and orchestration skills for worktree/agent-
  dispatch work in Orca-managed environments.
- [`conventional-changes`](plugins/conventional-changes/) — files or
  updates the issue or work item the work is tracked against, names the
  branch, commits changes using micro commits with conventional commit
  messages, then creates or updates a pull/merge request with a
  conventional-commit-style title and structured body. A SessionStart hook
  requires all four skills.
- [`chief`](plugins/chief/) — a lightweight supervisor for coding agents
  (Claude Code, Codex CLI, Copilot CLI): dispatches work to isolated
  builder/researcher/reviewer/brainstormer agents over the herdr or Orca
  backend, tracks a plain-markdown backlog, and supervises them with a
  near-zero-token watch loop.

## Adding a plugin

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Repo layout

```
common-agent-marketplace/
├── .claude-plugin/
│   └── marketplace.json      # lists every plugin in this repo
├── .github/workflows/        # tags marketplace releases
├── .devcontainer/            # dev environment
├── docs/                     # repo docs (testing)
├── plugins/
│   └── <plugin-name>/        # one directory per plugin
├── scripts/                  # devcontainer setup scripts
├── tests/                    # per-plugin and marketplace tests
├── CONTRIBUTING.md
└── LICENSE
```
