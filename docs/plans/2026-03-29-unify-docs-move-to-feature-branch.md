# Plan: Move documentation changes to feature branch (Safe Version)

For each component:

**Step 1: Pre-flight checks and Backup**
1. Verify current branch is `master`: `git rev-parse --abbrev-ref HEAD` (Must be `master`).
2. Create backup branch: `git branch master-backup-20260329`.

**Step 2: Create Feature Branch**
1. Create and switch to feature branch: `git checkout -b feature/unify-docs`.
2. Push feature branch: `git push origin feature/unify-docs`.

**Step 3: Reset Master to Fixed Hash**
1. Switch back to master: `git checkout master`.
2. Reset master to the last known good commit: `git reset --hard ffd4cc8`.

**Step 4: Verification**
1. Check master HEAD: `git rev-parse HEAD` (Expected: `ffd4cc8...`).
2. Verify feature branch exists and has the docs changes.

Components:
- [x] dotfiles-zsh
- [x] dotfiles-vim
- [x] dotfiles-git
- [x] dotfiles-term
- [x] dotfiles-ide
- [x] dotfiles-ai
- [x] dotfiles-gnome
- [x] dotfiles-system
