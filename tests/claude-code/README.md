# Claude Code Skill Tests

Bash tests for this repo's skills, using the `claude` CLI in headless mode.
Ported from [obra/superpowers](https://github.com/obra/superpowers)'s
`tests/claude-code/`.

## Requirements

- `claude` CLI on PATH (`claude --version` should work).
- The plugin whose skill you're testing discoverable by `claude -p` — either
  installed (`/plugin marketplace add .` then `/plugin install <plugin-name>`
  from within this repo) or auto-discovered because you're running from the
  **repo root** (Claude Code auto-discovers `skills/*/SKILL.md` under the
  current project, but only reliably from the repo root itself — running
  from a subdirectory such as `tests/claude-code/` is not reliable).
- For `--integration` tests: whatever the skill under test itself needs.
  For `convert-pdf-to-md`, that's `markitdown`+`pymupdf` — see
  `plugins/convert-pdf-to-md/skills/convert-pdf-to-md/references/setup.md`.

## Running

Run these from the **repo root** (not from within `tests/claude-code/`) —
`claude -p` skill discovery is unreliable from a subdirectory.

```bash
# Fast tests (default)
./tests/claude-code/run-skill-tests.sh

# Integration tests too (slow, several minutes, needs the skill's own deps)
./tests/claude-code/run-skill-tests.sh --integration

# One specific test file
./tests/claude-code/run-skill-tests.sh --test test-convert-pdf-to-md.sh

# Full output, not just pass/fail
./tests/claude-code/run-skill-tests.sh --verbose
```

## Test Structure

- `test-helpers.sh` — `run_claude`, `assert_contains`, `assert_not_contains`,
  `assert_count`, `assert_order`.
- `test-<skill-name>.sh` — fast, description-recall style: does the skill
  *describe* the right behavior when asked about it directly?
- `test-<skill-name>-integration.sh` — slow, `--integration`-gated: does the
  skill *actually produce* the right behavior end-to-end, given a real task?
- `fixtures/` — generators for any input files a skill's integration test
  needs (e.g. `generate_sample_pdf.py`), not committed binaries.

## Current Tests

### `test-convert-pdf-to-md.sh` (fast)

Four checks against SKILL.md's documented claims: implicit-trigger wording,
the "run the script, don't ad-hoc parse" discipline rule, the default
output-location rule, and the mixed-file-type sibling-skill rule.

### `test-convert-pdf-to-md-integration.sh` (`--integration`)

Application and Pressure scenarios, each generating a fixture PDF and
checking that a real `invoice/invoice.md` file gets produced with the
expected content. **Currently a documented, intentional failure** — see the
comment at the top of the script and `docs/testing.md` for why.

## Adding a New Test

1. Create `test-<skill-name>.sh` (and `test-<skill-name>-integration.sh` if
   the skill has real end-to-end behavior worth verifying).
2. Source `test-helpers.sh`, use `run_claude` + the `assert_*` functions.
3. Add the filename to the `tests` (or `integration_tests`) array in
   `run-skill-tests.sh`.
4. `chmod +x` the new file(s).

## Debugging Failed Tests

`./tests/claude-code/run-skill-tests.sh --verbose --test <file>` (run from
the repo root) shows full output, not just the failure summary.
