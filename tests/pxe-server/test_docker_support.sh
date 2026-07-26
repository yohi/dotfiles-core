#!/usr/bin/env bash
# Daemon-free regression tests for the PXE Docker support files.
#
# The entrypoint is copied beside a mock pxe-serve.sh, so these tests cover
# environment-to-argument translation without starting Docker or PXE services.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PXE_DIR="${REPO_ROOT}/scripts/pxe-server"
ENTRYPOINT="${PXE_DIR}/docker-entrypoint.sh"
HASH_HELPER="${PXE_DIR}/gen-password-hash.sh"
DOCKERFILE="${PXE_DIR}/Dockerfile"
COMPOSE_FILE="${PXE_DIR}/compose.yaml"
IGNORE_FILE="${PXE_DIR}/Dockerfile.dockerignore"
README_FILE="${PXE_DIR}/README.md"
COMPOSE_ENV_EXAMPLE="${PXE_DIR}/compose.env.example"

TESTS_RUN=0
TESTS_FAILED=0
TEST_PASSWORD_HASH="\$6\$rounds=5000\$abc\$def"
SHA512_HASH_PREFIX="\$6\$"
EXPECTED_SSH_PUBKEY_PATH="SSH_PUBKEY_FILE=\${HOME}/.ssh/id_ed25519.pub"

pass() {
    local message="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'ok    - %s\n' "${message}"
}

fail() {
    local message="$1"
    local detail="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'NOT OK - %s\n' "${message}" >&2
    if [[ -n "${detail}" ]]; then
        printf '         %s\n' "${detail}" >&2
    fi
}

assert_file_contains() {
    local file="$1"
    local expected="$2"
    local message="$3"

    if [[ -f "${file}" ]] && [[ "$(<"${file}")" == *"${expected}"* ]]; then
        pass "${message}"
    else
        fail "${message}" "missing ${expected} in ${file}"
    fi
}

assert_argument_present() {
    local capture_file="$1"
    local expected="$2"
    local message="$3"
    local argument

    while IFS= read -r argument; do
        if [[ "${argument}" == "${expected}" ]]; then
            pass "${message}"
            return
        fi
    done < "${capture_file}"

    fail "${message}" "missing argument: ${expected}"
}

assert_argument_absent() {
    local capture_file="$1"
    local unexpected="$2"
    local message="$3"
    local argument

    while IFS= read -r argument; do
        if [[ "${argument}" == "${unexpected}" ]]; then
            fail "${message}" "unexpected argument: ${unexpected}"
            return
        fi
    done < "${capture_file}"

    pass "${message}"
}

prepare_entrypoint_fixture() {
    ENTRYPOINT_FIXTURE="$(mktemp -d)"
    mkdir -p "${ENTRYPOINT_FIXTURE}/scripts"
    cp "${ENTRYPOINT}" "${ENTRYPOINT_FIXTURE}/scripts/docker-entrypoint.sh"
    cat > "${ENTRYPOINT_FIXTURE}/scripts/pxe-serve.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${CAPTURE_FILE}"
EOF
    chmod +x "${ENTRYPOINT_FIXTURE}/scripts/pxe-serve.sh"
}

cleanup() {
    if [[ -n "${ENTRYPOINT_FIXTURE:-}" ]]; then
        rm -rf "${ENTRYPOINT_FIXTURE}"
    fi
    if [[ -n "${HASH_HELPER_DIR:-}" ]]; then
        rm -rf "${HASH_HELPER_DIR}"
    fi
}
trap cleanup EXIT

# ---- Docker build and Compose assets -----------------------------------------

if [[ -e "${PXE_DIR}/.dockerignore" ]]; then
    fail "legacy .dockerignore is absent for the repository-root build context"
else
    pass "legacy .dockerignore is absent for the repository-root build context"
fi

assert_file_contains "${IGNORE_FILE}" "scripts/pxe-server/.cache" \
    "Dockerfile-specific ignore excludes the PXE cache"
assert_file_contains "${IGNORE_FILE}" ".env" \
    "Dockerfile-specific ignore excludes local environment files"
assert_file_contains "${DOCKERFILE}" "COPY scripts/bootstrap.sh /app/scripts/bootstrap.sh" \
    "Dockerfile includes the bootstrap dependency"
assert_file_contains "${DOCKERFILE}" "chmod +x /app/scripts/pxe-server/docker-entrypoint.sh" \
    "Dockerfile makes the entrypoint executable"
assert_file_contains "${REPO_ROOT}/.gitignore" "/.env" \
    "root .env is ignored"
assert_file_contains "${COMPOSE_ENV_EXAMPLE}" "${EXPECTED_SSH_PUBKEY_PATH}" \
    "environment example uses a portable HOME-based SSH public key path"

if python3 - "${COMPOSE_FILE}" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as source:
    document = yaml.safe_load(source)

service = document["services"]["pxe-server"]
assert service["network_mode"] == "host"
assert service["cap_add"] == ["NET_BIND_SERVICE", "NET_RAW"]
assert "privileged" not in service
assert service["stdin_open"] is True
assert service["tty"] is True
assert "pxe-cache:/app/scripts/pxe-server/.cache" in service["volumes"]
assert any(volume.endswith(":/app/ssh_key.pub:ro") for volume in service["volumes"])
assert document["volumes"]["pxe-cache"]["name"] == "pxe-cache"
PY
then
    pass "Compose configuration has host networking, minimal capabilities, and named cache"
else
    fail "Compose configuration has host networking, minimal capabilities, and named cache"
fi

assert_file_contains "${README_FILE}" "docker compose -f scripts/pxe-server/compose.yaml --env-file .env down" \
    "README documents routine shutdown that preserves the cache"
assert_file_contains "${README_FILE}" "docker compose -f scripts/pxe-server/compose.yaml --env-file .env down -v" \
    "README documents explicit cache purge"
assert_file_contains "${README_FILE}" "## 手動 PXE テスト" \
    "README includes a manual PXE acceptance section"
assert_file_contains "${README_FILE}" "同じ LAN" \
    "manual PXE acceptance confirms the same-LAN prerequisite"
assert_file_contains "${README_FILE}" "BIOS/UEFI でネットワークブート" \
    "manual PXE acceptance confirms BIOS or UEFI network boot"
assert_file_contains "${README_FILE}" "ISO、user-data、meta-data を取得" \
    "manual PXE acceptance confirms PXE payload retrieval"
assert_file_contains "${README_FILE}" "無人インストールが完了" \
    "manual PXE acceptance confirms unattended installation"

# ---- docker-entrypoint.sh -----------------------------------------------------

if [[ -f "${ENTRYPOINT}" ]]; then
    pass "docker entrypoint exists"
    prepare_entrypoint_fixture

    CAPTURE_FILE="${ENTRYPOINT_FIXTURE}/arguments"
    KEY_FILE="${ENTRYPOINT_FIXTURE}/operator.pub"
    printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest operator@test' > "${KEY_FILE}"

    if env \
        PXE_IFACE=eth0 \
        PXE_SUBNET=192.168.1.0 \
        PXE_NETMASK=255.255.255.0 \
        OPERATOR_IP=192.168.1.10 \
        VERSION=24.04 \
        USERNAME=operator \
        TARGET_HOSTNAME=target-pxe \
        SSH_PUBKEY_FILE="${KEY_FILE}" \
        PASSWORD_HASH="${TEST_PASSWORD_HASH}" \
        GITHUB_USER=example-user \
        HTTP_PORT=8181 \
        CAPTURE_FILE="${CAPTURE_FILE}" \
        bash "${ENTRYPOINT_FIXTURE}/scripts/docker-entrypoint.sh" \
        >"${ENTRYPOINT_FIXTURE}/stdout" 2>"${ENTRYPOINT_FIXTURE}/stderr"; then
        pass "entrypoint delegates when a password hash is configured"
    else
        fail "entrypoint delegates when a password hash is configured" "$(<"${ENTRYPOINT_FIXTURE}/stderr")"
    fi

    assert_argument_present "${CAPTURE_FILE}" "--ssh-pubkey-file" \
        "entrypoint uses the pxe-serve SSH public key flag"
    assert_argument_present "${CAPTURE_FILE}" "${TEST_PASSWORD_HASH}" \
        "entrypoint preserves password hashes containing dollar characters"
    assert_argument_present "${CAPTURE_FILE}" "--github-user" \
        "entrypoint translates optional GitHub user"

    if env \
        PXE_SUBNET=192.168.1.0 \
        PXE_NETMASK=255.255.255.0 \
        OPERATOR_IP=192.168.1.10 \
        VERSION=24.04 \
        USERNAME=operator \
        TARGET_HOSTNAME=target-pxe \
        SSH_PUBKEY_FILE="${KEY_FILE}" \
        PASSWORD_HASH="${TEST_PASSWORD_HASH}" \
        CAPTURE_FILE="${CAPTURE_FILE}" \
        bash "${ENTRYPOINT_FIXTURE}/scripts/docker-entrypoint.sh" \
        >"${ENTRYPOINT_FIXTURE}/missing.stdout" 2>"${ENTRYPOINT_FIXTURE}/missing.stderr"; then
        fail "entrypoint rejects missing required environment variables"
    elif [[ "$(<"${ENTRYPOINT_FIXTURE}/missing.stderr")" == *"PXE_IFACE environment variable is required"* ]]; then
        pass "entrypoint rejects missing required environment variables"
    else
        fail "entrypoint rejects missing required environment variables" "unexpected error output"
    fi

    if env \
        PXE_IFACE=eth0 \
        PXE_SUBNET=192.168.1.0 \
        PXE_NETMASK=255.255.255.0 \
        OPERATOR_IP=192.168.1.10 \
        VERSION=24.04 \
        USERNAME=operator \
        TARGET_HOSTNAME=target-pxe \
        SSH_PUBKEY_FILE="${KEY_FILE}" \
        PASSWORD_HASH= \
        CAPTURE_FILE="${CAPTURE_FILE}" \
        bash "${ENTRYPOINT_FIXTURE}/scripts/docker-entrypoint.sh" \
        </dev/null >"${ENTRYPOINT_FIXTURE}/non-tty.stdout" 2>"${ENTRYPOINT_FIXTURE}/non-tty.stderr"; then
        fail "entrypoint rejects an empty password hash without a TTY"
    elif [[ "$(<"${ENTRYPOINT_FIXTURE}/non-tty.stderr")" == *"PASSWORD_HASH is required when stdin is not a TTY"* ]]; then
        pass "entrypoint rejects an empty password hash without a TTY"
    else
        fail "entrypoint rejects an empty password hash without a TTY" "unexpected error output"
    fi

    : > "${CAPTURE_FILE}"
    if env \
        PXE_IFACE=eth0 \
        PXE_SUBNET=192.168.1.0 \
        PXE_NETMASK=255.255.255.0 \
        OPERATOR_IP=192.168.1.10 \
        VERSION=24.04 \
        USERNAME=operator \
        TARGET_HOSTNAME=target-pxe \
        SSH_PUBKEY_FILE="${KEY_FILE}" \
        PASSWORD_HASH= \
        CAPTURE_FILE="${CAPTURE_FILE}" \
        python3 - "${ENTRYPOINT_FIXTURE}/scripts/docker-entrypoint.sh" <<'PY'
import os
import pty
import sys

pid, _ = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["bash", sys.argv[1]])
_, status = os.waitpid(pid, 0)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY
    then
        pass "entrypoint delegates an empty password hash on a TTY"
        assert_argument_absent "${CAPTURE_FILE}" "--password-hash" \
            "TTY delegation leaves password prompting to pxe-serve"
    else
        fail "entrypoint delegates an empty password hash on a TTY"
    fi
else
    fail "docker entrypoint exists"
fi

# ---- gen-password-hash.sh -----------------------------------------------------

if [[ -f "${HASH_HELPER}" ]]; then
    HASH_HELPER_DIR="$(mktemp -d)"
    if hash_output="$(printf 'password-for-test\npassword-for-test\n' | bash "${HASH_HELPER}" 2>"${HASH_HELPER_DIR}/stderr")"; then
        if [[ "${hash_output}" == "${SHA512_HASH_PREFIX}"* ]] && [[ "${hash_output}" != *"password-for-test"* ]]; then
            pass "password hash helper emits a SHA-512 hash without the plaintext"
        else
            fail "password hash helper emits a SHA-512 hash without the plaintext"
        fi
    else
        fail "password hash helper accepts matching passwords" "$(<"${HASH_HELPER_DIR}/stderr")"
    fi

    if printf 'first\nsecond\n' | bash "${HASH_HELPER}" >"${HASH_HELPER_DIR}/mismatch.stdout" 2>"${HASH_HELPER_DIR}/mismatch.stderr"; then
        fail "password hash helper rejects mismatched passwords"
    elif [[ "$(<"${HASH_HELPER_DIR}/mismatch.stderr")" == *"パスワードが一致しません"* ]]; then
        pass "password hash helper rejects mismatched passwords"
    else
        fail "password hash helper rejects mismatched passwords" "unexpected error output"
    fi
else
    fail "password hash helper exists"
fi

echo ""
echo "==================================================="
echo "  ${TESTS_RUN} tests run, ${TESTS_FAILED} failed"
echo "==================================================="

if [[ "${TESTS_FAILED}" -gt 0 ]]; then
    exit 1
fi
