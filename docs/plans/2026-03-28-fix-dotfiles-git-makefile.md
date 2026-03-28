# Fix dotfiles-git Makefile Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `components/dotfiles-git/Makefile` のコメント修正と標準ターゲット (`all`, `clean`, `test`) の追加。

**Architecture:** 既存の `Makefile` を編集し、シンボリックリンクの階層不整合を解消するコメント修正と、プロジェクト標準のターゲットを追加して `checkmake` などの警告を解消します。

**Tech Stack:** GNU Make, Shell

---

### Task 1: Update Makefile Comment and .PHONY

**Files:**
- Modify: `components/dotfiles-git/Makefile:2,15,21`

**Step 1: Update the symlink reference comment**
Change the comment in line 2 to reflect the actual path.
```make
# Note: These are symlinked from ../../../common-mk/ when managed by dotfiles-core
```

**Step 2: Update .PHONY declaration**
Include `all`, `clean`, and `test` in the `.PHONY` list.
```make
.PHONY: setup all clean test
```

**Step 3: Verify the changes visually**
Run: `cat components/dotfiles-git/Makefile | head -n 5`
Expected: Line 2 shows `../../../common-mk/`.

**Step 4: Commit**
```bash
git add components/dotfiles-git/Makefile
git commit -m "chore(git): update Makefile comment and .PHONY targets"
```

---

### Task 2: Implement Standard Targets (all, clean, test)

**Files:**
- Modify: `components/dotfiles-git/Makefile:25+`

**Step 1: Add implementation for all, clean, and test**
Add the following targets after the `setup` target.
```make
all: setup ## 全て実行（setup と同一）

clean: ## 一時ファイルのクリーンアップ
	@echo "==> Cleaning dotfiles-git"

test: ## テスト実行（スタブ）
	@echo "==> Testing dotfiles-git"
```

**Step 2: Verify targets are available in help**
Run: `make -C components/dotfiles-git help`
Expected: `all`, `clean`, `test` が一覧に表示される。

**Step 3: Verify each target runs without error**
Run: `make -C components/dotfiles-git all`
Run: `make -C components/dotfiles-git clean`
Run: `make -C components/dotfiles-git test`
Expected: Each command outputs its respective message and exits with 0.

**Step 4: Commit**
```bash
git add components/dotfiles-git/Makefile
git commit -m "feat(git): add all, clean, and test targets to Makefile"
```
