# PROJECT KNOWLEDGE BASE

**Generated:** 2026-02-21
**Repository:** dotfiles-core (Meta-Repository / Orchestrator)

## OVERVIEW

`dotfiles-core` is a **meta-repository** that orchestrates multiple independent dotfiles repositories (`dotfiles-zsh`, `dotfiles-vim`, `dotfiles-ai`, etc.). It uses the "Meta-Repository Pattern" with a "Flat Layout" to eliminate Git Submodule complexity.

**Core Purpose:** One-command bootstrap for a fully modularized development environment on Ubuntu.

## BUILD / LINT / TEST COMMANDS

This repository has **no tests, no lint, no build**. It is purely an orchestrator.

| Task | Command | Description |
| :--- | :--- | :--- |
| **Full Setup** | `make setup` | Install deps, sync repos, resolve secrets, link files, delegate to components |
| **Init** | `make init` | Install `vcstool`, `stow`, `jq` and clone all repos |
| **Sync** | `make sync` | Pull latest changes for all components via `vcstool` |
| **Link** | `make link` | Apply symlinks from `components/` to `~` using GNU Stow |
| **Secrets** | `make secrets` | Resolve credentials via Bitwarden CLI (`bw`) |
| **Clean** | `make clean` | Remove all components (CAUTION: destructive) |

## DIRECTORY STRUCTURE

```text
~/dotfiles/                     <-- [dotfiles-core] (this repo)
├── .gitignore                  <-- Excludes "components/"
├── Makefile                    <-- Main dispatcher
├── repos.yaml                  <-- vcstool repository manifest
├── README.md                   <-- User documentation
├── SPEC.md                     <-- Detailed specification
├── GEMINI.md                   <-- Gemini CLI context
├── scripts/                    <-- Management scripts (TBD)
└── components/                 <-- Cloned repos (ignored by Git)
    ├── dotfiles-zsh/           <-- [Repo: dotfiles-zsh]
    ├── dotfiles-vim/           <-- [Repo: dotfiles-vim]
    ├── dotfiles-git/           <-- [Repo: dotfiles-git]
    ├── dotfiles-term/          <-- [Repo: dotfiles-term]
    ├── dotfiles-ide/           <-- [Repo: dotfiles-ide]
    ├── dotfiles-ai/            <-- [Repo: dotfiles-ai]
    └── dotfiles-gnome/         <-- [Repo: dotfiles-gnome]
```

## CODE STYLE GUIDELINES

### Language

- **Documentation**: Japanese (日本語) for README, comments, and user-facing text
- **AGENTS.md**: English (for AI agent consumption)
- **Commit Messages**: Japanese (e.g., `feat: 新機能追加`, `fix: バグ修正`)

### Shell Scripts (Bash)

When writing shell scripts in `scripts/` or inline in Makefile:

```bash
# Path resolution: Always resolve paths dynamically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Error handling: Use set -e for fail-fast behavior
set -euo pipefail

# Logging: Use echo with prefixes
echo "==> Doing something..."
echo "ERROR: Something failed" >&2

# Idempotency: Check before creating
mkdir -p "${TARGET_DIR}"  # -p is idempotent
```

### Makefile Conventions

```makefile
# Use .PHONY for non-file targets
.PHONY: help init sync link secrets setup clean

# Use variables for paths
COMPONENTS_DIR := components
STOW_TARGET := $(HOME)

# Echo progress for user feedback
init:
 @echo "==> Initializing dependencies..."

# Use @for loops with proper escaping
link:
 @for dir in $(shell find $(COMPONENTS_DIR) -maxdepth 1 -mindepth 1 -type d); do \
  name=$$(basename $$dir); \
  echo "Stowing $$name..."; \
  stow --restow --target=$(STOW_TARGET) --dir=$(COMPONENTS_DIR) $$name; \
 done
```

### YAML (repos.yaml)

```yaml
repositories:
  components/dotfiles-<name>:
    type: git
    url: git@github.com:yohi/dotfiles-<name>.git
    version: master  # or main
```

## ARCHITECTURAL PRINCIPLES

### 1. Idempotency (冪等性)

All operations must be safe to run multiple times:

- `make setup` should never break an existing environment
- Use `mkdir -p`, `stow --restow`, idempotent shell patterns

### 2. Minimalism

`dotfiles-core` should remain thin:

- Orchestration logic only
- No component-specific configuration
- Delegate to component Makefiles

### 3. Component Delegation

When `make setup` runs:

1. Check if `components/<name>/Makefile` exists
2. Check if `setup` target is defined (`grep -q "^setup:"`)
3. If both true: `$(MAKE) -C "$dir" setup`

### 4. No Git Submodules

**NEVER** use `git submodule`. Always use `vcstool` + `repos.yaml`.

### 5. Security

- **NEVER** commit secrets in plaintext
- Use Bitwarden CLI (`bw`) for credential resolution
- `.gitignore` must exclude `.bw_session`, `*.log`, `.tmp/`

## PATH RESOLUTION PATTERN

Each component's scripts must resolve paths dynamically:

```bash
# Correct: Dynamic resolution
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Wrong: Hardcoded paths
# source ~/dotfiles/components/dotfiles-zsh/config.sh
```

## FORBIDDEN OPERATIONS

If `opencode.jsonc` exists, this section applies as **AI agent runtime constraints**.
These restrictions are not global project rules for humans: legitimate operations by developers, CI, or repository automation (for example, controlled `sudo`/`rm` usage in `Makefile`) can still be valid.
If exceptions are allowed for agent execution, they must be explicitly declared in `opencode.jsonc`.

Per `opencode.jsonc` (when present), these operations are blocked for agent execution unless explicitly allowed:

- `rm` (destructive file operations)
- `ssh` (remote access)
- `sudo` (privilege escalation)

## KEY FILES TO REFERENCE

| File | Purpose |
| :--- | :--- |
| `Makefile` | Main entry point, all targets |
| `repos.yaml` | Repository manifest for vcstool |
| `SPEC.md` | Detailed specification and requirements |
| `GEMINI.md` | Project context for Gemini CLI |
| `COMPONENT_LAYOUT.md` | Component directory/file structure convention (all repos must comply) |

## COMMON TASKS

### Adding a New Component

1. Add entry to `repos.yaml`:

   ```yaml
   components/dotfiles-<name>:
     type: git
     url: git@github.com:yohi/dotfiles-<name>.git
     version: master
   ```

2. Run `make sync` to clone
3. Create `Makefile` with `setup` target in the component repo

### Debugging Stow Issues

```bash
# Dry-run (explicit single-component form)
stow --no --target=$HOME --dir=components/dotfiles-zsh .

# Dry-run (Makefile loop form)
stow --no --target=$HOME --dir=$(COMPONENTS_DIR) $$name

# Restow (explicit single-component form)
stow --restow --target=$HOME --dir=components/dotfiles-zsh .

# Restow (Makefile loop form)
stow --restow --target=$HOME --dir=$(COMPONENTS_DIR) $$name
```

### Checking Component Status

```bash
# List all components
ls -la components/

# Check git status of all components
vcs status components/
```

## TARGET ENVIRONMENT

- **OS**: Ubuntu 22.04 / 24.04 LTS
- **Shell**: Bash / Zsh
- **Required Tools**: GNU Make, Python3, curl, jq, GNU Stow
