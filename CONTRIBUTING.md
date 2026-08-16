# Contributing

## Adding a new plugin

Each plugin is a self-contained directory under `plugins/<new-plugin-name>/`:

```
plugins/<new-plugin-name>/
├── .claude-plugin/
│   └── plugin.json      # name, description, version, author, license
├── skills/               # optional — see "Skill conventions" below
│   └── <skill-name>/
│       └── SKILL.md
├── agents/               # optional — see "Agent conventions" below
│   └── <agent-name>.md
└── README.md
```

1. Create `plugins/<new-plugin-name>/.claude-plugin/plugin.json` — `name`
   (kebab-case, matches the directory), `description`, `version`, `author`
   (the marketplace owner unless the plugin has a different author),
   `license`.
2. Add the plugin's skill(s) and/or agent(s), following the conventions
   below.
3. Write `plugins/<new-plugin-name>/README.md` describing the plugin.
4. Add an entry to **both** marketplace manifests' `plugins` arrays — see
   "Claude Code / Copilot CLI compatibility" below for why there are two:
   - `.claude-plugin/marketplace.json` (Claude Code)
   - `.github/plugin/marketplace.json` (Copilot CLI)
5. Validate every manifest parses: `python3 -m json.tool <path>`.

## Skill conventions

- One directory per skill under `<plugin>/skills/<skill-name>/SKILL.md`.
- Frontmatter: `name` (matches the directory name) and `description`
  (states when the skill should be used — specific triggers, not vague
  topics).
- Body: purpose, when to use, a concrete step-by-step process, and what
  the agent should output when done.

## Agent conventions

- One file per agent under `<plugin>/agents/<agent-name>.md`.
- Frontmatter: `name` (matches the filename), `description` (include one
  or two usage examples showing when Claude should invoke it), and
  `model`.
- Body: the agent's process, output format, and an explicit "when NOT to
  use this agent" section so overlapping agents stay distinguishable.

## Claude Code / Copilot CLI compatibility

Both platforms are built on the same Open Plugin Spec, but the
marketplace-level manifest is maintained as two separate files by design:

- **`plugin.json` is shared, no duplication.** Both platforms read
  `<plugin-dir>/.claude-plugin/plugin.json` directly — one file per
  plugin, regardless of which marketplace manifest pointed to it.
- **`marketplace.json` is maintained separately per platform, on
  purpose.** Claude Code reads `.claude-plugin/marketplace.json`.
  Copilot CLI reads `.github/plugin/marketplace.json` — Copilot CLI also
  accepts `.claude-plugin/marketplace.json` as a fallback per its docs,
  but this repo keeps the two marketplace listings independent rather
  than relying on that undocumented-precedence fallback. **Every plugin
  needs an entry in both files** (see step 4 above) — nothing keeps them
  in sync automatically, and their per-plugin metadata (author,
  description, version) is allowed to diverge between the two listings.
- `skills/<name>/SKILL.md` uses the same format on both platforms.
- **Agents are Claude Code-only for now.** Claude Code loads every `*.md`
  file under `agents/`; Copilot CLI loads only files named `*.agent.md` in
  the same directory. Because a `.agent.md` file still matches `*.md`,
  adding a Copilot-formatted agent alongside a Claude Code one in the same
  directory would make Claude Code attempt to load it too, with
  frontmatter it doesn't expect (`tools` as an array, no `model` field).
  This hasn't been verified against the real Claude Code plugin loader,
  so until it has, agents in this marketplace target Claude Code only. If
  you need a Copilot CLI agent, test the collision behavior first and
  update this note with what you find.

## Tooling

Manifests are still validated by hand (JSON parses, referenced paths
exist, frontmatter fields are present).

Plugins with real executable code or checkable skill behavior get actual
tests. See [docs/testing.md](docs/testing.md) for the two tiers
(`tests/<plugin-name>/` for non-LLM mechanics, `tests/claude-code/` for
skill-behavior checks) and how to add coverage when you add a new plugin.
No CI workflow yet — tests run locally, by hand.
