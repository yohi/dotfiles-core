# Component Layout Convention（コンポーネント配置規約）

> **対象**: `components/` 配下の全マイクロリポジトリ

## 概要

各コンポーネントリポジトリは、`ln -sfn` による明示的なシンボリックリンク展開と Make による自動化を前提としたフラットレイアウト構成を採る。
本規約は、リポジトリ間の一貫性を保ち、新規コンポーネント追加時のスキャフォールディングを容易にすることを目的とする。

---

## ディレクトリ構成テンプレート

```text
dotfiles-<name>/
├── .git/
├── .gitignore
├── Makefile                     # [必須] setup, link ターゲットを含むエントリポイント
├── README.md                    # [必須] コンポーネント概要
├── LICENSE                      # [必須] ライセンスファイル
├── AGENTS.md                    # [必須] AIエージェントへの指示・タスク定義
│
├── _mk/                          # [任意] Makefile を機能ごとに分割する場合
│   ├── <feature-a>.mk
│   └── <feature-b>.mk
│
├── _bin/                        # [任意] $PATH に追加する実行可能スクリプト
│   └── <script-name>
│
├── _scripts/                    # [任意] 内部ユーティリティ（$PATH 非公開）
│   └── <internal-helper>.sh
│
├── _docs/                       # [任意] 詳細ドキュメント
│   └── <topic>.md
│
├── _tests/                      # [任意] テストスクリプト
│   └── test-<feature>.sh
│
├── <tool-specific-dir>/         # [リンク対象] ツール固有の設定ディレクトリ
│   └── ...                      #   例: starship/, prompts/, claude/, opencode/
│
└── <file>                       # [リンク対象] 設定ファイル（Makefile内で明示的にリンク）
                                 #   例: zshrc -> ~/.zshrc
```

---

## ファイル分類ルール

### 必須ファイル（全コンポーネント共通）

| ファイル | 役割 | 備考 |
| :--- | :--- | :--- |
| `Makefile` | `setup`, `link` ターゲットを公開。dotfiles-core から委譲呼び出しされる | 後述のMakefile規約に従う |
| `README.md` | コンポーネントの概要・使い方 | 日本語で記述 |
| `LICENSE` | ライセンス | MIT |
| `AGENTS.md` | AIエージェントへの指示・タスク定義 | — |
| `.gitignore` | Git 除外ルール | — |

### リンク対象ファイル（`~` にリンクされるもの）

リポジトリ直下に置かれたファイル（`zshrc` など）やディレクトリは、コンポーネントの Makefile 内で `ln -sfn` を用いて明示的に `~` にシンボリックリンクする。シンボリックリンクは明示的に管理されるため、リポジトリ内で `dot-` や `.` プレフィックスを付ける必要はない。標準的なファイル名で配置し、ターゲット側で隠しファイルとしてリンクする（例: `zshrc` を `~/.zshrc` にリンク）。

**原則**: Makefile で `~` に展開されるファイルは、ユーザーの `$HOME` に直接必要な設定ファイルのみ。

### 管理・開発用ファイル

以下のファイル/ディレクトリは、コンポーネント内で管理されるが、`~` にリンクは行わない:

| 対象 | 理由 |
| :--- | :--- |
| `Makefile` | ビルド制御ファイル |
| `README.md` / `QUICKSTART.md` 等 | ドキュメント |
| `LICENSE` | ライセンスファイル |
| `.git` | Git メタデータ |
| `.gitignore` | Git 除外ルール |
| `_mk/` | Makefile 分割ファイル |
| `_bin/` | PATH 追加スクリプト（Stowではなく `$PATH` で参照） |
| `_scripts/` | 内部ユーティリティ |
| `_docs/` | ドキュメント |
| `_tests/` | テスト |
| `archive/` | アーカイブ |
| `examples/` | 設定例 |

---

## Makefile 規約

### 基本構造

```makefile
# dotfiles-<name> Makefile
.DEFAULT_GOAL := setup

# _mk/ ディレクトリにサブターゲットがある場合は include
# include _mk/<feature>.mk

.PHONY: setup
setup:
 @echo "==> Setting up dotfiles-<name>"
 # コンポーネント固有のセットアップ処理

.PHONY: link
link:
 @echo "==> Linking dotfiles-<name>"
 # 明示的な ln -sfn コマンドを記述
```

### ルール

1. **`setup` および `link` ターゲットは必須**。これらは `dotfiles-core` から委譲呼び出しされる基本的なインターフェース。
2. **`.DEFAULT_GOAL := setup`** を設定する（`_mk/` を include する場合は特に重要）。
3. **`.PHONY`** で `setup` およびすべての非ファイルターゲットを宣言する。
4. **`_mk/` ディレクトリ** でサブターゲットを分割する場合は `include _mk/*.mk` で読み込む。ルート Makefile には `setup` ターゲットのみを定義し、肥大化を防ぐ。
5. **進捗表示**: `@echo "==> ..."` 形式で処理の開始を通知する。

---

## `_bin/` と `_scripts/` の使い分け

| ディレクトリ | 用途 | `$PATH` 追加 | リンク対象 |
| :--- | :--- | :--- | :--- |
| `_bin/` | 他コンポーネントやユーザーが呼び出す**公開コマンド** | ✅ dotfiles-zsh 側で動的追加 | ❌ `~` にはリンクしない |
| `_scripts/` | コンポーネント内部でのみ使う**ヘルパー** | ❌ | ❌ `~` にはリンクしない |

> [!NOTE]
> `_bin/` のパスは、SPEC.md に記載の疎結合パターンに従い、dotfiles-zsh の `.zshrc` 等で
> `export PATH="${DOTFILES_SHELL_ROOT}/../dotfiles-git/_bin:$PATH"` のように動的に追加する。

---

## パス解決ルール（SPEC.md §3 準拠）

すべてのスクリプトは、カレントディレクトリに依存しない防御的パス解決を行うこと。

```bash
#!/usr/bin/env bash
set -euo pipefail

# 自身のリポジトリルートを動的解決
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
```

**禁止事項**:

- ハードコードされた絶対パス（例: `~/dotfiles/components/dotfiles-zsh/...`）
- モノレポ時代の `$DOTFILES_DIR` による参照

---

## 新規コンポーネント追加チェックリスト

新しい `dotfiles-<name>` リポジトリを作成する際のチェックリスト:

- [ ] `Makefile` — `setup` および `link` ターゲットを持つこと
- [ ] `README.md` — コンポーネントの概要を日本語で記述
- [ ] `LICENSE` — MIT ライセンスを配置
- [ ] `.gitignore` — 必要な除外ルールを定義
- [ ] `repos.yaml` への登録 — dotfiles-core 側で追記
- [ ] リンク処理の確認 — `make -n link` でドライラン確認
