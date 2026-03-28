# Design Doc: Makefile 共通ルールと「プロジェクトの掟」の共通化

## 1. 目的
全コンポーネント（`dotfiles-xxx`）において、`make setup` を基本コマンドとし、`make`（引数なし）でヘルプを表示する運用を徹底する。また、AIエージェントやIDEが参照すべき共通の「掟」を一箇所で管理し、各リポジトリから参照可能にする。

## 2. アーキテクチャ

### 2.1. 共通リソース (`common-mk/`)
以下のファイルを実体として管理する。
- `DOTFILES_COMMON_RULES.md`: 自然言語による共通の基本ルール。
- `help.mk`: `make`（引数なし）でターゲット一覧と説明を表示するロジック。
- `core.mk`: デフォルトターゲット（`.DEFAULT_GOAL := setup`）や共通変数の定義。

### 2.2. 配布メカニズム
ルートの `Makefile` の `_inject_common_mk` ターゲットを改造し、`cp`（コピー）ではなく `ln -sf`（シンボリックリンク）を使用して各コンポーネントに展開する。

### 2.3. コンポーネント側の構成
各 `components/dotfiles-xxx/` は以下のように構成される。
- `DOTFILES_COMMON_RULES.md` (symlink -> `../../common-mk/DOTFILES_COMMON_RULES.md`)
- `_mk/help.mk` (symlink -> `../../common-mk/help.mk`)
- `_mk/core.mk` (symlink -> `../../common-mk/core.mk`)
- `AGENTS.md` (実体): 冒頭で `DOTFILES_COMMON_RULES.md` を参照するよう記述し、リポジトリ固有のルールを下に続ける。
- `Makefile` (実体): `include _mk/core.mk` および `include _mk/help.mk` をインクルードする。

## 3. コンポーネント単体での動作
シンボリックリンクを使用するため、`dotfiles-core` のディレクトリ構造を維持した状態でのみ機能する。コンポーネント単体でリポジトリを切り出した場合はリンクが切れるが、本プロジェクトの運用（オーケストレーター経由のセットアップ）を優先する。

## 4. テスト・検証
- `make setup` を実行し、リンクが正しく作成されるか。
- 各コンポーネントで `make` を実行し、ヘルプが表示されるか。
- `make setup` がデフォルトで動作するか。
- AIエージェント（Gemini等）が `DOTFILES_COMMON_RULES.md` を通じてルールを認識できるか。
