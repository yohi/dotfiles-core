# Unify Component README.md and AGENTS.md Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify documentation across all component repositories to clearly state their relationship with `dotfiles-core`.

**Architecture:** Systematic batch updates to `README.md` and `AGENTS.md` in each component directory under `components/`.

**Tech Stack:** Bash, Git, Markdown.

---

### Task 1: Setup and Validation of Target List

**Files:**
- Read: `repos.yaml`

**Step 1: Extract component list from repos.yaml**
Run: `grep -E '^[[:space:]]{2}[A-Za-z0-9._-]+:' repos.yaml | sed 's/^[[:space:]]\{2\}//; s/:$//' | xargs`
Expected: List of components (`dotfiles-zsh`, `dotfiles-vim`, etc.)

**Step 2: Verify all directories exist**
Run: `for d in $(grep -E '^[[:space:]]{2}[A-Za-z0-9._-]+:' repos.yaml | sed 's/^[[:space:]]\{2\}//; s/:$//' | xargs); do ls -d components/$d; done`
Expected: List of existing directories.

---

### Task 2: Unify dotfiles-zsh Documentation

**Files:**
- Modify: `components/dotfiles-zsh/README.md`
- Modify: `components/dotfiles-zsh/AGENTS.md`

**Step 1: Apply README.md template**
Insert after the first `#` or `概要` section.
```markdown
## 管理と依存関係

本リポジトリは [dotfiles-core](https://github.com/yohi/dotfiles-core) によって管理されるコンポーネントの一つです。

### ⚠️ 単体使用時の注意点
本リポジトリは `dotfiles-core` の共通 Makefile ルール（`common-mk`）に依存しています。単体で使用（クローン）する場合は、以下の手順が必要です：

1. `common-mk` ディレクトリを本リポジトリの親ディレクトリに配置するか、パスを適切に設定してください。
2. `make help` を実行して、正しく設定されていることを確認してください。

推奨される使用方法は、`dotfiles-core` から `make setup` を実行することです。
```

**Step 2: Apply AGENTS.md template**
Insert before the first occurrence of `## STRUCTURE` or `## PROJECT KNOWLEDGE BASE`.
```markdown
## COMPONENT LAYOUT CONVENTION

This repository is part of the **dotfiles polyrepo** orchestrated by [dotfiles-core](https://github.com/yohi/dotfiles-core).
All changes MUST comply with the central layout rules. Please refer to the central [ARCHITECTURE.md](https://raw.githubusercontent.com/yohi/dotfiles-core/refs/heads/master/docs/ARCHITECTURE.md) for the full, authoritative rules and constraints.
```

**Step 3: Commit changes in component repo**
Run: `cd components/dotfiles-zsh && git add README.md AGENTS.md && git commit -m "docs: dotfiles-coreとの関係記述を統一"`

---

### Task 3: Unify dotfiles-vim Documentation
(Repeat steps in Task 2 for `components/dotfiles-vim`)

---

### Task 4: Unify dotfiles-git Documentation
(Repeat steps in Task 2 for `components/dotfiles-git`. Note: Already has similar sections, replace them with the standard template.)

---

### Task 5: Unify dotfiles-term Documentation
(Repeat steps in Task 2 for `components/dotfiles-term`)

---

### Task 6: Unify dotfiles-ide Documentation
(Repeat steps in Task 2 for `components/dotfiles-ide`)

---

### Task 7: Unify dotfiles-ai Documentation
(Repeat steps in Task 2 for `components/dotfiles-ai`)

---

### Task 8: Unify dotfiles-gnome Documentation
(Repeat steps in Task 2 for `components/dotfiles-gnome`)

---

### Task 9: Unify dotfiles-system Documentation
(Repeat steps in Task 2 for `components/dotfiles-system`)

---

### Task 10: Final Verification

**Step 1: Check all modified files**
Run: `grep -r "管理と依存関係" components/`
Expected: 8 matches in README.md files.

Run: `grep -r "COMPONENT LAYOUT CONVENTION" components/`
Expected: 8 matches in AGENTS.md files.
