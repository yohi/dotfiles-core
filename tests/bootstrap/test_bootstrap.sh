#!/bin/bash
set -euo pipefail

# ユーザーが存在すること
id y_ohi

# sudo グループに所属
groups y_ohi | grep -q sudo

# sudoers ファイルが存在し、visudo 検証済み
[ -f /etc/sudoers.d/y_ohi ]
/usr/sbin/visudo -cf /etc/sudoers.d/y_ohi

# authorized_keys が fixture の公開鍵と完全一致する
[ -f /home/y_ohi/.ssh/authorized_keys ]
EXPECTED_SSH_PUBLIC_KEY="$(cat /tmp/testkeys/id_ed25519.pub)"
test "$(cat /home/y_ohi/.ssh/authorized_keys)" = "${EXPECTED_SSH_PUBLIC_KEY}"

# SSH 設定が正しく変更されている
SSHD_EFFECTIVE_CONFIG="$(sshd -T)"
grep -q "permitrootlogin no" <<<"${SSHD_EFFECTIVE_CONFIG}"
grep -q "passwordauthentication no" <<<"${SSHD_EFFECTIVE_CONFIG}"
grep -q "pubkeyauthentication yes" <<<"${SSHD_EFFECTIVE_CONFIG}"

echo "=== Bootstrap test passed ==="
