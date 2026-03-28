# Design Doc: Fix Makefile path inconsistency and missing targets in dotfiles-git

## 1. Overview
`components/dotfiles-git/Makefile` において、シンボリックリンクの参照先を示すコメントのパスが実際と異なっている問題、および標準的な Makefile ターゲット (`all`, `clean`, `test`) が欠落している問題を修正します。

## 2. Constraints & Success Criteria
- **Constraints**: 既存の `setup` や `link` ターゲットの動作を損なわないこと。
- **Success Criteria**:
  - `Makefile` 2行目のコメントが `../../../common-mk/` に更新されていること。
  - `all`, `clean`, `test` ターゲットが `.PHONY` に追加され、実装されていること。

## 3. Proposed Design
### 3.1. Path Correction
`_mk/` ディレクトリ内のファイルは、`components/dotfiles-git/` から見て 1 階層深いため、`common-mk/` への相対パスは `../../../common-mk/` となります。コメントをこれに合わせます。

### 3.2. Standard Targets
- `all`: `setup` と同様の動作をデフォルトとして提供します。
- `clean`: 現時点ではプレースホルダー（メッセージ出力のみ）を実装します。
- `test`: 現時点ではプレースホルダー（メッセージ出力のみ）を実装します。

## 4. Implementation Details
`components/dotfiles-git/Makefile` に対して以下の変更を行います。

```make
# Line 2: 修正
# Note: These are symlinked from ../../../common-mk/ when managed by dotfiles-core

# .PHONY 宣言の更新
.PHONY: setup all clean test

# 新規ターゲット追加
all: setup ## 全て実行（setup と同一）

clean: ## 一時ファイルのクリーンアップ
	@echo "==> Cleaning dotfiles-git"

test: ## テスト実行（スタブ）
	@echo "==> Testing dotfiles-git"
```

## 5. Verification Plan
1. `make help` を実行し、`all`, `clean`, `test` が表示されることを確認する。
2. `make all`, `make clean`, `make test` を個別に実行し、エラーが出ないことを確認する。
3. `Makefile` のコメントが正しく修正されていることを目視で確認する。
