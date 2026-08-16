# Contributing

## Adding a new plugin

1. Copy `plugins/example-plugin/` to `plugins/<new-plugin-name>/`.
2. Update `plugins/<new-plugin-name>/.claude-plugin/plugin.json` — `name`,
   `description`, `version`, and `author` if different from the
   marketplace owner.
3. Replace the example skill(s) and agent(s) with the plugin's real
   content.
4. Rewrite `plugins/<new-plugin-name>/README.md`.
5. Add an entry to `.claude-plugin/marketplace.json`'s `plugins` array.
6. Validate both manifests parse: `python3 -m json.tool <path>`.

This exact process is also captured as a working skill:
`plugins/example-plugin/skills/example-skill/SKILL.md`.

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

Both platforms are built on the same Open Plugin Spec:

- `marketplace.json` and `plugin.json` are read directly from
  `.claude-plugin/` by both Claude Code and Copilot CLI — one manifest,
  no duplication.
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
exist, frontmatter fields are present) — see the `example-reviewer` agent
in `plugins/example-plugin/agents/` for a scripted version of that
checklist you can run against a new plugin directory.

Plugins with real executable code or checkable skill behavior get actual
tests. See [docs/testing.md](docs/testing.md) for the two tiers
(`tests/<plugin-name>/` for non-LLM mechanics, `tests/claude-code/` for
skill-behavior checks) and how to add coverage when you add a new plugin.
No CI workflow yet — tests run locally, by hand.
