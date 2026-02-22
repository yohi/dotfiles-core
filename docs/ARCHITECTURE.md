# Component Layout Convention

> **Scope**: All micro-repositories under `components/`

## Overview

Each component repository adopts a flat layout designed for symbolic link deployment using GNU Stow and automation via Make.
This convention ensures consistency across repositories and simplifies scaffolding when adding new components.

---

## Directory Structure Template

```text
dotfiles-<name>/
├── .git/
├── .gitignore
├── .stow-local-ignore          # [Required] Stow exclusion rules
├── Makefile                     # [Required] Entry point with 'setup' target
├── README.md                    # [Required] Component overview
├── LICENSE                      # [Required] License file (MIT)
├── AGENTS.md                    # [Required] Instructions and task definitions for AI agents
│
├── _mk/                          # [Optional] For split Makefile modules
│   ├── <feature-a>.mk
│   └── <feature-b>.mk
│
├── bin/                         # [Optional] Executable scripts to be added to $PATH
│   └── <script-name>
│
├── scripts/                     # [Optional] Internal utilities (not in $PATH)
│   └── <internal-helper>.sh
│
├── docs/                        # [Optional] Detailed documentation
│   └── <topic>.md
│
├── tests/                       # [Optional] Test scripts
│   └── test-<feature>.sh
│
├── <tool-specific-dir>/         # [Stow Target] Tool-specific configuration directories
│   └── ...                      #   e.g., starship/, prompts/, claude/, opencode/
│
└── dot-<file>                   # [Stow Target] Dotfiles (expanded via Stow's --dotfiles)
                                 #   e.g., dot-zshrc -> ~/.zshrc
```

---

## File Classification Rules

### Required Files (Common to all components)

| File | Role | Remarks |
| :--- | :--- | :--- |
| `Makefile` | Exposes `setup` target. Called by delegation from `dotfiles-core`. | Follows Makefile convention below. |
| `.stow-local-ignore` | Lists files/directories that Stow should not link. | Follows .stow-local-ignore convention below. |
| `README.md` | Component overview and usage. | Documented in Japanese (or English). |
| `LICENSE` | License. | MIT |
| `AGENTS.md` | AI agent instructions and task definitions. | Essential for agentic workflows. |
| `.gitignore` | Git exclusion rules. | Standard practice. |

### Stow Target Files (Linked to `~`)

Files placed at the repository root (e.g., `dot-zshrc`) or directories are symlinked to `~` unless excluded by `.stow-local-ignore`. For configuration files intended to be hidden, use the `dot-` prefix; Stow's `--dotfiles` option will expand them correctly (e.g., `dot-zshrc` becomes `~/.zshrc`).

**Principle**: Only configuration files directly required in the user's `$HOME` should be expanded by Stow.

### Non-Stow Files (Management and Development)

The following files/directories must be listed in `.stow-local-ignore` to prevent them from being symlinked:

| Item | Reason |
| :--- | :--- |
| `Makefile` | Build control file. |
| `README.md` / `QUICKSTART.md` | Documentation. |
| `LICENSE` | License file. |
| `.git` | Git metadata. |
| `.gitignore` | Git exclusion rules. |
| `_mk/` | Makefile modules. |
| `bin/` | Scripts to be referenced via `$PATH` (not symlinked to `~`). |
| `scripts/` | Internal utilities. |
| `docs/` | Documentation. |
| `tests/` | Tests. |
| `archive/` | Archives. |
| `examples/` | Configuration examples. |

---

## `.stow-local-ignore` Convention

Every component MUST include a `.stow-local-ignore` file to prevent management files from being linked to `~`.

### Basic Template

```text
# === VCS / Meta ===
\.git
\.gitignore

# === Build / Docs ===
Makefile
README\.md
QUICKSTART\.md
LICENSE
AGENTS\.md

# === Management Dirs ===
_mk
scripts
docs
tests
archive
examples
bin
```

> [!IMPORTANT]
> Patterns in `.stow-local-ignore` are interpreted as **regular expressions**. Since `.` matches any character, escape it as `\.` for literal dots in filenames.
>
> [!TIP]
> Providing a `.stow-local-ignore` file **disables** Stow's default exclusion rules (like automatic exclusion of `README.*` or `LICENSE`). You must list them explicitly.

---

## Makefile Convention

### Basic Structure

```makefile
# dotfiles-<name> Makefile
.DEFAULT_GOAL := setup

# Include sub-targets from _mk/ if necessary
# include _mk/<feature>.mk

.PHONY: setup
setup:
 @echo "==> Setting up dotfiles-<name>"
 # Component-specific setup logic goes here
```

### Rules

1. **`setup` target is mandatory**. This is the primary interface called by `dotfiles-core`.
2. **Set `.DEFAULT_GOAL := setup`**. This is especially important when including files from `_mk/`.
3. **Declare all non-file targets as `.PHONY`**.
4. **Use `_mk/` directory** for modularizing Makefiles. Keep the root `Makefile` clean with only the `setup` target and includes.
5. **Progress display**: Use `@echo "==> ..."` to notify the start of a process.

---

## `bin/` vs `scripts/`

| Directory | Purpose | Added to `$PATH` | Stow Target |
| :--- | :--- | :--- | :--- |
| `bin/` | **Public commands** called by users or other components. | ✅ Dynamically added via `dotfiles-zsh`. | ❌ Excluded via `.stow-local-ignore`. |
| `scripts/` | **Internal helpers** used only within the component. | ❌ | ❌ Excluded via `.stow-local-ignore`. |

> [!NOTE]
> Following the decoupling pattern in `SPEC.md §3`, paths to `bin/` are dynamically added in `.zshrc` (e.g., `export PATH="${DOTFILES_SHELL_ROOT}/../dotfiles-git/bin:$PATH"`).

---

## Path Resolution Rules (Compliance with SPEC.md §3)

All scripts must perform defensive path resolution that does not depend on the current working directory.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Dynamically resolve the absolute path to the repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
```

**Prohibited Actions**:

- Hardcoded absolute paths (e.g., `~/dotfiles/components/dotfiles-zsh/...`).
- References using `$DOTFILES_DIR` from the previous monorepo architecture.

---

## New Component Checklist

When creating a new `dotfiles-<name>` repository, ensure the following are present:

- [ ] `Makefile`: Must include a `setup` target.
- [ ] `.stow-local-ignore`: Must explicitly list all management and non-configuration files.
- [ ] `README.md`: Component overview (in Japanese or English).
- [ ] `LICENSE`: MIT License file.
- [ ] `.gitignore`: Necessary exclusion rules.
- [ ] Register in `repos.yaml`: Update the central `dotfiles-core` repository.
- [ ] Verify Stow operation: Perform a dry run with `stow --no --verbose=2`.
