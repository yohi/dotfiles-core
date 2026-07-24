#!/bin/bash
# scripts/pxe-server/render-autoinstall.sh
#
# Renders autoinstall.yaml + meta-data for one provisioning session from a
# username, hostname, operator SSH public key, optional GitHub username
# (for additional public keys, fetched unauthenticated from
# https://github.com/<user>.keys), and a pre-hashed password. Never accepts
# or stores a plaintext password on disk.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

# shellcheck source=../bootstrap.sh
# Reuse the already-tested validate_pubkeys() function instead of
# reimplementing key-format validation. Sourcing is side-effect-free
# because scripts/bootstrap.sh's main() is behind a BASH_SOURCE guard.
source "${REPO_ROOT}/scripts/bootstrap.sh"

# hash_password_interactive
#
# Prompts (masked, twice) for a password and prints only the
# `openssl passwd -6` hash to stdout. The plaintext password is held in a
# local shell variable for the minimum time required and is piped to
# openssl via stdin (never passed as an argv, never written to disk).
hash_password_interactive() {
    local pw1 pw2 hash

    read -rs -p "新規ユーザーのパスワードを入力してください: " pw1
    echo >&2
    read -rs -p "確認のためもう一度入力してください: " pw2
    echo >&2

    if [[ "${pw1}" != "${pw2}" ]]; then
        echo "ERROR: パスワードが一致しません" >&2
        return 1
    fi
    if [[ -z "${pw1}" ]]; then
        echo "ERROR: パスワードは空にできません" >&2
        return 1
    fi

    hash="$(printf '%s' "${pw1}" | openssl passwd -6 -stdin)"
    pw1=""
    pw2=""
    printf '%s\n' "${hash}"
    return 0
}

# fetch_github_keys <github_user>
#
# Fetches public keys from the unauthenticated https://github.com/<user>.keys
# endpoint and validates them via the sourced validate_pubkeys(). Prints the
# validated payload on success. Returns 1 (with no stdout) if <github_user>
# is empty, unreachable, or produces no valid keys.
fetch_github_keys() {
    local github_user="$1"
    local payload

    if [[ -z "${github_user}" ]]; then
        return 1
    fi

    payload="$(curl --proto '=https' --proto-redir '=https' -fsSL "https://github.com/${github_user}.keys")"
    if ! validate_pubkeys "${payload}"; then
        echo "ERROR: https://github.com/${github_user}.keys did not return a valid key set" >&2
        return 1
    fi

    printf '%s\n' "${payload}"
    return 0
}

# build_ssh_keys_yaml <operator_pubkey_file> <github_user>
#
# Builds the indented YAML list block for autoinstall's
# ssh.authorized-keys, combining the operator's local public key with any
# keys fetched from GitHub. Always includes the operator key; GitHub keys
# are best-effort (a fetch failure only drops GitHub keys, it does not
# fail the whole render).
build_ssh_keys_yaml() {
    local operator_pubkey_file="$1"
    local github_user="$2"
    local key github_keys

    if [[ ! -f "${operator_pubkey_file}" ]]; then
        echo "ERROR: operator SSH public key file not found: ${operator_pubkey_file}" >&2
        return 1
    fi

    while IFS= read -r key || [[ -n "${key}" ]]; do
        [[ -n "${key}" ]] && printf '      - %s\n' "${key}"
    done < "${operator_pubkey_file}"

    if github_keys="$(fetch_github_keys "${github_user}")"; then
        while IFS= read -r key || [[ -n "${key}" ]]; do
            [[ -n "${key}" ]] && printf '      - %s\n' "${key}"
        done <<< "${github_keys}"
    fi

    return 0
}

# render_autoinstall <username> <hostname> <ssh_pubkey_file> <github_user> <password_hash> <out_dir>
render_autoinstall() {
    local username="$1"
    local hostname="$2"
    local ssh_pubkey_file="$3"
    local github_user="$4"
    local password_hash="$5"
    local out_dir="$6"
    local ssh_keys_yaml

    if [[ -z "${username}" ]] || [[ -z "${hostname}" ]] || [[ -z "${password_hash}" ]]; then
        echo "ERROR: username, hostname, and password_hash are required" >&2
        return 1
    fi

    if ! ssh_keys_yaml="$(build_ssh_keys_yaml "${ssh_pubkey_file}" "${github_user}")"; then
        return 1
    fi

    mkdir -p "${out_dir}"

    AI_HOSTNAME="${hostname}" \
    AI_USERNAME="${username}" \
    AI_PASSWORD_HASH="${password_hash}" \
    AI_SSH_KEYS_YAML="${ssh_keys_yaml}" \
        envsubst '${AI_HOSTNAME} ${AI_USERNAME} ${AI_PASSWORD_HASH} ${AI_SSH_KEYS_YAML}' \
        < "${TEMPLATE_DIR}/autoinstall.yaml.tmpl" \
        > "${out_dir}/autoinstall.yaml"

    AI_HOSTNAME="${hostname}" \
    AI_INSTANCE_ID="${hostname}-$(date +%s)" \
        envsubst '${AI_HOSTNAME} ${AI_INSTANCE_ID}' \
        < "${TEMPLATE_DIR}/meta-data.tmpl" \
        > "${out_dir}/meta-data"

    if ! python3 -c "import yaml,sys; yaml.safe_load(open('${out_dir}/autoinstall.yaml'))" 2>&1; then
        echo "ERROR: generated autoinstall.yaml is not valid YAML" >&2
        return 1
    fi

    return 0
}

main() {
    set -euo pipefail
    local username="" hostname="" ssh_pubkey_file="" github_user="" password_hash="" out_dir=""
    local arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "${arg}" in
            --username) username="$2"; shift 2 ;;
            --hostname) hostname="$2"; shift 2 ;;
            --ssh-pubkey-file) ssh_pubkey_file="$2"; shift 2 ;;
            --github-user) github_user="$2"; shift 2 ;;
            --password-hash) password_hash="$2"; shift 2 ;;
            --out-dir) out_dir="$2"; shift 2 ;;
            *) echo "ERROR: unknown argument: ${arg}" >&2; exit 1 ;;
        esac
    done

    if [[ -z "${password_hash}" ]]; then
        password_hash="$(hash_password_interactive)" || exit 1
    fi

    if ! render_autoinstall "${username}" "${hostname}" "${ssh_pubkey_file}" "${github_user}" "${password_hash}" "${out_dir}"; then
        return 1
    fi
    return 0
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
