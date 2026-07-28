# Ansible 初期セットアッププレイブック

本ディレクトリのプレイブックは、Ubuntu サーバーの初期セットアップ（ユーザー作成、セキュリティ設定、GitHub SSH鍵の登録およびリポジトリのクローン等）を行うためのものです。

## 構成ファイル

- **hosts.ini**: 対象サーバーのインベントリ（接続先情報）を定義します。
- **vars.yml**: プレイブックの動作を制御する変数を定義します。
- **setup.yml**: 初期セットアップを実行する Ansible プレイブック本体です。
- **docs/ansible.md**: 本ドキュメント（使い方の説明）。

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
7. **SSH 設定の変更**: `ssh.socket` のオーバーライド設定（`/etc/systemd/system/ssh.socket.d/override.conf`）を作成してポート番号（デフォルト: `5310`）を変更し、`/etc/ssh/sshd_config` に以下の設定を適用します。また、常時起動サービス（`ssh.service`）を無効化し、`ssh.socket` を有効化して再起動します。
   - root ユーザーでの直接ログインを禁止 (`PermitRootLogin no`)
   - パスワード認証を禁止 (`PasswordAuthentication no`)

   変更後の接続確認および次回以降の Ansible 実行手順：
   - 設定変更後の接続検証: `ssh -p <configured_ssh_port> <username>@<target_ip>`（例: `ssh -p 5310 y_ohi@192.168.1.100`）
   - 今後の playbook 実行のため、必要に応じて `hosts.ini` の接続ポート（例: `ansible_port=<configured_ssh_port>`）をデフォルトの 22 から設定した SSH ポートに更新してください。

## セットアップフロー

### 物理 PC のセットアップ（PXE 無人インストール、推奨）

物理 PC の電源を入れるだけで OS インストールからユーザー作成・SSH 公開鍵登録までを
完了させる方式です。ISO の手動インストールも `scripts/bootstrap.sh` のコンソール実行も
不要になります。操作 PC とターゲット PC は同一 LAN に接続してください。

> [!NOTE]
> 事前に操作 PC で `sudo apt install dnsmasq gettext-base python3 curl openssl python3-yaml` を実行し、必要なパッケージをインストールしてください（stock Ubuntu には `dnsmasq`・`envsubst` が未導入のことが多く、`run-pxe.sh` が起動直後に不足を検出して停止します）。

```bash
cd scripts/pxe-server
./run-pxe.sh
# プロンプトに従って入力後、root権限で一時的な PXE/TFTP/HTTP サーバーが起動します。
# ターゲット PC の電源を入れ、ネットワークブート（PXE Boot）を選択してください。
```

- ここで起動する dnsmasq は **ProxyDHCP モード**で動作し、既存ルーターの DHCP を
  一切奪いません（IP アドレス割り当てはそのまま既存ルーターが行います）。
- インストール完了後、ターゲット PC はポート 22・SSH 公開鍵認証で接続可能な状態に
  なっています（パスワード認証は autoinstall の `ssh.allow-pw: false` により最初から
  無効です）。
- インストール完了を確認したら、PXE サーバー側で `Ctrl+C` を押して一時サーバーを
  終了してください（このプロセスは常駐しません）。
- その後は下記の「操作 PC で以下を実行します」以降を通常通り実行し、
  `ansible/run.sh` で `bootstrap.yml` を選択してください
  （Deploy Key 登録・dotfiles-core クローン・SSH ハードニング・ポート変更は
  引き続き Ansible が担当します）。

対応 Ubuntu バージョン: 22.04 (jammy) / 24.04 (noble) / 26.04。
詳細な内部構成は `scripts/pxe-server/` 配下の各スクリプトのコメントを参照してください。

### 物理 PC のセットアップ（手動 ISO インストール、レガシー）

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
