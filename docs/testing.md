# Testing This Repo

Three kinds of tests, the first two mirroring how
[obra/superpowers](https://github.com/obra/superpowers) tests itself
(see its own `docs/testing.md`), adapted for hosting multiple plugins
instead of one:

- **`tests/<plugin-name>/`** — does a plugin's non-LLM executable code
  work? Plain pytest, no `claude` CLI, no API key. Currently:
  `tests/convert-pdf-to-md/test_convert_pdf_to_md.py`.
- **`tests/claude-code/`** — does a skill actually get followed? Bash
  scripts shelling out to `claude -p` (headless mode), asserting on
  captured output via `test-helpers.sh`. Split into fast tests (run by
  default — does the skill describe the right behavior) and
  `--integration`-gated slow tests (does the skill actually produce the
  right behavior end-to-end).
- **`tests/marketplace/`** — does the marketplace actually install? Real,
  live `claude plugin marketplace add` + `install` and
  `copilot plugin marketplace add` + `install` runs, one per platform,
  each isolated to a throwaway `$HOME` **and** the CLI's own config-dir
  override (`CLAUDE_CONFIG_DIR` / `COPILOT_HOME`) so a test run doesn't
  touch your real global Claude Code or Copilot CLI config, plus a
  control-throwaway safety net as a backstop (see "Isolation guarantee"
  below) that never reads or touches your real config either. Plugin names
  are read from the manifests at run time, so a new plugin is covered
  automatically — no test file to update.

## Running

```bash
# Non-LLM tests
pip install -r tests/requirements.txt
python3 -m pytest tests/convert-pdf-to-md/ -v
```

On systems with an externally-managed system Python (PEP 668, e.g. Ubuntu
24.04/this devcontainer), a plain `pip install` above will fail with an
"externally-managed-environment" error. Use a venv instead — the clean
option:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r tests/requirements.txt
```

— or add `--break-system-packages` to the `pip install` command for a
quicker, non-isolated alternative.

```bash

# Skill-behavior tests (fast)
./tests/claude-code/run-skill-tests.sh

# Skill-behavior tests (fast + integration; also needs markitdown/pymupdf,
# see plugins/convert-pdf-to-md/skills/convert-pdf-to-md/references/setup.md)
./tests/claude-code/run-skill-tests.sh --integration

# Marketplace install tests (needs both `claude` and `copilot` on PATH)
./tests/marketplace/run-marketplace-tests.sh
```

## Isolation guarantee for `tests/marketplace/`

`tests/marketplace/test-claude-install.sh` and `test-copilot-install.sh`
used to isolate their real installs by overriding `$HOME` alone, on the
assumption that a CLI's config always lives under `$HOME`. That assumption
doesn't hold: **as of 2026-09**, Claude Code resolves its config directory
from `$CLAUDE_CONFIG_DIR` when that env var is set, ignoring `$HOME`
entirely. This repo's own devcontainers (`.devcontainer/chief`,
`.devcontainer/orca`) set `CLAUDE_CONFIG_DIR` globally, so a `HOME`-only
override there silently installed test plugins into the real, shared
Claude Code config — confirmed by reproducing it directly (installing a
plugin under a throwaway `$HOME` and watching it appear in
`claude plugin list` under the real `$HOME` immediately after).

The fix has two layers:

- **Both `$HOME` and the CLI's own config-dir override are pointed at the
  same throwaway directory.** `test-claude-install.sh` now sets both
  `HOME` and `CLAUDE_CONFIG_DIR`; `test-copilot-install.sh` sets both
  `HOME` and `COPILOT_HOME` (GitHub's documented override for Copilot
  CLI's `~/.copilot` config dir — the same class of HOME-independent
  override, though not empirically reproduced here since `copilot` wasn't
  on `PATH` in the environment this was diagnosed in).
- **A control-throwaway safety net runs regardless, and never touches the
  real config.** Each script also creates a second, disposable throwaway
  HOME/config dir that nothing ever installs into, and checks it once at
  the end of the run. If isolation is working, it's still empty; if
  anything shows up there, the override wasn't actually confining installs
  and the test fails loudly (exit 1, the leaked plugin ids printed to
  stderr). This is deliberate defense in depth, even if a future CLI
  version resolves its config directory some other way.

  Note: an earlier draft of this fix had the safety net snapshot/diff/revert
  against the **real** config instead of a control throwaway, on the theory
  that it should actively clean up anything that leaked. In practice, an
  unattended repro-and-revert pass against that real config left it worse
  off than it started (an incidental `marketplace remove`/`add` round-trip
  deregistered unrelated plugins). The control-throwaway design gives the
  same leak-detection guarantee without ever reading or writing anything
  real, which is the right tradeoff for a test run's blast radius.

## Prerequisite: the plugin must actually be installed

`tests/claude-code/test-convert-pdf-to-md-integration.sh` (and the fast
`test-convert-pdf-to-md.sh`) shell out to `claude -p`, which only has a
skill available if `convert-pdf-to-md@common-agent-marketplace` is
installed and enabled in that environment's Claude Code config (`claude
plugin install convert-pdf-to-md@common-agent-marketplace` — see the
plugin's own README). Without it, the integration test fails regardless of
what SKILL.md says, because the skill is never loaded into context. This
bit a run of this exact test in 2026-08 and looked identical to a genuine
SKILL.md defect until the plugin install state was checked.

## Resolved: convert-pdf-to-md's integration test was a documented failure

As of 2026-08-15, both the Application and Pressure scenarios failed
against the real skill: Claude Code's `Read` tool can read `.pdf` files
directly, and the agent took that path instead of running the bundled
script — even with zero pressure framing — despite SKILL.md's "do not
attempt to parse PDF content directly" rule.

Fixed 2026-08-20: SKILL.md now names the `Read` tool explicitly as
off-limits on the `.pdf` file (the original wording didn't cover it, since
using a normal tool doesn't read as "ad-hoc parsing"), plus an explicit
counter for time-pressure framing ("quickly," "just skim it"), which was
needed separately — the Read-tool wording alone fixed the Application
scenario but not the Pressure one. Both scenarios now pass reproducibly
(2 consecutive full runs). See `plugins/convert-pdf-to-md/README.md`'s
Provenance section for the diff summary.

## What this repo deliberately omits, and why

- **No manifest-sync tests.** `marketplace.json`/`plugin.json` are read
  directly by both Claude Code and Copilot CLI from `.claude-plugin/` —
  one manifest, no per-platform copy to drift. `tests/marketplace/`
  instead tests that this single manifest actually produces a working
  install on both platforms.
- **No frontmatter schema validator.** Matches superpowers: none exists
  there either. Malformed SKILL.md/agent frontmatter fails to load at
  runtime and surfaces naturally.
- **No `evals/`-style drill harness.** Disproportionate to a four-plugin
  repo — `tests/claude-code/` already covers both "describes itself
  right" and "actually works" without a separate tmux/multi-CLI harness.
- **No CI workflow.** Local/manual only, for now.

## Adding tests for a new plugin

- Real executable code worth testing without an LLM? Add
  `tests/<plugin-name>/`, same pattern as `tests/convert-pdf-to-md/`.
- A skill worth behavior-testing? Add
  `tests/claude-code/test-<skill-name>.sh` (and `-integration.sh` if it has
  real end-to-end behavior to verify), then add it to the lists in
  `tests/claude-code/run-skill-tests.sh`.
- No executable code and no behavioral claims worth verifying (e.g. a pure
  template)? No tests needed.
- `tests/marketplace/` needs nothing added — it reads plugin names
  straight out of `.claude-plugin/marketplace.json`, so registering a new
  plugin there (a required step regardless, see `CONTRIBUTING.md`) is
  the only thing needed for install-test coverage.
