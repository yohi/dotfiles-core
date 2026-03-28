# Design: Makefile and Integration Test Script Refactoring

Date: 2026-03-28
Topic: Makefile macro refactoring, .env loading improvement, and shell script local variables.

## 1. Problem Statement
The current `Makefile` and `tests/integration_test.sh` have several maintenance and reliability issues:
- **Makefile**:
    - Redundant `.env` loading logic in `dispatch` macro.
    - Silent failure of `.env` parsing due to `|| true`.
    - Unnecessary trailing empty lines at the end of the file.
- **tests/integration_test.sh**:
    - Global variable pollution by `exit_code` inside `run_test_make` function.

## 2. Proposed Changes

### 2.1 Makefile Refactoring
- **Define `LOAD_ENV` Macro**:
    Extract the `.env` loading logic into a reusable shell snippet.
    ```make
    LOAD_ENV = if [ -f .env ]; then \
        eval "$$(grep -v '^[[:space:]]*#' .env 2>/dev/null | sed -e 's/[[:space:]]*#.*//' -e 's/^[[:space:]]*//' -e '/^[[:space:]]*$$/d' -e "s/'/'\\\\''/g" -e "s/^\([^=]*\)=\(.*\)$$/export \1='\2';/")"; \
    fi
    ```
- **Improve Error Detection**:
    Remove `|| true` from `eval`. In the `dispatch` macro, capture the result of `LOAD_ENV` and report failures if they occur.
- **Clean EOF**:
    Remove extra blank lines at the end of `Makefile`.

### 2.2 Integration Test Script Fix
- **Localize `exit_code`**:
    Add `local exit_code` in `run_test_make` function.

## 3. Verification Plan
- **Manual Verification**: Run `make help` and `make status`.
- **Automated Tests**: Run `tests/integration_test.sh` via `make test`.
- **Error Handling Test**: Create a temporary component with a broken `.env` to verify that `make` now correctly reports the failure.
