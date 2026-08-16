# Testing This Repo

Two kinds of tests, mirroring how
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
```

## Known state: convert-pdf-to-md's integration test is a documented failure

`tests/claude-code/test-convert-pdf-to-md-integration.sh`'s Application AND
Pressure scenarios both currently fail against the real skill: Claude
Code's `Read` tool can read `.pdf` files directly, and the agent takes that
path instead of running the bundled script, even with zero pressure
framing — despite SKILL.md's explicit "do not attempt to parse PDF content
directly" rule. This was confirmed by live testing while building this
harness (see `docs/superpowers/plans/2026-08-15-plugin-validation-testing.md`,
Task 4). The test is intentionally kept red as a regression guard for
whichever future change closes that loophole in SKILL.md — don't loosen
the assertion to make it pass.

## What this repo deliberately omits, and why

- **No manifest-sync tests.** `marketplace.json`/`plugin.json` are read
  directly by both Claude Code and Copilot CLI — no per-platform
  generation step exists here to drift, unlike superpowers' many CLI
  targets.
- **No frontmatter schema validator.** Matches superpowers: none exists
  there either. Malformed SKILL.md/agent frontmatter fails to load at
  runtime and surfaces naturally.
- **No `evals/`-style drill harness.** Disproportionate to a two-plugin
  repo — `tests/claude-code/` already covers both "describes itself
  right" and "actually works" without a separate tmux/multi-CLI harness.
- **No CI workflow.** Local/manual only, for now.

See
[docs/superpowers/specs/2026-08-15-plugin-validation-testing-design.md](superpowers/specs/2026-08-15-plugin-validation-testing-design.md)
for the full rationale.

## Adding tests for a new plugin

- Real executable code worth testing without an LLM? Add
  `tests/<plugin-name>/`, same pattern as `tests/convert-pdf-to-md/`.
- A skill worth behavior-testing? Add
  `tests/claude-code/test-<skill-name>.sh` (and `-integration.sh` if it has
  real end-to-end behavior to verify), then add it to the lists in
  `tests/claude-code/run-skill-tests.sh`.
- No executable code and no behavioral claims worth verifying (e.g. a pure
  template)? No tests needed.
