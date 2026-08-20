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

The `skills/convert-pdf-to-md/` directory originated as a verbatim copy of:

- Source repository: [github/awesome-copilot](https://github.com/github/awesome-copilot)
- Path: [`skills/convert-pdf-to-md`](https://github.com/github/awesome-copilot/tree/e4a1f57fd9d8c22d2a345d498fe6fde306c6456e/skills/convert-pdf-to-md)
- Commit: [`e4a1f57fd9d8c22d2a345d498fe6fde306c6456e`](https://github.com/github/awesome-copilot/commit/e4a1f57fd9d8c22d2a345d498fe6fde306c6456e)

Besides the plugin scaffolding (`plugin.json`, this README) added locally to
fit this marketplace's conventions, this repo's own test suite
(`tests/claude-code/`) later found that the skill's "don't parse the PDF
directly" rule didn't actually stop agents from using the Read tool on the
`.pdf` file. `SKILL.md` was subsequently modified locally to close that
loophole and trim its frontmatter `description`, and
`scripts/convert_pdf_to_md.py` had dead code removed — see git history for
the exact diff from the upstream commit above.

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
