# AGENTS.md

## What

`dotfiles-core` is the orchestrator (meta-repository) for a Polyrepo dotfiles setup
targeting Ubuntu. It coordinates independent component repos (`dotfiles-zsh`,
`dotfiles-vim`, `dotfiles-ai`, `dotfiles-git`, `dotfiles-term`, `dotfiles-ide`,
`dotfiles-gnome`, `dotfiles-system`) checked out flat under `components/` — no Git
submodules, ever.

## Why

Goal: one command (`make setup`) takes a machine from zero to a fully configured Ubuntu
dev environment — clone all component repos, resolve secrets, symlink dotfiles, and
delegate setup to each component's own `Makefile`.

## How to work here

- This repo itself has **no app code, no tests, no lint/build** — it's pure orchestration.
  `make test` runs a Docker-based smoke test of the whole flow (`tests/`).
- Repos live in `repos.yaml` and sync via `vcstool` (`make init` / `make sync`). Never
  hand-roll a `git clone` loop and never use `git submodule` — see
  `docs/agent/PROJECT_CONVENTIONS.md` for why.
- Secrets flow through Bitwarden CLI (`bw`) via `make secrets`; never commit plaintext
  credentials.
- Run `make help` for the full target list (`init`, `sync`, `status`, `diff`, `link`,
  `secrets`, `setup`, `test`, `clean`).
- Writing/editing a script or Makefile target? Read `docs/agent/SHELL_CONVENTIONS.md` first.
- Component-specific conventions belong in each `components/<name>/AGENTS.md`, not here —
  `docs/ARCHITECTURE.md` defines the layout every `dotfiles-*` repo must follow.
- Provisioning a brand-new Ubuntu machine (physical PC / VPS) that doesn't have
  `dotfiles-core` yet is a separate flow, not `make setup` — see `ansible/README.md`.

## Language policy

- User-facing docs / comments: Japanese
- `AGENTS.md` files (this one included): English
- Commit messages: Japanese Conventional Commits (e.g. `feat: 新機能追加`)

## Agent runtime constraints

When `opencode.jsonc` is present, these operations are blocked for agent execution unless
explicitly allowed there: `rm`, `ssh`, `sudo`. (Not a rule for humans/CI — see
`opencode.jsonc` for the authoritative exception list.)

## Reference docs (read only when relevant to your task)

| Doc | Read it when... |
| --- | --- |
| `SPEC.md` | You need the full spec, architecture, or data-flow diagrams |
| `docs/ARCHITECTURE.md` | Creating or restructuring a `dotfiles-*` component |
| `docs/agent/SHELL_CONVENTIONS.md` | Writing/editing a shell script or Makefile |
| `docs/agent/COMMON_TASKS.md` | Adding a component, checking component status |
| `docs/agent/PROJECT_CONVENTIONS.md` | Rationale behind idempotency / delegation / security rules |
| `ansible/README.md` | New-machine Ubuntu bootstrap (physical PC / VPS) |
| `scripts/workers/README.md` | Cloudflare Workers bootstrap-script distribution config |
