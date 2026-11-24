# Architecture

How the pieces of this repo fit together. Rules live in [AGENTS.md](AGENTS.md)
and [CONTRIBUTING.md](CONTRIBUTING.md).

## Marketplace layer

- [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json) lists every
  plugin with its `source` directory and version; `metadata.version` versions
  the marketplace as a whole.
- Each plugin has `plugins/<name>/.claude-plugin/plugin.json`. Claude Code and
  Copilot CLI both read these two manifests.
- `plugins/chief/.codex-plugin/plugin.json` is chief's Codex manifest; it names
  the Codex hooks file.

## Plugin shapes

| Shape | Plugins | Contents |
|---|---|---|
| Skill only | `convert-pdf-to-md`, `clean-code`, `clean-architecture` | `skills/<skill>/SKILL.md` with references or scripts beside it |
| Skill plus `SessionStart` hook | `using-orca`, `conventional-changes` | skills and `hooks/` (`hooks.json`, `session-start.sh`) |
| Full tool | `chief` | skills, hooks, `bin/` scripts, templates and a Copilot extension |
| Skills and scripts | `chief-of-staff` | skills (`chief`, `helpers`, one per backend: `herdr`, `orca`) and brief templates |

## Chief

Details and contracts are in [plugins/chief/README.md](plugins/chief/README.md).

- **Call path:** `skills/` (`using-chief`, `setup`, `dispatch`) tell the agent
  which `bin/` scripts to run (`bin/chief-*.sh`, `bin/task/chief-*.sh`); those
  source the helpers in `bin/lib/`.
- **Backend adapter seam:** `bin/lib/backends/backend.sh` loads the configured
  adapter, one of `herdr.sh`, `orca.sh` or `hc.sh`; `screen.sh` holds the
  screen-driven parts they share. The contract is in the header of `backend.sh`.
- **Agent adapter seam:** `bin/lib/agents/agent.sh` loads a task's adapter, one
  of `claude.sh`, `codex.sh` or `copilot.sh`. The contract is in its header.
- **Harness wake paths:** Chief's own session runs on Claude Code, Codex CLI or
  Copilot CLI. `hooks/hooks.json` serves Claude Code and Copilot,
  `hooks/hooks.codex.json` Codex; the idle session is woken by
  `stop-watch-claude.sh`, `stop-watch-codex.sh` or
  `extensions/chief-watch/extension.mjs`, all through `watch-reason.sh`.
- **Templates:** `templates/brief-<role>.md` and `templates/lifecycle-<role>.md`
  per worker role, rendered at spawn.
- **Runtime state:** `.chief/` under `CHIEF_HOME`, outside the plugin package
  (paths in `bin/lib/paths.sh`).

## Tests

See [docs/testing.md](docs/testing.md) and
[tests/chief/README.md](tests/chief/README.md).

- `tests/<plugin>/` - a plugin's non-LLM code: `tests/convert-pdf-to-md/`
  (pytest) and `tests/chief/` (bats).
- `tests/claude-code/` - skill-behavior tests that run the real `claude` CLI.
- `tests/marketplace/` - real install runs on Claude Code and Copilot CLI.
- `tests/chief/` tiers: `unit/` (no backend, no agent), `workflow/` (real herdr,
  stand-in agent), `backends/` (the herdr, hc and Orca adapter contracts),
  `harness/` (the test doubles), `live/` (real agents, opt-in).

## CI and releases

- [tests.yml](.github/workflows/tests.yml) runs the chief suite on pull requests
  and pushes to `main`, as the jobs `chief-herdr`, `chief-orca` and `chief-hc`.
- [tag-marketplace.yml](.github/workflows/tag-marketplace.yml) runs when
  `marketplace.json` changes on `main` and creates the tag `v<metadata.version>`
  if it does not exist yet.

## Dev environment

- `.devcontainer/devcontainer.json` is the only config. Its features install
  the herdr, `hc` (herdr-core) and Orca backends and the Claude Code, Codex and
  Copilot CLIs, with this repo's `chief` and `conventional-changes` plugins.
  Its `Dockerfile` only adds an `apt-get` wrapper that lets features install
  under podman.
- `scripts/setup.sh` (`postCreateCommand`) fixes volume ownership and `$HOME`
  for SSH logins and sets up key-only SSH. `scripts/orca-serve.sh`
  (`postStartCommand`) starts the Orca server, bound to `127.0.0.1:6768`.
- SSH is on host port 2253 (container 2222), public-key login only. Before
  creating the container, put your public key in `.devcontainer/authorized_keys`
  (gitignored); `setup.sh` installs it as `~/.ssh/authorized_keys`. The herdr
  app connects with the matching private key.
