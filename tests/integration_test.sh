#!/bin/bash
set -euo pipefail

echo "==> [Test] Starting integration tests inside container..."

# Create a workspace in /tmp to avoid permission issues with mounted volumes
export TEST_WORKSPACE="/tmp/dotfiles-core"
mkdir -p "$TEST_WORKSPACE"
cp -r . "$TEST_WORKSPACE"
cd "$TEST_WORKSPACE"

# Fix remotes of existing components to HTTPS to avoid vcstool conflict
# This preserves local changes made during the test
if [ -d components ]; then
    echo "==> [Test] Converting component remotes to HTTPS..."
    find components -maxdepth 2 -name .git -type d | while IFS= read -r gitdir; do
        repo_dir=$(dirname "$gitdir")
        pushd "$repo_dir" >/dev/null
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ "$remote_url" == git@github.com:* ]]; then
            new_url="${remote_url/git@github.com:/https://github.com/}"
            git remote set-url origin "$new_url"
            echo "    Updated \"$repo_dir\": \"$remote_url\" -> \"$new_url\""
        fi
        popd >/dev/null
    done
fi

# 1. Check if setup target works (includes init, sync, secrets, and delegated setup)
echo "==> [Test] Running 'make setup'..."
# WITH_BW=0 to skip Bitwarden in test, and we use a sub-shell to ensure PATH is updated
# Some dependencies might install to ~/.local/bin
export WITH_BW=0
export SKIP_FONTS=1
make setup

# 2. Verify dependencies installation
echo "==> [Test] Checking if core dependencies are installed..."
# vcs is installed by dotfiles-core/Makefile
export PATH="$HOME/.local/bin:$PATH"
command -v vcs >/dev/null 2>&1 || { echo "ERROR: vcs not found (should be installed by core)"; exit 1; }

# 3. Verify component delegation (dotfiles-system's job)
echo "==> [Test] Checking if dotfiles-system successfully installed packages..."
ls -l /usr/bin/zsh || echo "DEBUG: /usr/bin/zsh not found"
which zsh || echo "DEBUG: zsh not in PATH"
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
