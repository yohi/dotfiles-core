#!/bin/bash
# 依存するAnsibleコレクションをインストールし、対話式に入力された情報を基に初期セットアッププレイブックを実行します。

set -euo pipefail

# 依存コレクションのインストール
echo "==> 必要な Ansible コレクションをインストールしています..."
ansible-galaxy collection install ansible.posix community.general

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USE_CONFIG=false
ANSIBLE_ARGS=()

# スクリプトに渡された引数をそのまま ansible-playbook に転送するための配列
for arg in "$@"; do
    ANSIBLE_ARGS+=("$arg")
done

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# --- デフォルト値の初期設定 ---
DEFAULT_TARGET_IP=""
DEFAULT_INIT_PORT="22"
DEFAULT_INIT_USER="root"
DEFAULT_INIT_KEY_PATH=""

DEFAULT_USERNAME="y_ohi"
DEFAULT_SSH_KEY_PATH="~/.ssh/id_ed25519.pub"
DEFAULT_NEW_SSH_PORT="5310"

# --- 既存ファイルからのデフォルト値の抽出 ---
# hosts.ini から初期接続情報の抽出
if [ -f "${SCRIPT_DIR}/hosts.ini" ]; then
    HOST_LINE=$(grep "ansible_host=" "${SCRIPT_DIR}/hosts.ini" || true)
    if [ -n "${HOST_LINE}" ]; then
        TEMP_IP=$(echo "${HOST_LINE}" | sed -n -E 's/.*ansible_host=([^[:space:]]+).*/\1/p' || true)
        [ -n "${TEMP_IP}" ] && [[ ! "${TEMP_IP}" == *"ansible_host="* ]] && DEFAULT_TARGET_IP="${TEMP_IP}"

        TEMP_PORT=$(echo "${HOST_LINE}" | sed -n -E 's/.*ansible_port=([^[:space:]]+).*/\1/p' || true)
        [ -n "${TEMP_PORT}" ] && DEFAULT_INIT_PORT="${TEMP_PORT}"

        TEMP_USER=$(echo "${HOST_LINE}" | sed -n -E 's/.*ansible_user=([^[:space:]]+).*/\1/p' || true)
        [ -n "${TEMP_USER}" ] && DEFAULT_INIT_USER="${TEMP_USER}"

        TEMP_KEY=$(echo "${HOST_LINE}" | sed -n -E 's/.*ansible_private_key_file=([^[:space:]]+).*/\1/p' || true)
        [ -n "${TEMP_KEY}" ] && DEFAULT_INIT_KEY_PATH="${TEMP_KEY}"
    else
        # [servers] の直下にIPアドレスやホスト名が直接書かれている場合のフォールバック
        LINE=$(grep -A 1 "^\[servers\]" "${SCRIPT_DIR}/hosts.ini" | tail -n 1 || true)
        if [ -n "${LINE}" ] && [[ ! "${LINE}" =~ ^\[ ]] && [[ ! "${LINE}" =~ ^# ]]; then
            TEMP_IP=$(echo "${LINE}" | tr -d '[:space:]')
            [ -n "${TEMP_IP}" ] && DEFAULT_TARGET_IP="${TEMP_IP}"
        fi
    fi
fi

# vars.yml から変数設定の抽出
if [ -f "${SCRIPT_DIR}/vars.yml" ]; then
    # username
    TEMP_VAR=$(grep "^username:" "${SCRIPT_DIR}/vars.yml" | sed -E 's/^username:[[:space:]]*["'\''#]?([^"'\''#[:space:]]+)["'\''#]?.*/\1/' || true)
    [ -n "${TEMP_VAR}" ] && [[ ! "${TEMP_VAR}" == *"username:"* ]] && DEFAULT_USERNAME="${TEMP_VAR}"

    # ssh_public_key_path
    TEMP_VAR=$(grep "^ssh_public_key_path:" "${SCRIPT_DIR}/vars.yml" | sed -E 's/^ssh_public_key_path:[[:space:]]*["'\'']?([^"'\''#]+)["'\'']?.*/\1/' | sed -E 's/[[:space:]]+$//' || true)
    [ -n "${TEMP_VAR}" ] && [[ ! "${TEMP_VAR}" == *"ssh_public_key_path:"* ]] && DEFAULT_SSH_KEY_PATH="${TEMP_VAR}"

    # new_ssh_port
    TEMP_VAR=$(grep "^new_ssh_port:" "${SCRIPT_DIR}/vars.yml" | sed -E 's/^new_ssh_port:[[:space:]]*([0-9]+).*/\1/' || true)
    [ -n "${TEMP_VAR}" ] && [[ ! "${TEMP_VAR}" == *"new_ssh_port:"* ]] && DEFAULT_NEW_SSH_PORT="${TEMP_VAR}"
fi

# すでに設定ファイルが存在する場合の確認処理
if [ -f "${SCRIPT_DIR}/hosts.ini" ] && [ -f "${SCRIPT_DIR}/vars.yml" ]; then
    echo ""
    read -p "既存の設定をつかいますか？（y/N）: " USE_EXISTING
    if [[ "${USE_EXISTING}" =~ ^[yY]$ ]]; then
        USE_CONFIG=true
    fi
fi

# 既存の設定を使用する場合の実行処理
if [ "${USE_CONFIG}" = true ]; then
    echo ""
    echo "==> 既存の設定ファイルを使用して Ansible プレイブックを実行しています..."
    ansible-playbook "${SCRIPT_DIR}/setup.yml" -i "${SCRIPT_DIR}/hosts.ini" "${ANSIBLE_ARGS[@]}"
    exit 0
fi

echo ""
echo "======================================================="
echo "  Ansible サーバー初期セットアップ - 対話式設定"
echo "======================================================="

# 1. 接続先IPアドレス/ホスト名
if [ -n "${DEFAULT_TARGET_IP}" ]; then
    read -p "ターゲットサーバーの IPアドレス または ホスト名 [${DEFAULT_TARGET_IP}]: " TARGET_IP
    TARGET_IP="${TARGET_IP:-${DEFAULT_TARGET_IP}}"
else
    read -p "ターゲットサーバーの IPアドレス または ホスト名: " TARGET_IP
    if [ -z "${TARGET_IP}" ]; then
        echo "エラー: IPアドレスまたはホスト名の入力は必須です。" >&2
        exit 1
    fi
fi

# 2. 初期接続用のSSHポート番号
while true; do
    read -p "初期接続用の SSH ポート番号 [${DEFAULT_INIT_PORT}]: " INIT_PORT
    INIT_PORT="${INIT_PORT:-${DEFAULT_INIT_PORT}}"
    if validate_port "${INIT_PORT}"; then
        break
    else
        echo "エラー: ポート番号は1から65535の範囲の整数で入力してください。" >&2
    fi
done

# 3. 初期接続用のSSHユーザー
read -p "初期接続用の SSH ユーザー [${DEFAULT_INIT_USER}]: " INIT_USER
INIT_USER="${INIT_USER:-${DEFAULT_INIT_USER}}"

# 4. 初期接続用のSSH秘密鍵パス
if [ -n "${DEFAULT_INIT_KEY_PATH}" ]; then
    read -p "初期接続用の SSH 秘密鍵パス [${DEFAULT_INIT_KEY_PATH}]: " INIT_KEY_PATH
    INIT_KEY_PATH="${INIT_KEY_PATH:-${DEFAULT_INIT_KEY_PATH}}"
else
    read -p "初期接続用の SSH 秘密鍵パス (空の場合はデフォルトの鍵を使用): " INIT_KEY_PATH
fi

# 5. 新規作成する一般ユーザー名
read -p "新規作成する一般ユーザー名 [${DEFAULT_USERNAME}]: " USERNAME
USERNAME="${USERNAME:-${DEFAULT_USERNAME}}"

# 6. 実行元PCのSSH公開鍵パス (ターゲット of 新規ユーザー用)
read -p "実行元PCのSSH公開鍵のパス [${DEFAULT_SSH_KEY_PATH}]: " SSH_KEY_PATH
SSH_KEY_PATH="${SSH_KEY_PATH:-${DEFAULT_SSH_KEY_PATH}}"

# 7. 新しいSSHポート番号
while true; do
    read -p "変更後の SSH ポート番号 [${DEFAULT_NEW_SSH_PORT}]: " NEW_SSH_PORT
    NEW_SSH_PORT="${NEW_SSH_PORT:-${DEFAULT_NEW_SSH_PORT}}"
    if validate_port "${NEW_SSH_PORT}"; then
        break
    else
        echo "エラー: ポート番号は1から65535の範囲の整数で入力してください。" >&2
    fi
done

# --- 各種パスの検証 ---
# 登録する公開鍵のパス展開と存在チェック
SSH_KEY_PATH_EXPANDED="${SSH_KEY_PATH/#\~/$HOME}"
SSH_KEY_PATH_EXPANDED="$(realpath -m "${SSH_KEY_PATH_EXPANDED}")"
if [ ! -f "${SSH_KEY_PATH_EXPANDED}" ]; then
    echo "警告: 指定された公開鍵ファイルが見つかりません: ${SSH_KEY_PATH}"
    read -p "このまま続行しますか？ (y/N): " KEY_CONFIRM
    if [[ ! "${KEY_CONFIRM}" =~ ^[yY]$ ]]; then
        echo "中断しました。"
        exit 1
    fi
fi

# 接続用秘密鍵のパス展開と存在チェック
INIT_KEY_PARAM=""
if [ -n "${INIT_KEY_PATH}" ]; then
    INIT_KEY_PATH_EXPANDED="${INIT_KEY_PATH/#\~/$HOME}"
    if [ ! -f "${INIT_KEY_PATH_EXPANDED}" ]; then
        echo "警告: 指定された接続用秘密鍵が見つかりません: ${INIT_KEY_PATH}"
        read -p "このまま続行しますか？ (y/N): " KEY_CONFIRM_2
        if [[ ! "${KEY_CONFIRM_2}" =~ ^[yY]$ ]]; then
            echo "中断しました。"
            exit 1
        fi
    fi
    INIT_KEY_PARAM="ansible_private_key_file=${INIT_KEY_PATH_EXPANDED}"
fi

echo ""
echo "======================================================="
echo "設定内容を確認してください:"
echo "  - 接続先ホスト        : ${TARGET_IP}"
echo "  - 初期接続ポート      : ${INIT_PORT}"
echo "  - 初期接続ユーザー    : ${INIT_USER}"
echo "  - 初期接続秘密鍵      : ${INIT_KEY_PATH:-(デフォルトの鍵を使用)}"
echo "  - 新規作成ユーザー    : ${USERNAME}"
echo "  - 登録するSSH公開鍵   : ${SSH_KEY_PATH}"
echo "  - 変更後のSSHポート   : ${NEW_SSH_PORT}"
echo "======================================================="
read -p "この設定で Ansible プレイブックを実行しますか？ (y/N): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[yY]$ ]]; then
    echo "キャンセルしました。"
    exit 0
fi

# ポート番号の最終検証
if ! validate_port "${INIT_PORT}"; then
    echo "エラー: 初期接続用SSHポート番号が不正です (${INIT_PORT})。" >&2
    exit 1
fi
if ! validate_port "${NEW_SSH_PORT}"; then
    echo "エラー: 変更後SSHポート番号が不正です (${NEW_SSH_PORT})。" >&2
    exit 1
fi

# 対話入力された設定内容で既存の設定ファイル（hosts.ini と vars.yml）を更新する
echo "==> 設定ファイルを更新しています..."
cat <<EOF > "${SCRIPT_DIR}/hosts.ini"
[servers]
target_host ansible_host=${TARGET_IP} ansible_port=${INIT_PORT} ansible_user=${INIT_USER}${INIT_KEY_PARAM:+ ${INIT_KEY_PARAM}}
EOF

cat <<EOF > "${SCRIPT_DIR}/vars.yml"
---
username: "${USERNAME}"
ssh_public_key_path: "${SSH_KEY_PATH_EXPANDED}"
new_ssh_port: ${NEW_SSH_PORT}
github_token: ""
EOF

echo "==> Ansible プレイブックを実行しています..."
ansible-playbook "${SCRIPT_DIR}/setup.yml" \
  -i "${SCRIPT_DIR}/hosts.ini" \
  "${ANSIBLE_ARGS[@]}"
