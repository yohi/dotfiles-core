#!/bin/bash
set -euo pipefail

echo "==> [Test] Starting mock-based integration tests..."

# Get absolute path of this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/components"

cd "$PROJECT_ROOT"

# Helper for testing make commands
run_test_make() {
    local target=$1
    local components_dir=$2
    local should_succeed=$3
    local exit_code
    
    echo "--- Testing target '$target' with components in '$components_dir' ---"
    
    # Run make test-dispatch to only test the dispatch macro logic
    set +e
    make test-dispatch TARGET="$target" COMPONENTS_DIR="$components_dir"
    exit_code=$?
    set -e
    
    if [ "$should_succeed" = "true" ]; then
        if [ "$exit_code" -ne 0 ]; then
            echo "ERROR: Expected success, but got exit code $exit_code"
            exit 1
        fi
    else
        if [ "$exit_code" -eq 0 ]; then
            echo "ERROR: Expected failure, but got exit code 0"
            exit 1
        fi
        echo "[OK] Command failed as expected (exit code $exit_code)."
    fi
}

# Create a clean temporary directory for each scenario
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# 1. Verify successful dispatch and .env loading
SCENARIO_1="$WORK_DIR/scenario1"
mkdir -p "$SCENARIO_1"
cp -r "$FIXTURES_DIR/mock-ok" "$SCENARIO_1/"
cp -r "$FIXTURES_DIR/mock-env" "$SCENARIO_1/"

echo "==> [Test Scenario] Success case and .env loading"
run_test_make "setup" "$SCENARIO_1" "true"
echo "[OK] Success case and .env loading PASSED."

# 2. Verify error detection
SCENARIO_2="$WORK_DIR/scenario2"
mkdir -p "$SCENARIO_2"
cp -r "$FIXTURES_DIR/mock-fail" "$SCENARIO_2/"

echo "==> [Test Scenario] Failure detection"
run_test_make "setup" "$SCENARIO_2" "false"
echo "[OK] Failure detection PASSED."

# 3. Verify target skip
SCENARIO_3="$WORK_DIR/scenario3"
mkdir -p "$SCENARIO_3"
cp -r "$FIXTURES_DIR/mock-ok" "$SCENARIO_3/"

echo "==> [Test Scenario] Skipping non-existent target"
run_test_make "non-existent-target" "$SCENARIO_3" "true"
echo "[OK] Skipping non-existent target PASSED."

# 4. Verify broken .env detection
SCENARIO_4="$WORK_DIR/scenario4"
mkdir -p "$SCENARIO_4"
cp -r "$FIXTURES_DIR/mock-broken-env" "$SCENARIO_4/"

echo "==> [Test Scenario] Broken .env detection"
output=$(run_test_make "setup" "$SCENARIO_4" "false" 2>&1)
echo "$output"
if echo "$output" | grep -q "\[ERROR\] Failed to parse \.env"; then
    echo "[OK] Broken .env detection PASSED."
else
    echo "ERROR: Expected parse error not found in output"
    exit 1
fi

# 5. Verify _inject_common_mk and symlinks
SCENARIO_5="$WORK_DIR/scenario5"
# Prepare temporary structure inside SCENARIO_5 to simulate root
mkdir -p "$SCENARIO_5/common-mk"
mkdir -p "$SCENARIO_5/components/mock-ok"
cp -r common-mk/. "$SCENARIO_5/common-mk/"
cp tests/fixtures/components/mock-ok/Makefile "$SCENARIO_5/components/mock-ok/"

echo "==> [Test Scenario] _inject_common_mk and symlinks"
# Run _inject_common_mk in the scenario 5 context
(cd "$SCENARIO_5" && COMPONENTS_DIR="components" make -f "$PROJECT_ROOT/Makefile" _inject_common_mk > /dev/null)

# Check symlinks (valid and not broken)
for f in _mk/help.mk _mk/idempotency.mk _mk/core.mk DOTFILES_COMMON_RULES.md; do
    target="$SCENARIO_5/components/mock-ok/$f"
    if [ ! -L "$target" ] || [ ! -e "$target" ]; then
        echo "ERROR: $f is not a valid symlink in mock-ok"
        exit 1
    fi
done

echo "[OK] _inject_common_mk and symlinks PASSED."

echo "==> [Test] All mock-based integration tests PASSED!"
