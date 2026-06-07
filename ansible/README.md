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
   - `github_token`: GitHub の Personal Access Token。トークンを指定すると、ターゲット上で自動生成されたSSH公開鍵を自動的に GitHub アカウントに登録します。空のままにした場合は、実行時にコンソールへ公開鍵の内容が表示されるので、手動で GitHub に登録してください。
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
