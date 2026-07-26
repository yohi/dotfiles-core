# PXEサーバーのDocker対応設計

## 概要

`dotfiles-core` リポジトリの `scripts/pxe-server/` にあるPXE無人インストールサーバーを、Dockerコンテナで動作させる。目的はホスト環境を汚さずに `docker compose up` 一発でPXEサーバーを起動できるようにすること。既存のネイティブ実行（`sudo ./scripts/pxe-server/pxe-serve.sh`）は維持する。

## 背景

現在の `pxe-serve.sh` は、ホストPC上でフォアグラウンドで実行するスクリプトである。以下のプロセスを起動する。

- `dnsmasq`: ProxyDHCP + TFTP
- `python3 -m http.server`: ISO / autoinstall ファイル配信

これらを動作させるには、ホストに `dnsmasq` などをインストールし、root権限で実行する必要がある。ホスト環境をできるだけ汚したくない、かつ運用用途で簡単に起動したい、という要求からDocker化を行う。

## 目標と成功条件

### 目標

- ホストにパッケージをインストールすることなく、PXEサーバーを起動できる。
- 起動コマンドは `docker compose up` 程度に簡潔にする。
- 既存の `pxe-serve.sh` や `render-autoinstall.sh` などの主要ロジックを流用する。
- 停止時には、コンテナ内のプロセスをクリーンに終了する。

### 成功条件

- `docker compose -f scripts/pxe-server/compose.yaml up --build` でサービスが起動する。
- 対象PCからPXEブートが可能で、ISO / user-data / meta-data が取得できる。
- 停止時に `docker compose down` でdnsmasq と HTTPサーバーが確実に終了する。
- 既存のネイティブ実行パスも維持される。

## 設計方針

### 採用アプローチ: 薄いラッパー方式

既存の `pxe-serve.sh` をそのまま流用し、Dockerfileで必要な依存を入れるだけの「薄いラッパー」とする。他に検討したアプローチは以下の通り。

| アプローチ | 評価 |
| --- | --- |
| 薄いラッパー方式 | 既存コードを最大限流用、変更が最小、推奨 |
| 構成をイメージ埋め込み方式 | 柔軟性が低く、今回の運用用途に合わない |
| Supervisord + マルチサービス方式 | 不要な依存増加、既存の cleanup トラップと競合 |

## ネットワーク設計

PXEブートはDHCP / TFTPを必要とするため、Dockerでは **host ネットワークモード** を使用する。`--net=host` により、コンテナはホストのネットワークスタックを直接使用する。

### 採用理由

- ProxyDHCPは、既存のルーターDHCPに対してPXE特有のオプションを追加で返す動作をする。
- TFTPはポート69をリッスンする。
- これらはホストのネットワークインターフェースに直接バインドする必要がある。

他のmacvlan/ipvlan方式は、追加のIP/MAC管理やホストからの通信設定が必要で、今回の「簡単に起動したい」という目的に合わない。

## 権限設計

`dnsmasq` は特権ポートやRAWソケットを必要とするため、最小限の capabilities を付与する。`--privileged` は避ける。

### 必要な capabilities

- `NET_BIND_SERVICE`: ポート69(TFTP)などの特権ポートバインド
- `NET_RAW`: 一部のDHCP操作でRAWソケットが必要な場合がある

## キャッシュ設計

netboot tarball と ISO のダウンロードは、Docker named volume で永続化する。

### 理由

- 毎回ダウンロードすると遅い。
- ホストの `scripts/pxe-server/.cache/` 配下にファイルを残したくない。
- Docker volume は `docker volume rm pxe-cache` 一発で削除でき、ホストを汚さない。

## 構成ファイル

### 新規作成ファイル

| ファイル | 説明 |
| --- | --- |
| `scripts/pxe-server/Dockerfile` | PXEサーバー用のコンテナイメージ定義 |
| `scripts/pxe-server/compose.yaml` | Docker Compose サービス定義 |
| `scripts/pxe-server/compose.env.example` | `.env` ファイルのテンプレート |
| `scripts/pxe-server/docker-entrypoint.sh` | 環境変数を `pxe-serve.sh` 引数に変換する薄いラッパー |
| `scripts/pxe-server/gen-password-hash.sh` | ホスト側でパスワードハッシュを生成するヘルパー |
| `scripts/pxe-server/README.md` | Docker対応の運用手順 |
| `scripts/pxe-server/Dockerfile.dockerignore` | ビルドコンテキストから不要なファイルを除外する（リポジトリルートをcontextとする） |

### 変更ファイル

| ファイル | 変更内容 |
| --- | --- |
| `.gitignore` | `.env` を追加（`PASSWORD_HASH` などを含む） |

### 既存スクリプトの変更方針

- `pxe-serve.sh`: 原則変更しない。ネイティブ実行も維持する。
- `run-pxe.sh`: ホスト側の対話式ランチャーとして維持する。
- `fetch-netboot.sh` / `render-autoinstall.sh`: 変更しない。

## Dockerfile 設計

### ベースイメージ

`ubuntu:24.04` を採用する。理由は以下の通り。

- PXEブートに必要な `pxelinux`, `GRUB`, `dnsmasq` などがネイティブに近い形で使える。
- Alpine などにすると、dnsmasq の設定やパスが異なる場合があり、既存テンプレートとの互換性を保ちにくい。

### インストールパッケージ

- `dnsmasq`
- `python3`
- `python3-yaml`
- `curl`
- `openssl`
- `openssh-client`
- `gettext-base`（`envsubst` 用）
- `iproute2`
- `ca-certificates`

### コピーするファイル

以下のファイルをイメージにコピーする。

- `scripts/pxe-server/` 配下のスクリプト・テンプレート
- `scripts/bootstrap.sh`（`pxe-serve.sh` の依存）

リポジトリルートをビルドコンテキストとするため、`Dockerfile.dockerignore` で `.env` や `.git`、`tests`、`docs`、既存の PXE キャッシュなどを除外する。


### イメージ内構成

- `WORKDIR`: `/app`
- `pxe-server` スクリプト: `/app/scripts/pxe-server/`
- エントリポイント: `/app/scripts/pxe-server/docker-entrypoint.sh`

## エントリポイント設計

`docker-entrypoint.sh` は以下の役割を持つ。

1. 必須環境変数（`PXE_IFACE`, `PXE_SUBNET`, `PXE_NETMASK`, `OPERATOR_IP`, `VERSION`, `USERNAME`, `TARGET_HOSTNAME`, `PASSWORD_HASH` または対話入力）を確認する。
2. `pxe-serve.sh` の引数形式に変換する。
3. `exec` で `pxe-serve.sh` を起動する。

`PASSWORD_HASH` が未設定の場合、コンテナ内で対話的に入力を求める。CIや非対話用途では、事前に `gen-password-hash.sh` で生成して `.env` に設定する。

## Docker Compose 設計

### `compose.yaml` 概要

```yaml
services:
  pxe-server:
    build:
      context: ../..
      dockerfile: scripts/pxe-server/Dockerfile
    image: dotfiles-pxe-server
    container_name: dotfiles-pxe-server
    network_mode: host
    cap_add:
      - NET_BIND_SERVICE
      - NET_RAW
    volumes:
      - pxe-cache:/app/scripts/pxe-server/.cache
      - ${SSH_PUBKEY_FILE:?SSH_PUBKEY_FILE must be set}:/app/ssh_key.pub:ro
    environment:
      PXE_IFACE: ${PXE_IFACE:?PXE_IFACE must be set}
      PXE_SUBNET: ${PXE_SUBNET:?PXE_SUBNET must be set}
      PXE_NETMASK: ${PXE_NETMASK:?PXE_NETMASK must be set}
      OPERATOR_IP: ${OPERATOR_IP:?OPERATOR_IP must be set}
      VERSION: ${VERSION:-24.04}
      USERNAME: ${USERNAME:-y_ohi}
      TARGET_HOSTNAME: ${TARGET_HOSTNAME:-ubuntu-pxe}
      PASSWORD_HASH: ${PASSWORD_HASH:-}
      GITHUB_USER: ${GITHUB_USER:-}
      HTTP_PORT: ${HTTP_PORT:-8080}
      SSH_PUBKEY_FILE: /app/ssh_key.pub
    stdin_open: true
    tty: true

volumes:
  pxe-cache:
    name: pxe-cache
```

### 設定ファイルの分離

`.env` ファイルに設定を集約する。例を `compose.env.example` に提供する。

```bash
PXE_IFACE=eth0
PXE_SUBNET=192.168.1.0
PXE_NETMASK=255.255.255.0
OPERATOR_IP=192.168.1.10
VERSION=24.04
USERNAME=y_ohi
TARGET_HOSTNAME=ubuntu-pxe
SSH_PUBKEY_FILE=${HOME}/.ssh/id_ed25519.pub
GITHUB_USER=
HTTP_PORT=8080
PASSWORD_HASH=
```

## パスワードハッシュ生成

### 対話的入力

`.env` で `PASSWORD_HASH` を空にして `docker compose up` すると、コンテナ内でパスワードを入力できる。ただし `stdin_open` と `tty` を有効にする必要がある。

### 事前生成

生成されたハッシュを `.env` の `PASSWORD_HASH` に貼り付ける。ハッシュ内の `$` がシェル展開されないよう、値を単一引用符 `'` で囲んで設定すること。

```bash
./scripts/pxe-server/gen-password-hash.sh
```

このスクリプトは `openssl passwd -6` を呼び出し、平文パスワードをハッシュ化する。平文は端末に表示しない。

## 起動・停止フロー

### 起動

```bash
cp scripts/pxe-server/compose.env.example .env
# .env を編集
docker compose -f scripts/pxe-server/compose.yaml --env-file .env up --build
```

### 停止

```bash
# 別端末から（キャッシュを保持して停止）
docker compose -f scripts/pxe-server/compose.yaml --env-file .env down

# キャッシュごと破棄する場合
docker compose -f scripts/pxe-server/compose.yaml --env-file .env down -v
```

`pxe-serve.sh` の `trap cleanup` が SIGTERM を受け取って、dnsmasq と HTTPサーバーを停止し、作業ディレクトリを削除する。

## エラーハンドリング

- 必須環境変数が不足している場合、エントリポイントで即座にエラーメッセージを出力して終了する。
- `PASSWORD_HASH` が未設定かつ非対話実行（`tty` なし）の場合、エラーを出力して終了する。
- SSH公開鍵ファイルが存在しない場合、マウント時点でエラーとなる。`compose.yaml` でのパス検証は行わない（実行時に失敗してわかるため）。

## テスト方針

### 自動テスト（可能な範囲）

- Dockerfile のビルドが成功することを確認する。
- `scripts/pxe-server/docker-entrypoint.sh` の環境変数から引数への変換を、テストハーネス `tests/pxe-server/test_docker_support.sh` で確認する（Docker daemon を起動せずに検証可能）。
- `render-autoinstall.sh` の既存テストは維持する。

### 手動テスト

実際のPXEブートはネットワーク環境とハードウェアに依存するため、手動手順を `README.md` に記載する。

- 対象PCを同じLANに接続
- ネットワークブートを選択
- インストールが自動で進行することを確認

## セキュリティ考慮事項

- `.env` ファイルには `PASSWORD_HASH` が含まれるため、`.gitignore` に追加してコミットしない。
- コンテナは最小限の capabilities のみ付与する。
- SSH公開鍵は read-only でマウントする。
- HTTPサーバーはPXEインストール用途のため、平文HTTPを使用する（`pxe-serve.sh` コメントと同じ理由）。
- `Dockerfile.dockerignore` により、ローカルの `.env` や PXE キャッシュ、ドキュメントがイメージに含まれないようにする。

## 既存機能との関係

- ネイティブ実行パス（`sudo ./scripts/pxe-server/pxe-serve.sh`）は維持される。
- `run-pxe.sh` はホスト側で引き続き使用する。
- Docker化はあくまで新しい実行方法を追加するものであり、既存方法を置き換えるものではない。

## 実装後の成果物

- `docker compose -f scripts/pxe-server/compose.yaml up --build` でPXEサーバーが起動する。
- ホストにパッケージをインストールせずに、Ubuntu Server のPXE無人インストールが可能になる。
- 停止時にはクリーンに終了する。
