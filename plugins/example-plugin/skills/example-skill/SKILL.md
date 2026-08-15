---
name: example-skill
description: Use when adding a new plugin to this marketplace repository. Walks through copying the example plugin, updating its manifest, and registering it in marketplace.json.
---

# Adding a Plugin to This Marketplace

## Purpose

Every plugin in this marketplace is a self-contained directory under
`plugins/` with its own manifest, skills, and agents. This skill walks
through adding a new one correctly, so the plugin is discoverable by both
Claude Code and Copilot CLI.

## When to use

Use this skill whenever the user asks to add, create, or scaffold a new
plugin in this repository.

## Process

1. Copy the template: `cp -r plugins/example-plugin plugins/<new-plugin-name>`
2. Edit `plugins/<new-plugin-name>/.claude-plugin/plugin.json`:
   - Set `name` to `<new-plugin-name>` (kebab-case, matches the directory).
   - Rewrite `description`, reset `version` to `1.0.0`.
   - Update `author` if the new plugin has a different author than the
     marketplace owner.
3. Replace or remove the example skill/agent under
   `plugins/<new-plugin-name>/skills/` and `plugins/<new-plugin-name>/agents/`
   with the plugin's real content, following the same frontmatter
   conventions shown in `plugins/example-plugin/skills/example-skill/SKILL.md`
   and `plugins/example-plugin/agents/example-reviewer.md`.
4. Rewrite `plugins/<new-plugin-name>/README.md` to describe the new
   plugin instead of the template.
5. Register the plugin in the root `.claude-plugin/marketplace.json` by
   adding an entry to the `plugins` array:
   ```json
   {
     "name": "<new-plugin-name>",
     "description": "<matches plugin.json description>",
     "version": "1.0.0",
     "source": "./plugins/<new-plugin-name>/",
     "author": {
       "name": "Jubast",
       "email": "30406814+Jubast@users.noreply.github.com"
     }
   }
   ```
6. Validate both manifests parse as JSON:
   `python3 -m json.tool plugins/<new-plugin-name>/.claude-plugin/plugin.json`
   and `python3 -m json.tool .claude-plugin/marketplace.json`.

## Output

A new `plugins/<new-plugin-name>/` directory registered in
`marketplace.json`, installable in Claude Code via
`/plugin marketplace add` + `/plugin install <new-plugin-name>`, and in
Copilot CLI via `copilot plugin marketplace add` + `copilot plugin install`.
