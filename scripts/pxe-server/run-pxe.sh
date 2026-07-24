#!/bin/bash
# scripts/pxe-server/run-pxe.sh
#
# Interactive launcher for pxe-serve.sh, mirroring the prompt style of
# ansible/run.sh. Auto-detects the default network interface and its
# subnet/netmask, prompts for the rest, confirms, then execs pxe-serve.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_iface() {
    ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

detect_ip_and_cidr() {
    local iface="$1"
    ip -4 -o addr show dev "${iface}" 2>/dev/null | awk '{print $4; exit}'
}

cidr_to_netmask() {
    local cidr="$1"
    python3 -c "
import ipaddress, sys
net = ipaddress.ip_network('${cidr}', strict=False)
print(net.netmask)
"
}

main() {
    local default_iface default_cidr default_ip default_subnet default_netmask
    default_iface="$(detect_iface)"
    local separator="======================================================="

    if [[ -n "${default_iface}" ]]; then
        default_cidr="$(detect_ip_and_cidr "${default_iface}")"
        if [[ -n "${default_cidr}" ]]; then
            default_ip="${default_cidr%/*}"
            default_netmask="$(cidr_to_netmask "${default_cidr}")"
            default_subnet="$(python3 -c "
import ipaddress
net = ipaddress.ip_network('${default_cidr}', strict=False)
print(net.network_address)
")"
        fi
    fi

    echo "${separator}"
    echo "  Ubuntu Server Autoinstall PXE - 対話式設定"
    echo "${separator}"

    read -rp "ネットワークインターフェース [${default_iface:-eth0}]: " IFACE
    IFACE="${IFACE:-${default_iface:-eth0}}"

    read -rp "操作PCのIPアドレス [${default_ip:-}]: " OPERATOR_IP
    OPERATOR_IP="${OPERATOR_IP:-${default_ip:-}}"
    if [[ -z "${OPERATOR_IP}" ]]; then
        echo "エラー: 操作PCのIPアドレスの入力は必須です。" >&2
        exit 1
    fi

    read -rp "LANのサブネット [${default_subnet:-192.168.1.0}]: " SUBNET
    SUBNET="${SUBNET:-${default_subnet:-192.168.1.0}}"

    read -rp "LANのネットマスク [${default_netmask:-255.255.255.0}]: " NETMASK
    NETMASK="${NETMASK:-${default_netmask:-255.255.255.0}}"

    read -rp "インストール対象のUbuntuバージョン [24.04]: " VERSION
    VERSION="${VERSION:-24.04}"

    read -rp "新規作成する一般ユーザー名 [y_ohi]: " USERNAME
    USERNAME="${USERNAME:-y_ohi}"

    read -rp "ホスト名 [ubuntu-pxe]: " HOSTNAME
    HOSTNAME="${HOSTNAME:-ubuntu-pxe}"

    read -rp "操作PCのSSH公開鍵のパス [~/.ssh/id_ed25519.pub]: " SSH_KEY_PATH
    SSH_KEY_PATH="${SSH_KEY_PATH:-~/.ssh/id_ed25519.pub}"
    SSH_KEY_PATH="${SSH_KEY_PATH/#\~/${HOME}}"

    read -rp "GitHub ユーザー名 (追加のSSH公開鍵を https://github.com/<user>.keys から取得、空でスキップ): " GITHUB_USER

    echo ""
    echo "${separator}"
    echo "設定内容を確認してください:"
    echo "  - 操作PC IP           : ${OPERATOR_IP}"
    echo "  - サブネット/ネットマスク: ${SUBNET} / ${NETMASK}"
    echo "  - Ubuntuバージョン    : ${VERSION}"
    echo "  - 新規ユーザー名      : ${USERNAME}"
    echo "  - ホスト名            : ${HOSTNAME}"
    echo "  - SSH公開鍵           : ${SSH_KEY_PATH}"
    echo "  - GitHubユーザー名    : ${GITHUB_USER:-(スキップ)}"
    echo "${separator}"
    read -rp "この設定でPXEサーバーを起動しますか？ (root権限が必要です) (y/N): " CONFIRM
    if [[ ! "${CONFIRM}" =~ ^[yY]$ ]]; then
        echo "キャンセルしました。"
        exit 0
    fi

    exec sudo "${SCRIPT_DIR}/pxe-serve.sh" \
        --iface "${IFACE}" \
        --subnet "${SUBNET}" \
        --netmask "${NETMASK}" \
        --operator-ip "${OPERATOR_IP}" \
        --version "${VERSION}" \
        --username "${USERNAME}" \
        --hostname "${HOSTNAME}" \
        --ssh-pubkey-file "${SSH_KEY_PATH}" \
        --github-user "${GITHUB_USER}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
