# Component Layout Convention

> **Scope**: All micro-repositories under `components/`

## Overview

Each component repository adopts a flat layout designed for explicit symbolic link deployment (`ln -sfn`) and automation via Make.
This convention ensures consistency across repositories and simplifies scaffolding when adding new components.

---

## Directory Structure Template

```text
dotfiles-<name>/
├── .git/
├── .gitignore
├── Makefile                     # [Required] Entry point with 'setup' and 'link' targets
├── README.md                    # [Required] Component overview
├── LICENSE                      # [Required] License file (MIT)
├── AGENTS.md                    # [Required] Instructions and task definitions for AI agents
│
├── _mk/                          # [Optional] For split Makefile modules
│   ├── <feature-a>.mk
│   └── <feature-b>.mk
│
├── _bin/                        # [Optional] Executable scripts to be added to $PATH
│   └── <script-name>
│
├── _scripts/                    # [Optional] Internal utilities (not in $PATH)
│   └── <internal-helper>.sh
│
├── _docs/                       # [Optional] Detailed documentation
│   └── <topic>.md
│
├── _tests/                      # [Optional] Test scripts
│   └── test-<feature>.sh
│
├── <tool-specific-dir>/         # [Link Target] Tool-specific configuration directories
│   └── ...                      #   e.g., starship/, prompts/, claude/, opencode/
│
└── <file>                       # [Link Target] Configuration files (explicitly linked by component Makefile)
                                 #   e.g., zshrc -> ~/.zshrc
```

---

## File Classification Rules

### Required Files (Common to all components)

| File | Role | Remarks |
| :--- | :--- | :--- |
| `Makefile` | Exposes `setup` and `link` targets. Called by delegation from `dotfiles-core`. | Follows Makefile convention below. |
| `README.md` | Component overview and usage. | Documented in Japanese (or English). |
| `LICENSE` | License. | MIT |
| `AGENTS.md` | AI agent instructions and task definitions. | Essential for agentic workflows. |
| `.gitignore` | Git exclusion rules. | Standard practice. |

### Link Target Files (Linked to `~`)

Files placed at the repository root (e.g., `zshrc`) or directories should be symlinked to `~` using explicit `ln -sfn` commands in the component's Makefile. Since symbolic links are managed explicitly, there is no need to use a `dot-` or `.` prefix in the repository. You can use standard names (e.g., `zshrc`) and map them to hidden files in the target directory (e.g., linking `zshrc` to `~/.zshrc`).

**Principle**: Only configuration files directly required in the user's `$HOME` should be linked by the component's Makefile.

### Management and Development Files

The following files/directories are managed within the component but should not be linked to `~`:

| Item | Reason |
| :--- | :--- |
| `Makefile` | Build control file. |
| `README.md` / `QUICKSTART.md` | Documentation. |
| `LICENSE` | License file. |
| `.git` | Git metadata. |
| `.gitignore` | Git exclusion rules. |
| `_mk/` | Makefile modules. |
| `_bin/` | Scripts to be referenced via `$PATH` (not symlinked to `~`). |
| `_scripts/` | Internal utilities. |
| `_docs/` | Documentation. |
| `_tests/` | Tests. |
| `archive/` | Archives. |
| `examples/` | Configuration examples. |

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

.PHONY: link
link:
 @echo "==> Linking dotfiles-<name>"
 # Explicit ln -sfn commands go here
```

### Rules

1. **`setup` and `link` targets are mandatory**. These are the primary interfaces called by `dotfiles-core`.
2. **Set `.DEFAULT_GOAL := setup`**. This is especially important when including files from `_mk/`.
3. **Declare all non-file targets as `.PHONY`**.
4. **Use `_mk/` directory** for modularizing Makefiles. Keep the root `Makefile` clean with only the `setup` target and includes.
5. **Progress display**: Use `@echo "==> ..."` to notify the start of a process.

---

## `_bin/` vs `_scripts/`

| Directory | Purpose | Added to `$PATH` | Link Target |
| :--- | :--- | :--- | :--- |
| `_bin/` | **Public commands** called by users or other components. | ✅ Dynamically added via `dotfiles-zsh`. | ❌ Not linked to `~`. |
| `_scripts/` | **Internal helpers** used only within the component. | ❌ | ❌ Not linked to `~`. |

> [!NOTE]
> Following the decoupling pattern in `SPEC.md §3`, paths to `_bin/` are dynamically added in `.zshrc` (e.g., `export PATH="${DOTFILES_SHELL_ROOT}/../dotfiles-git/_bin:$PATH"`).

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

- [ ] `Makefile`: Must include `setup` and `link` targets.
- [ ] `README.md`: Component overview (in Japanese or English).
- [ ] `LICENSE`: MIT License file.
- [ ] `.gitignore`: Necessary exclusion rules.
- [ ] Register in `repos.yaml`: Update the central `dotfiles-core` repository.
- [ ] Verify Link operation: Perform a dry run with `make -n link`.
