#!/bin/bash
set -euo pipefail

echo "==> [Test] Starting integration tests inside container..."

# Create a unique workspace in /tmp to avoid permission issues and residue
TMPDIR=$(mktemp -d /tmp/dotfiles-test.XXXXXX) || { echo "mktemp failed"; exit 1; }
export TEST_WORKSPACE="$TMPDIR"
trap 'rm -rf "$TEST_WORKSPACE"' EXIT
echo "==> [Test] Created workspace: $TEST_WORKSPACE"

# Sync current directory to workspace, excluding unnecessary files
rsync -a --exclude=".git" . "$TEST_WORKSPACE/"
cd "$TEST_WORKSPACE"

# Fix remotes of existing components to HTTPS to avoid vcstool conflict
# This handles multiple SSH patterns: git@github.com:PATH, git@github.com/PATH, and ssh://git@github.com/PATH
if [ -d components ]; then
    echo "==> [Test] Converting component remotes to HTTPS..."
    find components -maxdepth 2 -name .git -type d | while IFS= read -r gitdir; do
        repo_dir=$(dirname "$gitdir")
        pushd "$repo_dir" >/dev/null
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        
        # Normalized replacement for common SSH patterns
        new_url=$(echo "$remote_url" | sed -E 's|^(ssh://)?git@github.com[:/]|https://github.com/|')
        
        if [[ "$remote_url" != "$new_url" ]]; then
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
