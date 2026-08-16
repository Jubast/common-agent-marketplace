# convert-pdf-to-md

Converts PDF documents into Markdown so their contents can be accurately
analyzed, summarized, searched, or extracted from.

## What's in here

- `.claude-plugin/plugin.json` — the plugin manifest, read directly by both
  Claude Code and Copilot CLI.
- `skills/convert-pdf-to-md/` — the skill: `SKILL.md`, a setup guide under
  `references/`, and a conversion script with pinned dependencies under
  `scripts/`.

## Provenance

The `skills/convert-pdf-to-md/` directory was copied verbatim from:

- Source repository: [github/awesome-copilot](https://github.com/github/awesome-copilot)
- Path: [`skills/convert-pdf-to-md`](https://github.com/github/awesome-copilot/tree/e4a1f57fd9d8c22d2a345d498fe6fde306c6456e/skills/convert-pdf-to-md)
- Commit: [`e4a1f57fd9d8c22d2a345d498fe6fde306c6456e`](https://github.com/github/awesome-copilot/commit/e4a1f57fd9d8c22d2a345d498fe6fde306c6456e)

Only the plugin scaffolding (`plugin.json`, this README) was added locally to
fit this marketplace's conventions; the skill content itself is unmodified.

## Using this plugin

Install the marketplace, then this plugin, from a Claude Code session:

```
/plugin marketplace add <org>/<repo>
/plugin install convert-pdf-to-md
```

Copilot CLI equivalent:

```
copilot plugin marketplace add <org>/<repo>
copilot plugin install convert-pdf-to-md
```

(Replace `<org>/<repo>` with this repository's path once it's pushed to
GitHub.)
