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

- **物理 PC**（外部から SSH 接続できない場合）: 同一 LAN 上であれば、
  `scripts/pxe-server/run-pxe.sh` を使った **PXE 無人インストール**
  （OS インストールからユーザー作成・SSH 鍵登録まで自動化）が推奨です。操作 PC 上で
  一時的な PXE/TFTP/HTTP サーバーを起動し、ターゲット PC の電源を入れるだけで
  セットアップが始まります。Docker コンテナ経由で同じ PXE サーバーを起動する経路も
  利用できます。詳細は [`ansible/README.md`](ansible/README.md) と後述の Docker 手順を
  参照してください。
  PXE が使えない環境では、ターゲット PC のコンソールでブートストラップスクリプト（`scripts/bootstrap.sh`）をダウンロードして実行するレガシー経路も利用できます。スクリプトは Cloudflare Workers（`scripts/workers/`）経由で HTTPS 配信され、`X-Script-SHA256` ヘッダによる整合性検証が可能です。
- **VPS**（外部から SSH 接続できる場合）: ターゲット PC のコンソールには入らず、操作 PC から Ansible（`ansible/setup.yml`）のみで全て実施します。

両方とも、対話式ランチャー `ansible/run.sh` から実行します。詳細な手順・セキュリティ設計は [`ansible/README.md`](ansible/README.md) を参照してください。

> [!NOTE]
> このフローは「まだ Ubuntu マシンがセットアップされていない」段階を対象とします。dotfiles-core のクローンと本セットアップ（`common-setup` ロール）は Ansible が自動的に実行するため、上記フローの後に以下の Quick Start を別途実行する必要はありません。
>
> なお、Ubuntu 26.04 のネットブート成果物（codename: `resolute`）は執筆時点で未検証です。`fetch_netboot()` は URL の到達性を確認し、存在しない場合は明確なエラーメッセージを返して即座に失敗します。

### PXE サーバー（Docker）

Docker は PXE サーバーの追加実行経路です。ホストへ `dnsmasq` などを導入せずに
起動できますが、ネイティブの `bash scripts/pxe-server/run-pxe.sh` も引き続き利用できます。

#### 設計の要点

Docker 対応は既存の `pxe-serve.sh` を置き換えるのではなく、Dockerfile / エントリポイント / Compose で薄くラップする「薄いラッパー」方式です。これにより、ホストへの `dnsmasq` 導入なしに PXE サーバーを起動でき、既存のネイティブ実行経路も維持します。

- **ホストネットワーク**: PXE に必要な DHCP/TFTP 通信のため `network_mode: host` を使用します。
- **最小権限**: `privileged` は使用せず、`NET_BIND_SERVICE` と `NET_RAW` の capability のみを追加します。
- **キャッシュ分離**: netboot 成果物と ISO は Docker named volume `pxe-cache` に保存し、ホストを汚しません。
- **設定の秘匿**: パスワードハッシュを含む `.env` は `.gitignore` で Git 管理対象外としています。

#### 設定と起動

Docker Engine、Docker Compose v2、同一 LAN 上の操作 PC と対象 PC、および操作 PC の
SSH 公開鍵を用意します。リポジトリルートで環境ファイルを作成し、必須値を設定します。

```bash
cp scripts/pxe-server/compose.env.example .env
```

必須値は `PXE_IFACE`、`PXE_SUBNET`、`PXE_NETMASK`、`OPERATOR_IP`、
`SSH_PUBKEY_FILE` です。`VERSION`、`USERNAME`、`TARGET_HOSTNAME`、`HTTP_PORT`、
`GITHUB_USER`、`PASSWORD_HASH` は既定値または任意値として設定できます。

非対話起動では、事前にパスワードハッシュを生成して `.env` の `PASSWORD_HASH` に設定します。`$` を含むハッシュは単一引用符で囲みます。

```bash
bash scripts/pxe-server/gen-password-hash.sh
# PASSWORD_HASH='$6$...'

docker compose -f scripts/pxe-server/compose.yaml --env-file .env up --build
```

`PASSWORD_HASH` を空にした場合は、起動端末の TTY で対話入力します。非対話実行で空の
ままにすると起動は失敗します。必須環境変数の不足や `SSH_PUBKEY_FILE` の不在も即時
エラーになります。

同じ Docker ホスト上で複数のチェックアウトを並行運用する場合は、`.env` の
`COMPOSE_PROJECT_NAME` に固有の名前を設定してください。未設定の場合、イメージタグ
とキャッシュボリューム名が固定値となり、別チェックアウト間で上書き・競合が発生する
可能性があります。

#### 停止と受入確認

通常停止では netboot 成果物と ISO を保持する named volume `pxe-cache` を残します。
キャッシュを破棄する場合だけ `-v` を付けます。

```bash
docker compose -f scripts/pxe-server/compose.yaml --env-file .env down
docker compose -f scripts/pxe-server/compose.yaml --env-file .env down -v
```

実際の PXE ブートはネットワーク環境とハードウェアに依存します。操作 PC と対象 PC が
同じ LAN にあることを確認し、対象 PC で BIOS/UEFI のネットワークブートを選択して、
ISO、`user-data`、`meta-data` の取得と無人インストール完了を確認してください。

PXE の DHCP/TFTP 通信のため Docker Compose はホストネットワークを使用し、
`NET_BIND_SERVICE` と `NET_RAW` のみを追加します。詳細な運用手順は
[`scripts/pxe-server/README.md`](scripts/pxe-server/README.md) を参照してください。

#### セキュリティとエラーハンドリング

- `.env` にはパスワードハッシュが含まれるため、リポジトリにコミットしないでください（`.gitignore` で除外済み）。
- SSH 公開鍵ファイルはコンテナに read-only でマウントされます。
- `PASSWORD_HASH` を空にして非 TTY 環境で起動すると、即座に失敗します。対話入力を使う場合は TTY 端末から実行してください。
- `PXE_IFACE` などの必須環境変数が不足している場合、または `SSH_PUBKEY_FILE` が存在しない場合も即座に失敗します。
- PXE 配信は Ubuntu 無人インストールの仕様上平文 HTTP を使用します。これは Docker 化によっても変わりません。
- 同じ Docker ホスト上で複数のチェックアウトを並行運用する場合は、`.env` の `COMPOSE_PROJECT_NAME` に固有の名前を設定してください。未設定の場合、イメージタグとキャッシュボリューム名が固定値となり、別チェックアウト間で上書き・競合が発生する可能性があります。

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
