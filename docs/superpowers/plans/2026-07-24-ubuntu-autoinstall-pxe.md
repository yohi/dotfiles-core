# Ubuntu Server Autoinstall over PXE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual, interactive Ubuntu Server ISO installation for physical PCs with a fully unattended PXE network-boot flow that uses Ubuntu's `autoinstall` (subiquity) feature to pre-set hostname, username, SSH access, and disk layout, ending in an SSH-reachable box with zero console/USB interaction beyond powering the machine on.

**Architecture:** An ephemeral PXE/TFTP/HTTP stack (dnsmasq in ProxyDHCP mode + `python3 -m http.server`) is started on the **operator PC** only for the duration of a provisioning session — no persistent service, no changes to the existing home router's DHCP. It serves the official Ubuntu netboot boot files (vmlinuz/initrd) over TFTP and a generated `autoinstall.yaml` + the live-server ISO over HTTP. The target physical PC PXE-boots, subiquity reads the autoinstall config, creates the user with SSH-key-only access, and reboots. The existing `ansible/bootstrap.yml` flow then takes over exactly as it does today (Deploy Key registration, dotfiles-core clone, SSH hardening, port change, UFW) — `scripts/bootstrap.sh` becomes an optional fallback for the old manual-ISO path only, since autoinstall now performs its job (user creation + SSH key install) during OS install itself.

**Tech Stack:** Bash (project convention, see `docs/agent/SHELL_CONVENTIONS.md`), `dnsmasq` (ProxyDHCP+TFTP), `python3 -m http.server` (already a project prerequisite), `envsubst` (`gettext-base`), `openssl passwd -6` for password hashing, `python3 -c 'import yaml'` for autoinstall.yaml validation, Docker-based bash regression tests mirroring `tests/bootstrap/`.

## Global Constraints

- Target Ubuntu Server versions: 22.04 (jammy), 24.04 (noble), 26.04 (next LTS; URL/codename for its netboot artifacts is **unverified** as of this plan's writing — code must probe and fail with a clear error rather than assume the artifact exists).
- No plaintext secrets anywhere on disk or in shell argv: passwords are hashed locally via `openssl passwd -6 -stdin` and only the hash is written to `autoinstall.yaml`; GitHub SSH keys are fetched from the public, unauthenticated `https://github.com/<user>.keys` endpoint (no token required for this flow).
- PXE/DHCP must run in **ProxyDHCP mode only** (`dhcp-range=<iface>,<subnet>,proxy,<netmask>` in dnsmasq) — never take over IP address assignment from the existing home router's DHCP server.
- The PXE/TFTP/HTTP stack is **ephemeral**: started in the foreground on the operator PC for one provisioning session, torn down via a trap on exit/SIGINT. No systemd unit, no persistent daemon.
- Do not duplicate SSH hardening (`PermitRootLogin no`, `PasswordAuthentication no`, port change) inside `autoinstall.yaml`/late-commands — that responsibility stays solely in `ansible/roles/common-setup` (already handles it) to avoid two divergent sources of truth, matching the existing caution comment in `ansible/roles/common-setup/tasks/main.yml` about cloud-init overriding sshd_config.
- Never hardcode netboot artifact filenames (`vmlinuz`, `initrd`) — historical Ubuntu releases have used inconsistent naming; discover files by glob after extracting the tarball.
- Follow `docs/agent/SHELL_CONVENTIONS.md`: dynamic path resolution (`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`), `set -euo pipefail`, `==>`/`ERROR:` echo prefixes, idempotent `mkdir -p`, and a clean `shellcheck` pass on every new/modified `.sh` file.
- Regression tests follow the `tests/bootstrap/` pattern exactly: hand-rolled bash pass/fail counters, script sourced with a `BASH_SOURCE` guard so `main()` never runs during tests, executed inside a disposable Docker container (`ubuntu:24.04` base image with only the minimal extra packages needed).
- Reuse `scripts/bootstrap.sh`'s already-tested `validate_pubkeys` function (via `source`) when validating GitHub-fetched keys — do not reimplement key validation logic.

---

## File Structure

```
scripts/
├── bootstrap.sh                        # MODIFY: add 26.04 to supported OS check
└── pxe-server/
    ├── fetch-netboot.sh                 # NEW: downloads+verifies Ubuntu netboot tarball + ISO
    ├── render-autoinstall.sh            # NEW: builds autoinstall.yaml/meta-data from inputs
    ├── pxe-serve.sh                     # NEW: orchestrator — starts dnsmasq + HTTP server
    ├── run-pxe.sh                       # NEW: interactive launcher (mirrors ansible/run.sh UX)
    └── templates/
        ├── autoinstall.yaml.tmpl        # NEW: envsubst template
        ├── meta-data.tmpl                # NEW: envsubst template
        ├── dnsmasq.conf.tmpl             # NEW: envsubst template
        ├── grub.cfg.tmpl                 # NEW: envsubst template (UEFI boot menu)
        └── pxelinux.cfg.default.tmpl     # NEW: envsubst template (legacy BIOS boot menu)
tests/
└── pxe-server/
    ├── Dockerfile                        # NEW: mirrors tests/bootstrap/Dockerfile
    └── test_render_autoinstall.sh        # NEW: mirrors tests/bootstrap/test_bootstrap.sh
ansible/README.md                         # MODIFY: document the new PXE flow
README.md                                 # MODIFY: mention PXE flow as the default physical-PC path
SPEC.md                                   # MODIFY: update "Ubuntu Bootstrap Flow" section
```

Each new script has one responsibility: `fetch-netboot.sh` only fetches/verifies artifacts, `render-autoinstall.sh` only renders config from inputs, `pxe-serve.sh` only orchestrates running processes, `run-pxe.sh` only collects interactive input and delegates. This mirrors the existing separation between `ansible/run.sh` (interactive input) and `ansible/*.yml` (execution).

---

### Task 1: `fetch-netboot.sh` — download and verify Ubuntu netboot artifacts

**Files:**
- Create: `scripts/pxe-server/fetch-netboot.sh`
- Test: `tests/pxe-server/test_render_autoinstall.sh` (covers this indirectly in Task 3; this task is verified manually per Step 4 below since it requires network access that must not run inside the sandboxed Docker test image)

**Interfaces:**
- Consumes: nothing (standalone)
- Produces: `discover_boot_files <extract_dir>` (echoes two lines: `KERNEL=<path>` then `INITRD=<path>`), `fetch_netboot <version> <cache_dir>` (populates `<cache_dir>/<version>/{netboot/,iso/}`, returns 0 on success, 1 with an `ERROR:` message on failure), consumed by `pxe-serve.sh` in Task 5.

- [ ] **Step 1: Write the script skeleton with function boundaries**

```bash
#!/bin/bash
# scripts/pxe-server/fetch-netboot.sh
#
# Downloads and verifies the official Ubuntu Server netboot tarball and
# live-server ISO for a given version, caching them under <cache_dir>/<version>/.
# Source-able for testing (main() runs only on direct execution).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# codename_for_version <version>
#
# Maps a known Ubuntu LTS version number to its release codename, used to
# build the releases.ubuntu.com URL path. Unknown versions fall back to the
# version number itself as the path segment (this is unverified for 26.04+
# and future releases; fetch_netboot() must handle a 404 from this guess
# with a clear error rather than crashing).
codename_for_version() {
    local version="$1"
    case "${version}" in
        22.04) echo "jammy" ;;
        24.04) echo "noble" ;;
        *) echo "${version}" ;;
    esac
}

# url_exists <url>
#
# Returns 0 if a HEAD request to <url> succeeds (HTTP 200/3xx), 1 otherwise.
# Does not download the body.
url_exists() {
    local url="$1"
    curl --proto '=https' --proto-redir '=https' -fsSL -o /dev/null "${url}"
}

# discover_boot_files <extract_dir>
#
# Finds the kernel and initrd inside an extracted netboot tarball without
# assuming a fixed filename (historical releases have varied). Searches the
# amd64/ subdirectory. Fails if either file is missing or ambiguous.
discover_boot_files() {
    local extract_dir="$1"
    local amd64_dir="${extract_dir}/amd64"
    local kernel initrd

    if [ ! -d "${amd64_dir}" ]; then
        echo "ERROR: expected amd64/ directory not found under ${extract_dir}" >&2
        return 1
    fi

    kernel="$(find "${amd64_dir}" -maxdepth 1 -type f -iname 'vmlinuz*' -print -quit)"
    initrd="$(find "${amd64_dir}" -maxdepth 1 -type f -iname 'initrd*' -print -quit)"

    if [ -z "${kernel}" ] || [ ! -f "${kernel}" ]; then
        echo "ERROR: no vmlinuz* file found under ${amd64_dir}" >&2
        return 1
    fi
    if [ -z "${initrd}" ] || [ ! -f "${initrd}" ]; then
        echo "ERROR: no initrd* file found under ${amd64_dir}" >&2
        return 1
    fi

    echo "KERNEL=${kernel}"
    echo "INITRD=${initrd}"
    return 0
}

# verify_sha256 <file> <sums_file>
#
# Verifies <file> against the matching line in <sums_file> (Ubuntu's
# SHA256SUMS format: "<hex-digest>  <filename>"). Returns 1 on mismatch or
# if the file is not listed.
verify_sha256() {
    local file="$1"
    local sums_file="$2"
    local basename_file
    basename_file="$(basename "${file}")"

    if ! grep -q "  ${basename_file}\$" "${sums_file}"; then
        echo "ERROR: ${basename_file} not listed in $(basename "${sums_file}")" >&2
        return 1
    fi

    ( cd "$(dirname "${file}")" && grep "  ${basename_file}\$" "${sums_file}" | sha256sum -c - )
}

# fetch_netboot <version> <cache_dir>
#
# Downloads (if not already cached and verified) the netboot tarball and
# live-server ISO for <version> into <cache_dir>/<version>/. Idempotent:
# re-running with an intact, checksum-verified cache does nothing.
fetch_netboot() {
    local version="$1"
    local cache_dir="$2"
    local codename base_url version_dir tarball_name iso_name

    codename="$(codename_for_version "${version}")"
    base_url="https://releases.ubuntu.com/${codename}"
    version_dir="${cache_dir}/${version}"
    tarball_name="ubuntu-${version}-netboot-amd64.tar.gz"
    iso_name="ubuntu-${version}-live-server-amd64.iso"

    mkdir -p "${version_dir}"

    if ! url_exists "${base_url}/SHA256SUMS"; then
        echo "ERROR: ${base_url}/SHA256SUMS is not reachable." >&2
        echo "ERROR: Ubuntu ${version} (codename guess: ${codename}) may not be released yet, or the codename mapping in codename_for_version() needs updating." >&2
        return 1
    fi

    curl --proto '=https' --proto-redir '=https' -fsSL \
        -o "${version_dir}/SHA256SUMS" "${base_url}/SHA256SUMS"

    for artifact in "${tarball_name}" "${iso_name}"; do
        local dest="${version_dir}/${artifact}"
        if [ -f "${dest}" ] && verify_sha256 "${dest}" "${version_dir}/SHA256SUMS" >/dev/null 2>&1; then
            echo "==> ${artifact} already cached and verified, skipping download."
            continue
        fi
        echo "==> Downloading ${artifact}..."
        curl --proto '=https' --proto-redir '=https' -fsSL \
            -o "${dest}" "${base_url}/${artifact}"
        if ! verify_sha256 "${dest}" "${version_dir}/SHA256SUMS"; then
            echo "ERROR: checksum verification failed for ${artifact}" >&2
            rm -f "${dest}"
            return 1
        fi
    done

    mkdir -p "${version_dir}/netboot-extracted"
    tar -xzf "${version_dir}/${tarball_name}" -C "${version_dir}/netboot-extracted"

    return 0
}

main() {
    set -euo pipefail
    local version="${1:?Usage: fetch-netboot.sh <version> <cache_dir>}"
    local cache_dir="${2:?Usage: fetch-netboot.sh <version> <cache_dir>}"
    fetch_netboot "${version}" "${cache_dir}"
    discover_boot_files "${cache_dir}/${version}/netboot-extracted"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

- [ ] **Step 2: shellcheck the new file**

Run: `shellcheck scripts/pxe-server/fetch-netboot.sh`
Expected: no errors (warnings about the `find -print -quit` idiom are acceptable; if shellcheck flags SC2155 on `local ... = "$( ... )"` split the declaration and assignment as shown above, which already avoids it).

- [ ] **Step 3: Manual smoke test (network-dependent, not part of the Docker test suite)**

Run: `bash scripts/pxe-server/fetch-netboot.sh 24.04 /tmp/pxe-cache`
Expected: downloads `SHA256SUMS`, the netboot tarball, and the ISO into `/tmp/pxe-cache/24.04/`, verifies checksums, extracts the tarball, and prints two lines `KERNEL=...` / `INITRD=...` pointing at real files.

- [ ] **Step 4: Re-run to confirm idempotency**

Run: `bash scripts/pxe-server/fetch-netboot.sh 24.04 /tmp/pxe-cache`
Expected: both artifacts print `already cached and verified, skipping download.` and the command still exits 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/pxe-server/fetch-netboot.sh
git commit -m "feat: Ubuntu netboot成果物の取得・検証スクリプトを追加"
```

---

### Task 2: `render-autoinstall.sh` — build `autoinstall.yaml` and `meta-data`

**Files:**
- Create: `scripts/pxe-server/render-autoinstall.sh`
- Create: `scripts/pxe-server/templates/autoinstall.yaml.tmpl`
- Create: `scripts/pxe-server/templates/meta-data.tmpl`
- Test: `tests/pxe-server/test_render_autoinstall.sh` (Task 3)

**Interfaces:**
- Consumes: `validate_pubkeys` from `scripts/bootstrap.sh` (sourced), `GITHUB_KEYS_URL` pattern (`https://github.com/<user>.keys`)
- Produces: `render_autoinstall <username> <hostname> <ssh_pubkey_file> <github_user> <password_hash> <out_dir>` — writes `<out_dir>/autoinstall.yaml` and `<out_dir>/meta-data`, returns 0/1. Consumed by `pxe-serve.sh` (Task 5) and by the test in Task 3.
- Also produces: `hash_password_interactive` — prompts twice (masked) for a password and prints the `openssl passwd -6` hash on stdout (nothing else on stdout), used by `run-pxe.sh` (Task 6) and bypassable via `--password-hash` for testing.

- [ ] **Step 1: Write the templates**

`scripts/pxe-server/templates/autoinstall.yaml.tmpl`:

```yaml
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: ${AI_HOSTNAME}
    username: ${AI_USERNAME}
    password: "${AI_PASSWORD_HASH}"
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
${AI_SSH_KEYS_YAML}
  storage:
    layout:
      name: lvm
  late-commands:
    - curtin in-target -- systemctl enable ssh
    - curtin in-target -- touch /var/log/dotfiles-autoinstall-complete
```

`scripts/pxe-server/templates/meta-data.tmpl`:

```yaml
instance-id: ${AI_INSTANCE_ID}
local-hostname: ${AI_HOSTNAME}
```

Note: `late-commands` intentionally does **not** touch `/etc/ssh/sshd_config` (no `PermitRootLogin`/`PasswordAuthentication`/port changes) — that remains the sole responsibility of `ansible/roles/common-setup`, per Global Constraints.

- [ ] **Step 2: Write the failing test for YAML key rendering**

Add to `tests/pxe-server/test_render_autoinstall.sh` (created fully in Task 3; this step shows the specific assertions this task must satisfy):

```bash
OUT_DIR="$(mktemp -d)"
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPERATORKEYEXAMPLEONLY operator@pc" > "${OUT_DIR}/operator.pub"

if render_autoinstall "y_ohi" "ubuntu-pxe" "${OUT_DIR}/operator.pub" "" '$6$fakehash$abcdefgh' "${OUT_DIR}"; then
    pass "render_autoinstall exits 0 with valid inputs"
else
    fail "render_autoinstall exits 0 with valid inputs"
fi

if [ -f "${OUT_DIR}/autoinstall.yaml" ]; then
    pass "autoinstall.yaml is created"
else
    fail "autoinstall.yaml is created"
fi

if python3 -c "import yaml,sys; yaml.safe_load(open('${OUT_DIR}/autoinstall.yaml'))" 2>/dev/null; then
    pass "autoinstall.yaml is valid YAML"
else
    fail "autoinstall.yaml is valid YAML"
fi

if grep -q 'username: y_ohi' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml contains the requested username"
else
    fail "autoinstall.yaml contains the requested username"
fi

if grep -q 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPERATORKEYEXAMPLEONLY' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml embeds the operator's SSH public key"
else
    fail "autoinstall.yaml embeds the operator's SSH public key"
fi

if grep -q 'password: "\$6\$fakehash\$abcdefgh"' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml embeds the password hash verbatim (including \$ characters)"
else
    fail "autoinstall.yaml embeds the password hash verbatim (including \$ characters)"
fi

if ! grep -qi 'PermitRootLogin\|PasswordAuthentication' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml does not duplicate sshd hardening (left to Ansible)"
else
    fail "autoinstall.yaml does not duplicate sshd hardening (left to Ansible)"
fi

rm -rf "${OUT_DIR}"
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `docker build -t dotfiles-pxe-test -f tests/pxe-server/Dockerfile . && docker run --rm dotfiles-pxe-test`
Expected: FAIL — `render_autoinstall: command not found` (the function does not exist yet).

- [ ] **Step 4: Write `render-autoinstall.sh`**

```bash
#!/bin/bash
# scripts/pxe-server/render-autoinstall.sh
#
# Renders autoinstall.yaml + meta-data for one provisioning session from a
# username, hostname, operator SSH public key, optional GitHub username
# (for additional public keys, fetched unauthenticated from
# https://github.com/<user>.keys), and a pre-hashed password. Never accepts
# or stores a plaintext password on disk.

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

    if [ "${pw1}" != "${pw2}" ]; then
        echo "ERROR: パスワードが一致しません" >&2
        return 1
    fi
    if [ -z "${pw1}" ]; then
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

    if [ -z "${github_user}" ]; then
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

    if [ ! -f "${operator_pubkey_file}" ]; then
        echo "ERROR: operator SSH public key file not found: ${operator_pubkey_file}" >&2
        return 1
    fi

    while IFS= read -r key || [ -n "${key}" ]; do
        [ -n "${key}" ] && printf '      - %s\n' "${key}"
    done < "${operator_pubkey_file}"

    if github_keys="$(fetch_github_keys "${github_user}")"; then
        while IFS= read -r key || [ -n "${key}" ]; do
            [ -n "${key}" ] && printf '      - %s\n' "${key}"
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

    if [ -z "${username}" ] || [ -z "${hostname}" ] || [ -z "${password_hash}" ]; then
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

    if ! python3 -c "import yaml,sys; yaml.safe_load(open('${out_dir}/autoinstall.yaml'))"; then
        echo "ERROR: generated autoinstall.yaml is not valid YAML" >&2
        return 1
    fi

    return 0
}

main() {
    set -euo pipefail
    local username="" hostname="" ssh_pubkey_file="" github_user="" password_hash="" out_dir=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --username) username="$2"; shift 2 ;;
            --hostname) hostname="$2"; shift 2 ;;
            --ssh-pubkey-file) ssh_pubkey_file="$2"; shift 2 ;;
            --github-user) github_user="$2"; shift 2 ;;
            --password-hash) password_hash="$2"; shift 2 ;;
            --out-dir) out_dir="$2"; shift 2 ;;
            *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
        esac
    done

    if [ -z "${password_hash}" ]; then
        password_hash="$(hash_password_interactive)"
    fi

    render_autoinstall "${username}" "${hostname}" "${ssh_pubkey_file}" "${github_user}" "${password_hash}" "${out_dir}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `docker build -t dotfiles-pxe-test -f tests/pxe-server/Dockerfile . && docker run --rm dotfiles-pxe-test`
Expected: all assertions from Step 2 report `ok`.

- [ ] **Step 6: shellcheck**

Run: `shellcheck scripts/pxe-server/render-autoinstall.sh`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add scripts/pxe-server/render-autoinstall.sh scripts/pxe-server/templates/autoinstall.yaml.tmpl scripts/pxe-server/templates/meta-data.tmpl
git commit -m "feat: autoinstall.yaml/meta-dataのレンダリングスクリプトを追加"
```

---

### Task 3: Docker regression test harness for `render-autoinstall.sh`

**Files:**
- Create: `tests/pxe-server/Dockerfile`
- Create: `tests/pxe-server/test_render_autoinstall.sh`

**Interfaces:**
- Consumes: `render_autoinstall`, `build_ssh_keys_yaml`, `hash_password_interactive`, `validate_pubkeys` (all sourced from the two scripts under test)
- Produces: a `docker run` exit code (0 = all pass, 1 = at least one failure), consumed by CI/manual verification only.

- [ ] **Step 1: Write `tests/pxe-server/Dockerfile`**

```dockerfile
# dotfiles-pxe-server render-autoinstall regression test image.
#
# Provides Ubuntu with the runtime deps render-autoinstall.sh needs at
# source-time (gettext-base for envsubst, python3+pyyaml for YAML
# validation, openssl for password hashing, curl+openssh-client because
# bootstrap.sh is sourced transitively). Does NOT run the imperative PXE
# flow (no dnsmasq, no network boot), so no root/network access is needed
# at test time beyond what curl needs for the (network-dependent) GitHub
# key fetch test cases, which use an empty github_user to skip fetching.
#
# Build context is the repository root:
#   docker build -t dotfiles-pxe-test -f tests/pxe-server/Dockerfile .
#   docker run --rm dotfiles-pxe-test
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y openssh-client gettext-base python3 python3-yaml openssl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY scripts/bootstrap.sh /work/scripts/bootstrap.sh
COPY scripts/pxe-server/render-autoinstall.sh /work/scripts/pxe-server/render-autoinstall.sh
COPY scripts/pxe-server/templates/ /work/scripts/pxe-server/templates/
COPY tests/pxe-server/test_render_autoinstall.sh /work/tests/pxe-server/test_render_autoinstall.sh

CMD ["/bin/bash", "/work/tests/pxe-server/test_render_autoinstall.sh"]
```

- [ ] **Step 2: Write `tests/pxe-server/test_render_autoinstall.sh`**

```bash
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

if [ -f "${OUT_DIR}/autoinstall.yaml" ]; then
    pass "autoinstall.yaml is created"
else
    fail "autoinstall.yaml is created"
fi

if [ -f "${OUT_DIR}/meta-data" ]; then
    pass "meta-data is created"
else
    fail "meta-data is created"
fi

if python3 -c "import yaml,sys; yaml.safe_load(open('${OUT_DIR}/autoinstall.yaml'))" 2>/dev/null; then
    pass "autoinstall.yaml is valid YAML"
else
    fail "autoinstall.yaml is valid YAML"
fi

if grep -q 'username: y_ohi' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml contains the requested username"
else
    fail "autoinstall.yaml contains the requested username"
fi

if grep -q 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOPERATORKEYEXAMPLEONLY' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml embeds the operator's SSH public key"
else
    fail "autoinstall.yaml embeds the operator's SSH public key"
fi

if grep -Fq 'password: "$6$fakehash$abcdefgh"' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml embeds the password hash verbatim (including \$ characters)"
else
    fail "autoinstall.yaml embeds the password hash verbatim (including \$ characters)"
fi

if ! grep -qi 'PermitRootLogin\|PasswordAuthentication' "${OUT_DIR}/autoinstall.yaml"; then
    pass "autoinstall.yaml does not duplicate sshd hardening (left to Ansible)"
else
    fail "autoinstall.yaml does not duplicate sshd hardening (left to Ansible)"
fi

rm -rf "${OUT_DIR}"

# ---- render_autoinstall: rejects missing required fields -------------------

OUT_DIR2="$(mktemp -d)"
if render_autoinstall "" "ubuntu-pxe" "${OUT_DIR}/operator.pub" "" '$6$fakehash$abcdefgh' "${OUT_DIR2}" 2>/dev/null; then
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

# ---- Summary -----------------------------------------------------------------

echo ""
echo "==================================================="
echo "  ${TESTS_RUN} tests run, ${TESTS_FAILED} failed"
echo "==================================================="

if [ "${TESTS_FAILED}" -gt 0 ]; then
    exit 1
fi
exit 0
```

- [ ] **Step 3: Build and run to verify the suite executes end-to-end**

Run: `docker build -t dotfiles-pxe-test -f tests/pxe-server/Dockerfile . && docker run --rm dotfiles-pxe-test`
Expected: `0 failed` in the summary, exit code 0.

- [ ] **Step 4: shellcheck the test script**

Run: `shellcheck tests/pxe-server/test_render_autoinstall.sh`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add tests/pxe-server/Dockerfile tests/pxe-server/test_render_autoinstall.sh
git commit -m "test: render-autoinstall.shの回帰テストを追加"
```

---

### Task 4: dnsmasq / GRUB / PXELINUX templates

**Files:**
- Create: `scripts/pxe-server/templates/dnsmasq.conf.tmpl`
- Create: `scripts/pxe-server/templates/grub.cfg.tmpl`
- Create: `scripts/pxe-server/templates/pxelinux.cfg.default.tmpl`

**Interfaces:**
- Consumes: nothing (pure templates)
- Produces: rendered config files consumed by `pxe-serve.sh` (Task 5) via `envsubst`.

- [ ] **Step 1: Write `dnsmasq.conf.tmpl`**

```ini
# Rendered by scripts/pxe-server/pxe-serve.sh — ProxyDHCP mode only.
# Does NOT hand out IP addresses; the existing router's DHCP server keeps
# doing that. This only answers PXE-specific DHCP options.
interface=${PXE_IFACE}
bind-interfaces
dhcp-range=${PXE_IFACE},${PXE_SUBNET},proxy,${PXE_NETMASK}

pxe-prompt="dotfiles-core autoinstall PXE", 5
pxe-service=x86PC,"Ubuntu Autoinstall (BIOS)",pxelinux.0
pxe-service=BC_EFI,"Ubuntu Autoinstall (UEFI)",bootx64.efi

enable-tftp
tftp-root=${TFTP_ROOT}

log-dhcp
no-daemon
```

- [ ] **Step 2: Write `grub.cfg.tmpl`** (served over TFTP at `grub/grub.cfg` for UEFI clients)

```
set default="0"
set timeout=10

menuentry 'Ubuntu ${AI_VERSION} Server (dotfiles-core autoinstall)' {
    linux /vmlinuz ip=dhcp url=http://${OPERATOR_IP}:${HTTP_PORT}/${AI_ISO_FILENAME} "autoinstall" "ds=nocloud-net;s=http://${OPERATOR_IP}:${HTTP_PORT}/autoinstall/" cloud-config-url=/dev/null ---
    initrd /initrd
}

menuentry 'Boot from local disk' {
    exit 1
}
```

- [ ] **Step 3: Write `pxelinux.cfg.default.tmpl`** (served over TFTP at `pxelinux.cfg/default` for legacy BIOS clients)

```
DEFAULT autoinstall
TIMEOUT 100
PROMPT 0

LABEL autoinstall
  MENU LABEL Ubuntu ${AI_VERSION} Server (dotfiles-core autoinstall)
  KERNEL vmlinuz
  INITRD initrd
  APPEND ip=dhcp url=http://${OPERATOR_IP}:${HTTP_PORT}/${AI_ISO_FILENAME} autoinstall ds=nocloud-net;s=http://${OPERATOR_IP}:${HTTP_PORT}/autoinstall/ cloud-config-url=/dev/null

LABEL local
  MENU LABEL Boot from local disk
  LOCALBOOT 0
```

Note the quoted `"ds=nocloud-net;s=..."` form in `grub.cfg.tmpl` — GRUB's command-line parser can otherwise split on the bare `;`, per the PXE research findings; PXELINUX's `APPEND` does not need the quotes since it passes the whole line through unparsed.

- [ ] **Step 4: Verify templates only reference the variable names `pxe-serve.sh` will set**

Run: `grep -oE '\$\{[A-Z_]+\}' scripts/pxe-server/templates/dnsmasq.conf.tmpl scripts/pxe-server/templates/grub.cfg.tmpl scripts/pxe-server/templates/pxelinux.cfg.default.tmpl | sort -u`
Expected output (cross-check by eye against Task 5's `pxe-serve.sh` export list before continuing): `PXE_IFACE`, `PXE_SUBNET`, `PXE_NETMASK`, `TFTP_ROOT`, `AI_VERSION`, `OPERATOR_IP`, `HTTP_PORT`, `AI_ISO_FILENAME`.

- [ ] **Step 5: Commit**

```bash
git add scripts/pxe-server/templates/dnsmasq.conf.tmpl scripts/pxe-server/templates/grub.cfg.tmpl scripts/pxe-server/templates/pxelinux.cfg.default.tmpl
git commit -m "feat: dnsmasq/GRUB/PXELINUXのPXEブート設定テンプレートを追加"
```

---

### Task 5: `pxe-serve.sh` — ephemeral PXE/TFTP/HTTP orchestrator

**Files:**
- Create: `scripts/pxe-server/pxe-serve.sh`

**Interfaces:**
- Consumes: `fetch_netboot`, `discover_boot_files` (sourced from `fetch-netboot.sh`); `render_autoinstall` (sourced from `render-autoinstall.sh`); all five templates from Task 4
- Produces: a foreground process that exits cleanly on SIGINT/SIGTERM/EXIT, tearing down `dnsmasq` and the HTTP server and removing its working directory. Invoked directly or via `run-pxe.sh` (Task 6).

- [ ] **Step 1: Write `pxe-serve.sh`**

```bash
#!/bin/bash
# scripts/pxe-server/pxe-serve.sh
#
# Ephemeral PXE/TFTP/HTTP orchestrator for one Ubuntu Server autoinstall
# provisioning session. Runs in the FOREGROUND on the operator PC only;
# never installs a systemd unit or persists after this process exits.
# Requires root (dnsmasq needs CAP_NET_BIND_SERVICE for TFTP/proxy-DHCP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"
CACHE_DIR="${SCRIPT_DIR}/.cache"

# shellcheck source=./fetch-netboot.sh
source "${SCRIPT_DIR}/fetch-netboot.sh"
# shellcheck source=./render-autoinstall.sh
source "${SCRIPT_DIR}/render-autoinstall.sh"

WORK_DIR=""
DNSMASQ_PID=""
HTTP_PID=""

cleanup() {
    echo "==> Cleaning up..."
    if [ -n "${DNSMASQ_PID}" ] && kill -0 "${DNSMASQ_PID}" 2>/dev/null; then
        kill "${DNSMASQ_PID}" 2>/dev/null || true
    fi
    if [ -n "${HTTP_PID}" ] && kill -0 "${HTTP_PID}" 2>/dev/null; then
        kill "${HTTP_PID}" 2>/dev/null || true
    fi
    if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT INT TERM

usage() {
    cat <<'EOF'
Usage: pxe-serve.sh --iface <if> --subnet <a.b.c.0> --netmask <mask> \
                     --operator-ip <ip> --version <22.04|24.04|26.04> \
                     --username <name> --hostname <name> \
                     --ssh-pubkey-file <path> [--github-user <user>] \
                     [--password-hash <hash>] [--http-port <port>]
EOF
}

main() {
    local iface="" subnet="" netmask="" operator_ip="" version="" \
          username="" hostname="" ssh_pubkey_file="" github_user="" \
          password_hash="" http_port="8080"

    while [ $# -gt 0 ]; do
        case "$1" in
            --iface) iface="$2"; shift 2 ;;
            --subnet) subnet="$2"; shift 2 ;;
            --netmask) netmask="$2"; shift 2 ;;
            --operator-ip) operator_ip="$2"; shift 2 ;;
            --version) version="$2"; shift 2 ;;
            --username) username="$2"; shift 2 ;;
            --hostname) hostname="$2"; shift 2 ;;
            --ssh-pubkey-file) ssh_pubkey_file="$2"; shift 2 ;;
            --github-user) github_user="$2"; shift 2 ;;
            --password-hash) password_hash="$2"; shift 2 ;;
            --http-port) http_port="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
        esac
    done

    for required in iface subnet netmask operator_ip version username hostname ssh_pubkey_file; do
        if [ -z "${!required}" ]; then
            echo "ERROR: --${required//_/-} is required" >&2
            usage
            exit 1
        fi
    done

    if [ "${EUID}" -ne 0 ]; then
        echo "ERROR: pxe-serve.sh must run as root (dnsmasq needs raw socket / privileged ports)." >&2
        exit 1
    fi

    if [ -z "${password_hash}" ]; then
        password_hash="$(hash_password_interactive)"
    fi

    echo "==> Fetching Ubuntu ${version} netboot artifacts..."
    fetch_netboot "${version}" "${CACHE_DIR}"
    local boot_files kernel_path initrd_path
    boot_files="$(discover_boot_files "${CACHE_DIR}/${version}/netboot-extracted")"
    kernel_path="$(printf '%s\n' "${boot_files}" | sed -n 's/^KERNEL=//p')"
    initrd_path="$(printf '%s\n' "${boot_files}" | sed -n 's/^INITRD=//p')"

    WORK_DIR="$(mktemp -d)"
    local tftp_root="${WORK_DIR}/tftp"
    local http_root="${WORK_DIR}/http"
    mkdir -p "${tftp_root}/pxelinux.cfg" "${tftp_root}/grub" "${http_root}/autoinstall"

    echo "==> Staging TFTP boot files..."
    cp "${kernel_path}" "${tftp_root}/vmlinuz"
    cp "${initrd_path}" "${tftp_root}/initrd"
    cp "${CACHE_DIR}/${version}/netboot-extracted/amd64/pxelinux.0" "${tftp_root}/" 2>/dev/null || true
    cp "${CACHE_DIR}/${version}/netboot-extracted/amd64/ldlinux.c32" "${tftp_root}/" 2>/dev/null || true
    cp "${CACHE_DIR}/${version}/netboot-extracted/amd64/bootx64.efi" "${tftp_root}/" 2>/dev/null || true
    cp "${CACHE_DIR}/${version}/netboot-extracted/amd64/grubx64.efi" "${tftp_root}/" 2>/dev/null || true

    local iso_filename="ubuntu-${version}-live-server-amd64.iso"
    cp "${CACHE_DIR}/${version}/${iso_filename}" "${http_root}/"

    echo "==> Rendering autoinstall.yaml..."
    render_autoinstall "${username}" "${hostname}" "${ssh_pubkey_file}" "${github_user}" "${password_hash}" "${http_root}/autoinstall"

    echo "==> Rendering boot menu configs..."
    AI_VERSION="${version}" OPERATOR_IP="${operator_ip}" HTTP_PORT="${http_port}" AI_ISO_FILENAME="${iso_filename}" \
        envsubst '${AI_VERSION} ${OPERATOR_IP} ${HTTP_PORT} ${AI_ISO_FILENAME}' \
        < "${TEMPLATE_DIR}/grub.cfg.tmpl" > "${tftp_root}/grub/grub.cfg"
    AI_VERSION="${version}" OPERATOR_IP="${operator_ip}" HTTP_PORT="${http_port}" AI_ISO_FILENAME="${iso_filename}" \
        envsubst '${AI_VERSION} ${OPERATOR_IP} ${HTTP_PORT} ${AI_ISO_FILENAME}' \
        < "${TEMPLATE_DIR}/pxelinux.cfg.default.tmpl" > "${tftp_root}/pxelinux.cfg/default"

    echo "==> Rendering dnsmasq.conf..."
    PXE_IFACE="${iface}" PXE_SUBNET="${subnet}" PXE_NETMASK="${netmask}" TFTP_ROOT="${tftp_root}" \
        envsubst '${PXE_IFACE} ${PXE_SUBNET} ${PXE_NETMASK} ${TFTP_ROOT}' \
        < "${TEMPLATE_DIR}/dnsmasq.conf.tmpl" > "${WORK_DIR}/dnsmasq.conf"

    echo "==> Starting HTTP server on :${http_port} (serving ${http_root})..."
    python3 -m http.server "${http_port}" --directory "${http_root}" --bind "${operator_ip}" &
    HTTP_PID=$!

    echo "==> Starting dnsmasq (ProxyDHCP + TFTP) on ${iface}..."
    dnsmasq -C "${WORK_DIR}/dnsmasq.conf" &
    DNSMASQ_PID=$!

    echo ""
    echo "==================================================="
    echo "  PXE server ready."
    echo "  Interface : ${iface}"
    echo "  HTTP      : http://${operator_ip}:${http_port}/"
    echo "  Now power on the target PC and select network boot."
    echo "  Press Ctrl+C here once the install completes to tear down."
    echo "==================================================="
    echo ""

    wait "${DNSMASQ_PID}" "${HTTP_PID}"
}

main "$@"
```

- [ ] **Step 2: shellcheck**

Run: `shellcheck scripts/pxe-server/pxe-serve.sh`
Expected: no errors. If shellcheck flags the `${!required}` indirect-expansion idiom (SC2086/SC2296 depending on version), keep it — it's valid POSIX-adjacent bash and is the correct way to loop-check multiple required variables without repeating five `if [ -z ... ]` blocks.

- [ ] **Step 3: Dry-run argument validation (no root/network needed)**

Run: `bash scripts/pxe-server/pxe-serve.sh --iface eth0`
Expected: exits 1 with `ERROR: --subnet is required` and prints usage — confirms the required-argument loop and usage function work before ever needing root or network access.

- [ ] **Step 4: Commit**

```bash
git add scripts/pxe-server/pxe-serve.sh
git commit -m "feat: PXE/TFTP/HTTPを一時起動するオーケストレータを追加"
```

---

### Task 6: `run-pxe.sh` — interactive launcher

**Files:**
- Create: `scripts/pxe-server/run-pxe.sh`

**Interfaces:**
- Consumes: nothing new; shells out to `pxe-serve.sh` (Task 5) with resolved arguments.
- Produces: an interactive prompt session mirroring `ansible/run.sh`'s UX, ending in `exec "${SCRIPT_DIR}/pxe-serve.sh" ...`.

- [ ] **Step 1: Write `run-pxe.sh`**

```bash
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
    local default_iface default_cidr default_ip default_subnet default_netmask default_operator_ip

    default_iface="$(detect_iface)"
    if [ -n "${default_iface}" ]; then
        default_cidr="$(detect_ip_and_cidr "${default_iface}")"
        default_ip="${default_cidr%/*}"
        default_netmask="$(cidr_to_netmask "${default_cidr}")"
        default_subnet="$(python3 -c "
import ipaddress
net = ipaddress.ip_network('${default_cidr}', strict=False)
print(net.network_address)
")"
    fi

    echo "======================================================="
    echo "  Ubuntu Server Autoinstall PXE - 対話式設定"
    echo "======================================================="

    read -rp "ネットワークインターフェース [${default_iface:-eth0}]: " IFACE
    IFACE="${IFACE:-${default_iface:-eth0}}"

    read -rp "操作PCのIPアドレス [${default_ip:-}]: " OPERATOR_IP
    OPERATOR_IP="${OPERATOR_IP:-${default_ip:-}}"
    if [ -z "${OPERATOR_IP}" ]; then
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
    echo "======================================================="
    echo "設定内容を確認してください:"
    echo "  - インターフェース    : ${IFACE}"
    echo "  - 操作PC IP           : ${OPERATOR_IP}"
    echo "  - サブネット/ネットマスク: ${SUBNET} / ${NETMASK}"
    echo "  - Ubuntuバージョン    : ${VERSION}"
    echo "  - 新規ユーザー名      : ${USERNAME}"
    echo "  - ホスト名            : ${HOSTNAME}"
    echo "  - SSH公開鍵           : ${SSH_KEY_PATH}"
    echo "  - GitHubユーザー名    : ${GITHUB_USER:-(スキップ)}"
    echo "======================================================="
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
```

- [ ] **Step 2: shellcheck**

Run: `shellcheck scripts/pxe-server/run-pxe.sh`
Expected: no errors.

- [ ] **Step 3: Manual smoke test of the detection helpers only**

Run: `bash -c 'source scripts/pxe-server/run-pxe.sh; detect_iface'`
Expected: prints the default network interface name (e.g. `eth0` or `wlp2s0`), exits 0. Sourcing must not invoke `main` (guarded by the `BASH_SOURCE` check added in Step 1), so no prompts should appear.

- [ ] **Step 4: Commit**

```bash
git add scripts/pxe-server/run-pxe.sh
git commit -m "feat: PXEプロビジョニングの対話式ランチャーを追加"
```

---

### Task 7: Extend `scripts/bootstrap.sh` OS support to include 26.04

**Files:**
- Modify: `scripts/bootstrap.sh` (the `main()` OS-version check)
- Modify: `tests/bootstrap/test_bootstrap.sh` if it asserts on the exact version list (check first; add a case if so)

**Interfaces:**
- Consumes: nothing new
- Produces: `scripts/bootstrap.sh` now accepts `VERSION_ID` of `22.04`, `24.04`, or `26.04` (previously only the first two), keeping the manual-ISO fallback path usable on the newest LTS too.

- [ ] **Step 1: Write the failing check**

Run: `grep -n '24.04' scripts/bootstrap.sh`
Expected: shows the current `[[ "${VERSION_ID:-}" != "22.04" && "${VERSION_ID:-}" != "24.04" ]]` line — confirms 26.04 is not yet accepted.

- [ ] **Step 2: Update the version check**

In `scripts/bootstrap.sh`, change:

```bash
    if [[ "${ID:-}" != "ubuntu" ]] ||
        [[ "${VERSION_ID:-}" != "22.04" && "${VERSION_ID:-}" != "24.04" ]]; then
        echo "ERROR: Unsupported OS: ${ID:-unknown} ${VERSION_ID:-unknown}." >&2
        echo "ERROR: Ubuntu 22.04 or 24.04 is required." >&2
        exit 1
    fi
```

to:

```bash
    if [[ "${ID:-}" != "ubuntu" ]] ||
        [[ "${VERSION_ID:-}" != "22.04" && "${VERSION_ID:-}" != "24.04" && "${VERSION_ID:-}" != "26.04" ]]; then
        echo "ERROR: Unsupported OS: ${ID:-unknown} ${VERSION_ID:-unknown}." >&2
        echo "ERROR: Ubuntu 22.04, 24.04, or 26.04 is required." >&2
        exit 1
    fi
```

- [ ] **Step 3: Verify the Docker regression suite still passes (it does not exercise this OS check, but confirms the edit introduced no syntax break)**

Run: `docker build -t dotfiles-bootstrap-test -f tests/bootstrap/Dockerfile . && docker run --rm dotfiles-bootstrap-test`
Expected: all existing `ok` lines unchanged, `0` failures.

- [ ] **Step 4: shellcheck**

Run: `shellcheck scripts/bootstrap.sh`
Expected: no new warnings introduced by this edit.

- [ ] **Step 5: Commit**

```bash
git add scripts/bootstrap.sh
git commit -m "feat: bootstrap.shの対応OSにUbuntu 26.04を追加"
```

---

### Task 8: Documentation — wire the new flow into existing docs

**Files:**
- Modify: `ansible/README.md`
- Modify: `README.md`
- Modify: `SPEC.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Add a new section to `ansible/README.md`, before the existing "### 物理 PC のセットアップ" section**

Insert (Japanese, matching the file's existing style):

```markdown
### 物理 PC のセットアップ（PXE 無人インストール、推奨）

物理 PC の電源を入れるだけで OS インストールからユーザー作成・SSH 公開鍵登録までを
完了させる方式です。ISO の手動インストールも `scripts/bootstrap.sh` のコンソール実行も
不要になります。操作 PC とターゲット PC は同一 LAN に接続してください。

```bash
cd scripts/pxe-server
./run-pxe.sh
# プロンプトに従って入力後、root権限で一時的な PXE/TFTP/HTTP サーバーが起動します。
# ターゲット PC の電源を入れ、ネットワークブート（PXE Boot）を選択してください。
```

- ここで起動する dnsmasq は **ProxyDHCP モード**で動作し、既存ルーターの DHCP を
  一切奪いません（IP アドレス割り当てはそのまま既存ルーターが行います）。
- インストール完了後、ターゲット PC はポート 22・SSH 公開鍵認証で接続可能な状態に
  なっています（パスワード認証は autoinstall の `ssh.allow-pw: false` により最初から
  無効です）。
- インストール完了を確認したら、PXE サーバー側で `Ctrl+C` を押して一時サーバーを
  終了してください（このプロセスは常駐しません）。
- その後は下記の「操作 PC で以下を実行します」以降を通常通り実行し、
  `ansible/run.sh` で `bootstrap.yml` を選択してください
  （Deploy Key 登録・dotfiles-core クローン・SSH ハードニング・ポート変更は
  引き続き Ansible が担当します）。

対応 Ubuntu バージョン: 22.04 (jammy) / 24.04 (noble) / 26.04。
詳細な内部構成は `scripts/pxe-server/` 配下の各スクリプトのコメントを参照してください。

### 物理 PC のセットアップ（手動 ISO インストール、レガシー）
```

(The existing "物理 PC のセットアップ" heading immediately below is renamed to "手動 ISO インストール、レガシー" as shown, and its content is otherwise unchanged — it remains a valid fallback for operators who cannot use PXE.)

- [ ] **Step 2: Update `README.md`'s "🖥️ 新規 Ubuntu マシンの初期セットアップ" section**

Add one sentence after the existing 物理PC bullet:

```markdown
  同一LAN上であれば、`scripts/pxe-server/run-pxe.sh` を使った PXE 無人インストール
  （OS インストール自体の自動化、ユーザー名・SSH 鍵設定込み）も利用できます。
  詳細は [`ansible/README.md`](ansible/README.md) を参照してください。
```

- [ ] **Step 3: Update `SPEC.md`'s "## Ubuntu Bootstrap Flow" section**

After the existing bullet list (`bootstrap.sh` の責務 / Ansible の責務), add:

```markdown
* **`scripts/pxe-server/` の責務**: 物理 PC 向けの PXE 無人インストール。ProxyDHCP
  (dnsmasq) + TFTP + HTTP を操作 PC 上で一時的に起動し、Ubuntu Server autoinstall
  (subiquity) 経由でホスト名・ユーザー作成・SSH 公開鍵登録までを OS インストール中に
  完了させる。`scripts/bootstrap.sh` が担っていたユーザー作成・SSH 鍵登録の責務を
  autoinstall 側に移し、`scripts/bootstrap.sh` は PXE を使わない手動 ISO インストール
  時のみのレガシー経路として残す。SSH ハードニング（ポート変更・root ログイン禁止・
  パスワード認証禁止）は従来通り Ansible (`common-setup` ロール) が単一の責務として
  担い、autoinstall の late-commands では重複させない。
```

- [ ] **Step 4: Proofread rendered Markdown**

Run: `markdownlint-cli2 ansible/README.md README.md SPEC.md` (per this repo's global `global-rules/MARKDOWN.md` convention)
Expected: no new errors introduced by the added sections (fix heading levels / list spacing if flagged).

- [ ] **Step 5: Commit**

```bash
git add ansible/README.md README.md SPEC.md
git commit -m "docs: PXE無人インストールの手順をドキュメントに追加"
```

---

### Task 9: Full verification pass

**Files:** none created; this task only runs checks across everything from Tasks 1–8.

- [ ] **Step 1: shellcheck every new/modified script**

Run:
```bash
shellcheck scripts/bootstrap.sh \
  scripts/pxe-server/fetch-netboot.sh \
  scripts/pxe-server/render-autoinstall.sh \
  scripts/pxe-server/pxe-serve.sh \
  scripts/pxe-server/run-pxe.sh \
  tests/pxe-server/test_render_autoinstall.sh
```
Expected: no errors on any file.

- [ ] **Step 2: Run both Docker regression suites**

Run:
```bash
docker build -t dotfiles-bootstrap-test -f tests/bootstrap/Dockerfile . && docker run --rm dotfiles-bootstrap-test
docker build -t dotfiles-pxe-test -f tests/pxe-server/Dockerfile . && docker run --rm dotfiles-pxe-test
```
Expected: `0 failed` in both summaries.

- [ ] **Step 3: `ansible-playbook --syntax-check` on the untouched playbooks (regression guard — this plan does not modify any `.yml` under `ansible/`)**

Run: `cd ansible && ansible-playbook --syntax-check setup.yml -i hosts.ini && ansible-playbook --syntax-check bootstrap.yml -i hosts.ini`
Expected: `playbook: setup.yml` / `playbook: bootstrap.yml` with no errors (confirms Tasks 1–8 did not accidentally break the existing Ansible flow, since none of them should have touched `.yml` files).

- [ ] **Step 4: End-to-end manual dry run (requires a spare physical or virtual PC on the same LAN — not automatable in CI)**

Run: `cd scripts/pxe-server && sudo ./run-pxe.sh` and PXE-boot a spare machine (a VM with a bridged network adapter is sufficient for this dry run).
Expected: the target machine shows the "Ubuntu Server (dotfiles-core autoinstall)" boot menu entry, completes an unattended install, and is reachable via `ssh <username>@<target-ip>` with the configured SSH key once it reboots — with no console/keyboard interaction on the target at any point.

- [ ] **Step 5: Commit (if Steps 1–4 required any fixes)**

```bash
git add -A
git commit -m "fix: 検証で見つかった問題を修正"
```

---

## Execution Handoff

Two execution options once this plan is approved:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task above, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints for review.
