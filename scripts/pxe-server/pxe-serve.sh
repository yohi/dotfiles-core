#!/bin/bash
# scripts/pxe-server/pxe-serve.sh
#
# Ephemeral PXE/TFTP/HTTP orchestrator for one Ubuntu Server autoinstall
# provisioning session. Runs in the FOREGROUND on the operator PC only;
# never installs a systemd unit or persists after this process exits.
# Requires root (dnsmasq needs CAP_NET_BIND_SERVICE for TFTP/proxy-DHCP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

    for tool in dnsmasq envsubst python3 curl; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            echo "ERROR: required tool not found: ${tool}" >&2
            echo "ERROR: try: sudo apt install dnsmasq gettext-base python3 curl" >&2
            exit 1
        fi
    done

    if [ ! -f "${ssh_pubkey_file}" ]; then
        echo "ERROR: --ssh-pubkey-file not found: ${ssh_pubkey_file}" >&2
        exit 1
    fi

    if [ "${EUID}" -ne 0 ]; then
        echo "ERROR: pxe-serve.sh must run as root (dnsmasq needs raw socket / privileged ports)." >&2
        exit 1
    fi

    if [ -z "${password_hash}" ]; then
        password_hash="$(hash_password_interactive)"
    fi

    echo "==> Fetching Ubuntu ${version} netboot artifacts..."
    # NOTE: fetch_netboot resolves the real point-release ISO filename
    # dynamically (e.g. ubuntu-24.04.4-live-server-amd64.iso, not a predictable
    # ubuntu-${version}-...) and echoes two lines to stdout on success:
    #   ISO=<absolute-path>
    #   TARBALL=<absolute-path>
    # Capture that output and derive the ISO path/filename from it; never
    # hardcode the ISO name.
    local fetch_output iso_path iso_filename
    fetch_output="$(fetch_netboot "${version}" "${CACHE_DIR}")"
    iso_path="$(printf '%s\n' "${fetch_output}" | sed -n 's/^ISO=//p')"
    if [ -z "${iso_path}" ] || [ ! -f "${iso_path}" ]; then
        echo "ERROR: fetch_netboot did not return a usable ISO path" >&2
        exit 1
    fi
    iso_filename="$(basename "${iso_path}")"

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

    # Copy the ISO from the exact path fetch_netboot resolved (dynamic filename),
    # not a hardcoded ubuntu-${version}-... path.
    cp "${iso_path}" "${http_root}/"

    echo "==> Rendering user-data (autoinstall config)..."
    render_autoinstall "${username}" "${hostname}" "${ssh_pubkey_file}" "${github_user}" "${password_hash}" "${http_root}/autoinstall"

    echo "==> Rendering boot menu configs..."
    AI_VERSION="${version}" OPERATOR_IP="${operator_ip}" HTTP_PORT="${http_port}" AI_ISO_FILENAME="${iso_filename}" \
        envsubst '${AI_VERSION} ${OPERATOR_IP} ${HTTP_PORT} ${AI_ISO_FILENAME}' \
        < "${TEMPLATE_DIR}/grub.cfg.tmpl" > "${tftp_root}/grub/grub.cfg"
    AI_VERSION="${version}" OPERATOR_IP="${operator_ip}" HTTP_PORT="${http_port}" AI_ISO_FILENAME="${iso_filename}" \
        envsubst '${AI_VERSION} ${OPERATOR_IP} ${HTTP_PORT} ${AI_ISO_FILENAME}' \
        < "${TEMPLATE_DIR}/pxelinux.cfg.default.tmpl" > "${tftp_root}/pxelinux.cfg/default"

    echo "==> Rendering dnsmasq.conf..."
    # The current dnsmasq.conf.tmpl references exactly these four variables:
    #   interface=${PXE_IFACE}
    #   dhcp-range=${PXE_SUBNET},proxy,${PXE_NETMASK}
    #   tftp-root=${TFTP_ROOT}
    # Pass exactly the variable names that appear in the template.
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
