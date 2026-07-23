# Shell / Makefile Conventions

Read this when writing or editing scripts under `scripts/`, `ansible/*.sh`, or Makefile
logic in this repo. These are style guidelines, not enforced by a linter here — follow
existing patterns in neighboring files over these snippets whenever they conflict.

## Bash scripts

```bash
# Path resolution: always resolve paths dynamically, never hardcode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Fail fast
set -euo pipefail

# Logging: echo with prefixes
echo "==> Doing something..."
echo "ERROR: Something failed" >&2

# Idempotency: check before creating
mkdir -p "${TARGET_DIR}"  # -p is idempotent
```

Run `shellcheck` on any new or modified `.sh` file before considering it done.

## Makefile

```makefile
# Non-file targets must be .PHONY
.PHONY: help init sync link secrets setup clean

# Path variables at the top
COMPONENTS_DIR := components
STOW_TARGET := $(HOME)

# Progress echo per target
init:
	@echo "==> Initializing dependencies..."

# Delegate to components with a loop
link:
	@for dir in $$(find $(COMPONENTS_DIR) -maxdepth 1 -mindepth 1 -type d); do \
		if [ -f "$$dir/Makefile" ]; then \
			$(MAKE) -C "$$dir" link || true; \
		fi; \
	done
```

## `repos.yaml`

```yaml
repositories:
  components/dotfiles-<name>:
    type: git
    url: git@github.com:yohi/dotfiles-<name>.git
    version: master  # or main
```

## Path resolution rule

Every script must resolve its own location dynamically — never reference
`~/dotfiles/components/...` as a hardcoded path. See the snippet above.
