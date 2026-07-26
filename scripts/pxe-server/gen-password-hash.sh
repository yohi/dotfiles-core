#!/usr/bin/env bash
set -euo pipefail

# デフォルトの出力先ファイル
OUTPUT_FILE="${1:-.password_hash}"

read -r -s -p "新規ユーザーのパスワードを入力してください: " password
printf '\n' >&2
read -r -s -p "確認のためもう一度入力してください: " confirmation
printf '\n' >&2

if [[ "${password}" != "${confirmation}" ]]; then
    printf 'ERROR: パスワードが一致しません\n' >&2
    exit 1
fi

if [[ -z "${password}" ]]; then
    printf 'ERROR: パスワードは空にできません\n' >&2
    exit 1
fi

hash_value=$(printf '%s' "${password}" | openssl passwd -6 -stdin)
printf '%s\n' "${hash_value}" > "${OUTPUT_FILE}"

printf 'SUCCESS: パスワードハッシュを %s に保存しました。\n' "${OUTPUT_FILE}" >&2
