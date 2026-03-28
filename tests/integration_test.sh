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
        if [ $exit_code -ne 0 ]; then
            echo "ERROR: Expected success, but got exit code $exit_code"
            exit 1
        fi
    else
        if [ $exit_code -eq 0 ]; then
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

echo "==> [Test] All mock-based integration tests PASSED!"
