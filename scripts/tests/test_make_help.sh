#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAKE_ENV=(MAKEFLAGS=--no-print-directory)
MAKE_CMD=(make -s -C "$DOTFILES_DIR")

if ! command -v timeout >/dev/null 2>&1; then
  echo "timeout command is required for this test." >&2
  exit 1
fi

default_out="$(mktemp)"
help_out="$(mktemp)"
tmp_state="$(mktemp -d)"
trap 'rm -rf "$default_out" "$help_out" "$tmp_state"' EXIT

if ! timeout 5s env "${MAKE_ENV[@]}" XDG_STATE_HOME="$tmp_state" "${MAKE_CMD[@]}" >"$default_out" 2>&1; then
  echo "make failed or timed out." >&2
  exit 1
fi

if ! timeout 5s env "${MAKE_ENV[@]}" XDG_STATE_HOME="$tmp_state" "${MAKE_CMD[@]}" help >"$help_out" 2>&1; then
  echo "make help failed or timed out." >&2
  exit 1
fi

if ! cmp -s "$default_out" "$help_out"; then
  echo "make and make help outputs differ." >&2
  diff -u "$default_out" "$help_out" >&2 || true
  exit 1
fi

if grep -Eq '\bmake[[:space:]]+_' "$help_out"; then
  echo "internal targets are shown in help output." >&2
  exit 1
fi

required_sections=(
  "システム設定"
  "パッケージ"
  "設定"
  "管理"
  "プリセット"
  "段階的セットアップ"
  "フォント"
  "メモリ"
  "AI"
)

for section in "${required_sections[@]}"; do
  if ! grep -q "$section" "$help_out"; then
    echo "missing help section: $section" >&2
    exit 1
  fi
done

if [ -d "$tmp_state/dots" ]; then
  echo "make help created marker directory." >&2
  exit 1
fi

echo "OK: help entrypoint"
