#!/usr/bin/env bash
set -euo pipefail

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

printf '%s' "${password}" | openssl passwd -6 -stdin
