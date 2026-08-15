# example-plugin

A minimal, working example plugin for `common-agent-marketplace`. It exists
to be copied — see the `example-skill` skill in this plugin for the exact
steps to turn a copy of this directory into a new plugin.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by both
  Claude Code and Copilot CLI.
- `skills/example-skill/` — a working skill that walks through adding a new
  plugin to this marketplace.
- `agents/example-reviewer.md` — a working agent that checks a plugin
  directory's structure (manifest validity, marketplace registration,
  skill/agent frontmatter) before it's registered.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install example-plugin
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install example-plugin
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)
