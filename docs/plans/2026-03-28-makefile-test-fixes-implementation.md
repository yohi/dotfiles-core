# Makefile and Integration Test Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the refactoring of Makefile and integration tests, including error handling verification for .env loading.

**Architecture:** 
- Finalize Makefile cleanup (EOF blank lines).
- Extend `tests/integration_test.sh` to test failure scenarios (specifically broken .env files).
- Ensure the `dispatch` macro correctly reports and halts on target detection failures.

**Tech Stack:** 
- GNU Make
- Bash
- Docker (for testing)

---

### Task 1: Makefile Cleanup

**Files:**
- Modify: `Makefile` (EOF)

**Step 1: Remove trailing empty lines at the end of Makefile**

Run: `sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' Makefile`
(Or manually edit to ensure only one newline at EOF)

**Step 2: Verify cleanup**

Run: `cat -e Makefile | tail -n 3`
Expected: 
```
        fi$
```
(No extra empty lines with `$`)

**Step 3: Commit**

```bash
git add Makefile
git commit -m "refactor: remove extra blank lines at EOF of Makefile"
```

---

### Task 2: Implement Failure Detection Test Case

**Files:**
- Modify: `tests/integration_test.sh`
- Create: `tests/fixtures/components/mock-broken-env/Makefile`
- Create: `tests/fixtures/components/mock-broken-env/.env`

**Step 1: Create a mock component with a broken .env**

File: `tests/fixtures/components/mock-broken-env/Makefile`
```make
setup:
	@echo "Should not reach here"
```

File: `tests/fixtures/components/mock-broken-env/.env`
```
INVALID_VAR='unclosed quote
```

**Step 2: Add a new test scenario to `tests/integration_test.sh`**

Modify: `tests/integration_test.sh` (Add scenario 4)
```bash
    echo "==> [Test Scenario] Broken .env detection"
    local scenario4_dir="$TEMP_DIR/scenario4"
    mkdir -p "$scenario4_dir"
    cp -r tests/fixtures/components/mock-broken-env "$scenario4_dir/"
    
    # Run make test-dispatch. It should fail because LOAD_ENV fails due to unclosed quote.
    run_test_make "setup" "$scenario4_dir" "fail"
    
    # Verify that the error message from LOAD_ENV (eval) is present in the output
    # Note: Bash eval error for unclosed quote usually contains "unexpected EOF" or similar
    if grep -iq "unexpected EOF" "$TEMP_DIR/make_output.txt"; then
        echo "[OK] Broken .env detection PASSED."
    else
        echo "[ERROR] Broken .env detection FAILED: Error message not found in output."
        exit 1
    fi
```

**Step 3: Run the tests to verify failure detection**

Run: `make test`
Expected: `[OK] Broken .env detection PASSED.` and overall `All mock-based integration tests PASSED!`

**Step 4: Commit**

```bash
git add tests/integration_test.sh tests/fixtures/components/mock-broken-env/
git commit -m "test: add scenario for broken .env detection"
```

---

### Task 3: Final Verification

**Step 1: Run all tests in the worktree**

Run: `make test`
Expected: All tests pass.

**Step 2: Verify help and status**

Run: `make help` and `make status`
Expected: Normal operation.

**Step 3: Commit final state**

```bash
git commit --allow-empty -m "chore: finalize feature/make-rule changes"
```
