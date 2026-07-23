#!/bin/bash
# dotfiles-bootstrap
#
# 物理 PC 用ブートストラップスクリプト。
# ターゲット PC 上で root として実行され、操作 PC からの Ansible 接続に必要な
# 最小限の準備を行う。
#
# このスクリプトは実行可能かつソース可能である。
#   - 直接実行時   : main() が起動し、ブートストラップ処理一式を実行する。
#   - source 時    : 関数定義のみ読み込み、命令的な処理（apt/systemd/ユーザー
#                     作成など）は一切実行しない。テストから個別関数を検証できる。
#
# セキュリティ上重要な点として、GitHub から取得した公開鍵は
# `authorized_keys` 内の「管理ブロック」だけを置き換えて登録する。
# 管理ブロック外の既存鍵（手動追加した保守用鍵など）は再実行時も保持する。

GITHUB_KEYS_URL="https://github.com/yohi.keys"
USERNAME="y_ohi"

# authorized_keys 管理ブロックのマーカー（テストと完全一致させること）。
AUTHORIZED_KEYS_BEGIN="# >>> dotfiles-bootstrap managed keys (github.com/yohi.keys) >>>"
AUTHORIZED_KEYS_END="# <<< dotfiles-bootstrap managed keys <<<"

# -----------------------------------------------------------------------------
# validate_pubkeys <payload>
#
# GitHub から取得した公開鍵ペイロードを検証する。
#   - 空ペイロードを拒否する。
#   - 空行を拒否する。
#   - 制御文字・非印字文字（印字可能 ASCII 以外）を拒否する。
#   - `ssh-keygen -l -f -` で解釈できない鍵形式を拒否する。
#   - 単一・複数の有効な公開鍵を受理する。
#
# 検証成功で 0、失敗で 1 を返す。副作用（ファイル変更）は持たない。
# 各コマンドは明示的に戻り値を確認するため、set -e の有無に依存しない。
# -----------------------------------------------------------------------------
validate_pubkeys() {
    local pubkeys="$1"
    local key
    local found=0

    if [ -z "${pubkeys}" ]; then
        echo "ERROR: 公開鍵のペイロードが空です" >&2
        return 1
    fi

    while IFS= read -r key || [ -n "${key}" ]; do
        if [ -z "${key}" ]; then
            echo "ERROR: 公開鍵ペイロードに空行が含まれています" >&2
            return 1
        fi
        if LC_ALL=C printf '%s' "${key}" | grep -q '[^ -~]'; then
            echo "ERROR: 公開鍵に制御文字/非印字文字が含まれています" >&2
            return 1
        fi
        if ! printf '%s\n' "${key}" | ssh-keygen -l -f - >/dev/null 2>&1; then
            echo "ERROR: 公開鍵の形式が不正です" >&2
            return 1
        fi
        found=1
    done <<EOF
${pubkeys}
EOF

    if [ "${found}" -eq 0 ]; then
        echo "ERROR: 有効な公開鍵がありません" >&2
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# strip_managed_block <file>
#
# 指定ファイルから dotfiles-bootstrap 管理ブロックを取り除いた内容を標準出力へ
# 書き出す。ファイルが存在しない場合は何も出力せず 0 を返す。
#
# 管理ブロックのマーカーが不整合な場合は 1 を返す:
#   - 終了マーカーなしの開始マーカー（unterminated BEGIN）
#   - 開始マーカーなしの終了マーカー（orphan END）
#   - 開始マーカーの重複（duplicate BEGIN）
#   - 終了マーカーの重複（duplicate END）
# -----------------------------------------------------------------------------
strip_managed_block() {
    local file="$1"
    [ -f "${file}" ] || return 0

    if ! awk -v b="${AUTHORIZED_KEYS_BEGIN}" -v e="${AUTHORIZED_KEYS_END}" '
            $0 == b { if (inblk) { exit 1 } inblk = 1; next }
            $0 == e { if (!inblk) { exit 1 } inblk = 0; next }
            inblk { next }
            { print }
            END { if (inblk) exit 1 }
        ' "${file}"; then
        echo "ERROR: authorized_keys の管理ブロックが不完全です" >&2
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# render_authorized_keys <file> <managed_keys>
#
# authorized_keys の新しい内容を標準出力へ書き出す。
#   - 既存ファイルの管理ブロック外の行はすべて保持する。
#   - 末尾に新しい管理ブロックを 1 つだけ追加する。
#
# 既存ファイルの管理ブロックが不整合な場合は 1 を返し、何も追記しない。
# （strip_managed_block が途中まで出力した内容は呼び出し側の一時ファイルに
#   残るが、戻り値が非 0 のため呼び出し側で破棄される。）
# -----------------------------------------------------------------------------
render_authorized_keys() {
    local file="$1"
    local managed_keys="$2"

    if [ -f "${file}" ]; then
        if ! strip_managed_block "${file}"; then
            return 1
        fi
    fi

    printf '%s\n' "${AUTHORIZED_KEYS_BEGIN}"
    printf '%s\n' "${managed_keys}"
    printf '%s\n' "${AUTHORIZED_KEYS_END}"

    return 0
}

# -----------------------------------------------------------------------------
# install_managed_authorized_keys <target> <pubkeys>
#
# 検証済みの公開鍵を authorized_keys の管理ブロックへ原子的に反映する。
#   1. 鍵ペイロードを検証する（不正なら何も変更しない）。
#   2. ターゲットと同一ディレクトリの一時ファイルへ新内容を書き出す。
#   3. `mv` で原子的に置換する。
#
# 検証失敗・レンダリング失敗（管理ブロック不整合を含む）時は、既存ファイルを
# バイト単位で変更せず、一時ファイルを必ず削除して 1 を返す。
# -----------------------------------------------------------------------------
install_managed_authorized_keys() {
    local target="$1"
    local pubkeys="$2"
    local dir
    local tmp

    if ! validate_pubkeys "${pubkeys}"; then
        return 1
    fi

    dir="$(dirname "${target}")"
    mkdir -p "${dir}"

    if ! tmp="$(mktemp "${dir}/.authorized_keys.XXXXXX")"; then
        echo "ERROR: authorized_keys の一時ファイル作成に失敗しました" >&2
        return 1
    fi

    if ! render_authorized_keys "${target}" "${pubkeys}" >"${tmp}"; then
        rm -f "${tmp}"
        return 1
    fi

    chmod 600 "${tmp}"

    if ! mv -f "${tmp}" "${target}"; then
        rm -f "${tmp}"
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# set_sshd_directive <key> <value>
#
# sshd_config の指定ディレクティブを設定する。既存行（コメントアウト含む）が
# あれば置換し、なければ追記する。
# -----------------------------------------------------------------------------
set_sshd_directive() {
    local key="$1"
    local value="$2"

    if grep -Eq \
        "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" \
        /etc/ssh/sshd_config; then
        sed -i -E \
            "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" \
            /etc/ssh/sshd_config
    else
        printf '%s %s\n' "${key}" "${value}" >>/etc/ssh/sshd_config
    fi
}

# -----------------------------------------------------------------------------
# main
#
# ブートストラップ処理一式。直接実行時のみ起動する（末尾の BASH_SOURCE ガード
# 参照）。source 時は実行されないため、apt/systemd/ユーザー作成などの副作用は
# 発生しない。
# -----------------------------------------------------------------------------
main() {
    set -euo pipefail

    local ssh_dir
    local pubkeys
    local ip_addr

    echo "==> Checking OS..."
    if [ ! -f /etc/os-release ]; then
        echo "ERROR: /etc/os-release not found" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]] ||
        [[ "${VERSION_ID:-}" != "22.04" && "${VERSION_ID:-}" != "24.04" ]]; then
        echo "ERROR: Unsupported OS: ${ID:-unknown} ${VERSION_ID:-unknown}." >&2
        echo "ERROR: Ubuntu 22.04 or 24.04 is required." >&2
        exit 1
    fi

    echo "==> Updating packages..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl openssh-server sudo

    echo "==> Creating user ${USERNAME}..."
    if ! id "${USERNAME}" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "${USERNAME}"
    fi
    usermod -aG sudo "${USERNAME}"

    echo "==> Configuring passwordless sudo..."
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${USERNAME}" \
        >"/etc/sudoers.d/${USERNAME}"
    chmod 0440 "/etc/sudoers.d/${USERNAME}"
    /usr/sbin/visudo -cf "/etc/sudoers.d/${USERNAME}"

    echo "==> Fetching SSH public keys from GitHub..."
    pubkeys="$(curl --proto '=https' --proto-redir '=https' -fsSL "${GITHUB_KEYS_URL}")"

    echo "==> Installing managed authorized_keys..."
    ssh_dir="/home/${USERNAME}/.ssh"
    mkdir -p "${ssh_dir}"
    # 取得・検証が完了するまで authorized_keys を変更しない。検証失敗や管理
    # ブロック不整合時は install_managed_authorized_keys が既存ファイルを保持し、
    # 一時ファイルを削除したうえで非 0 を返すため、set -e により即座に終了する。
    install_managed_authorized_keys "${ssh_dir}/authorized_keys" "${pubkeys}"

    chmod 700 "${ssh_dir}"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${USERNAME}:${USERNAME}" "${ssh_dir}"

    echo "==> Hardening SSH configuration..."
    if ! sshd -t; then
        echo "ERROR: sshd configuration is invalid before modification" >&2
        exit 1
    fi

    set_sshd_directive PermitRootLogin no
    set_sshd_directive PasswordAuthentication no
    set_sshd_directive PubkeyAuthentication yes

    if ! sshd -t; then
        echo "ERROR: sshd configuration became invalid after modification" >&2
        exit 1
    fi

    if ! sshd -T | grep -qx 'permitrootlogin no' ||
        ! sshd -T | grep -qx 'passwordauthentication no' ||
        ! sshd -T | grep -qx 'pubkeyauthentication yes'; then
        echo "ERROR: sshd effective settings do not match the required hardening" >&2
        exit 1
    fi

    echo "==> Restarting SSH service..."
    systemctl restart sshd || service sshd restart || systemctl restart ssh

    ip_addr="$(hostname -I | awk '{print $1}')"
    echo ""
    echo "==================================================="
    echo "  Bootstrap complete."
    echo "  User: ${USERNAME}"
    echo "  IP:   ${ip_addr}"
    echo "  Port: 22"
    echo "  Next: Run ansible/run.sh from your operator PC."
    echo "==================================================="
    echo ""
    echo "NOTE: root ログインとパスワード認証は無効化されました。"
    echo "      以後、コンソール以外から root で接続できなくなります。"
}

# 直接実行時のみ main を起動する。source 時は関数定義のみ読み込む。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
