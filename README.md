# dotfiles-core (Meta-Repository)

本プロジェクトは、モジュール化された `dotfiles` 群を統括する**メタ・リポジトリ（オーケストレーター）**です。
「メタ・リポジトリパターン」と「フラット・レイアウト」を採用し、巨大化した `dotfiles` を関心事ごとに分離して管理します。

## 🚀 Concept

- **Polyrepo & Modularization**: 機能（zsh, vim, git, etc.）ごとにリポジトリを分割し、独立したライフサイクルを持たせます。
- **Meta-Repository Pattern**: `dotfiles-core` が全リポジトリの同期、シークレットの解決、シンボリックリンクの展開を制御します。
- **Flat Layout**: Git Submodule を排除し、`components/` 配下に各リポジトリを並列に配置することで、管理の複雑さを解消します。
- **Secret Management**: Bitwarden CLI (`bw`) を使用し、シークレットを動的に解決します。

## 📂 Directory Structure

```text
~/dotfiles/                     <-- [Repo: dotfiles-core]
├── .gitignore                  <-- "components/" を除外
├── Makefile                    <-- メイン・ディスパッチャー
├── repos.yaml                  <-- vcstool用 リポジトリ定義
├── common-mk/                  <-- 共通Makefileマクロ (各コンポーネントへ自動注入)
├── tests/                      <-- インテグレーションテスト (Docker環境)
├── scripts/                    <-- 管理スクリプト群
└── components/                 <-- 各リポジトリのチェックアウト先 (Ignored by Git)
    ├── dotfiles-zsh/           <-- [Repo: dotfiles-zsh]
    ├── dotfiles-vim/           <-- [Repo: dotfiles-vim]
    ├── dotfiles-ai/            <-- [Repo: dotfiles-ai]
    └── ...
```

## 🛠 Prerequisites

- **OS**: Ubuntu (22.04 / 24.04 LTS 推奨)
- **Tools**: GNU Make, Python3, curl, jq, vcstool（リポジトリ管理）, bw（Bitwarden CLI: シークレット管理）
- **Note**: `make init` で一部ツールが自動インストールされる場合がありますが、事前に利用可能な状態にしておくことを推奨します。

## ⚡ Quick Start (Bootstrap)

まっさらな環境から以下の手順でセットアップを完了させます。

```bash
# 1. リポジトリをクローン（以下のどちらか1つ）
# SSH キーの設定が必要
git clone git@github.com:yohi/dotfiles-core.git ~/dotfiles

# SSH キー未設定の場合（HTTPS）
git clone https://github.com/yohi/dotfiles-core.git ~/dotfiles
cd ~/dotfiles

# 2. 初期化と一括セットアップ
# (依存関係のインストール、全リポジトリの同期、リンクの展開、各リポジトリ固有のセットアップを実行)
make setup
```

## ⌨️ Makefile Targets

| Target | Description |
| :--- | :--- |
| `make init` | 依存関係 (`vcstool`, `jq`, `curl` 等) を導入し、リポジトリを初期クローンします。 |
| `make sync` | `vcstool` を使用して、全コンポーネントを最新の状態に更新します。 |
| `make link` | `components/` 以下の各ディレクトリに対してリンク処理 (`ln -sfn`) を委譲し、`~` へ設定を展開します。 |
| `make secrets` | Bitwarden CLI を呼び出し、クレデンシャルを解決します。 |
| `make setup` | 上記を順に実行し、各コンポーネント固有の `make setup` があれば呼び出して処理を委譲します。実行時に `common-mk/` のマクロが自動注入されます。 |
| `make test`  | Docker コンテナを使用して、Ubuntu クリーン環境でのセットアップを検証します。 |

## 🔗 Component Delegation

`make setup` を実行すると、`components/*` 内に `Makefile` が存在する場合、その処理を自動的に実行（委譲）します。

### 共通基盤の自動注入 (Bootstrap & Inject)
各コンポーネントの実行直前に、`dotfiles-core` は共通の Makefile マクロを `components/*/_mk/idempotency.mk` として自動的に配布します。
各コンポーネントの `Makefile` で以下のようにインクルードすることで、冪等性管理（`check_marker` 等）を簡単に行えます。

```makefile
-include _mk/idempotency.mk
```

各コンポーネント側で必要なライブラリのインストールや固有の設定（例：`vim` のプラグインマネージャの初期化など）は、それぞれの `Makefile` で記述してください。

## 🔐 Secret Management

Bitwarden CLI (`bw`) を使用します。
`make secrets` を実行することで、セッションの確立と必要なクレデンシャルの取得を行います。

---
Created by Gemini CLI based on @SPEC.md.
