#!/usr/bin/env bash
# dotfiles-pxe-server render-autoinstall.sh regression tests
#
# Focused regression tests for scripts/pxe-server/render-autoinstall.sh.
# Sources the script (main() must stay behind a BASH_SOURCE guard) and
# drives render_autoinstall()/build_ssh_keys_yaml() directly. Does not run
# the interactive hash_password_interactive() prompt.
#
# NOTE: set -e is intentionally omitted; this harness tracks pass/fail
# counts itself and deliberately exercises expected-failure paths.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RENDER_SH="${REPO_ROOT}/scripts/pxe-server/render-autoinstall.sh"

TESTS_RUN=0
TESTS_FAILED=0

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'ok    - %s\n' "$1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'NOT OK - %s\n' "$1" >&2
    if [ -n "${2:-}" ]; then
        printf '         %s\n' "$2" >&2
    fi
}

if [ ! -f "${RENDER_SH}" ]; then
    echo "FATAL: render-autoinstall.sh not found: ${RENDER_SH}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${RENDER_SH}"

for fn in render_autoinstall build_ssh_keys_yaml hash_password_interactive fetch_github_keys main; do
    if declare -F "${fn}" >/dev/null 2>&1; then
        pass "function is defined: ${fn}"
    else
        fail "function is defined: ${fn}"
    fi
done

# ---- render_autoinstall: happy path -----------------------------------------

OUT_DIR="$(mktemp -d)"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPERATORKEYEXAMPLEONLY operator@pc" > "${OUT_DIR}/operator.pub"

if render_autoinstall "y_ohi" "ubuntu-pxe" "${OUT_DIR}/operator.pub" "" '$6$fakehash$abcdefgh' "${OUT_DIR}"; then
    pass "render_autoinstall exits 0 with valid inputs"
else
    fail "render_autoinstall exits 0 with valid inputs"
fi

if [ -f "${OUT_DIR}/user-data" ]; then
    pass "user-data is created"
else
    fail "user-data is created"
fi

if [ -f "${OUT_DIR}/meta-data" ]; then
    pass "meta-data is created"
else
    fail "meta-data is created"
fi

if python3 -c "import yaml,sys; yaml.safe_load(open('${OUT_DIR}/user-data'))" 2>/dev/null; then
    pass "user-data is valid YAML"
else
    fail "user-data is valid YAML"
fi

if grep -q 'username: y_ohi' "${OUT_DIR}/user-data"; then
    pass "user-data contains the requested username"
else
    fail "user-data contains the requested username"
fi

if grep -q 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPERATORKEYEXAMPLEONLY' "${OUT_DIR}/user-data"; then
    pass "user-data embeds the operator's SSH public key"
else
    fail "user-data embeds the operator's SSH public key"
fi

if grep -Fq 'password: "$6$fakehash$abcdefgh"' "${OUT_DIR}/user-data"; then
    pass "user-data embeds the password hash verbatim (including \$ characters)"
else
    fail "user-data embeds the password hash verbatim (including \$ characters)"
fi

if ! grep -qi 'PermitRootLogin\|PasswordAuthentication' "${OUT_DIR}/user-data"; then
    pass "user-data does not duplicate sshd hardening (left to Ansible)"
else
    fail "user-data does not duplicate sshd hardening (left to Ansible)"
fi

rm -rf "${OUT_DIR}"

# ---- render_autoinstall: rejects missing required fields -------------------

OUT_DIR2="$(mktemp -d)"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPERATORKEYEXAMPLEONLY operator@pc" > "${OUT_DIR2}/operator.pub"

if render_autoinstall "" "ubuntu-pxe" "${OUT_DIR2}/operator.pub" "" '$6$fakehash$abcdefgh' "${OUT_DIR2}" 2>/dev/null; then
    fail "render_autoinstall rejects an empty username"
else
    pass "render_autoinstall rejects an empty username"
fi
rm -rf "${OUT_DIR2}"

# ---- build_ssh_keys_yaml: missing operator key file -------------------------

if build_ssh_keys_yaml "/nonexistent/path.pub" "" >/dev/null 2>&1; then
    fail "build_ssh_keys_yaml rejects a missing operator key file"
else
    pass "build_ssh_keys_yaml rejects a missing operator key file"
fi

# ---- build_ssh_keys_yaml: empty operator key file (I1 zero-key lockout guard) --

EMPTY_KEY_DIR="$(mktemp -d)"
: > "${EMPTY_KEY_DIR}/empty.pub"
if build_ssh_keys_yaml "${EMPTY_KEY_DIR}/empty.pub" "" >/dev/null 2>&1; then
    fail "build_ssh_keys_yaml rejects an empty operator key file with no github user"
else
    pass "build_ssh_keys_yaml rejects an empty operator key file with no github user"
fi
rm -rf "${EMPTY_KEY_DIR}"

# ---- build_ssh_keys_yaml: whitespace-only operator key file (blank-lines lockout guard) --

WS_KEY_DIR="$(mktemp -d)"
printf '   \n\t\n' > "${WS_KEY_DIR}/blank.pub"
if build_ssh_keys_yaml "${WS_KEY_DIR}/blank.pub" "" >/dev/null 2>&1; then
    fail "build_ssh_keys_yaml rejects a whitespace-only operator key file"
else
    pass "build_ssh_keys_yaml rejects a whitespace-only operator key file"
fi
rm -rf "${WS_KEY_DIR}"

# ---- Summary -----------------------------------------------------------------

echo ""
echo "==================================================="
echo "  ${TESTS_RUN} tests run, ${TESTS_FAILED} failed"
echo "==================================================="

if [ "${TESTS_FAILED}" -gt 0 ]; then
    exit 1
fi
exit 0
