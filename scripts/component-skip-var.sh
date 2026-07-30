#!/usr/bin/env bash
# scripts/component-skip-var.sh
# コンポーネント名（例: dotfiles-gnome）から SKIP_<NAME> 変数名（例: SKIP_GNOME）を出力するヘルパー

comp="${1:-}"
if [ -z "$comp" ]; then
    exit 1
fi

echo "SKIP_$(echo "$comp" | sed 's/dotfiles-//' | tr 'a-z-' 'A-Z_')"
