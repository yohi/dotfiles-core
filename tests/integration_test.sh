#!/bin/bash
set -euo pipefail

echo "==> [Test] Starting integration tests inside container..."

# Create a workspace in /tmp to avoid permission issues with mounted volumes
export TEST_WORKSPACE="/tmp/dotfiles-core"
mkdir -p "$TEST_WORKSPACE"
cp -r . "$TEST_WORKSPACE"
cd "$TEST_WORKSPACE"

# 1. Check if setup target works (includes init, sync, secrets, and delegated setup)
echo "==> [Test] Running 'make setup'..."
# WITH_BW=0 to skip Bitwarden in test, and we use a sub-shell to ensure PATH is updated
# Some dependencies might install to ~/.local/bin
make setup WITH_BW=0

# 2. Verify dependencies installation
echo "==> [Test] Checking if core dependencies are installed..."
# vcs is installed by dotfiles-core/Makefile
export PATH="$HOME/.local/bin:$PATH"
command -v vcs >/dev/null 2>&1 || { echo "ERROR: vcs not found (should be installed by core)"; exit 1; }

# 3. Verify component delegation (dotfiles-system's job)
echo "==> [Test] Checking if dotfiles-system successfully installed packages..."
command -v zsh >/dev/null 2>&1 || { echo "ERROR: zsh not found (should be installed by dotfiles-system)"; exit 1; }
echo "[OK] zsh is present (installed by component delegation)."

# 4. Verify directory structure
echo "==> [Test] Verifying directory structure..."
if [ -d "components/components" ]; then
    echo "ERROR: Nested components directory detected!"
    exit 1
fi
echo "[OK] No nested components directory."

echo "==> [Test] Integration tests PASSED!"
