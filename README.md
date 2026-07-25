# dotfiles-core (Orchestrator)

モジュール化された dotfiles 群を統括するメタ・リポジトリ（オーケストレーター）です。

## 管理と依存関係

本リポジトリは全体の司令塔（Orchestrator）として機能し、各コンポーネントの同期、シークレットの解決、シンボリックリンクの展開を制御します。

- **共通基盤**: `common-mk/` に各コンポーネントが共有する Makefile マクロを保持しています。
- **コンポーネント管理**: `repos.yaml` に定義されたリポジトリを `components/` 配下に展開します。

## 🚀 Concept

- **Polyrepo & Modularization**: 機能（zsh, vim, git, etc.）ごとにリポジトリを分割し、独立したライフサイクルを持たせます。
- **Meta-Repository Pattern**: `dotfiles-core` が全リポジトリの同期、シークレットの解決、シンボリックリンクの展開を制御します。
- **Flat Layout**: Git Submodule を排除し、`components/` 配下に各リポジトリを並列に配置することで、管理の複雑さを解消します。
- **Secret Management**: Bitwarden CLI (`bw`) を使用し、シークレットを動的に解決します。

## 📦 Components

Orchestrator によって管理される全コンポーネントのリポジトリ一覧です。

| Component | Repository Link |
| :--- | :--- |
| **dotfiles-zsh** | [yohi/dotfiles-zsh](https://github.com/yohi/dotfiles-zsh) |
| **dotfiles-vim** | [yohi/dotfiles-vim](https://github.com/yohi/dotfiles-vim) |
| **dotfiles-git** | [yohi/dotfiles-git](https://github.com/yohi/dotfiles-git) |
| **dotfiles-term** | [yohi/dotfiles-term](https://github.com/yohi/dotfiles-term) |
| **dotfiles-ide** | [yohi/dotfiles-ide](https://github.com/yohi/dotfiles-ide) |
| **dotfiles-ai** | [yohi/dotfiles-ai](https://github.com/yohi/dotfiles-ai) |
| **dotfiles-gnome** | [yohi/dotfiles-gnome](https://github.com/yohi/dotfiles-gnome) |
| **dotfiles-system** | [yohi/dotfiles-system](https://github.com/yohi/dotfiles-system) |

## ディレクトリ構成

```text
~/dotfiles/                     <-- [Repo: dotfiles-core]
├── .gitignore                  <-- "components/" を除外
├── Makefile                    <-- メイン・ディスパッチャー
├── repos.yaml                  <-- vcstool用 リポジトリ定義
├── common-mk/                  <-- 共通Makefileマクロ (各コンポーネントへ自動注入)
├── ansible/                    <-- 新規Ubuntuマシン（物理PC/VPS）の初期セットアップ用 Ansible プレイブック
├── tests/                      <-- インテグレーションテスト (Docker環境)
├── scripts/                    <-- 管理スクリプト群 (bootstrap.sh, pxe-server/, workers/ 等)
└── components/                 <-- 各リポジトリのチェックアウト先 (Ignored by Git)
    ├── dotfiles-zsh/           <-- [Repo: dotfiles-zsh]
    ├── dotfiles-vim/           <-- [Repo: dotfiles-vim]
    ├── dotfiles-ai/            <-- [Repo: dotfiles-ai]
    └── ...
```

## 🛠 Prerequisites

- **OS**: Ubuntu (22.04 / 24.04 / 26.04 LTS 推奨)
- **Tools**: GNU Make, Python3, curl, jq, vcstool（リポジトリ管理）, bw（Bitwarden CLI: シークレット管理）

> [!NOTE]
> `make init` で一部ツールが自動インストールされる場合がありますが、事前に利用可能な状態にしておくことを推奨します。

## 🖥️ 新規 Ubuntu マシンの初期セットアップ

まだ dotfiles-core を導入していない、まっさらな Ubuntu マシン（物理 PC / VPS）を用意する場合は、`ansible/` 配下のセットアップフローを使用します。

- **物理 PC**（外部から SSH 接続できない場合）: 同一 LAN 上であれば、`scripts/pxe-server/run-pxe.sh` を使った **PXE 無人インストール**（OS インストールからユーザー作成・SSH 鍵登録まで自動化）が推奨です。操作 PC 上で一時的な PXE/TFTP/HTTP サーバーを起動し、ターゲット PC の電源を入れるだけでセットアップが始まります。詳細は [`ansible/README.md`](ansible/README.md) を参照してください。  
  PXE が使えない環境では、ターゲット PC のコンソールでブートストラップスクリプト（`scripts/bootstrap.sh`）をダウンロードして実行するレガシー経路も利用できます。スクリプトは Cloudflare Workers（`scripts/workers/`）経由で HTTPS 配信され、`X-Script-SHA256` ヘッダによる整合性検証が可能です。
- **VPS**（外部から SSH 接続できる場合）: ターゲット PC のコンソールには入らず、操作 PC から Ansible（`ansible/setup.yml`）のみで全て実施します。

両方とも、対話式ランチャー `ansible/run.sh` から実行します。詳細な手順・セキュリティ設計は [`ansible/README.md`](ansible/README.md) を参照してください。

> [!NOTE]
> このフローは「まだ Ubuntu マシンがセットアップされていない」段階を対象とします。dotfiles-core のクローンと本セットアップ（`common-setup` ロール）は Ansible が自動的に実行するため、上記フローの後に以下の Quick Start を別途実行する必要はありません。

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
| `make status` | `vcstool` を使用して、全コンポーネントの Git ステータスを一括確認します。 |
| `make diff` | `vcstool` を使用して、全コンポーネントの Git 差分を一括確認します。 |
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

## ⚙️ Component Configuration (.env)

各コンポーネント（`components/dotfiles-*`）のルートディレクトリに `.env` ファイルを配置することで、コンポーネント固有の環境変数を設定できます。

### 📋 記述ルール
- **変数代入のみ**: `NAME=value` のような単純な変数代入のみを記述してください。
- **実行コマンドの禁止**: `source` コマンドで読み込まれるため、任意のシェルコマンドが実行可能ですが、副作用を防ぐため変数定義以外のロジックは含めないでください。

これらのファイルは、Orchestrator の `Makefile` および `dotfiles-zsh` の初期化時に自動的に読み込まれます。

---
Created by Gemini CLI based on @SPEC.md.
