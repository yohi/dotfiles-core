#!/usr/bin/env bash
# dotfiles-bootstrap authorized_keys managed-block regression tests
#
# These are FOCUSED regression tests for the security-critical
# authorized_keys merge logic in scripts/bootstrap.sh. They source the
# script (so main() must stay behind a BASH_SOURCE guard) and drive the
# public functions directly, without running the imperative bootstrap flow
# (no apt / systemd / user creation / sshd changes).
#
# NOTE: `set -e` is intentionally omitted. This harness deliberately invokes
# functions that are expected to fail, and tracks pass/fail counts itself.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOOTSTRAP_SH="${BOOTSTRAP_SH:-${REPO_ROOT}/scripts/bootstrap.sh}"

# Exact markers as specified by the design (must match bootstrap.sh byte-for-byte).
BEGIN_MARKER="# >>> dotfiles-bootstrap managed keys (github.com/yohi.keys) >>>"
END_MARKER="# <<< dotfiles-bootstrap managed keys <<<"
MANUAL_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMAINTENANCEKEYEXAMPLEONLY maintenance@ops"

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

# ---- Preconditions -----------------------------------------------------------

if [ ! -f "${BOOTSTRAP_SH}" ]; then
    echo "FATAL: bootstrap script not found: ${BOOTSTRAP_SH}" >&2
    echo "       (expected scripts/bootstrap.sh to exist)" >&2
    exit 1
fi

if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "FATAL: ssh-keygen is required for these tests" >&2
    exit 1
fi

# ---- Source the script (must have no side effects) ---------------------------

# Sourcing must have no side effects: main() is behind a BASH_SOURCE guard, so
# sourcing must emit no output and exit 0. Doing it in a child bash isolates any
# hypothetical side effect from this harness (and sidesteps a shellcheck 0.11.0
# crash on the `source` builtin inside command substitution).
source_out="$(bash -c 'source "$1" 2>&1' _ "${BOOTSTRAP_SH}")"
source_rc=$?
if [ "${source_rc}" -eq 0 ]; then
    pass "sourcing bootstrap.sh succeeds"
else
    fail "sourcing bootstrap.sh succeeds" "exit code ${source_rc}"
fi
if [ -z "${source_out}" ]; then
    pass "sourcing bootstrap.sh produces no output (no imperative side effects)"
else
    fail "sourcing bootstrap.sh produces no output (no imperative side effects)" \
        "output: ${source_out}"
fi

# Load the functions into the current shell for the remaining assertions.
# shellcheck source=/dev/null
source "${BOOTSTRAP_SH}"

for fn in validate_pubkeys strip_managed_block render_authorized_keys \
          install_managed_authorized_keys main; do
    if declare -F "${fn}" >/dev/null 2>&1; then
        pass "function is defined: ${fn}"
    else
        fail "function is defined: ${fn}"
    fi
done

if ! id "y_ohi" >/dev/null 2>&1; then
    pass "sourcing did not create the y_ohi user (main not executed)"
else
    # A pre-existing y_ohi user (e.g. on a dev host) is not a test failure by
    # itself, but in the clean Docker image it proves main() did not run.
    pass "y_ohi already present on host (skipping main-not-run check)"
fi

# ---- Test fixtures -----------------------------------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

KEYDIR="${WORK}/keys"
mkdir -p "${KEYDIR}"
ssh-keygen -t ed25519 -f "${KEYDIR}/k1" -N "" -q
ssh-keygen -t ed25519 -f "${KEYDIR}/k2" -N "" -q
KEY1="$(cat "${KEYDIR}/k1.pub")"
KEY2="$(cat "${KEYDIR}/k2.pub")"

# A key line containing a control character (BEL, 0x07).
CTRL_KEY="$(printf 'ssh-ed25519 AAAA\aBADCONTROL user@host')"
INVALID_KEY="this-is-definitely-not-a-valid-ssh-public-key"

# Helper: count exact-line occurrences in a file.
count_lines() { grep -cxF "$1" "$2" 2>/dev/null || true; }

# Helper: managed-block key body extraction.
managed_block_keys() {
    awk -v b="${BEGIN_MARKER}" -v e="${END_MARKER}" \
        '$0==b{inblk=1;next} $0==e{inblk=0;next} inblk{print}' "$1"
}

# Helper: assert no temp files leaked in a directory.
assert_no_temp_leak() {
    local dir="$1" desc="$2"
    local leaked
    leaked="$(find "${dir}" -maxdepth 1 -name '.authorized_keys.*' 2>/dev/null)"
    if [ -z "${leaked}" ]; then
        pass "${desc}"
    else
        fail "${desc}" "leaked: ${leaked}"
    fi
}

# =============================================================================
# validate_pubkeys
# =============================================================================

if validate_pubkeys "${KEY1}"; then
    pass "validate_pubkeys accepts a single valid key"
else
    fail "validate_pubkeys accepts a single valid key"
fi

if validate_pubkeys "$(printf '%s\n%s' "${KEY1}" "${KEY2}")"; then
    pass "validate_pubkeys accepts multiple valid keys"
else
    fail "validate_pubkeys accepts multiple valid keys"
fi

if validate_pubkeys "" 2>/dev/null; then
    fail "validate_pubkeys rejects empty payload"
else
    pass "validate_pubkeys rejects empty payload"
fi

if validate_pubkeys "$(printf '%s\n\n%s' "${KEY1}" "${KEY2}")" 2>/dev/null; then
    fail "validate_pubkeys rejects blank lines in payload"
else
    pass "validate_pubkeys rejects blank lines in payload"
fi

if validate_pubkeys "${CTRL_KEY}" 2>/dev/null; then
    fail "validate_pubkeys rejects control/non-printable characters"
else
    pass "validate_pubkeys rejects control/non-printable characters"
fi

if validate_pubkeys "${INVALID_KEY}" 2>/dev/null; then
    fail "validate_pubkeys rejects invalid ssh-keygen format"
else
    pass "validate_pubkeys rejects invalid ssh-keygen format"
fi

# =============================================================================
# strip_managed_block
# =============================================================================

# Non-existent file -> success, empty output.
strip_out="$(strip_managed_block "${WORK}/does-not-exist" 2>/dev/null)"
strip_rc=$?
if [ "${strip_rc}" -eq 0 ] && [ -z "${strip_out}" ]; then
    pass "strip_managed_block returns success and empty output for missing file"
else
    fail "strip_managed_block returns success and empty output for missing file" \
        "rc=${strip_rc} out=${strip_out}"
fi

# Well-formed block -> outside lines preserved, block removed.
wf="${WORK}/wellformed"
printf '%s\n%s\n%s\n%s\n%s\n' \
    "${MANUAL_KEY}" "${BEGIN_MARKER}" "${KEY1}" "${END_MARKER}" "outside-tail" >"${wf}"
strip_out="$(strip_managed_block "${wf}")"
strip_rc=$?
if [ "${strip_rc}" -eq 0 ] \
    && printf '%s\n' "${strip_out}" | grep -qxF "${MANUAL_KEY}" \
    && printf '%s\n' "${strip_out}" | grep -qxF "outside-tail" \
    && ! printf '%s\n' "${strip_out}" | grep -qxF "${KEY1}" \
    && ! printf '%s\n' "${strip_out}" | grep -qxF "${BEGIN_MARKER}"; then
    pass "strip_managed_block preserves outside lines and removes managed block"
else
    fail "strip_managed_block preserves outside lines and removes managed block" \
        "out=${strip_out}"
fi

# Unterminated BEGIN -> failure.
printf '%s\n%s\n%s\n' "${MANUAL_KEY}" "${BEGIN_MARKER}" "${KEY1}" >"${WORK}/unterminated"
if strip_managed_block "${WORK}/unterminated" >/dev/null 2>&1; then
    fail "strip_managed_block rejects unterminated BEGIN"
else
    pass "strip_managed_block rejects unterminated BEGIN"
fi

# Orphan END -> failure.
printf '%s\n%s\n' "${MANUAL_KEY}" "${END_MARKER}" >"${WORK}/orphanend"
if strip_managed_block "${WORK}/orphanend" >/dev/null 2>&1; then
    fail "strip_managed_block rejects orphan END"
else
    pass "strip_managed_block rejects orphan END"
fi

# Duplicate BEGIN -> failure.
printf '%s\n%s\n%s\n%s\n' "${BEGIN_MARKER}" "${KEY1}" "${BEGIN_MARKER}" "${END_MARKER}" \
    >"${WORK}/dupbegin"
if strip_managed_block "${WORK}/dupbegin" >/dev/null 2>&1; then
    fail "strip_managed_block rejects duplicate BEGIN"
else
    pass "strip_managed_block rejects duplicate BEGIN"
fi

# Duplicate END -> failure.
printf '%s\n%s\n%s\n%s\n' "${BEGIN_MARKER}" "${KEY1}" "${END_MARKER}" "${END_MARKER}" \
    >"${WORK}/dupend"
if strip_managed_block "${WORK}/dupend" >/dev/null 2>&1; then
    fail "strip_managed_block rejects duplicate END"
else
    pass "strip_managed_block rejects duplicate END"
fi

# =============================================================================
# render_authorized_keys
# =============================================================================

rtarget="${WORK}/render_existing"
printf '%s\n%s\n%s\n%s\n' "${MANUAL_KEY}" "${BEGIN_MARKER}" "old-key" "${END_MARKER}" \
    >"${rtarget}"
render_out="$(render_authorized_keys "${rtarget}" "${KEY1}")"
render_rc=$?
begin_ct="$(printf '%s\n' "${render_out}" | grep -cxF "${BEGIN_MARKER}")"
end_ct="$(printf '%s\n' "${render_out}" | grep -cxF "${END_MARKER}")"
if [ "${render_rc}" -eq 0 ] \
    && printf '%s\n' "${render_out}" | grep -qxF "${MANUAL_KEY}" \
    && printf '%s\n' "${render_out}" | grep -qxF "${KEY1}" \
    && ! printf '%s\n' "${render_out}" | grep -qxF "old-key" \
    && [ "${begin_ct}" -eq 1 ] && [ "${end_ct}" -eq 1 ]; then
    pass "render_authorized_keys preserves outside lines + exactly one fresh block"
else
    fail "render_authorized_keys preserves outside lines + exactly one fresh block" \
        "rc=${render_rc} begin=${begin_ct} end=${end_ct}"
fi

# render on malformed existing content -> failure.
printf '%s\n%s\n' "${MANUAL_KEY}" "${BEGIN_MARKER}" >"${WORK}/render_malformed"
if render_authorized_keys "${WORK}/render_malformed" "${KEY1}" >/dev/null 2>&1; then
    fail "render_authorized_keys fails on malformed existing content"
else
    pass "render_authorized_keys fails on malformed existing content"
fi

# =============================================================================
# install_managed_authorized_keys
# =============================================================================

# --- first run: manual key preservation --------------------------------------
sshdir="${WORK}/ssh_firstrun"
mkdir -p "${sshdir}"
auth="${sshdir}/authorized_keys"
printf '%s\n' "${MANUAL_KEY}" >"${auth}"

if install_managed_authorized_keys "${auth}" "${KEY1}"; then
    if grep -qxF "${MANUAL_KEY}" "${auth}" \
        && managed_block_keys "${auth}" | grep -qxF "${KEY1}" \
        && [ "$(count_lines "${BEGIN_MARKER}" "${auth}")" -eq 1 ] \
        && [ "$(count_lines "${END_MARKER}" "${auth}")" -eq 1 ]; then
        pass "install: first run preserves manual key and adds one managed block"
    else
        fail "install: first run preserves manual key and adds one managed block" \
            "$(cat "${auth}")"
    fi
else
    fail "install: first run succeeds"
fi
assert_no_temp_leak "${sshdir}" "install: first run leaves no temp files"

# --- idempotency --------------------------------------------------------------
if install_managed_authorized_keys "${auth}" "${KEY1}"; then
    if [ "$(count_lines "${KEY1}" "${auth}")" -eq 1 ] \
        && [ "$(count_lines "${MANUAL_KEY}" "${auth}")" -eq 1 ] \
        && [ "$(count_lines "${BEGIN_MARKER}" "${auth}")" -eq 1 ] \
        && [ "$(count_lines "${END_MARKER}" "${auth}")" -eq 1 ]; then
        pass "install: idempotent re-run keeps single copies + single block"
    else
        fail "install: idempotent re-run keeps single copies + single block" \
            "$(cat "${auth}")"
    fi
else
    fail "install: idempotent re-run succeeds"
fi

# --- key rotation -------------------------------------------------------------
if install_managed_authorized_keys "${auth}" "${KEY2}"; then
    if managed_block_keys "${auth}" | grep -qxF "${KEY2}" \
        && ! managed_block_keys "${auth}" | grep -qxF "${KEY1}" \
        && grep -qxF "${MANUAL_KEY}" "${auth}" \
        && [ "$(count_lines "${BEGIN_MARKER}" "${auth}")" -eq 1 ]; then
        pass "install: key rotation replaces managed key, preserves manual key"
    else
        fail "install: key rotation replaces managed key, preserves manual key" \
            "$(cat "${auth}")"
    fi
else
    fail "install: key rotation succeeds"
fi

# --- multiple managed keys ----------------------------------------------------
sshdir_multi="${WORK}/ssh_multi"
mkdir -p "${sshdir_multi}"
auth_multi="${sshdir_multi}/authorized_keys"
if install_managed_authorized_keys "${auth_multi}" "$(printf '%s\n%s' "${KEY1}" "${KEY2}")"; then
    if managed_block_keys "${auth_multi}" | grep -qxF "${KEY1}" \
        && managed_block_keys "${auth_multi}" | grep -qxF "${KEY2}" \
        && [ "$(count_lines "${BEGIN_MARKER}" "${auth_multi}")" -eq 1 ] \
        && [ "$(count_lines "${END_MARKER}" "${auth_multi}")" -eq 1 ]; then
        pass "install: writes multiple managed keys inside one block"
    else
        fail "install: writes multiple managed keys inside one block" \
            "$(cat "${auth_multi}")"
    fi
else
    fail "install: multiple managed keys succeeds"
fi

# --- malformed existing: BEGIN without END -> no mutation, no leak ------------
malformed_case() {
    local name="$1"
    shift
    local dir="${WORK}/ssh_${name}"
    mkdir -p "${dir}"
    local f="${dir}/authorized_keys"
    printf '%s\n' "$@" >"${f}"
    local before
    before="$(cat "${f}")"
    if install_managed_authorized_keys "${f}" "${KEY2}" >/dev/null 2>&1; then
        fail "install: malformed ${name} must fail"
    else
        pass "install: malformed ${name} fails without success exit"
    fi
    if [ "${before}" = "$(cat "${f}")" ]; then
        pass "install: malformed ${name} leaves existing file byte-for-byte unchanged"
    else
        fail "install: malformed ${name} leaves existing file byte-for-byte unchanged" \
            "after=$(cat "${f}")"
    fi
    assert_no_temp_leak "${dir}" "install: malformed ${name} leaves no temp files"
}

malformed_case "begin_without_end" "${MANUAL_KEY}" "${BEGIN_MARKER}" "${KEY1}"
malformed_case "end_without_begin" "${MANUAL_KEY}" "${END_MARKER}"
malformed_case "duplicate_begin" "${BEGIN_MARKER}" "${KEY1}" "${BEGIN_MARKER}" "${END_MARKER}"
malformed_case "duplicate_end" "${BEGIN_MARKER}" "${KEY1}" "${END_MARKER}" "${END_MARKER}"

# --- invalid payload -> no mutation, no leak ----------------------------------
sshdir_bad="${WORK}/ssh_badpayload"
mkdir -p "${sshdir_bad}"
auth_bad="${sshdir_bad}/authorized_keys"
printf '%s\n' "${MANUAL_KEY}" >"${auth_bad}"
before_bad="$(cat "${auth_bad}")"
if install_managed_authorized_keys "${auth_bad}" "" >/dev/null 2>&1; then
    fail "install: empty payload must fail"
else
    pass "install: empty payload fails"
fi
if [ "${before_bad}" = "$(cat "${auth_bad}")" ]; then
    pass "install: empty payload leaves existing file unchanged"
else
    fail "install: empty payload leaves existing file unchanged"
fi
assert_no_temp_leak "${sshdir_bad}" "install: empty payload leaves no temp files"

if install_managed_authorized_keys "${auth_bad}" "${INVALID_KEY}" >/dev/null 2>&1; then
    fail "install: invalid-format payload must fail"
else
    pass "install: invalid-format payload fails"
fi
if [ "${before_bad}" = "$(cat "${auth_bad}")" ]; then
    pass "install: invalid-format payload leaves existing file unchanged"
else
    fail "install: invalid-format payload leaves existing file unchanged"
fi
assert_no_temp_leak "${sshdir_bad}" "install: invalid-format payload leaves no temp files"

# =============================================================================
# Summary
# =============================================================================

echo "-------------------------------------------------------------"
printf 'Tests run: %d, failed: %d\n' "${TESTS_RUN}" "${TESTS_FAILED}"
if [ "${TESTS_FAILED}" -ne 0 ]; then
    echo "=== Bootstrap authorized_keys merge test FAILED ===" >&2
    exit 1
fi
echo "=== Bootstrap authorized_keys merge test passed ==="
