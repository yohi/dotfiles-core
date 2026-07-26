# PXEサーバー Docker 対応 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `scripts/pxe-server/` 配下のPXE無人インストールサーバーを、ホスト環境を汚さずに `docker compose up` 一発で起動できるようにする。

**Architecture:** 既存の `pxe-serve.sh` をそのまま流用し、Dockerfile / エントリポイント / compose.yaml でラップする「薄いラッパー」方式。ネットワークは host モード、権限は最小限の capabilities、netboot/ISO キャッシュは Docker named volume。

**Tech Stack:** Docker, Docker Compose, Ubuntu 24.04 base image, bash, dnsmasq, python3, envsubst

## Global Constraints

- ベースイメージ: `ubuntu:24.04`
- ネットワークモード: `--net=host`
- capabilities: `NET_BIND_SERVICE`, `NET_RAW`
- キャッシュ: Docker named volume `pxe-cache`
- 既存の `pxe-serve.sh`, `render-autoinstall.sh`, `fetch-netboot.sh`, `run-pxe.sh` は原則変更しない
- `.env` は `.gitignore` に追加してコミット対象外とする
- `run-pxe.sh` はホスト側の対話式ランチャーとして維持する

## 実装との同期

この計画の実装では、リポジトリルートをビルドコンテキストにするため、ignore ファイルは `scripts/pxe-server/Dockerfile.dockerignore` を使用する。Dockerfile は `scripts/bootstrap.sh` もコピーする。SSH 公開鍵の環境例は `${HOME}/.ssh/id_ed25519.pub` とし、通常停止は `docker compose ... down`、キャッシュ破棄時だけ `down -v` とする。Docker daemon を使わない回帰テストは `tests/pxe-server/test_docker_support.sh` で実行し、Docker build と実機 PXE ブートは別途受入確認する。

## File Structure

### 新規作成

| ファイル | 責任 |
| --- | --- |
| `scripts/pxe-server/Dockerfile` | PXEサーバー用コンテナイメージを定義する |
| `scripts/pxe-server/compose.yaml` | Docker Compose サービス定義、network_mode=host と capabilities/volumes を設定 |
| `scripts/pxe-server/compose.env.example` | `.env` ファイルのテンプレート、必須・任意の環境変数を示す |
| `scripts/pxe-server/docker-entrypoint.sh` | 環境変数を `pxe-serve.sh` のコマンドライン引数に変換し、必須チェックを行う |
| `scripts/pxe-server/gen-password-hash.sh` | ホスト側で `openssl passwd -6` を使ってパスワードハッシュを生成する |
| `scripts/pxe-server/README.md` | Docker 対応の起動・停止・設定手順を記載する |
| `scripts/pxe-server/Dockerfile.dockerignore` | リポジトリルートのビルドコンテキストから不要なファイルを除外する |

### 変更

| ファイル | 変更内容 |
| --- | --- |
| `.gitignore` | `.env` を追加する |

---

## Task 1: `Dockerfile.dockerignore` の作成

**Files:**
- Create: `scripts/pxe-server/Dockerfile.dockerignore`

**Interfaces:**
- Consumes: リポジトリルートのビルドコンテキスト
- Produces: Docker ビルド時に無視されるファイルリスト

- [ ] **Step 1: ファイルを作成する**

```dockerignore
# Git / CI / local configuration
.git
.github
.gitignore
.env
*.env

# Editor / IDE
.vscode
.idea
*.swp
*.swo

# Tests not needed at PXE server runtime
tests

# Existing cache must not be baked into image
scripts/pxe-server/.cache

# Documentation not needed inside image
README.md
docs

# Large / non-runtime files
*.iso
*.tar.gz
*.md
```

- [ ] **Step 2: ビルドコンテキストで確認する**

Run:
```bash
./tests/pxe-server/test_docker_support.sh
```

(注: Dockerfile 固有の ignore ファイルの静的契約は daemon-free harness で確認する。実際の Docker build は受入確認で実施する。)

- [ ] **Step 3: Commit**

```bash
git add scripts/pxe-server/Dockerfile.dockerignore
git commit -m "chore: PXEサーバー用 Dockerfile ignore を追加"
```

---

## Task 2: `Dockerfile` の作成

**Files:**
- Create: `scripts/pxe-server/Dockerfile`

**Interfaces:**
- Consumes: リポジトリルートのビルドコンテキスト
- Produces: `dotfiles-pxe-server` イメージ

- [ ] **Step 1: Dockerfile を作成する**

```dockerfile
# PXE server container for Ubuntu Server autoinstall
# Usage: docker compose -f scripts/pxe-server/compose.yaml up --build
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dnsmasq \
        gettext-base \
        iproute2 \
        openssh-client \
        openssl \
        python3 \
        python3-yaml && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts/bootstrap.sh /app/scripts/bootstrap.sh
COPY scripts/pxe-server/ /app/scripts/pxe-server/

# Ensure the cache directory exists and is writable by the entrypoint
RUN mkdir -p /app/scripts/pxe-server/.cache

ENTRYPOINT ["/app/scripts/pxe-server/docker-entrypoint.sh"]
```

- [ ] **Step 2: ビルドテストを実行する**

Run:
```bash
docker build -f scripts/pxe-server/Dockerfile -t dotfiles-pxe-server .
```

Expected: 成功し、イメージ `dotfiles-pxe-server` が作成される

- [ ] **Step 3: Commit**

```bash
git add scripts/pxe-server/Dockerfile
git commit -m "feat: PXEサーバー用 Dockerfile を追加"
```

---

## Task 3: `docker-entrypoint.sh` の作成

**Files:**
- Create: `scripts/pxe-server/docker-entrypoint.sh`

**Interfaces:**
- Consumes: 環境変数 `PXE_IFACE`, `PXE_SUBNET`, `PXE_NETMASK`, `OPERATOR_IP`, `VERSION`, `USERNAME`, `TARGET_HOSTNAME`, `PASSWORD_HASH`, `GITHUB_USER`, `HTTP_PORT`, `SSH_PUBKEY_FILE`
- Produces: `pxe-serve.sh` への引数、対話型パスワード入力の分岐

- [ ] **Step 1: エントリポイントスクリプトを作成する**

```bash
#!/bin/bash
# scripts/pxe-server/docker-entrypoint.sh
#
# Thin entrypoint wrapper that translates environment variables into the
# existing pxe-serve.sh CLI arguments. Runs pxe-serve.sh in the foreground.
set -euo pipefail

APP_DIR="/app/scripts/pxe-server"
PXE_SERVE="${APP_DIR}/pxe-serve.sh"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

# Required environment variables
PXE_IFACE="${PXE_IFACE:-}"
PXE_SUBNET="${PXE_SUBNET:-}"
PXE_NETMASK="${PXE_NETMASK:-}"
OPERATOR_IP="${OPERATOR_IP:-}"
VERSION="${VERSION:-}"
USERNAME="${USERNAME:-}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/app/ssh_key.pub}"

for var in PXE_IFACE PXE_SUBNET PXE_NETMASK OPERATOR_IP VERSION USERNAME TARGET_HOSTNAME; do
    if [[ -z "${!var}" ]]; then
        fail "${var} environment variable is required"
    fi
done

if [[ ! -f "${SSH_PUBKEY_FILE}" ]]; then
    fail "SSH public key file not found: ${SSH_PUBKEY_FILE}"
fi

PASSWORD_HASH="${PASSWORD_HASH:-}"
HTTP_PORT="${HTTP_PORT:-8080}"
GITHUB_USER="${GITHUB_USER:-}"

if [[ -z "${PASSWORD_HASH}" ]] && [[ ! -t 0 ]]; then
    fail "PASSWORD_HASH is required when stdin is not a TTY"
fi

ARGS=(
    --iface "${PXE_IFACE}"
    --subnet "${PXE_SUBNET}"
    --netmask "${PXE_NETMASK}"
    --operator-ip "${OPERATOR_IP}"
    --version "${VERSION}"
    --username "${USERNAME}"
    --hostname "${TARGET_HOSTNAME}"
    --ssh-pubkey-file "${SSH_PUBKEY_FILE}"
    --http-port "${HTTP_PORT}"
)

if [[ -n "${GITHUB_USER}" ]]; then
    ARGS+=(--github-user "${GITHUB_USER}")
fi

if [[ -n "${PASSWORD_HASH}" ]]; then
    ARGS+=(--password-hash "${PASSWORD_HASH}")
fi

exec "${PXE_SERVE}" "${ARGS[@]}"
```

- [ ] **Step 2: エントリポイントスクリプトに実行権限を付与する**

Run:
```bash
chmod +x scripts/pxe-server/docker-entrypoint.sh
```

- [ ] **Step 3: 構文チェックを実行する**

Run:
```bash
bash -n scripts/pxe-server/docker-entrypoint.sh
```

Expected: エラーなし

- [ ] **Step 4: ビルドしてエントリポイントが存在することを確認する**

Run:
```bash
docker build -f scripts/pxe-server/Dockerfile -t dotfiles-pxe-server . && \
docker run --rm dotfiles-pxe-server ls -l /app/scripts/pxe-server/docker-entrypoint.sh
```

Expected: ファイルが存在し、実行権限がある

- [ ] **Step 5: Commit**

```bash
git add scripts/pxe-server/docker-entrypoint.sh
git commit -m "feat: PXEサーバー用 Docker エントリポイントを追加"
```

---

## Task 4: `gen-password-hash.sh` の作成

**Files:**
- Create: `scripts/pxe-server/gen-password-hash.sh`

**Interfaces:**
- Consumes: ユーザーからの標準入力（パスワード）
- Produces: `openssl passwd -6` 形式のハッシュ文字列を標準出力

- [ ] **Step 1: パスワードハッシュ生成スクリプトを作成する**

```bash
#!/bin/bash
# scripts/pxe-server/gen-password-hash.sh
#
# Helper to generate a password hash for the PXE autoinstall user-data.
# Prompts twice for the password and prints the openssl passwd -6 hash.
# Never writes the plaintext password to disk.
set -euo pipefail

read -rs -p "新規ユーザーのパスワードを入力してください: " pw1
echo >&2
read -rs -p "確認のためもう一度入力してください: " pw2
echo >&2

if [[ "${pw1}" != "${pw2}" ]]; then
    echo "ERROR: パスワードが一致しません" >&2
    exit 1
fi

if [[ -z "${pw1}" ]]; then
    echo "ERROR: パスワードは空にできません" >&2
    exit 1
fi

printf '%s' "${pw1}" | openssl passwd -6 -stdin
```

- [ ] **Step 2: 実行権限を付与し、構文チェックする**

Run:
```bash
chmod +x scripts/pxe-server/gen-password-hash.sh
bash -n scripts/pxe-server/gen-password-hash.sh
```

Expected: エラーなし

- [ ] **Step 3: テスト実行する**

Run:
```bash
# テスト用にパスワードをリダイレクトではなく、期待される動作を確認
# 実際には ./scripts/pxe-server/gen-password-hash.sh を実行し、
# 同じパスワードを2回入力して "$6$" で始まるハッシュが出力されることを確認
```

Expected: 標準出力に `$6$...` 形式のハッシュが出力される

- [ ] **Step 4: Commit**

```bash
git add scripts/pxe-server/gen-password-hash.sh
git commit -m "feat: PXE用パスワードハッシュ生成ヘルパーを追加"
```

---

## Task 5: `compose.yaml` の作成

**Files:**
- Create: `scripts/pxe-server/compose.yaml`

**Interfaces:**
- Consumes: `.env` ファイルからの環境変数
- Produces: `dotfiles-pxe-server` サービス

- [ ] **Step 1: compose.yaml を作成する**

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
      PASSWORD_HASH: ${PASSWORD_HASH}
      GITHUB_USER: ${GITHUB_USER}
      HTTP_PORT: ${HTTP_PORT:-8080}
      SSH_PUBKEY_FILE: /app/ssh_key.pub
    stdin_open: true
    tty: true

volumes:
  pxe-cache:
    name: pxe-cache
```

- [ ] **Step 2: `docker compose config` で構文を確認する**

Run:
```bash
docker compose -f scripts/pxe-server/compose.yaml --env-file scripts/pxe-server/compose.env.example config
```

Expected: エラーなしで設定が出力される

- [ ] **Step 3: Commit**

```bash
git add scripts/pxe-server/compose.yaml
git commit -m "feat: PXEサーバー用 Docker Compose 定義を追加"
```

---

## Task 6: `compose.env.example` の作成

**Files:**
- Create: `scripts/pxe-server/compose.env.example`

**Interfaces:**
- Consumes: ユーザーの環境設定
- Produces: `.env` ファイルのテンプレート

- [ ] **Step 1: テンプレートを作成する**

```bash
# PXE server Docker Compose environment variables
# Copy this file to the repository root as .env and edit values.

# Network interface on the operator PC to use for PXE (e.g., eth0, enp3s0)
PXE_IFACE=eth0

# PXE subnet and netmask (must match the LAN the target PC is on)
PXE_SUBNET=192.168.1.0
PXE_NETMASK=255.255.255.0

# IP address of the operator PC on the above interface
OPERATOR_IP=192.168.1.10

# Ubuntu version to install
VERSION=24.04

# New user to create on the installed machine
USERNAME=y_ohi

# Hostname of the installed machine
TARGET_HOSTNAME=ubuntu-pxe

# Path to the operator's SSH public key on the host
SSH_PUBKEY_FILE=${HOME}/.ssh/id_ed25519.pub

# Optional GitHub username to fetch additional SSH public keys
GITHUB_USER=

# HTTP port for serving ISO and autoinstall files
HTTP_PORT=8080

# Pre-generated password hash for the new user.
# Generate with: ./scripts/pxe-server/gen-password-hash.sh
# Leave empty to be prompted for a password on container startup (requires tty).
# 例: PASSWORD_HASH='$6$rounds=5000$...'
PASSWORD_HASH=
```

- [ ] **Step 2: Commit**

```bash
git add scripts/pxe-server/compose.env.example
git commit -m "docs: PXEサーバー用 .env テンプレートを追加"
```

---

## Task 7: `.gitignore` の更新

**Files:**
- Modify: `.gitignore`

**Interfaces:**
- Consumes: 既存の `.gitignore`
- Produces: `.env` を無視するよう変更

- [ ] **Step 1: `.gitignore` に `.env` を追加する**

```gitignore
# PXE server local configuration (contains password hash)
/.env
```

- [ ] **Step 2: 既存の `.gitignore` を確認して、重複がないことを確認する**

Run:
```bash
grep -n "^/\.env$" .gitignore || true
```

Expected: 追加した行が存在する

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: .env を .gitignore に追加"
```

---

## Task 8: `README.md` の作成

**Files:**
- Create: `scripts/pxe-server/README.md`

**Interfaces:**
- Consumes: 設計ドキュメントと各ファイルの説明
- Produces: 運用手順書

- [ ] **Step 1: README.md を作成する**

```markdown
# PXE Server (Docker)

Ubuntu Server 無人インストール用の PXE サーバーを Docker コンテナで実行する。

## 前提条件

- Docker Engine
- Docker Compose v2
- 操作PCとインストール対象PCが同じLANに接続されていること

## クイックスタート

```bash
# 1. 設定テンプレートをコピー
cp scripts/pxe-server/compose.env.example .env

# 2. .env を編集（PXE_IFACE, OPERATOR_IP, SUBNET など）
# 3. パスワードハッシュを生成（対話入力を使わない場合）
./scripts/pxe-server/gen-password-hash.sh
# 生成されたハッシュを .env の PASSWORD_HASH に貼り付ける

# 4. 起動
docker compose -f scripts/pxe-server/compose.yaml --env-file .env up --build

# 5. 別端末から停止
docker compose -f scripts/pxe-server/compose.yaml down
```

## ネットワーク

`compose.yaml` は `network_mode: host` を使用する。これは PXE ブートに必要な DHCP/TFTP ポートをホストのネットワークスタックで直接扱うため。

## 権限

以下の capabilities を最小限に付与する。

- `NET_BIND_SERVICE`
- `NET_RAW`

## キャッシュ

netboot tarball と ISO は Docker named volume `pxe-cache` に保存される。通常停止ではこのキャッシュを保持し、不要になった場合だけ以下で削除する。

```bash
docker compose -f scripts/pxe-server/compose.yaml down -v
```

## パスワードの設定

`.env` に `PASSWORD_HASH` を設定しない場合、コンテナ起動時に対話的に入力を求める。CI や非対話用途では `gen-password-hash.sh` を使って事前に生成する。

## 既存のネイティブ実行

ホストに直接パッケージをインストールして実行する場合は、引き続き以下を使用する。

```bash
sudo ./scripts/pxe-server/pxe-serve.sh ...
```

- [ ] **Step 2: Commit**

```bash
git add scripts/pxe-server/README.md
git commit -m "docs: PXEサーバー Docker 運用手順を追加"
```

---

## Task 9: 統合テスト

**Files:**
- Use: `scripts/pxe-server/compose.yaml`, `scripts/pxe-server/Dockerfile`, `scripts/pxe-server/docker-entrypoint.sh`

**Interfaces:**
- Consumes: これまでに作成したすべてのファイル
- Produces: 動作確認結果

- [ ] **Step 1: daemon-free Docker サポートテストを実行する**

Run:
```bash
./tests/pxe-server/test_docker_support.sh
```

Expected: Docker daemon を起動せずにエントリポイント、パスワードヘルパー、Compose の静的契約が成功する

- [ ] **Step 2: Compose 構成を確認する**

Run:
```bash
docker compose -f scripts/pxe-server/compose.yaml --env-file scripts/pxe-server/compose.env.example config
```

Expected: エラーなし

- [ ] **Step 3: イメージビルドテストを実行する**

Run:
```bash
docker compose -f scripts/pxe-server/compose.yaml --env-file .env build
```

Expected: ビルドが成功する

- [ ] **Step 4: エントリポイントの引数変換を確認する**

Run:
```bash
# ダミーSSH公開鍵を用意（mktempで通常ファイルを作成して検証可能にする）
DUMMY_KEY=$(mktemp -t ssh_key.pub.XXXXXX)
cat > "$DUMMY_KEY" <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDIhz2GK/XCUj4i6Q5yQJNL1MXMY0RxzPV2QrBqfHrDq fake-key
EOF

# モック用 pxe-serve.sh を用意してエントリポイントの引数変換を検証
cat > /tmp/mock-pxe-serve.sh <<'EOF'
#!/bin/bash
printf '%s\n' "$*"
EOF
chmod +x /tmp/mock-pxe-serve.sh

docker run --rm --net=host \
  --cap-add=NET_BIND_SERVICE \
  --cap-add=NET_RAW \
  -v pxe-cache:/app/scripts/pxe-server/.cache \
  -v "$DUMMY_KEY:/app/ssh_key.pub:ro" \
  -v /tmp/mock-pxe-serve.sh:/app/scripts/pxe-server/pxe-serve.sh:ro \
  -e PXE_IFACE=eth0 \
  -e PXE_SUBNET=192.168.1.0 \
  -e PXE_NETMASK=255.255.255.0 \
  -e OPERATOR_IP=192.168.1.10 \
  -e VERSION=24.04 \
  -e USERNAME=testuser \
  -e TARGET_HOSTNAME=test-pxe \
  -e PASSWORD_HASH='$6$fake$fakehash' \
  dotfiles-pxe-server
```

（注: このテストは `docker-entrypoint.sh` が環境変数から構築した固定の引数をモック `pxe-serve.sh` に渡す動作を検証する。`/dev/null` ではなく `mktemp` で作成した通常ファイルをマウントすることで、`[[ -f "${SSH_PUBKEY_FILE}" ]]` のチェックを通過し、`--ssh-pubkey-file` 引数の生成も含めて検証可能にしている。`docker run` への追加 CLI 引数を `pxe-serve.sh` に転送する前提はない。）

- [ ] **Step 5: 実際のネットワーク環境での手動PXEブートテスト**

条件:
- 実機またはVMを同じLANに接続
- 対象をネットワークブート
- ISO/user-data/meta-data が取得でき、autoinstallが進行することを確認

- [ ] **Step 6: Commit 確認**

```bash
git status
```

Expected: すべての新規ファイルがコミット済み

---

## セルフレビュー

### Spec coverage

- 薄いラッパー方式: Task 1-3, Task 5 でカバー
- host ネットワーク: Task 5
- 最小限 capabilities: Task 5
- named volume キャッシュ: Task 5
- 既存スクリプト変更しない: Global Constraints
- `.env` 管理: Task 6, Task 7
- パスワードハッシュ生成: Task 4
- 対話/非対話両対応: Task 3, Task 4
- README 運用手順: Task 8
- テスト: Task 9

### Placeholder scan

- TBD/TODO: なし
- 未確定のコマンド: すべて具体例を記載
- 実際のPXEブートは手動テストと明記

### Type consistency

- 環境変数名: `compose.yaml`, `docker-entrypoint.sh`, `compose.env.example` で統一
- ファイルパス: `/app/...` と `scripts/pxe-server/...` の使い分けを明確化
