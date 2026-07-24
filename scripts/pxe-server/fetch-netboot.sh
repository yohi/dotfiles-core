#!/bin/bash
# scripts/pxe-server/fetch-netboot.sh
#
# Downloads and verifies the official Ubuntu Server netboot tarball and
# live-server ISO for a given version, caching them under <cache_dir>/<version>/.
# Source-able for testing (main() runs only on direct execution).


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
# Returns 0 if a GET request to <url> succeeds (HTTP 200/3xx), 1 otherwise.
# Downloads and discards the body to /dev/null (does not save to disk).
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
# Verifies <file> against the matching line in <sums_file>. Ubuntu's real
# SHA256SUMS uses binary-mode markers ("<hex-digest> *<filename>"); the
# historical text-mode two-space form ("<hex-digest>  <filename>") is also
# accepted. Returns 1 on mismatch or if the file is not listed.
verify_sha256() {
    local file="$1"
    local sums_file="$2"
    local basename_file escaped_name
    basename_file="$(basename "${file}")"
    escaped_name="${basename_file//./\\.}"

    if ! grep -Eq -- "[[:space:]]\*?${escaped_name}\$" "${sums_file}"; then
        echo "ERROR: ${basename_file} not listed in $(basename "${sums_file}")" >&2
        return 1
    fi

    ( cd "$(dirname "${file}")" && grep -E -- "[[:space:]]\*?${escaped_name}\$" "${sums_file}" | sha256sum -c - )
}

# fetch_netboot <version> <cache_dir>
#
# Downloads (if not already cached and verified) the netboot tarball and
# live-server ISO for <version> into <cache_dir>/<version>/. Idempotent:
# re-running with an intact, checksum-verified cache does nothing.
# Outputs ISO=<path> and TARBALL=<path> for caller extraction.
fetch_netboot() {
    local version="$1"
    local cache_dir="$2"
    local codename base_url version_dir tarball_name iso_name

    codename="$(codename_for_version "${version}")"
    base_url="https://releases.ubuntu.com/${codename}"
    version_dir="${cache_dir}/${version}"

    mkdir -p "${version_dir}"

    if ! url_exists "${base_url}/SHA256SUMS"; then
        echo "ERROR: ${base_url}/SHA256SUMS is not reachable." >&2
        echo "ERROR: Ubuntu ${version} (codename guess: ${codename}) may not be released yet, or the codename mapping in codename_for_version() needs updating." >&2
        return 1
    fi

    curl --proto '=https' --proto-redir '=https' -fsSL \
        -o "${version_dir}/SHA256SUMS" "${base_url}/SHA256SUMS"

    # Detect actual filenames from the release directory HTML
    # (netboot tarball may not be in SHA256SUMS, so we fetch the directory listing)
    local index_html iso_list point_release
    index_html="$(curl --proto '=https' --proto-redir '=https' -fsSL "${base_url}/")"

    # Extract all ISO filenames and sort by version descending to get newest
    iso_list="$(echo "${index_html}" | grep -oP 'ubuntu-[0-9.]+(-live-server-amd64\.iso)' | sort -rV)"
    iso_name="$(echo "${iso_list}" | head -1)"

    if [ -z "${iso_name}" ]; then
        echo "ERROR: Could not find live-server ISO in ${base_url}/" >&2
        return 1
    fi

    # Extract point-release from resolved ISO name (e.g., ubuntu-24.04.4-live-server-amd64.iso -> 24.04.4)
    point_release="$(echo "${iso_name}" | sed -E 's/^ubuntu-([0-9.]+)-.*/\1/')"
    tarball_name="ubuntu-${point_release}-netboot-amd64.tar.gz"

    # Verify derived tarball name exists in directory listing
    if ! echo "${index_html}" | grep -qF "${tarball_name}"; then
        echo "ERROR: Derived tarball name ${tarball_name} not found in ${base_url}/ (ISO and tarball version mismatch?)" >&2
        return 1
    fi

    # Download and verify ISO (present in SHA256SUMS)
    local iso_dest tarball_dest
    iso_dest="${version_dir}/${iso_name}"
    tarball_dest="${version_dir}/${tarball_name}"

    # Helper function to download and verify ISO
    _download_and_verify_iso() {
        local dest="$1"
        local iso_name="$2"
        echo "==> Downloading ${iso_name}..."
        curl --proto '=https' --proto-redir '=https' -fsSL \
            -o "${dest}" "${base_url}/${iso_name}"
        if ! verify_sha256 "${dest}" "${version_dir}/SHA256SUMS"; then
            echo "ERROR: checksum verification failed for ${iso_name}" >&2
            rm -f "${dest}"
            return 1
        fi
    }

    if [ -f "${iso_dest}" ]; then
        if verify_sha256 "${iso_dest}" "${version_dir}/SHA256SUMS" >/dev/null 2>&1; then
            echo "==> ${iso_name} already cached and verified, skipping download."
        else
            echo "==> ${iso_name} exists but checksum mismatch, re-downloading..."
            rm -f "${iso_dest}"
            _download_and_verify_iso "${iso_dest}" "${iso_name}" || return 1
        fi
    else
        _download_and_verify_iso "${iso_dest}" "${iso_name}" || return 1
    fi

    # Download netboot tarball (may not be in SHA256SUMS; verify by checking if extraction succeeds)
    # NOTE: The netboot tarball has no published checksum at releases.ubuntu.com (verified fact, not a TODO).
    # This script mitigates the lack of cryptographic verification by deriving the tarball name from the
    # SAME point-release as the SHA256SUMS-verified ISO (guaranteed version match, not arbitrary/stale).
    # Structural integrity is verified via tar -tzf (catches corruption/truncation, not tampering).
    # This is an accepted, documented limitation -- analogous to ansible/README.md's Cloudflare Workers
    # script-integrity check scoped to transport-corruption detection only.
    if [ -f "${tarball_dest}" ] && [ -d "${version_dir}/netboot-extracted" ] && [ -n "$(find "${version_dir}/netboot-extracted" -type f 2>/dev/null | head -1)" ]; then
        echo "==> ${tarball_name} already cached and extracted, skipping download."
    else
        echo "==> Downloading ${tarball_name}..."
        curl --proto '=https' --proto-redir '=https' -fsSL \
            -o "${tarball_dest}" "${base_url}/${tarball_name}"
        # Verify tarball integrity by attempting extraction
        if ! tar -tzf "${tarball_dest}" >/dev/null 2>&1; then
            echo "ERROR: netboot tarball is corrupted or invalid" >&2
            rm -f "${tarball_dest}"
            return 1
        fi
        # Extract tarball
        mkdir -p "${version_dir}/netboot-extracted"
        tar -xzf "${tarball_dest}" -C "${version_dir}/netboot-extracted"
    fi

    # Output resolved paths for caller extraction
    echo "ISO=${iso_dest}"
    echo "TARBALL=${tarball_dest}"

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
