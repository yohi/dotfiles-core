# Refine Component README.md Content Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refine the content of all component READMEs to accurately reflect their features, directory structures, and Makefile targets.

**Architecture:** Systematic update of each component's README.md, ensuring the standardized structure while enriching the "Directory Structure" and "Key Features" sections.

**Tech Stack:** Markdown, Git.

---

### Task 1: Refine dotfiles-zsh README.md
**Files:**
- Modify: `components/dotfiles-zsh/README.md`

**Step 1: Update Directory Structure to tree format**
**Step 2: Clarify setup for secrets/config**
**Step 3: Add "Key Features" section**
- Plugin management (Zinit)
- Prompt (Powerlevel10k)
- Environment variables (.zsh_env)
- Custom functions library

---

### Task 2: Refine dotfiles-vim README.md
**Files:**
- Modify: `components/dotfiles-vim/README.md`

**Step 1: Change title to `# dotfiles-vim`**
**Step 2: Fix tree root in Directory Structure**
**Step 3: Clean up redundant "Standalone Usage" mentions**

---

### Task 3: Refine dotfiles-git README.md
**Files:**
- Modify: `components/dotfiles-git/README.md`

**Step 1: Update "Setup" section to recommend `make setup`**
**Step 2: Ensure "Directory Structure" follows the standard tree format**

---

### Task 4: Refine dotfiles-ai README.md
**Files:**
- Modify: `components/dotfiles-ai/README.md`

**Step 1: Reorder sections: Title -> Desc -> Management -> Directory -> Features**
**Step 2: Add visual tree to "Directory Structure"**

---

### Task 5: Refine dotfiles-system README.md
**Files:**
- Modify: `components/dotfiles-system/README.md`

**Step 1: Add "Key Features" based on Makefile**
- Package management (Homebrew/Brewfile)
- Font management
- Memory optimization
- Clipboard integration
- System monitoring scripts

---

### Task 6: Refine dotfiles-term README.md
**Files:**
- Modify: `components/dotfiles-term/README.md`

**Step 1: Add "Key Features" based on Makefile**
- WezTerm configuration (Lua)
- Tilix configuration (dconf)

---

### Task 7: Refine dotfiles-gnome README.md
**Files:**
- Modify: `components/dotfiles-gnome/README.md`

**Step 1: Add "Key Features" based on Makefile**
- GNOME Extensions management
- Custom shortcuts
- Mozc (Japanese Input) configuration
- Accessibility (Sticky keys) settings

---

### Task 8: Refine dotfiles-ide README.md
**Files:**
- Modify: `components/dotfiles-ide/README.md`

**Step 1: Add "Key Features" based on Makefile**
- VS Code / Cursor settings synchronization
- Extension list management

---

### Task 9: Final Commit and Push
**Step 1: Commit with `docs: READMEの記述を実態に合わせて精査・更新`**
**Step 2: Push to `feature/unify-docs` branch for all components**
