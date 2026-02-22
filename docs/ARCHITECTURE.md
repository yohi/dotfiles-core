# Component Layout Convention（コンポーネント配置規約）

> **対象**: `components/` 配下の全マイクロリポジトリ

## 概要

各コンポーネントリポジトリは、GNU Stow によるシンボリックリンク展開と Make による自動化を前提としたフラットレイアウト構成を採る。
本規約は、リポジトリ間の一貫性を保ち、新規コンポーネント追加時のスキャフォールディングを容易にすることを目的とする。

---

## ディレクトリ構成テンプレート

```text
dotfiles-<name>/
├── .git/
├── .gitignore
├── .stow-local-ignore          # [必須] Stow除外ルール
├── Makefile                     # [必須] setup ターゲットを含むエントリポイント
├── README.md                    # [必須] コンポーネント概要
├── LICENSE                      # [必須] ライセンスファイル
├── AGENTS.md                    # [必須] AIエージェントへの指示・タスク定義
│
├── _mk/                          # [任意] Makefile を機能ごとに分割する場合
│   ├── <feature-a>.mk
│   └── <feature-b>.mk
│
├── bin/                         # [任意] $PATH に追加する実行可能スクリプト
│   └── <script-name>
│
├── scripts/                     # [任意] 内部ユーティリティ（$PATH 非公開）
│   └── <internal-helper>.sh
│
├── docs/                        # [任意] 詳細ドキュメント
│   └── <topic>.md
│
├── tests/                       # [任意] テストスクリプト
│   └── test-<feature>.sh
│
├── <tool-specific-dir>/         # [Stow対象] ツール固有の設定ディレクトリ
│   └── ...                      #   例: starship/, prompts/, claude/, opencode/
│
└── dot-<file>                   # [Stow対象] ドットファイル（Stowの --dotfiles で展開）
                                 #   例: dot-zshrc -> ~/.zshrc
```

---

## ファイル分類ルール

### 必須ファイル（全コンポーネント共通）

| ファイル | 役割 | 備考 |
| :--- | :--- | :--- |
| `Makefile` | `setup` ターゲットを公開。dotfiles-core から委譲呼び出しされる | 後述のMakefile規約に従う |
| `.stow-local-ignore` | Stow がリンクしないファイル/ディレクトリを列挙 | 後述の.stow-local-ignore規約に従う |
| `README.md` | コンポーネントの概要・使い方 | 日本語で記述 |
| `LICENSE` | ライセンス | MIT |
| `AGENTS.md` | AIエージェントへの指示・タスク定義 | — |
| `.gitignore` | Git 除外ルール | — |

### Stow 対象ファイル（`~` にリンクされるもの）

リポジトリ直下に置かれたファイル（`dot-zshrc` など）やディレクトリは、`.stow-local-ignore` で除外されない限り `~` にシンボリックリンクされる。隠しファイルとして配置したい設定ファイルのファイル名には `dot-` プレフィックスを付けること（Stow の `--dotfiles` オプションにより `~/.zshrc` 等の隠しファイルとして展開される）。

**原則**: Stow が `~` に展開するファイルは、ユーザーの `$HOME` に直接必要な設定ファイルのみ。

### Stow 非対象ファイル（管理・開発用）

以下のファイル/ディレクトリは `.stow-local-ignore` に列挙し、Stow のリンク対象から除外する:

| 対象 | 理由 |
| :--- | :--- |
| `Makefile` | ビルド制御ファイル |
| `README.md` / `QUICKSTART.md` 等 | ドキュメント |
| `LICENSE` | ライセンスファイル |
| `.git` | Git メタデータ |
| `.gitignore` | Git 除外ルール |
| `_mk/` | Makefile 分割ファイル |
| `bin/` | PATH 追加スクリプト（Stowではなく `$PATH` で参照） |
| `scripts/` | 内部ユーティリティ |
| `docs/` | ドキュメント |
| `tests/` | テスト |
| `archive/` | アーカイブ |
| `examples/` | 設定例 |

---

## `.stow-local-ignore` 規約

各コンポーネントは必ず `.stow-local-ignore` を配置し、管理用ファイルが `~` にリンクされることを防ぐ。

### 最低限のテンプレート

```text
# === VCS / Meta ===
\.git
\.gitignore

# === Build / Docs ===
Makefile
README\.md
QUICKSTART\.md
LICENSE
AGENTS\.md

# === Management Dirs ===
mk
scripts
docs
tests
archive
examples
bin
```

> [!IMPORTANT]
> `.stow-local-ignore` のパターンは **正規表現** として解釈される（`.` は任意文字にマッチするため、ファイル名中の `.` は `\.` とエスケープする）。

> [!TIP]
> `.stow-local-ignore` を配置すると Stow のデフォルト除外ルール（`README.*`, `LICENSE` 等の自動除外）が**無効化**されるため、それらも明示的に列挙すること。

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
```

### ルール

1. **`setup` ターゲットは必須**。dotfiles-core の `make setup` から委譲呼び出しされる唯一のインターフェース。
2. **`.DEFAULT_GOAL := setup`** を設定する（`_mk/` を include する場合は特に重要）。
3. **`.PHONY`** で `setup` およびすべての非ファイルターゲットを宣言する。
4. **`_mk/` ディレクトリ** でサブターゲットを分割する場合は `include _mk/*.mk` で読み込む。ルート Makefile には `setup` ターゲットのみを定義し、肥大化を防ぐ。
5. **進捗表示**: `@echo "==> ..."` 形式で処理の開始を通知する。

---

## `bin/` と `scripts/` の使い分け

| ディレクトリ | 用途 | `$PATH` 追加 | Stow 対象 |
| :--- | :--- | :--- | :--- |
| `bin/` | 他コンポーネントやユーザーが呼び出す**公開コマンド** | ✅ dotfiles-zsh 側で動的追加 | ❌ `.stow-local-ignore` で除外 |
| `scripts/` | コンポーネント内部でのみ使う**ヘルパー** | ❌ | ❌ `.stow-local-ignore` で除外 |

> [!NOTE]
> `bin/` のパスは、SPEC.md に記載の疎結合パターンに従い、dotfiles-zsh の `.zshrc` 等で
> `export PATH="${DOTFILES_SHELL_ROOT}/../dotfiles-git/bin:$PATH"` のように動的に追加する。

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

- [ ] `Makefile` — `setup` ターゲットを持つこと
- [ ] `.stow-local-ignore` — 管理用ファイルをすべて列挙すること
- [ ] `README.md` — コンポーネントの概要を日本語で記述
- [ ] `LICENSE` — MIT ライセンスを配置
- [ ] `.gitignore` — 必要な除外ルールを定義
- [ ] `repos.yaml` への登録 — dotfiles-core 側で追記
- [ ] Stow 対象ファイルの確認 — `stow --no --verbose=2` でドライラン確認
