#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PXE_SERVE="${SCRIPT_DIR}/pxe-serve.sh"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

PXE_IFACE="${PXE_IFACE:-}"
PXE_SUBNET="${PXE_SUBNET:-}"
PXE_NETMASK="${PXE_NETMASK:-}"
OPERATOR_IP="${OPERATOR_IP:-}"
VERSION="${VERSION:-}"
USERNAME="${USERNAME:-}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/app/ssh_key.pub}"
PASSWORD_HASH="${PASSWORD_HASH:-}"
if [[ -z "${PASSWORD_HASH}" ]] && [[ -f /app/password.hash ]]; then
    PASSWORD_HASH="$(cat /app/password.hash | xargs)"
fi
GITHUB_USER="${GITHUB_USER:-}"
HTTP_PORT="${HTTP_PORT:-8080}"

for variable in PXE_IFACE PXE_SUBNET PXE_NETMASK OPERATOR_IP VERSION USERNAME TARGET_HOSTNAME; do
    if [[ -z "${!variable}" ]]; then
        fail "${variable} environment variable is required"
    fi
done

if [[ ! -f "${SSH_PUBKEY_FILE}" ]]; then
    fail "SSH public key file not found: ${SSH_PUBKEY_FILE}"
fi

if [[ -z "${PASSWORD_HASH}" ]] && [[ ! -t 0 ]]; then
    fail "PASSWORD_HASH is required when stdin is not a TTY"
fi

arguments=(
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
    arguments+=(--github-user "${GITHUB_USER}")
fi

if [[ -n "${PASSWORD_HASH}" ]]; then
    arguments+=(--password-hash "${PASSWORD_HASH}")
fi

exec "${PXE_SERVE}" "${arguments[@]}"
