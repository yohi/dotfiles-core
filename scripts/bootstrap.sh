#!/bin/bash
# dotfiles-bootstrap
set -euo pipefail

GITHUB_KEYS_URL="https://github.com/yohi.keys"
USERNAME="y_ohi"

echo "==> Checking OS..."
if [ ! -f /etc/os-release ]; then
    echo "ERROR: /etc/os-release not found" >&2
    exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID}" != "ubuntu" ]] || \
   [[ "${VERSION_ID}" != "22.04" && "${VERSION_ID}" != "24.04" ]]; then
    echo "ERROR: Unsupported OS: ${ID} ${VERSION_ID}." >&2
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
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${USERNAME}" > /etc/sudoers.d/"${USERNAME}"
chmod 0440 /etc/sudoers.d/"${USERNAME}"
/usr/sbin/visudo -cf /etc/sudoers.d/"${USERNAME}"

echo "==> Fetching SSH public key from GitHub..."
PUBKEYS="$(curl -fsSL "${GITHUB_KEYS_URL}")"
if [ -z "${PUBKEYS}" ]; then
    echo "ERROR: Failed to fetch public keys from ${GITHUB_KEYS_URL}" >&2
    exit 1
fi

while IFS= read -r key || [ -n "${key}" ]; do
    if [ -z "${key}" ] || LC_ALL=C printf '%s' "${key}" | grep -q '[^ -~]'; then
        echo "ERROR: Invalid characters in SSH public key" >&2
        exit 1
    fi

    if ! printf '%s\n' "${key}" | ssh-keygen -l -f - >/dev/null 2>&1; then
        echo "ERROR: Invalid SSH public key format" >&2
        exit 1
    fi
done <<EOF
${PUBKEYS}
EOF

SSH_DIR="/home/${USERNAME}/.ssh"
mkdir -p "${SSH_DIR}"
printf '%s\n' "${PUBKEYS}" > "${SSH_DIR}/authorized_keys"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"
chown -R "${USERNAME}:${USERNAME}" "${SSH_DIR}"

echo "==> Hardening SSH configuration..."
if ! sshd -t; then
    echo "ERROR: sshd configuration is invalid before modification" >&2
    exit 1
fi

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
        printf '%s %s\n' "${key}" "${value}" >> /etc/ssh/sshd_config
    fi
}

set_sshd_directive PermitRootLogin no
set_sshd_directive PasswordAuthentication no
set_sshd_directive PubkeyAuthentication yes

if ! sshd -t; then
    echo "ERROR: sshd configuration became invalid after modification" >&2
    exit 1
fi

SSHD_EFFECTIVE_CONFIG="$(sshd -T)"
if ! grep -qx 'permitrootlogin no' <<<"${SSHD_EFFECTIVE_CONFIG}" || \
   ! grep -qx 'passwordauthentication no' <<<"${SSHD_EFFECTIVE_CONFIG}" || \
   ! grep -qx 'pubkeyauthentication yes' <<<"${SSHD_EFFECTIVE_CONFIG}"; then
    echo "ERROR: sshd effective settings do not match the required hardening" >&2
    exit 1
fi

echo "==> Restarting SSH service..."
systemctl restart sshd || service sshd restart || systemctl restart ssh || service ssh restart

IP_ADDR="$(hostname -I | awk '{print $1}')"
echo ""
echo "==================================================="
echo "  Bootstrap complete."
echo "  User: ${USERNAME}"
echo "  IP:   ${IP_ADDR}"
echo "  Port: 22"
echo "  Next: Run ansible/run.sh from your operator PC."
echo "==================================================="
