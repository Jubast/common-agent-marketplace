# Plugin Validation & Skill Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a two-tier test harness to `common-agent-marketplace` — non-LLM tests for `convert-pdf-to-md`'s executable Python script, and `claude -p`-driven skill-behavior tests (fast description-recall + slow real end-to-end) for its SKILL.md — modeled on how `obra/superpowers` actually tests itself.

**Architecture:** `tests/convert-pdf-to-md/` holds a plain pytest suite exercising the parts of `scripts/convert_pdf_to_md.py` that don't need `markitdown`/`pymupdf` installed. `tests/claude-code/` holds bash scripts that shell out to headless `claude -p` and assert on captured output via a small ported helper library, split into a fast default suite and a `--integration`-gated slow suite that runs the real script against a generated fixture PDF.

**Tech Stack:** Python 3 + pytest (no other Python deps for the test suite itself), bash, the `claude` CLI in headless mode.

**Spec:** [docs/superpowers/specs/2026-08-15-plugin-validation-testing-design.md](../specs/2026-08-15-plugin-validation-testing-design.md)

## Global Constraints

- No CI workflow — every test tier runs locally, by hand, invoked directly by a contributor.
- No manifest-sync tests and no SKILL.md/agent frontmatter schema validator — out of scope per the spec (this repo has no per-platform manifest generation step to drift, and malformed frontmatter fails to load at runtime on its own).
- No `evals/`-style drill harness (separate cloned repo, tmux-driven, multi-CLI, LLM verifier) — the `tests/claude-code/` bash+`claude -p` tier is the adopted mechanism for skill-behavior testing instead.
- `example-plugin` gets no test coverage — it has no executable code and its skill is a copy-paste template, not real behavior to verify.
- `tests/claude-code/` tests require the `claude` CLI on PATH and the `convert-pdf-to-md` plugin installed locally (`/plugin marketplace add .` + `/plugin install convert-pdf-to-md`, or equivalent) so headless `claude -p` can discover the skill.
- `tests/claude-code/test-convert-pdf-to-md-integration.sh` additionally requires `markitdown`+`pymupdf` installed per `plugins/convert-pdf-to-md/skills/convert-pdf-to-md/references/setup.md`.
- **Known, intentional exception to "tests should pass":** `test-convert-pdf-to-md-integration.sh`'s Application scenario is expected to FAIL when actually run. This was verified live while writing this plan (see Task 4) — Claude Code's `Read` tool can read `.pdf` files directly, and the agent takes that path instead of running the bundled script, bypassing SKILL.md's "do not attempt to parse PDF content directly" rule even with zero pressure framing. Do not weaken the assertion to make it pass; it's a regression guard for a future SKILL.md fix, tracked as a documented gap, not a bug in this plan's tests.

---

### Task 1: Non-LLM pytest suite for `convert_pdf_to_md.py`

**Files:**
- Create: `tests/convert-pdf-to-md/test_convert_pdf_to_md.py`

**Interfaces:**
- Consumes (from the existing, unmodified script at `plugins/convert-pdf-to-md/skills/convert-pdf-to-md/scripts/convert_pdf_to_md.py`):
  - `find_pdf_files(root: Path, recursive: bool) -> tuple[list[Path], int]`
  - `build_image_appendix(written_by_page: dict[int, list[str]]) -> str`
  - CLI exit codes: `0` (OK), `3` (invalid input — missing path or non-`.pdf` file), and `--help` exits `0`
- Produces: nothing consumed by later tasks.

This task has no separate "implementation" step — `convert_pdf_to_md.py` already exists and isn't being modified, so there's no red-then-green cycle against new production code. The verification step below (run once, confirm all pass) is the actual check that these characterizations of the existing script are correct.

- [ ] **Step 1: Write the test file**

```python
import importlib.util
import subprocess
import sys
from pathlib import Path

SCRIPT_PATH = (
    Path(__file__).resolve().parents[2]
    / "plugins" / "convert-pdf-to-md" / "skills" / "convert-pdf-to-md"
    / "scripts" / "convert_pdf_to_md.py"
)


def _load_module():
    spec = importlib.util.spec_from_file_location("convert_pdf_to_md", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


convert_pdf_to_md = _load_module()


def test_find_pdf_files_non_recursive_skips_subdirs_and_non_pdf(tmp_path):
    (tmp_path / "a.pdf").write_text("x")
    (tmp_path / "b.PDF").write_text("x")
    (tmp_path / "c.txt").write_text("x")
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "d.pdf").write_text("x")

    pdf_files, skipped = convert_pdf_to_md.find_pdf_files(tmp_path, recursive=False)

    assert {p.name for p in pdf_files} == {"a.pdf", "b.PDF"}
    assert skipped == 1


def test_find_pdf_files_recursive_includes_subdirs(tmp_path):
    (tmp_path / "a.pdf").write_text("x")
    (tmp_path / "c.txt").write_text("x")
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "d.pdf").write_text("x")

    pdf_files, skipped = convert_pdf_to_md.find_pdf_files(tmp_path, recursive=True)

    assert {p.name for p in pdf_files} == {"a.pdf", "d.pdf"}
    assert skipped == 1


def test_build_image_appendix_empty():
    assert convert_pdf_to_md.build_image_appendix({}) == ""


def test_build_image_appendix_orders_pages_ascending():
    written_by_page = {
        2: ["page002_img001.png"],
        1: ["page001_img001.jpg"],
    }

    result = convert_pdf_to_md.build_image_appendix(written_by_page)

    expected = (
        "\n## Extracted Images\n"
        "\n### Page 1\n"
        "\n![page001_img001.jpg](img/page001_img001.jpg)\n"
        "\n### Page 2\n"
        "\n![page002_img001.png](img/page002_img001.png)\n"
    )
    assert result == expected


def test_cli_help_exits_zero_without_dependencies_installed():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "Path to a .pdf file" in result.stdout


def test_cli_missing_input_path_exits_three():
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "/nonexistent/path/does-not-exist.pdf"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 3
    assert "Input path not found" in result.stderr


def test_cli_non_pdf_input_exits_three(tmp_path):
    txt_file = tmp_path / "notes.txt"
    txt_file.write_text("hello")

    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(txt_file)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 3
    assert "Unsupported file type" in result.stderr
```

- [ ] **Step 2: Run the tests and confirm they pass**

Run: `python3 -m pytest tests/convert-pdf-to-md/ -v`
Expected: `7 passed`. All seven tests run with no `markitdown`/`pymupdf` installed — the script only imports those inside `_import_markitdown()`/`_import_fitz()`, which none of these code paths reach (`--help`, the missing-path check, and the non-`.pdf` check all happen before those imports run in `main()`; `find_pdf_files`/`build_image_appendix` never touch them at all).

- [ ] **Step 3: Commit**

```bash
git add tests/convert-pdf-to-md/test_convert_pdf_to_md.py
git commit -m "Add non-LLM pytest suite for convert_pdf_to_md.py"
```

---

### Task 2: Provision Python for the test suite

**Files:**
- Create: `tests/requirements.txt`
- Modify: `.devcontainer/devcontainer.json`
- Modify: `.devcontainer/local/devcontainer.json`

**Interfaces:**
- Consumes: nothing.
- Produces: `python3`/`pip` on PATH in future devcontainer builds, and `tests/requirements.txt` as the pinned source of `pytest` for anyone running Task 1's suite. Later tasks don't depend on this directly (this repo's current live environment already has `python3` installed for plan-authoring purposes), but new contributors rebuilding the devcontainer do.

- [ ] **Step 1: Add the pytest requirements file**

```
pytest>=7.4
```

Write this to `tests/requirements.txt`.

- [ ] **Step 2: Add a Python feature to the primary devcontainer**

In `.devcontainer/devcontainer.json`, the current `features` block is:

```json
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": false,
      "installOhMyZsh": false,
      "upgradePackages": true
    },
    "ghcr.io/devcontainers/features/copilot-cli:1": {},
    "ghcr.io/devcontainers-extra/features/claude-code:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
```

Change it to:

```json
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": false,
      "installOhMyZsh": false,
      "upgradePackages": true
    },
    "ghcr.io/devcontainers/features/copilot-cli:1": {},
    "ghcr.io/devcontainers-extra/features/claude-code:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/python:1": {}
  },
```

- [ ] **Step 3: Add the same feature to the local devcontainer**

In `.devcontainer/local/devcontainer.json`, the current `features` block is identical to the one above. Apply the same one-line addition (`"ghcr.io/devcontainers/features/python:1": {}` as the last entry in `features`).

- [ ] **Step 4: Verify both devcontainer JSON files still parse**

Run: `python3 -m json.tool .devcontainer/devcontainer.json > /dev/null && python3 -m json.tool .devcontainer/local/devcontainer.json > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 5: Verify `tests/requirements.txt` actually installs**

Run: `python3 -m venv /tmp/verify-tests-venv && /tmp/verify-tests-venv/bin/pip install -q -r tests/requirements.txt && /tmp/verify-tests-venv/bin/python3 -m pytest --version && rm -rf /tmp/verify-tests-venv`
Expected: a pytest version string printed, no errors.

- [ ] **Step 6: Commit**

```bash
git add tests/requirements.txt .devcontainer/devcontainer.json .devcontainer/local/devcontainer.json
git commit -m "Provision Python in the devcontainer for the test suite"
```

---

### Task 3: Fast skill-behavior tests for convert-pdf-to-md

**Files:**
- Create: `tests/claude-code/test-helpers.sh`
- Create: `tests/claude-code/test-convert-pdf-to-md.sh`
- Create: `tests/claude-code/run-skill-tests.sh`

**Interfaces:**
- Consumes: the `convert-pdf-to-md` skill's documented claims at `plugins/convert-pdf-to-md/skills/convert-pdf-to-md/SKILL.md` (implicit-trigger wording, the "run the script, don't ad-hoc parse" rule, the default-output-location rule, the mixed-file-type rule).
- Produces (for Task 4): `run_claude(prompt, timeout, allowed_tools)`, `assert_contains(output, pattern, name)`, `assert_not_contains(output, pattern, name)`, `assert_count(output, pattern, count, name)`, `assert_order(output, pattern_a, pattern_b, name)` — all bash functions exported from `test-helpers.sh`. Also produces `run-skill-tests.sh`'s `tests=(...)`/`integration_tests=(...)` arrays, which Task 4 extends.

- [ ] **Step 1: Write the test helper library**

```bash
#!/usr/bin/env bash
# Helper functions for Claude Code skill tests. Ported from
# https://github.com/obra/superpowers tests/claude-code/test-helpers.sh.

# Run Claude Code with a prompt and capture output
# Usage: run_claude "prompt text" [timeout_seconds] [allowed_tools]
run_claude() {
    local prompt="$1"
    local timeout="${2:-60}"
    local allowed_tools="${3:-}"
    local output_file
    output_file=$(mktemp)

    local cmd=(claude -p "$prompt")
    if [ -n "$allowed_tools" ]; then
        cmd+=(--allowed-tools="$allowed_tools")
    fi

    # Redirect stdin from /dev/null: `claude -p` otherwise waits ~3s for
    # stdin and prints a warning that would pollute the captured output.
    if timeout "$timeout" "${cmd[@]}" < /dev/null > "$output_file" 2>&1; then
        cat "$output_file"
        rm -f "$output_file"
        return 0
    else
        local exit_code=$?
        cat "$output_file" >&2
        rm -f "$output_file"
        return $exit_code
    fi
}

# Check if output contains a pattern
# Usage: assert_contains "output" "pattern" "test name"
# Matching is case-insensitive: patterns are prose keywords, and models
# freely capitalize skill terms.
assert_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"

    if echo "$output" | grep -qi "$pattern"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected to find: $pattern"
        echo "  In output:"
        echo "$output" | sed 's/^/    /'
        return 1
    fi
}

# Check if output does NOT contain a pattern
# Usage: assert_not_contains "output" "pattern" "test name"
assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"

    if echo "$output" | grep -qi "$pattern"; then
        echo "  [FAIL] $test_name"
        echo "  Did not expect to find: $pattern"
        echo "  In output:"
        echo "$output" | sed 's/^/    /'
        return 1
    else
        echo "  [PASS] $test_name"
        return 0
    fi
}

# Check if output matches a count
# Usage: assert_count "output" "pattern" expected_count "test name"
assert_count() {
    local output="$1"
    local pattern="$2"
    local expected="$3"
    local test_name="${4:-test}"

    local actual
    actual=$(echo "$output" | grep -ci "$pattern" || echo "0")

    if [ "$actual" -eq "$expected" ]; then
        echo "  [PASS] $test_name (found $actual instances)"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected $expected instances of: $pattern"
        echo "  Found $actual instances"
        echo "  In output:"
        echo "$output" | sed 's/^/    /'
        return 1
    fi
}

# Check if pattern A appears before pattern B
# Usage: assert_order "output" "pattern_a" "pattern_b" "test name"
assert_order() {
    local output="$1"
    local pattern_a="$2"
    local pattern_b="$3"
    local test_name="${4:-test}"

    local line_a
    local line_b
    line_a=$(echo "$output" | grep -ni "$pattern_a" | head -1 | cut -d: -f1)
    line_b=$(echo "$output" | grep -ni "$pattern_b" | head -1 | cut -d: -f1)

    if [ -z "$line_a" ]; then
        echo "  [FAIL] $test_name: pattern A not found: $pattern_a"
        echo "  In output:"
        echo "$output" | sed 's/^/    /'
        return 1
    fi

    if [ -z "$line_b" ]; then
        echo "  [FAIL] $test_name: pattern B not found: $pattern_b"
        echo "  In output:"
        echo "$output" | sed 's/^/    /'
        return 1
    fi

    if [ "$line_a" -lt "$line_b" ]; then
        echo "  [PASS] $test_name (A at line $line_a, B at line $line_b)"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected '$pattern_a' before '$pattern_b'"
        echo "  But found A at line $line_a, B at line $line_b"
        return 1
    fi
}

export -f run_claude
export -f assert_contains
export -f assert_not_contains
export -f assert_count
export -f assert_order
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x tests/claude-code/test-helpers.sh`

- [ ] **Step 3: Write the fast description-recall test**

```bash
#!/usr/bin/env bash
# Test: convert-pdf-to-md skill content and requirements.
# Description-recall style, not real execution — see
# test-convert-pdf-to-md-integration.sh for end-to-end behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"

echo "=== Test: convert-pdf-to-md skill ==="
echo ""

echo "Test 1: Implicit trigger recognition..."
output=$(run_claude "Without mentioning the word 'convert', does the convert-pdf-to-md skill trigger when a user asks you to 'summarize' or 'extract data from' a PDF file? Answer using exactly this structure:
Triggers on summarize: <yes or no>
Triggers on extract data from: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Triggers on summarize:.*yes" "Triggers on 'summarize'"
assert_contains "$output" "Triggers on extract data from:.*yes" "Triggers on 'extract data from'"
echo ""

echo "Test 2: Discipline rule (no ad-hoc parsing)..."
output=$(run_claude "According to the convert-pdf-to-md skill, is it acceptable to write ad-hoc Python code to parse a PDF's content directly instead of running the bundled script? Answer using exactly this structure:
Ad-hoc parsing acceptable: <yes or no>
Must run bundled script: <yes or no>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Ad-hoc parsing acceptable:.*no" "Ad-hoc parsing not acceptable"
assert_contains "$output" "Must run bundled script:.*yes" "Must run bundled script"
echo ""

echo "Test 3: Default output location..."
output=$(run_claude "According to the convert-pdf-to-md skill, where does the output folder go by default, and when should the -o flag be used? Answer using exactly this structure:
Default location: <next to source or elsewhere>
Use -o flag when: <condition>" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "Default location:.*next to.*source" "Default location is next to source"
assert_contains "$output" "Use -o flag when:.*explicit" "-o only on explicit user request"
echo ""

echo "Test 4: Mixed file type rule..."
output=$(run_claude "If a user references a folder containing both .pdf and .docx files, does the convert-pdf-to-md skill say to invoke sibling skills for the other file types, or only handle the .pdf files and ignore the rest?" "$CLAUDE_PROMPT_TIMEOUT")

assert_contains "$output" "convert-word-to-md" "Mentions the convert-word-to-md sibling skill"
echo ""

echo "=== All convert-pdf-to-md skill tests passed ==="
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x tests/claude-code/test-convert-pdf-to-md.sh`

- [ ] **Step 5: Write the test runner**

```bash
#!/usr/bin/env bash
# Test runner for this repo's Claude Code skill-behavior tests.
# Ported from https://github.com/obra/superpowers tests/claude-code/run-skill-tests.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo " common-agent-marketplace Skills Test Suite"
echo "========================================"
echo ""
echo "Repository: $(cd ../.. && pwd)"
echo "Test time: $(date)"
echo "Claude version: $(claude --version 2>/dev/null || echo 'not found')"
echo ""

if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code CLI not found"
    echo "Install Claude Code first: https://code.claude.com"
    exit 1
fi

VERBOSE=false
SPECIFIC_TEST=""
TIMEOUT=900
RUN_INTEGRATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --test|-t)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --integration|-i)
            RUN_INTEGRATION=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --verbose, -v        Show verbose output"
            echo "  --test, -t NAME      Run only the specified test"
            echo "  --timeout SECONDS    Set timeout per test (default: 900)"
            echo "  --integration, -i    Run integration tests (slow, requires markitdown/pymupdf)"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Tests:"
            echo "  test-convert-pdf-to-md.sh  Skill content and requirements"
            echo ""
            echo "Integration Tests (use --integration):"
            echo "  test-convert-pdf-to-md-integration.sh  Real end-to-end conversion"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

tests=(
    "test-convert-pdf-to-md.sh"
)

integration_tests=(
    "test-convert-pdf-to-md-integration.sh"
)

if [ "$RUN_INTEGRATION" = true ]; then
    tests+=("${integration_tests[@]}")
fi

if [ -n "$SPECIFIC_TEST" ]; then
    tests=("$SPECIFIC_TEST")
fi

passed=0
failed=0
skipped=0

for test in "${tests[@]}"; do
    echo "----------------------------------------"
    echo "Running: $test"
    echo "----------------------------------------"

    test_path="$SCRIPT_DIR/$test"

    if [ ! -f "$test_path" ]; then
        echo "  [SKIP] Test file not found: $test"
        skipped=$((skipped + 1))
        continue
    fi

    if [ ! -x "$test_path" ]; then
        echo "  Making $test executable..."
        chmod +x "$test_path"
    fi

    start_time=$(date +%s)

    if [ "$VERBOSE" = true ]; then
        if timeout "$TIMEOUT" bash "$test_path"; then
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            echo ""
            echo "  [PASS] $test (${duration}s)"
            passed=$((passed + 1))
        else
            exit_code=$?
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            echo ""
            if [ $exit_code -eq 124 ]; then
                echo "  [FAIL] $test (timeout after ${TIMEOUT}s)"
            else
                echo "  [FAIL] $test (${duration}s)"
            fi
            failed=$((failed + 1))
        fi
    else
        if output=$(timeout "$TIMEOUT" bash "$test_path" 2>&1); then
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            echo "  [PASS] (${duration}s)"
            passed=$((passed + 1))
        else
            exit_code=$?
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            if [ $exit_code -eq 124 ]; then
                echo "  [FAIL] (timeout after ${TIMEOUT}s)"
            else
                echo "  [FAIL] (${duration}s)"
            fi
            echo ""
            echo "  Output:"
            echo "$output" | sed 's/^/    /'
            failed=$((failed + 1))
        fi
    fi

    echo ""
done

echo "========================================"
echo " Test Results Summary"
echo "========================================"
echo ""
echo "  Passed:  $passed"
echo "  Failed:  $failed"
echo "  Skipped: $skipped"
echo ""

if [ "$RUN_INTEGRATION" = false ] && [ ${#integration_tests[@]} -gt 0 ]; then
    echo "Note: Integration tests were not run (they take several minutes and"
    echo "require markitdown/pymupdf installed)."
    echo "Use --integration flag to run them."
    echo ""
fi

if [ $failed -gt 0 ]; then
    echo "STATUS: FAILED"
    exit 1
else
    echo "STATUS: PASSED"
    exit 0
fi
```

- [ ] **Step 6: Make it executable**

Run: `chmod +x tests/claude-code/run-skill-tests.sh`

- [ ] **Step 7: Run the fast suite and confirm it passes**

Run: `./tests/claude-code/run-skill-tests.sh`
Expected: `STATUS: PASSED`, with `Passed: 1` (the one fast test file) and `Skipped: 1` (the integration test file doesn't exist until Task 4 — the runner reports it as `[SKIP] Test file not found`, not a failure). If `convert-pdf-to-md` isn't installed as a plugin in your Claude Code setup, `claude -p` still answers correctly in practice because Claude Code auto-discovers `skills/*/SKILL.md` under the current repo even without an explicit `/plugin install` — this was confirmed live while writing this plan. If your setup differs, install the plugin per the root README first.

- [ ] **Step 8: Commit**

```bash
git add tests/claude-code/test-helpers.sh tests/claude-code/test-convert-pdf-to-md.sh tests/claude-code/run-skill-tests.sh
git commit -m "Add fast skill-behavior tests for convert-pdf-to-md"
```

---

### Task 4: Integration skill-behavior test for convert-pdf-to-md

**Files:**
- Create: `tests/claude-code/fixtures/generate_sample_pdf.py`
- Create: `tests/claude-code/test-convert-pdf-to-md-integration.sh`
- Create: `tests/claude-code/README.md`
- Modify: `tests/claude-code/run-skill-tests.sh` (already lists `test-convert-pdf-to-md-integration.sh` in `integration_tests` from Task 3 — no change needed there; this task just makes that filename resolve to a real file)

**Interfaces:**
- Consumes: `run_claude`, `assert_contains` from `test-helpers.sh` (Task 3); `convert_pdf_to_md.py` at `plugins/convert-pdf-to-md/skills/convert-pdf-to-md/scripts/convert_pdf_to_md.py`, invoked exactly as a user would (`python3 <script> <pdf>`), not imported.
- Produces: `generate_sample_pdf(dest_path: Path, text: str = SAMPLE_TEXT) -> None` in `generate_sample_pdf.py`, callable standalone via `python3 generate_sample_pdf.py <dest_path>`.

- [ ] **Step 1: Write the fixture PDF generator**

```python
"""Write a minimal, valid, single-page PDF using raw PDF object syntax.

No third-party dependencies (no reportlab/fpdf) -- this exists purely so
tests don't need to commit a binary .pdf fixture to git.
"""
from pathlib import Path

SAMPLE_TEXT = "Sample Invoice for Acme Corp. Total: 42.00 USD"


def generate_sample_pdf(dest_path: Path, text: str = SAMPLE_TEXT) -> None:
    """Write a one-page PDF containing `text` to `dest_path`."""
    content_stream = f"BT /F1 24 Tf 72 712 Td ({text}) Tj ET"
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> "
        "/MediaBox [0 0 612 792] /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        f"<< /Length {len(content_stream)} >>\nstream\n{content_stream}\nendstream",
    ]

    header = b"%PDF-1.4\n"
    body_parts = []
    offsets = [0]  # object 0 is the free-list head, offset unused
    offset = len(header)
    for i, obj in enumerate(objects, start=1):
        obj_bytes = f"{i} 0 obj\n{obj}\nendobj\n".encode("latin-1")
        offsets.append(offset)
        body_parts.append(obj_bytes)
        offset += len(obj_bytes)

    body = b"".join(body_parts)
    xref_offset = len(header) + len(body)

    xref_lines = [f"xref\n0 {len(objects) + 1}\n", "0000000000 65535 f \n"]
    for off in offsets[1:]:
        xref_lines.append(f"{off:010d} 00000 n \n")
    xref = "".join(xref_lines).encode("latin-1")

    trailer = (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n"
    ).encode("latin-1")

    dest_path.write_bytes(header + body + xref + trailer)


if __name__ == "__main__":
    import sys

    generate_sample_pdf(Path(sys.argv[1]))
```

Write this to `tests/claude-code/fixtures/generate_sample_pdf.py`.

- [ ] **Step 2: Verify the fixture is a genuinely valid, readable PDF**

Run: `python3 tests/claude-code/fixtures/generate_sample_pdf.py /tmp/verify-fixture.pdf && python3 -c "
from pathlib import Path
import subprocess
result = subprocess.run(['python3', '-c', 'print(Path(\"/tmp/verify-fixture.pdf\").read_bytes()[:8])'], capture_output=True, text=True)
print(result.stdout)
"`

Simpler equivalent if `pdftotext` (poppler-utils) is available: `python3 tests/claude-code/fixtures/generate_sample_pdf.py /tmp/verify-fixture.pdf && pdftotext /tmp/verify-fixture.pdf - && rm /tmp/verify-fixture.pdf`
Expected: prints `Sample Invoice for Acme Corp. Total: 42.00 USD`. (This was independently confirmed while writing this plan — the generator produces byte-for-byte extractable text.) If `pdftotext` isn't available, it's fine to skip this step's tool-based check — Step 5 below (running the real `convert_pdf_to_md.py` against the fixture) is the authoritative check and doesn't depend on `pdftotext`.

- [ ] **Step 3: Write the integration test**

```bash
#!/usr/bin/env bash
# Integration test: convert-pdf-to-md skill, real end-to-end execution.
#
# KNOWN BASELINE FAILURE (documented 2026-08-15, not a bug in this test):
# The Application scenario below currently FAILS against the real skill.
# Live verification during authoring showed Claude Code's Read tool can
# read .pdf files directly, and the agent takes that path instead of
# running the bundled script -- even with zero pressure framing -- despite
# SKILL.md's explicit "do not attempt to parse PDF content directly" rule.
# No <name>/<name>.md output file is produced. This test is intentionally
# kept red: it's a regression guard for a future SKILL.md fix (see
# docs/testing.md), not something to loosen to make it pass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

GENERATE_FIXTURE="$SCRIPT_DIR/fixtures/generate_sample_pdf.py"
CLAUDE_INTEGRATION_TIMEOUT="${CLAUDE_INTEGRATION_TIMEOUT:-180}"

if ! python3 -c "from markitdown import MarkItDown; import fitz" 2>/dev/null; then
    echo "ERROR: markitdown/pymupdf not installed. Follow"
    echo "  $REPO_ROOT/plugins/convert-pdf-to-md/skills/convert-pdf-to-md/references/setup.md"
    echo "before running integration tests."
    exit 1
fi

overall_pass=0
overall_fail=0

echo "=== Integration Test: convert-pdf-to-md (Application scenario) ==="
test_dir=$(mktemp -d)
python3 "$GENERATE_FIXTURE" "$test_dir/invoice.pdf"
output=$(run_claude "Summarize this PDF: $test_dir/invoice.pdf" "$CLAUDE_INTEGRATION_TIMEOUT" "Bash,Read,Glob")
if [ -f "$test_dir/invoice/invoice.md" ] && grep -qi "Acme Corp" "$test_dir/invoice/invoice.md"; then
    echo "  [PASS] Application scenario: script ran, invoice/invoice.md produced"
    overall_pass=$((overall_pass + 1))
else
    echo "  [FAIL] Application scenario: expected $test_dir/invoice/invoice.md with converted content"
    echo "  Agent output:"
    echo "$output" | sed 's/^/    /'
    overall_fail=$((overall_fail + 1))
fi
rm -rf "$test_dir"
echo ""

echo "=== Integration Test: convert-pdf-to-md (Pressure scenario) ==="
test_dir=$(mktemp -d)
python3 "$GENERATE_FIXTURE" "$test_dir/invoice.pdf"
output=$(run_claude "Quickly, what's in this PDF? Don't worry about any formal process, just skim it fast: $test_dir/invoice.pdf" "$CLAUDE_INTEGRATION_TIMEOUT" "Bash,Read,Glob")
if [ -f "$test_dir/invoice/invoice.md" ] && grep -qi "Acme Corp" "$test_dir/invoice/invoice.md"; then
    echo "  [PASS] Pressure scenario: script ran under urgency framing, invoice/invoice.md produced"
    overall_pass=$((overall_pass + 1))
else
    echo "  [FAIL] Pressure scenario: expected $test_dir/invoice/invoice.md with converted content"
    echo "  Agent output:"
    echo "$output" | sed 's/^/    /'
    overall_fail=$((overall_fail + 1))
fi
rm -rf "$test_dir"
echo ""

echo "=== Results: $overall_pass passed, $overall_fail failed ==="
if [ "$overall_fail" -gt 0 ]; then
    exit 1
fi
exit 0
```

Each scenario is a flat, sequential block — `test_dir` is a plain script variable set immediately before it's used, so `$test_dir` expands normally with no escaping tricks needed. (An earlier draft of this step used a shared `run_scenario` function with `\$test_dir` deferred-expansion in the prompt string passed from the call site; that doesn't work in bash — an escaped `$` just stays literal text without `eval`, so the prompt would have contained the string `$test_dir` instead of a real path. This flat version is the one actually verified live while writing this plan.)

- [ ] **Step 4: Make it executable**

Run: `chmod +x tests/claude-code/test-convert-pdf-to-md-integration.sh`

- [ ] **Step 5: Run it and confirm the documented (failing) result**

Prerequisite: `python3 -m pip install --break-system-packages "markitdown[pdf]" pymupdf` (or install into a venv and activate it) and the `convert-pdf-to-md` plugin discoverable by `claude -p` (see Task 3, Step 7).

Run: `./tests/claude-code/test-convert-pdf-to-md-integration.sh`
Expected: `[FAIL] Application scenario` (and likely `[FAIL] Pressure scenario` too) with exit code `1` — this matches the Global Constraints section's documented known gap. Confirm the failure reason printed matches "expected .../invoice/invoice.md with converted content" — if you instead see an unrelated error (e.g. a Python traceback, `command not found`, or a timeout with no agent output at all), that's a real bug in the test script itself and must be fixed before proceeding, since it would be a different failure than the documented one.

- [ ] **Step 6: Write the README**

```markdown
# Claude Code Skill Tests

Bash tests for this repo's skills, using the `claude` CLI in headless mode.
Ported from [obra/superpowers](https://github.com/obra/superpowers)'s
`tests/claude-code/`.

## Requirements

- `claude` CLI on PATH (`claude --version` should work).
- The plugin whose skill you're testing discoverable by `claude -p` — either
  installed (`/plugin marketplace add .` then `/plugin install <plugin-name>`
  from within this repo) or auto-discovered because you're running from
  within this repo (Claude Code auto-discovers `skills/*/SKILL.md` under the
  current project).
- For `--integration` tests: whatever the skill under test itself needs.
  For `convert-pdf-to-md`, that's `markitdown`+`pymupdf` — see
  `plugins/convert-pdf-to-md/skills/convert-pdf-to-md/references/setup.md`.

## Running

```bash
# Fast tests (default)
./run-skill-tests.sh

# Integration tests too (slow, several minutes, needs the skill's own deps)
./run-skill-tests.sh --integration

# One specific test file
./run-skill-tests.sh --test test-convert-pdf-to-md.sh

# Full output, not just pass/fail
./run-skill-tests.sh --verbose
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

`./run-skill-tests.sh --verbose --test <file>` shows full output, not just
the failure summary.
```

- [ ] **Step 7: Commit**

```bash
git add tests/claude-code/fixtures/generate_sample_pdf.py tests/claude-code/test-convert-pdf-to-md-integration.sh tests/claude-code/README.md
git commit -m "Add integration skill-behavior test for convert-pdf-to-md"
```

---

### Task 5: `docs/testing.md`

**Files:**
- Create: `docs/testing.md`

**Interfaces:**
- Consumes: nothing (pure documentation).
- Produces: nothing consumed by other tasks; referenced by Task 6's `CONTRIBUTING.md` update.

- [ ] **Step 1: Write the file**

```markdown
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

# Skill-behavior tests (fast)
./tests/claude-code/run-skill-tests.sh

# Skill-behavior tests (fast + integration; also needs markitdown/pymupdf,
# see plugins/convert-pdf-to-md/skills/convert-pdf-to-md/references/setup.md)
./tests/claude-code/run-skill-tests.sh --integration
```

## Known state: convert-pdf-to-md's integration test is a documented failure

`tests/claude-code/test-convert-pdf-to-md-integration.sh`'s Application
scenario currently fails against the real skill: Claude Code's `Read` tool
can read `.pdf` files directly, and the agent takes that path instead of
running the bundled script, even with zero pressure framing — despite
SKILL.md's explicit "do not attempt to parse PDF content directly" rule.
This was confirmed by live testing while building this harness (see
`docs/superpowers/plans/2026-08-15-plugin-validation-testing.md`, Task 4).
The test is intentionally kept red as a regression guard for whichever
future change closes that loophole in SKILL.md — don't loosen the
assertion to make it pass.

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
  template)? No tests needed — same as `example-plugin` today.
```

- [ ] **Step 2: Commit**

```bash
git add docs/testing.md
git commit -m "Add docs/testing.md"
```

---

### Task 6: Update `CONTRIBUTING.md`'s Tooling section

**Files:**
- Modify: `CONTRIBUTING.md`

**Interfaces:**
- Consumes: `docs/testing.md` (Task 5), by reference (a link).
- Produces: nothing.

- [ ] **Step 1: Replace the Tooling section**

The current section at the end of `CONTRIBUTING.md` reads:

```markdown
## Tooling

There's no CI, linter, or build step yet — plugins are validated by hand
(JSON parses, referenced paths exist, frontmatter fields are present). Add
tooling here when a real validation gap shows up.
```

Replace it with:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "Point CONTRIBUTING.md's Tooling section at docs/testing.md"
```
