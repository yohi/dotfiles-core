# AGENTS.md

## What

`dotfiles-core` is the orchestrator (meta-repository) for a Polyrepo dotfiles setup
targeting Ubuntu. It coordinates independent component repos (see `repos.yaml`) checked
out flat under `components/` — no Git submodules, ever.

## Why

Goal: one command (`make setup`) takes a machine from zero to a fully configured Ubuntu
dev environment — clone all component repos, resolve secrets, symlink dotfiles, and
delegate setup to each component's own `Makefile`.

## How

- This repo has **no app code, app-specific unit tests, or build artifacts** — pure
  orchestration. `make test` runs a Docker-based integration smoke test.
- Components sync via `vcstool` (`make init` / `make sync`). Never hand-roll a
  `git clone` loop and never use `git submodule`.
- Secrets resolve via Bitwarden CLI (`bw`). Never commit plaintext credentials.
- Provisioning a brand-new Ubuntu machine (physical PC / VPS) is a separate flow,
  not `make setup` — see `ansible/README.md`.
- Writing a shell script or Makefile? Read `docs/agent/SHELL_CONVENTIONS.md`.

## Language & Communication

- User-facing docs / comments: Japanese
- `AGENTS.md` files (including this one): English
- Commit messages: Japanese Conventional Commits (e.g., `feat: 新機能追加`)

## Agent Constraints

When `opencode.jsonc` is present, `rm`, `ssh`, `sudo` are blocked for agent execution
unless explicitly allowed there. (Not a rule for humans/CI — see `opencode.jsonc` for
the authoritative exception list.)

## Reference Docs (read only when relevant to your task)

| Doc | Context |
| --- | --- |
| `SPEC.md` | Architecture & data-flow diagrams |
| `docs/ARCHITECTURE.md` | Component repo structure |
| `docs/agent/SHELL_CONVENTIONS.md` | Shell script / Makefile authoring |
| `docs/agent/COMMON_TASKS.md` | Adding components, status checks |
| `docs/agent/PROJECT_CONVENTIONS.md` | Idempotency, delegation, security rationale |
| `ansible/README.md` | New-machine Ubuntu bootstrap |
| `scripts/workers/README.md` | Cloudflare Workers script distribution |
