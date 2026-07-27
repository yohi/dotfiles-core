# Ansible 初期セットアッププレイブック

本ディレクトリのプレイブックは、Ubuntu サーバーの初期セットアップ（ユーザー作成、セキュリティ設定、GitHub SSH鍵の登録およびリポジトリのクローン等）を行うためのものです。

## 構成ファイル

- **hosts.ini**: 対象サーバーのインベントリ（接続先情報）を定義します。
- **vars.yml**: プレイブックの動作を制御する変数を定義します。
- **setup.yml**: 初期セットアップを実行する Ansible プレイブック本体です。
- **README.md**: 本ドキュメント（使い方の説明）。

## 事前準備

1. **ホストの設定 (`hosts.ini`)**  
   対象サーバーの IP アドレスまたはホスト名、および初期接続ユーザー（通常は `root`）を設定します。
   ```ini
   [servers]
   target_host ansible_host=xxx.xxx.xxx.xxx ansible_user=root
   ```

2. **変数の設定 (`vars.yml`)**  
   環境に合わせて変数を編集します。
   - `username`: 作成する一般ユーザー名（デフォルト: `y_ohi`）。
   - `ssh_public_key_path`: 実行元PCのSSH公開鍵のパス（デフォルト: `"~/.ssh/id_ed25519.pub"`）。この公開鍵がターゲット上の指定ユーザーの `authorized_keys` に登録されます。
   - `github_token`: GitHub の Personal Access Token。`run.sh` 実行時にプロンプトで対話的に入力します（入力は隠蔽されます）。トークンは実行時に一時ファイル経由で渡され、`vars.yml` には永続保存されません。
   - `new_ssh_port`: SSH接続用に新しく設定するポート番号（デフォルト: `5310`）。

## 実行方法

### 1. 構文（シンタックス）チェック
実行前に、プレイブックの文法に誤りがないかチェックします。
```bash
ansible-playbook --syntax-check setup.yml -i hosts.ini
```

### 2. プレイブックの実行
初期セットアップを実行します。
```bash
ansible-playbook setup.yml -i hosts.ini
```
※初期の接続時にパスワードが必要な場合は `-k` オプションを追加し、秘密鍵を使用する場合は `--key-file <秘密鍵パス>` を適宜指定してください。

## 処理内容

1. **一般ユーザーの作成**: 指定したユーザー（`y_ohi`）をターゲット上に作成します。同時に SSH キー（Ed25519）を自動生成します。
2. **パスワードなし sudo の許可**: `/etc/sudoers.d/y_ohi` を作成し、パスワードなしで特権実行できるように設定します。
3. **実行PCの公開鍵登録**: `vars.yml` で指定された実行元PCの公開鍵をターゲットユーザーの `authorized_keys` に登録します。
4. **GitHub への公開鍵登録**: `github_token` が指定されている場合は GitHub API を経由して自動登録します。指定がない場合は、公開鍵の中身を表示して手動登録を促します。
5. **リポジトリのクローン**: GitHub上の `git@github.com:yohi/dotfiles-core.git` をターゲット上の `/home/y_ohi/dotfiles` にクローンします。
6. **ファイアウォール（UFW）の設定**: UFWが有効な場合、新しい SSH ポート（`5310`）へのアクセスを許可します。
7. **SSH 設定の変更**: `/etc/ssh/sshd_config` を編集し、以下の設定を適用して SSH デーモンを再起動します。
   - ポート番号を `5310` に変更
   - root ユーザーでの直接ログインを禁止 (`PermitRootLogin no`)
   - パスワード認証を禁止 (`PasswordAuthentication no`)

## セットアップフロー

### 物理 PC のセットアップ

物理 PC は外部からの SSH 接続ができないため、ターゲット PC のコンソールでスクリプトをダウンロード、転送整合性を確認し、内容を確認してから実行します。

```bash
SCRIPT_FILE="$(mktemp)"
HEADER_FILE="$(mktemp)"
trap 'rm -f "${SCRIPT_FILE}" "${HEADER_FILE}"' EXIT

curl -fsSL -D "${HEADER_FILE}" -o "${SCRIPT_FILE}" \
  https://install.y-ohi.com
EXPECTED_HASH="$(
  awk -F ': ' '
    tolower($1) == "x-script-sha256" {
      gsub("\\r", "", $2)
      print $2
    }
  ' "${HEADER_FILE}"
)"
ACTUAL_HASH="$(sha256sum "${SCRIPT_FILE}" | awk '{print $1}')"

if [ -z "${EXPECTED_HASH}" ] || [ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]; then
  echo "ERROR: install.sh SHA-256 verification failed" >&2
  exit 1
fi

less "${SCRIPT_FILE}"
read -r -p "内容を確認しました。実行しますか？ [y/N] " CONFIRM
[ "${CONFIRM}" = "y" ] || [ "${CONFIRM}" = "Y" ] || exit 0
/bin/bash "${SCRIPT_FILE}"
```

`X-Script-SHA256` は同じ Workers レスポンスから取得するため、上記の比較は転送中の破損検出に限られます。侵害された Workers を検出するには、別経路で信頼した固定ハッシュまたは署名が必要であり、このフローの範囲外です。

その後、操作 PC で以下を実行します。

```bash
cd ansible
./run.sh
# プロンプトで bootstrap.yml を選択
```

> **物理 PC の初期接続ユーザーに関する注意**: `scripts/bootstrap.sh` の実行により root ログインは既に無効化されており、ポート `22` では操作 PC の GitHub 公開鍵（`github.com/yohi.keys`）で認可された `y_ohi` のみが接続できます。そのため `run.sh` の「初期接続用の SSH ユーザー」の入力では `root` ではなく `y_ohi` を、ポートには `22` を指定してください（`root` はこの時点で無効化されています）。

### VPS のセットアップ

VPS はターゲット PC のコンソールに入らず、操作 PC から全て実行します。

```bash
cd ansible
./run.sh
# プロンプトで setup.yml を選択
```
