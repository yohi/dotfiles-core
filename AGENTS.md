# AGENTS.md

## What

`dotfiles-core` is the orchestrator (meta-repository) for an Ubuntu Polyrepo dotfiles
setup. It coordinates independent component repos declared in `repos.yaml`,
checked out flat under `components/`; never use Git submodules.

## Why

On an already-provisioned Ubuntu machine, `make setup` configures the development
environment: it clones component repos, resolves secrets, links dotfiles, and delegates
component-specific configuration to each component's `Makefile`.

Provisioning a brand-new Ubuntu machine (physical PC / VPS) is a separate flow;
see `docs/ansible.md`.

## How

- This repository is pure orchestration, not an application. `make test` runs
  a Docker-based integration smoke test.
- Components sync via `vcstool` (`make init` / `make sync`). Never hand-roll
  a `git clone` loop or use `git submodule`.
- Secrets resolve via Bitwarden CLI (`bw`). Never commit plaintext credentials.
- `make setup` first injects shared `common-mk/` macros into each component,
  then dispatches to the component's `Makefile` for environment-specific setup.

## Commands and Verification

- `make help` — verified; lists all root targets and their descriptions.
- `make test` — Docker-based integration smoke test for the root orchestration flow.
- `make init` / `make sync` — import and update components via `vcstool`.
- `make secrets` — resolve credentials via Bitwarden CLI; set `WITH_BW=1`
  to enable it.
- `make setup` — run the full configuration on an already-provisioned Ubuntu machine.

## Language & Communication

- User-facing docs / comments: Japanese
- `AGENTS.md` files (including this one): English
- Commit messages: Japanese Conventional Commits (e.g., `feat: 新機能追加`)

## Agent Constraints

When `opencode.jsonc` is present, `rm`, `ssh`, and `sudo` are blocked for
agent execution unless explicitly allowed there. This does not apply to humans
or CI; `opencode.jsonc` defines the authoritative exceptions.

## Reference Docs (read only when relevant to your task)

| Doc | Context |
| --- | --- |
| `SPEC.md` | Architecture & data-flow diagrams |
| `docs/ARCHITECTURE.md` | Component repo structure |
| `docs/agent/SHELL_CONVENTIONS.md` | Shell script / Makefile authoring |
| `docs/agent/COMMON_TASKS.md` | Adding components, status checks |
| `docs/agent/PROJECT_CONVENTIONS.md` | Project conventions and security |
| `docs/ansible.md` | New-machine Ubuntu bootstrap |
| `docs/pxe-server.md` | Docker-based PXE server setup |
| `docs/cf-workers.md` | Cloudflare Workers script distribution |
