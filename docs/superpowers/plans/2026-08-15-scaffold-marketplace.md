# Common Agent Marketplace Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold a Claude Code plugin marketplace repo — `.claude-plugin/marketplace.json` plus one working example plugin (`plugins/example-plugin/`) with a manifest, a functional skill, a functional agent, and docs — where the manifests and skills are also directly readable by GitHub Copilot CLI.

**Architecture:** Static scaffolding only — JSON manifests and Markdown skill/agent/doc files, no executable code. Each file follows the shape observed in sibling repos (`rockstar-prompter`, `GodotPrompter`) and documented in the [design spec](../specs/2026-08-15-scaffold-marketplace-design.md). "Tests" for this plan are validation commands (`python3 -m json.tool`, `grep`, `test -f`) rather than a unit-test suite, since there's no executable behavior to unit test.

**Tech Stack:** None beyond JSON + Markdown + git. No build step, no CI, no package manager (per spec's "explicitly out of scope").

## Global Constraints

- Owner/author identity everywhere is `name: Jubast`, `email: 30406814+Jubast@users.noreply.github.com` (from `git config --global user.name`/`user.email`) — verbatim in `marketplace.json` and `plugin.json`.
- `marketplace.json` and `plugin.json` live under `.claude-plugin/` (not `.github/plugin/`) — this path is read directly by both Claude Code and Copilot CLI, so one manifest serves both.
- Agents are Claude Code format only (`agents/<name>.md`, no `.agent.md` files) — do not add a Copilot-formatted agent in this plan; the spec documents why (`*.md` glob collision with Copilot's `*.agent.md` convention).
- No CI, devcontainer, pre-commit config, test harness, or `.github/instructions|prompts|chatmodes` files — out of scope per spec.
- License is MIT.
- No placeholder URLs: `plugin.json`/`marketplace.json` omit `homepage`/`repository` fields rather than guessing a GitHub URL, since no remote is configured yet.

---

### Task 1: Root scaffold — `.gitignore`, `LICENSE`, `marketplace.json`

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: a `marketplace.json` with one `plugins[]` entry named `example-plugin`, `source: "./plugins/example-plugin/"` — Task 2 must create a plugin directory at exactly that path with a `plugin.json` whose `name` field is `example-plugin`.

- [ ] **Step 1: Create `.gitignore`**

```
# OS
.DS_Store
Thumbs.db

# Editors
.vscode/
.idea/
*.swp

# Node (in case tooling is added later)
node_modules/
```

- [ ] **Step 2: Create `LICENSE`**

```
MIT License

Copyright (c) 2026 Jubast

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Create `.claude-plugin/marketplace.json`**

```json
{
  "name": "common-agent-marketplace",
  "description": "A marketplace of Claude Code plugins covering a range of skills and agents. Manifests and skills are also readable directly by GitHub Copilot CLI.",
  "owner": {
    "name": "Jubast",
    "email": "30406814+Jubast@users.noreply.github.com"
  },
  "plugins": [
    {
      "name": "example-plugin",
      "description": "A minimal example plugin demonstrating this marketplace's skill and agent conventions. Copy this directory to start a new plugin.",
      "version": "1.0.0",
      "source": "./plugins/example-plugin/",
      "author": {
        "name": "Jubast",
        "email": "30406814+Jubast@users.noreply.github.com"
      }
    }
  ]
}
```

- [ ] **Step 4: Validate the JSON parses**

Run: `python3 -m json.tool .claude-plugin/marketplace.json`
Expected: pretty-printed JSON is echoed back, no error.

- [ ] **Step 5: Commit**

```bash
git add .gitignore LICENSE .claude-plugin/marketplace.json
git commit -m "Add marketplace manifest, license, and gitignore"
```

---

### Task 2: Example plugin manifest

**Files:**
- Create: `plugins/example-plugin/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: nothing from Task 1 at parse time, but must satisfy the contract Task 1 set up — `name` must be exactly `example-plugin` and the file must live at `plugins/example-plugin/.claude-plugin/plugin.json` to match `marketplace.json`'s `source: "./plugins/example-plugin/"`.
- Produces: the plugin manifest that Tasks 3–5 add skill/agent/README content next to.

- [ ] **Step 1: Create `plugins/example-plugin/.claude-plugin/plugin.json`**

```json
{
  "name": "example-plugin",
  "description": "A minimal example plugin demonstrating this marketplace's skill and agent conventions. Copy this directory to start a new plugin.",
  "version": "1.0.0",
  "author": {
    "name": "Jubast",
    "email": "30406814+Jubast@users.noreply.github.com"
  },
  "license": "MIT",
  "keywords": [
    "example",
    "template",
    "skills",
    "agents"
  ]
}
```

- [ ] **Step 2: Validate the JSON parses and matches the marketplace entry**

Run:
```bash
python3 -m json.tool plugins/example-plugin/.claude-plugin/plugin.json
python3 -c "
import json
mp = json.load(open('.claude-plugin/marketplace.json'))
pl = json.load(open('plugins/example-plugin/.claude-plugin/plugin.json'))
entry = next(p for p in mp['plugins'] if p['name'] == pl['name'])
assert entry['source'].rstrip('/') == 'plugins/example-plugin', entry['source']
print('OK: marketplace entry matches plugin.json name and source path')
"
```
Expected: both JSON files print without error, and the script prints `OK: marketplace entry matches plugin.json name and source path`.

- [ ] **Step 3: Commit**

```bash
git add plugins/example-plugin/.claude-plugin/plugin.json
git commit -m "Add example-plugin manifest"
```

---

### Task 3: Example skill

**Files:**
- Create: `plugins/example-plugin/skills/example-skill/SKILL.md`

**Interfaces:**
- Produces: a functional skill (not a stub) that documents the exact steps for adding a new plugin to this marketplace — later referenced by the root `README.md` (Task 6) and `CONTRIBUTING.md` (Task 7).

- [ ] **Step 1: Create `plugins/example-plugin/skills/example-skill/SKILL.md`**

```markdown
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
```

- [ ] **Step 2: Validate frontmatter is well-formed**

Run:
```bash
python3 -c "
import re
text = open('plugins/example-plugin/skills/example-skill/SKILL.md').read()
m = re.match(r'^---\n(.*?)\n---\n(.*)$', text, re.DOTALL)
assert m, 'frontmatter block not found'
front, body = m.groups()
assert 'name: example-skill' in front
assert 'description:' in front
assert len(body.strip()) > 0
print('OK: SKILL.md frontmatter and body present')
"
```
Expected: `OK: SKILL.md frontmatter and body present`

- [ ] **Step 3: Commit**

```bash
git add plugins/example-plugin/skills/example-skill/SKILL.md
git commit -m "Add example-skill: walkthrough for adding a new plugin"
```

---

### Task 4: Example agent

**Files:**
- Create: `plugins/example-plugin/agents/example-reviewer.md`

**Interfaces:**
- Produces: a functional agent that structurally reviews a plugin directory in this marketplace (manifest validity, marketplace registration, skill/agent frontmatter) — referenced by the root `README.md` (Task 6).

- [ ] **Step 1: Create `plugins/example-plugin/agents/example-reviewer.md`**

```markdown
---
name: example-reviewer
description: |
  Use this agent to review a plugin directory in this marketplace for
  structural correctness before it's registered in marketplace.json —
  valid plugin.json, skill/agent frontmatter, and a source path that
  actually resolves.

  Examples:
  <example>Context: A new plugin was just scaffolded. user: "I added plugins/my-new-plugin, can you check it's set up right?" assistant: "I'll use the example-reviewer agent to check the plugin structure." <commentary>Structural review of a plugin directory before marketplace registration is exactly this agent's job.</commentary></example>
  <example>Context: marketplace.json won't load. user: "Claude Code says it can't find my plugin" assistant: "Let me use the example-reviewer agent to check the manifest and source path." <commentary>A broken source path or malformed JSON is a common cause — the agent checks both.</commentary></example>
model: inherit
---

You are a plugin structure reviewer for this marketplace repository. You
check a single plugin directory for the issues that most commonly break
installation in Claude Code or Copilot CLI.

## Your Process

1. **Locate the manifest** — read `<plugin-dir>/.claude-plugin/plugin.json`.
   Confirm it parses as valid JSON and has non-empty `name`, `description`,
   and `version` fields, and that `name` is kebab-case and matches the
   plugin's directory name.
2. **Check the marketplace entry** — read the root
   `.claude-plugin/marketplace.json`, find the entry whose `name` matches
   this plugin, and confirm its `source` path resolves to the plugin
   directory you're reviewing.
3. **Walk the skills** — for each `SKILL.md` under `<plugin-dir>/skills/*/`,
   confirm the frontmatter has non-empty `name` and `description` fields,
   the frontmatter `name` matches the containing directory name, and the
   body isn't empty.
4. **Walk the agents** — for each `*.md` under `<plugin-dir>/agents/`,
   confirm the frontmatter has non-empty `name` and `description` fields
   and the frontmatter `name` matches the filename (minus `.md`).
5. **Report** — list every issue found, each with the exact file path and
   what's wrong. If nothing is wrong, say so explicitly rather than
   staying silent.

## Output Format

A short list, one line per issue: `<file path>: <what's wrong>`. End with
either "No issues found." or a one-line count of issues found.

## When NOT to use this agent

- For reviewing the *content* quality of a skill or agent's instructions
  (this agent only checks structure, not whether the advice is good).
- For general code review outside `plugins/` — use the repository's normal
  code-review process instead.
```

- [ ] **Step 2: Validate frontmatter is well-formed**

Run:
```bash
python3 -c "
import re
text = open('plugins/example-plugin/agents/example-reviewer.md').read()
m = re.match(r'^---\n(.*?)\n---\n(.*)$', text, re.DOTALL)
assert m, 'frontmatter block not found'
front, body = m.groups()
assert 'name: example-reviewer' in front
assert 'description:' in front
assert 'model:' in front
assert len(body.strip()) > 0
print('OK: agent frontmatter and body present')
"
```
Expected: `OK: agent frontmatter and body present`

- [ ] **Step 3: Commit**

```bash
git add plugins/example-plugin/agents/example-reviewer.md
git commit -m "Add example-reviewer agent: structural plugin review"
```

---

### Task 5: Example plugin README

**Files:**
- Create: `plugins/example-plugin/README.md`

**Interfaces:**
- Consumes: the skill and agent names from Tasks 3–4 (`example-skill`, `example-reviewer`) — referenced by name in this README.

- [ ] **Step 1: Create `plugins/example-plugin/README.md`**

```markdown
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
```

- [ ] **Step 2: Verify the file references match the actual skill/agent names**

Run:
```bash
test -d plugins/example-plugin/skills/example-skill && \
test -f plugins/example-plugin/agents/example-reviewer.md && \
grep -q 'example-skill' plugins/example-plugin/README.md && \
grep -q 'example-reviewer' plugins/example-plugin/README.md && \
echo "OK: README references resolve"
```
Expected: `OK: README references resolve`

- [ ] **Step 3: Commit**

```bash
git add plugins/example-plugin/README.md
git commit -m "Add example-plugin README"
```

---

### Task 6: Root README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: `example-plugin` (Task 2), links to `CONTRIBUTING.md` (Task 7 — file referenced here, created next task; both land before the plan is considered done).

- [ ] **Step 1: Create `README.md`**

```markdown
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
```

- [ ] **Step 2: Verify links resolve to real paths**

Run:
```bash
test -d plugins/example-plugin && \
test -f plugins/example-plugin/skills/example-skill/SKILL.md && \
echo "OK: README links resolve"
```
Expected: `OK: README links resolve`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add root README"
```

---

### Task 7: CONTRIBUTING.md and final verification

**Files:**
- Create: `CONTRIBUTING.md`

**Interfaces:**
- Consumes: everything from Tasks 1–6 — this task's verification step checks the whole tree.

- [ ] **Step 1: Create `CONTRIBUTING.md`**

```markdown
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

There's no CI, linter, or build step yet — plugins are validated by hand
(JSON parses, referenced paths exist, frontmatter fields are present). Add
tooling here when a real validation gap shows up.
```

- [ ] **Step 2: Validate frontmatter and JSON across the whole repo**

Run:
```bash
python3 -c "
import json, re, os, glob

# 1. Both JSON manifests parse and cross-reference correctly.
mp = json.load(open('.claude-plugin/marketplace.json'))
assert mp['name'] == 'common-agent-marketplace'
assert mp['owner']['name'] == 'Jubast'
for entry in mp['plugins']:
    src = entry['source'].rstrip('/')
    plugin_json_path = os.path.join(src, '.claude-plugin', 'plugin.json')
    assert os.path.isfile(plugin_json_path), f'missing {plugin_json_path}'
    pl = json.load(open(plugin_json_path))
    assert pl['name'] == entry['name'], (pl['name'], entry['name'])

# 2. Every SKILL.md has well-formed frontmatter matching its directory name.
for skill_md in glob.glob('plugins/*/skills/*/SKILL.md'):
    text = open(skill_md).read()
    m = re.match(r'^---\n(.*?)\n---\n(.*)$', text, re.DOTALL)
    assert m, f'{skill_md}: no frontmatter block'
    front, body = m.groups()
    dir_name = os.path.basename(os.path.dirname(skill_md))
    assert f'name: {dir_name}' in front, f'{skill_md}: name mismatch'
    assert 'description:' in front, f'{skill_md}: missing description'
    assert body.strip(), f'{skill_md}: empty body'

# 3. Every agent .md has well-formed frontmatter matching its filename.
for agent_md in glob.glob('plugins/*/agents/*.md'):
    text = open(agent_md).read()
    m = re.match(r'^---\n(.*?)\n---\n(.*)$', text, re.DOTALL)
    assert m, f'{agent_md}: no frontmatter block'
    front, body = m.groups()
    file_name = os.path.splitext(os.path.basename(agent_md))[0]
    assert f'name: {file_name}' in front, f'{agent_md}: name mismatch'
    assert 'description:' in front, f'{agent_md}: missing description'
    assert body.strip(), f'{agent_md}: empty body'

print('OK: full repo verification passed')
"
```
Expected: `OK: full repo verification passed`

- [ ] **Step 3: Confirm the working tree is clean after committing**

Run:
```bash
git add CONTRIBUTING.md
git commit -m "Add CONTRIBUTING.md with plugin authoring and platform compatibility notes"
git status --short
```
Expected: `git status --short` prints nothing (clean tree).

---

## Definition of Done

- `find . -not -path './.git*' -not -path './docs*'` lists exactly: `.gitignore`, `LICENSE`, `README.md`, `CONTRIBUTING.md`, `.claude-plugin/marketplace.json`, `plugins/example-plugin/.claude-plugin/plugin.json`, `plugins/example-plugin/skills/example-skill/SKILL.md`, `plugins/example-plugin/agents/example-reviewer.md`, `plugins/example-plugin/README.md`.
- Task 7 Step 2's full-repo verification script passes.
- `git log --oneline` shows one commit per task (7 new commits on top of the 3 spec commits already on `main`).
