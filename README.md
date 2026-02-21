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
├── scripts/                    <-- 管理スクリプト群
└── components/                 <-- 各リポジトリのチェックアウト先 (Ignored by Git)
    ├── dotfiles-zsh/           <-- [Repo: dotfiles-zsh]
    ├── dotfiles-vim/           <-- [Repo: dotfiles-vim]
    ├── dotfiles-ai/            <-- [Repo: dotfiles-ai]
    └── ...
```

## 🛠 Prerequisites

- **OS**: Ubuntu (22.04 / 24.04 LTS 推奨)
- **Tools**: GNU Make, Python3, curl, jq, GNU Stow

## ⚡ Quick Start (Bootstrap)

まっさらな環境から以下の手順でセットアップを完了させます。

```bash
# 1. リポジトリをクローン
git clone git@github.com:yohi/dotfiles-core.git ~/dotfiles
cd ~/dotfiles

# 2. 初期化と一括セットアップ
# (依存関係のインストール、全リポジトリの同期、Stowによるリンク、各リポジトリ固有のセットアップを実行)
make setup
```

## ⌨️ Makefile Targets

| Target | Description |
| :--- | :--- |
| `make init` | 依存関係 (`vcstool`, `stow`, `jq` 等) を導入し、リポジトリを初期クローンします。 |
| `make sync` | `vcstool` を使用して、全コンポーネントを最新の状態に更新します。 |
| `make link` | `components/` 以下の各ディレクトリに対して `stow` を実行し、`~` へリンクを展開します。 |
| `make secrets` | Bitwarden CLI を呼び出し、クレデンシャルを解決します。 |
| `make setup` | 上記を順に実行し、各コンポーネント固有の `make setup` があれば呼び出して処理を委譲します。 |

## 🔗 Component Delegation

`make setup` を実行すると、`components/*` 内に `Makefile` が存在し、かつ `setup` ターゲットが定義されている場合に限り、その処理を自動的に実行（委譲）します。

各コンポーネント側で必要なライブラリのインストールや固有の設定（例：`vim` のプラグインマネージャの初期化など）は、それぞれの `Makefile` で記述してください。

## 🔐 Secret Management

Bitwarden CLI (`bw`) を使用します。
`make secrets` を実行することで、セッションの確立と必要なクレデンシャルの取得を行います。

---
Created by Gemini CLI based on @SPEC.md.
