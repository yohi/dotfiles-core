# Project Conventions (Detail)

Background and rationale for this repo's architectural principles. The one-line summaries
in the root `AGENTS.md` are the "universally applicable" subset; read this file when you
need the full reasoning (e.g. before proposing a structural change).

## Idempotency

All operations must be safe to run multiple times:

- `make setup` should never break an existing environment.
- Use `mkdir -p`, `ln -sfn`, and other idempotent shell patterns everywhere.

## Minimalism

`dotfiles-core` should remain thin:

- Orchestration logic only.
- No component-specific configuration at this level.
- Delegate to component Makefiles rather than special-casing components here.

## Component delegation

When `make setup` runs:

1. Check if `components/<name>/Makefile` exists.
2. If it exists: `$(MAKE) -C "$dir" setup`.

Same pattern for `make link`.

## No Git submodules

**Never** use `git submodule`. Repositories are declared in `repos.yaml` and managed
exclusively via `vcstool` (`vcs import`, `vcs pull`).

## Security

- **Never** commit secrets in plaintext.
- Use Bitwarden CLI (`bw`) for credential resolution (`make secrets`).
- `.gitignore` must exclude `.bw_session`, `*.log`, `.tmp/`.

## Component `.env` convention

Components may include a `.env` file in their root directory.

- **Purpose**: local, environment-specific configuration.
- **Format**: simple shell variable assignments only (e.g. `FOO=bar`).
- **Restriction**: no complex shell logic or commands with side effects — these files are
  sourced by the orchestrator `Makefile` (via the `dispatch` macro) and by `dotfiles-zsh`
  initialization, so arbitrary code would execute on every shell start / `make` invocation.
