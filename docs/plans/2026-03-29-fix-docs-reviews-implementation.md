# Fix Documentation Reviews Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Resolve issues identified in code review regarding README formatting, plan consistency, and git safety.

**Architecture:** Systematic fixes for identified Markdown and implementation plan issues across four files.

**Tech Stack:** Markdown, Bash, Git.

---

### Task 1: Fix README.md component list formatting

**Files:**
- Modify: `README.md:32`

**Step 1: Apply bold style to dotfiles-system**
Replace: `| dotfiles-system | [yohi/dotfiles-system](https://github.com/yohi/dotfiles-system) |`
With: `| **dotfiles-system** | [yohi/dotfiles-system](https://github.com/yohi/dotfiles-system) |`

**Step 2: Verify the change**
Run: `grep "dotfiles-system" README.md`
Expected: `| **dotfiles-system** | [yohi/dotfiles-system](https://github.com/yohi/dotfiles-system) |`

**Step 3: Commit**
Run: `git add README.md && git commit -m "docs: fix bold style for dotfiles-system in README"`

---

### Task 2: Fix heading levels in refine-component-readme-content.md

**Files:**
- Modify: `docs/plans/2026-03-29-refine-component-readme-content.md`

**Step 1: Change Task headings from ### to ##**
Run: `sed -i 's/^### Task/## Task/g' docs/plans/2026-03-29-refine-component-readme-content.md`

**Step 2: Verify heading levels**
Run: `grep "^## Task" docs/plans/2026-03-29-refine-component-readme-content.md`
Expected: 9 matches starting with `## Task`.

**Step 3: Commit**
Run: `git add docs/plans/2026-03-29-refine-component-readme-content.md && git commit -m "docs: fix heading levels in refine-component-readme-content plan"`

---

### Task 3: Improve patterns and conditions in unify-component-docs-implementation.md

**Files:**
- Modify: `docs/plans/2026-03-29-unify-component-docs-implementation.md`

**Step 1: Update Step 1 and Step 2 extraction patterns**
Replace: `grep -v "repositories:" repos.yaml | grep ":" | sed 's/://'`
With: `grep -E '^[[:space:]]{2}[A-Za-z0-9._-]+:' repos.yaml | sed 's/^[[:space:]]\{2\}//; s/:$//'` (applied to both Step 1 and Step 2 in Task 1).

**Step 2: Update AGENTS.md insertion condition**
Locate "Step 2: Apply AGENTS.md template" in Task 2.
Change "Insert before `## STRUCTURE`" to "Insert before the first occurrence of `## STRUCTURE` or `## PROJECT KNOWLEDGE BASE`".

**Step 3: Verify plan content**
Run: `grep "grep -E" docs/plans/2026-03-29-unify-component-docs-implementation.md`
Expected: Updated patterns are present.

**Step 4: Commit**
Run: `git add docs/plans/2026-03-29-unify-component-docs-implementation.md && git commit -m "docs: refine component extraction and AGENTS.md insertion logic in plan"`

---

### Task 4: Add safety guards and fixed hash to unify-docs-move-to-feature-branch.md

**Files:**
- Modify: `docs/plans/2026-03-29-unify-docs-move-to-feature-branch.md`

**Step 1: Rewrite git operations with safety guards**
Replace the content of the file with:
```markdown
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
```

**Step 2: Verify the rewrite**
Run: `cat docs/plans/2026-03-29-unify-docs-move-to-feature-branch.md`

**Step 3: Commit**
Run: `git add docs/plans/2026-03-29-unify-docs-move-to-feature-branch.md && git commit -m "docs: add safety guards and fixed hash to branch move plan"`
