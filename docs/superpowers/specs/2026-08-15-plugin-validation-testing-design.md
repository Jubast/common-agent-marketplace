# Plugin Validation & Skill Testing — Design

Date: 2026-08-15

## Purpose

`common-agent-marketplace` currently has no test harness at all —
[CONTRIBUTING.md](../../../CONTRIBUTING.md) explicitly defers this until "a
real validation gap shows up." `convert-pdf-to-md` now ships an actual
executable script (`convert_pdf_to_md.py`) and a skill with specific,
checkable behavioral claims (implicit-trigger phrasing, a "run the script,
don't ad-hoc parse" discipline rule, a documented output-folder layout).
That's a real gap: nothing currently confirms the script works or that the
skill's instructions are actually followed.

This spec adds a test harness modeled directly on
[obra/superpowers](https://github.com/obra/superpowers)'s own testing
approach (confirmed by reading its actual `tests/`, `docs/testing.md`, and
`skills/writing-skills/` in the locally cached plugin clone at
`~/.claude/plugins/cache/superpowers-marketplace/superpowers/`), adapted for
one difference: this repo hosts multiple independent plugins, where
superpowers ships exactly one.

## Reference: how superpowers actually does it

Superpowers splits testing into two kinds, in two places:

1. **`tests/<component>/`** — plain non-LLM tests (bash/Python/Node) for
   pieces of executable code the plugin ships: `tests/opencode/` (plugin
   loading), `tests/brainstorm-server/` (its JS server), `tests/kimi/` and
   `tests/codex-plugin-sync/` (manifest generation/sync across the many CLI
   targets superpowers supports). These exist because superpowers
   distributes the *same* plugin as generated, synced manifests across
   several CLI formats and has hit real drift bugs there (see the hooks-collision
   comment in `tests/codex/test-marketplace-manifest.sh`). There is **no**
   generic SKILL.md/frontmatter schema validator anywhere in the repo —
   malformed frontmatter just fails to load at runtime and surfaces
   naturally through use.

2. **`tests/claude-code/`** — bash scripts that shell out to `claude -p
   "prompt"` (headless mode) and assert on the captured output via helpers
   in `test-helpers.sh` (`run_claude`, `assert_contains`,
   `assert_not_contains`, `assert_count`, `assert_order`). Split into fast
   tests (run by default — does the skill *describe* the right behavior)
   and `--integration`-gated slow tests (does the skill *actually produce*
   the right behavior end-to-end, run manually, 10-30 min). This is
   distinct from `evals/` — a separate cloned repo (`superpowers-evals`)
   driving real tmux sessions across three different CLI agents with an
   LLM actor and LLM verifier, for deep pressure-tested skill-compliance
   checks. That harness is not part of this design — it's disproportionate
   to a two-plugin repo, and the `tests/claude-code/` pattern already covers
   both "does it describe itself right" and "does it actually work"
   without the extra infrastructure.

## What this repo doesn't need from that model

- **No manifest-sync tests.** Per
  [scaffold-marketplace-design.md](2026-08-15-scaffold-marketplace-design.md),
  `marketplace.json`/`plugin.json` are read directly by both Claude Code and
  Copilot CLI with no per-platform generation step — there's no sync/drift
  class of bug to guard against here.
- **No frontmatter schema validator.** Matches superpowers: none exists
  there either. Malformed SKILL.md/agent frontmatter fails at load time.
- **No `evals/`-style drill harness.** Out of scope per above — the
  `tests/claude-code/` bash+`claude -p` pattern is the adopted tier for
  skill-behavior testing.
- **No CI workflow.** Local scripts only, run by hand, matching
  `tests/claude-code/`'s own "CI/CD Integration" section in superpowers,
  which documents how *someone else* could wire it into CI but doesn't do
  so itself.
- **`example-plugin` gets no tests.** It has no executable code and its
  skill is a copy-paste template, not real behavior to verify — same reason
  superpowers doesn't write `tests/<component>/` entries for skills with no
  non-LLM logic behind them.

## Structure

```
tests/
  claude-code/
    test-helpers.sh
    test-convert-pdf-to-md.sh
    test-convert-pdf-to-md-integration.sh
    run-skill-tests.sh
    README.md
    fixtures/
      generate_sample_pdf.py
  convert-pdf-to-md/
    test_convert_pdf_to_md.py
docs/
  testing.md
```

## Components

### `tests/claude-code/test-helpers.sh`

Ported near-verbatim from superpowers' version: `run_claude "prompt"
[timeout] [allowed_tools]` (wraps `claude -p` with a timeout),
`assert_contains`/`assert_not_contains` (case-insensitive grep, since
models freely capitalize skill terms), `assert_count`, `assert_order`. No
`create_test_project`/`create_test_plan` equivalents needed yet — those
exist in superpowers for its plan-execution skills, which this repo doesn't
have.

### `tests/claude-code/test-convert-pdf-to-md.sh` (fast, default)

Content/description-recall style, mirroring
`test-subagent-driven-development.sh`: asks Claude questions about the
skill without requiring it to actually run anything, and asserts the
answers match specific, checkable claims already made in the SKILL.md:

- Skill is discoverable and Claude can describe when it triggers, including
  the implicit-trigger cases the SKILL.md calls out ("summarize", "what's
  in this file" — not just literal "convert").
- Skill states the "always run the script, never ad-hoc parse" rule.
- Skill states the default-output-location rule (next to the source file,
  `-o` only on explicit user request).
- Skill states the mixed-file-type rule (invoke sibling skills for
  `.docx`/`.xlsx` in the same folder) — tested as a description-recall
  claim only, since the sibling skills don't exist in this repo to actually
  invoke.

Runtime: seconds to low minutes, no dependencies beyond `claude` on PATH.

### `tests/claude-code/test-convert-pdf-to-md-integration.sh` (`--integration`, slow)

Real end-to-end run, mirroring the RED/GREEN/PRESSURE structure of
`test-worktree-native-preference.sh`:

- **Application scenario:** give Claude a fixture PDF and ask it to
  summarize the PDF (not "convert" — testing the implicit trigger for
  real). Assert the script actually ran (expected `OK` output pattern) and
  a real `<name>.md` file exists at the documented default location (next
  to the source).
- **Pressure scenario:** same fixture, framed with urgency ("just quickly
  tell me what's in this PDF, skip the formal process"). Assert Claude
  still runs the script rather than improvising ad-hoc PDF parsing —
  the discipline rule this skill explicitly states.

Fixture: `tests/claude-code/fixtures/generate_sample_pdf.py`, a
dependency-free helper that writes a minimal valid one-page PDF via raw PDF
object syntax (no `reportlab`/`fpdf`, nothing binary committed to git).
Requires `markitdown`+`pymupdf` installed and a live API-backed `claude`
session — documented as a prerequisite in the README, not silently skipped
if missing (the test should fail loudly, not report a false pass).

### `tests/claude-code/run-skill-tests.sh`

Ported: runs all fast tests by default, `--integration` to include slow
ones, `--test <file>` to run one, `--timeout <seconds>`, `--verbose` to
show full output on pass (not just failure).

### `tests/claude-code/README.md`

Adapted from superpowers' version: requirements, how to run, how to add a
new `test-<skill-name>.sh` when a new plugin's skill needs behavior
coverage, timeout notes, CI note (documents how CI *could* run this, same
as superpowers — doesn't add a workflow file).

### `tests/convert-pdf-to-md/test_convert_pdf_to_md.py`

Plain pytest, no LLM, no `markitdown`/`pymupdf` required — exercises the
parts of `convert_pdf_to_md.py` that don't need those imports:

- `find_pdf_files()`: correct file discovery, `--recursive` behavior,
  correct skip-count for non-`.pdf` files.
- `main()`'s argument/error paths: missing input path → exit code 3;
  non-`.pdf` single-file input → exit code 3; `--help` exits 0 without
  requiring `markitdown`/`pymupdf` to be installed (confirms the actual
  import ordering in the script, where argparse's `--help` short-circuits
  before `_import_markitdown()`/`_import_fitz()` run).
- `build_image_appendix()`: correct Markdown structure for empty vs.
  populated `written_by_page`, including page ordering.

Anything requiring a real PDF/`markitdown`/`pymupdf` (`convert_one`,
`extract_images`) is covered by the integration behavior test instead, not
duplicated here — consistent with keeping this tier fast and
dependency-light, the same role `tests/opencode/` and
`tests/brainstorm-server/` play in superpowers (mechanics only, no LLM, no
heavy runtime deps).

### `docs/testing.md`

Adapted from superpowers' `docs/testing.md`: states the two tiers that
exist here (`tests/<component>/` for non-LLM mechanics,
`tests/claude-code/` for skill-behavior), explicitly notes the tiers this
repo omits and why (see "What this repo doesn't need" above), and gives the
pattern for extending both tiers when a new plugin adds real executable
code or a skill worth behavior-testing.

### `CONTRIBUTING.md` update

Replace the current "Tooling" section ("There's no CI, linter, or build
step yet...") with a pointer to `docs/testing.md` and the two `run-*`
entry points.

## Extensibility for multiple plugins

Both tiers are additive per-plugin, no restructuring needed as the
marketplace grows:

- A new plugin with real executable code gets its own
  `tests/<plugin-name>/` directory, same pattern as
  `tests/convert-pdf-to-md/`.
- A new plugin's skill worth behavior-testing gets its own
  `tests/claude-code/test-<skill-name>.sh` (and
  `test-<skill-name>-integration.sh` if it has real end-to-end behavior to
  verify), added to the list in `run-skill-tests.sh` — exactly how
  superpowers itself would add a second skill's tests, just exercised here
  for the first time across more than one plugin.
- A plugin with no executable code and no skill claims worth verifying
  (like `example-plugin`) gets neither — same as today.

## Testing / verification

This design's own artifacts are verified by using them:

- `tests/convert-pdf-to-md/test_convert_pdf_to_md.py` passes via `pytest`
  with no extra dependencies installed.
- `tests/claude-code/run-skill-tests.sh` (fast tests) passes with `claude`
  on PATH and no special setup.
- `tests/claude-code/run-skill-tests.sh --integration` passes once
  `markitdown`+`pymupdf` are installed and a live API-backed session is
  available — run manually once during implementation to confirm the
  fixture generator and both scenarios actually work against the real
  skill, not just that the scripts are syntactically correct.
