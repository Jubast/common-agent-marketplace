#!/usr/bin/env bash
# Test runner for this repo's Claude Code skill-behavior tests.
# Ported from https://github.com/obra/superpowers tests/claude-code/run-skill-tests.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " common-agent-marketplace Skills Test Suite"
echo "========================================"
echo ""
echo "Repository: $(cd "$SCRIPT_DIR/../.." && pwd)"
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
            echo "  test-clean-code.sh         Skill content and trigger conditions"
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
    "test-clean-code.sh"
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
