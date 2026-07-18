# Ubuntu 初期セットアップフロー設計書

## 概要

本設計書は、新規 Ubuntu マシン（物理 PC / VPS）の初期セットアップを自動化するフローを定義する。
目的は以下の通り。

- 操作 PC から SSH 経由で Ansible を実行し、最小限の手作業で環境構築を完結させる。
- 物理 PC のように外部からの SSH 接続ができない場合は、ローカルで `curl | sh` するブートストラップスクリプトを用いて SSH 接続準備まで行う。
- VPS のように外部からの SSH 接続が可能な場合は、ターゲット PC のコンソールには入らず、操作 PC から Ansible で全て実施する。
- スクリプト配信は自分で管理しているドメイン（Cloudflare）経由とし、セキュリティリスクを極力減らす。

## 用語定義

| 用語 | 意味 |
| :--- | :--- |
| ターゲット PC | セットアップ対象の Ubuntu マシン |
| 操作 PC | Ansible を実行するマシン。通常は既存の開発マシン |
| ブートストラップ | ターゲット PC 上で直接実行され、SSH 接続準備まで行う最小限のスクリプト |
| 本セットアップ | 操作 PC から Ansible で実行される完全なセットアップ |

## 前提条件

- ターゲット PC は Ubuntu 22.04 / 24.04 LTS をインストール済み。
- ターゲット PC はインターネットに接続可能。
- ターゲット PC の初期接続方法は、物理 PC の場合はコンソール、VPS の場合はプロバイダー提供の方法（通常は SSH）で可能。
- 操作 PC には Ansible と必要なコレクションがインストール済み、または本フローでインストールする。
- ドメインおよび Cloudflare アカウントはユーザーが管理している。
- GitHub ユーザー `yohi` の SSH 公開鍵は `https://github.com/yohi.keys` から取得可能。

## 全体的な流れ

### 物理 PC の場合

1. ターゲット PC のコンソールで root としてログインする。
2. `ansible/README.md` の二段階手順に従い、`install.sh` を一時ファイルへ
   ダウンロードして SHA-256 を確認し、内容を確認した後に `/bin/bash` で実行する。
3. ブートストラップスクリプトが以下を実施する。
   - 最小限のパッケージ更新
   - 一般ユーザー `y_ohi` の作成
   - `y_ohi` に sudo（パスワードなし）権限を付与
   - GitHub から SSH 公開鍵を取得して `y_ohi` の `authorized_keys` に登録
   - SSH デーモンのセキュリティ設定（root ログイン禁止、パスワード認証無効化）
   - SSH サービスの再起動
4. 操作 PC から `ansible/run.sh` を実行し、`bootstrap.yml` で本セットアップを実施する。
5. 本セットアップはターゲット上で Deploy Key を生成し、その公開鍵を GitHub に
   read-only Deploy Key として登録してから、dotfiles-core のクローン、完全な
   パッケージインストール、SSH ポート変更などを行う。秘密鍵はターゲット上の
   `~/.ssh` にのみ保存し、ターゲット外へ転送・表示しない。トークン未指定時は
   公開鍵を表示して手動登録を待機する。

### VPS の場合

1. 操作 PC から `ansible/run.sh` を実行する。
2. 対話式にターゲット PC の初期接続情報（IP、ポート、ユーザー、秘密鍵）を入力する。
3. `setup.yml` が以下を実施する。
   - 一般ユーザー `y_ohi` の作成
   - `y_ohi` に sudo（パスワードなし）権限を付与
   - 操作 PC の SSH 公開鍵を `y_ohi` の `authorized_keys` に登録
   - SSH デーモンのセキュリティ設定（root ログイン禁止、パスワード認証無効化）
   - GitHub への Deploy Key 登録（トークンが指定されている場合）
   - dotfiles-core のクローン
   - 完全なパッケージインストール
   - SSH ポート変更
   - ファイアウォール（UFW）設定
4. ターゲット PC のコンソールには入らない。

## ファイル構成

```text
dotfiles-core/
├── scripts/
│   ├── bootstrap.sh              # 物理 PC 用ブートストラップスクリプト
│   └── workers/
│       └── install.js            # Cloudflare Workers 配信スクリプト
├── ansible/
│   ├── setup.yml                 # VPS 用 Ansible プレイブック
│   ├── bootstrap.yml             # 物理 PC 用 Ansible プレイブック
│   ├── run.sh                    # 対話式セットアップランチャー
│   ├── hosts.ini                 # インベントリ（実行時に生成・更新）
│   ├── vars.yml                  # 変数（実行時に生成・更新）
│   └── roles/
│       └── common-setup/         # 物理 PC / VPS 共通の本セットアップタスク
│           ├── tasks/
│           │   └── main.yml
│           └── defaults/
│               └── main.yml
├── Makefile                      # 既存のオーケストレーター
└── docs/superpowers/specs/
    └── 2026-07-18-ubuntu-bootstrap-design.md
```

## 各コンポーネントの詳細

### 1. ブートストラップスクリプト `scripts/bootstrap.sh`

#### 責務

ターゲット PC 上で root として実行され、Ansible 接続に必要な最小限の準備を行う。

#### 実行する処理

1. **OS チェック**
   - `/etc/os-release` を確認し、Ubuntu 以外の場合は即座に終了する。
   - エラーメッセージを表示し、終了コード `1` で終了する。

2. **最小限のパッケージ更新**
   - `apt-get update` を実行する。
   - 必要なパッケージをインストールする。
     - `curl`
     - `openssh-server`
     - `sudo`

3. **一般ユーザー `y_ohi` の作成**
   - ユーザー `y_ohi` が存在しない場合に作成する。
   - シェルは `/bin/bash` とする。
   - `sudo` グループに追加する。

4. **パスワードなし sudo の設定**
   - `/etc/sudoers.d/y_ohi` に `y_ohi ALL=(ALL) NOPASSWD:ALL` を書き込む。
   - ファイルモードは `0440` とし、`visudo -cf` で検証する。

5. **SSH 公開鍵の取得と登録**
   - `https://github.com/yohi.keys` から SSH 公開鍵を取得する。
   - 取得に失敗した場合、または内容が空の場合はエラー終了する。
   - 取得した内容を `/home/y_ohi/.ssh/authorized_keys` に書き込む。
   - ディレクトリ・ファイルの権限を適切に設定する。
     - `~/.ssh` : `700`
     - `~/.ssh/authorized_keys` : `600`

6. **SSH デーモンのセキュリティ設定**
   - `/etc/ssh/sshd_config` を編集する。
     - `PermitRootLogin no`
     - `PasswordAuthentication no`
     - `PubkeyAuthentication yes`
   - 設定後、SSH サービスを再起動する。

7. **完了メッセージ**
   - ユーザー名、接続先 IP アドレス、SSH ポート（22）を表示する。
   - 次のステップとして、操作 PC から Ansible を実行することを促す。

#### 実行しない処理

以下は本セットアップ（Ansible）の責務とする。

- SSH ポートの変更
- dotfiles-core のクローン
- 完全なパッケージインストール
- ファイアウォール設定
- GitHub Deploy Key の登録

#### セキュリティ上の注意

- スクリプト内で取得する GitHub 鍵は `https://github.com/yohi.keys` のみとする。
  複数鍵を含む通常の `.keys` 応答を許可しつつ、各非空行に制御文字が
  含まれないこと、および各行が `ssh-keygen -l -f -` で解釈できる公開鍵で
  あることを検証する。
- 鍵形式の検証は、侵害された GitHub アカウントから返る形式上正しい鍵の真正性を保証するものではない。
- スクリプトは idempotent（冪等）に記述し、同じコマンドを複数回実行しても安全にする。
- root ログイン禁止・パスワード認証無効化を実施するため、ブートストラップ実行後はコンソール以外で root に入れなくなることをユーザーに通知する。

### 2. Cloudflare Workers 配信スクリプト `scripts/workers/install.js`

#### 責務

`https://setup.yourdomain.com/install.sh` へのリクエストを受け取り、GitHub 上の `scripts/bootstrap.sh` を安全に配信する。

#### 動作

1. **リクエスト受信**
   - `GET /install.sh` へのリクエストを処理する。
   - それ以外のパス・メソッドは `404 Not Found` または `405 Method Not Allowed` を返す。

2. **GitHub raw からスクリプト取得**
   - 環境変数 `GITHUB_REPO`、`GITHUB_REF`、`SCRIPT_PATH` を使用して、GitHub raw URL を構築する。
   - 例: `https://raw.githubusercontent.com/yohi/dotfiles-core/master/scripts/bootstrap.sh`

3. **簡易整合性チェック**
   - 取得した内容が空でないことを確認する。
   - 内容の先頭が `#!/bin/bash` であることを確認する。
   - 内容にブートストラップ識別子（例: `# dotfiles-bootstrap`）が含まれることを確認する。
   - いずれかのチェックに失敗した場合、`500 Internal Server Error` を返す。

4. **SHA-256 ハッシュ計算**
   - 取得した内容の SHA-256 ハッシュを計算する。
   - レスポンスヘッダー `X-Script-SHA256` に付与する。

5. **レスポンス返却**
   - HTTP ステータス `200 OK`
   - ヘッダー:
     - `Content-Type: text/plain; charset=utf-8`
     - `X-Content-Type-Options: nosniff`
     - `Cache-Control: public, max-age=300`
     - `X-Script-SHA256: <sha256>`
   - ボディ: GitHub から取得したスクリプト内容そのまま

6. **エラー時の挙動**
   - GitHub 取得失敗時: `503 Service Unavailable`
   - 整合性チェック失敗時: `500 Internal Server Error`
   - エラーボディには必要最小限の情報のみ含める。

#### 環境変数

| 名前 | 説明 | 例 |
| :--- | :--- | :--- |
| `GITHUB_REPO` | GitHub リポジトリ名 | `yohi/dotfiles-core` |
| `GITHUB_REF` | 取得するブランチ・タグ・コミット | `master` |
| `SCRIPT_PATH` | リポジトリ内のスクリプトパス | `scripts/bootstrap.sh` |
| `EXPECTED_PREFIX` | 内容先頭の期待値 | `#!/bin/bash` |
| `EXPECTED_MARKER` | 内容内に含まれるべき識別子 | `# dotfiles-bootstrap` |

### 3. VPS 用 Ansible プレイブック `ansible/setup.yml`

#### 責務

操作 PC からターゲット PC の初期接続ユーザーで SSH 接続し、ゼロから全てのセットアップを行う。

#### 主なタスク

1. 一般ユーザー `y_ohi` の作成
2. `y_ohi` へのパスワードなし sudo 権限付与
3. 操作 PC の SSH 公開鍵を `y_ohi` の `authorized_keys` に登録
4. ターゲット PC 上で SSH 鍵（Ed25519）を生成
5. GitHub への Deploy Key 登録（`github_token` が指定されている場合）
   - トークン未指定時は公開鍵を表示し、手動登録を待機
6. dotfiles-core のクローン
7. 完全なパッケージインストール
8. SSH デーモンのセキュリティ設定
   - ポート番号変更
   - root ログイン禁止
   - パスワード認証無効化
9. ファイアウォール（UFW）設定
10. SSH 接続の再確認

#### 既存資産との関係

現状の `ansible/setup.yml` をベースに、以下を調整する。

- 本セットアップの共通部分を `roles/common-setup/` に切り出す。
- 操作 PC からの初期接続は、プロバイダー提供ユーザー（root 等）を想定する。
- ユーザー作成、sudo 設定、SSH 鍵生成、Deploy Key 登録は VPS 固有の処理として `setup.yml` に残す。

### 4. 物理 PC 用 Ansible プレイブック `ansible/bootstrap.yml`

#### 責務

ブートストラップ済みのターゲット PC に対し、操作 PC から `y_ohi` ユーザーで SSH 接続（ポート 22）して本セットアップを行う。

#### 前提条件

- ターゲット PC 上で `scripts/bootstrap.sh` の実行が完了している。
- `y_ohi` ユーザーが存在し、操作 PC の SSH 公開鍵で認証可能である。
- 初期接続はポート 22 を使用する。
- private な dotfiles-core を取得するため、ターゲット上で生成した Deploy Key の
  公開鍵を GitHub に read-only で登録する。登録には一時 extra-vars ファイル経由の
  `github_token` を用いるか、公開鍵を手動登録する。秘密鍵はターゲット外へ渡さない。

#### 主なタスク

1. 一般ユーザー `y_ohi` が存在することを確認（冪等性のため）
2. 操作 PC の SSH 公開鍵が `y_ohi` の `authorized_keys` に登録されていることを確認
3. ターゲット用 Deploy Key の生成と read-only 登録
4. dotfiles-core のクローン
5. 完全なパッケージインストール
6. SSH デーモンのセキュリティ設定
   - ポート番号変更
   - root ログイン禁止
   - パスワード認証無効化
7. ファイアウォール（UFW）設定
8. 新ポート・対象ユーザー・公開鍵認証による SSH 接続とコマンド実行の再確認

#### 既存資産との関係

- ユーザー作成と sudo 設定はブートストラップ側で済んでいる。Deploy Key は private repository の clone 前に本プレイブックで生成・登録する。
- 本セットアップの共通部分は `roles/common-setup/` を参照する。

### 5. 対話式セットアップランチャー `ansible/run.sh`

#### 責務

`setup.yml` / `bootstrap.yml` を実行する前に、対話式で必要な情報を収集し、`hosts.ini` と `vars.yml` を生成する。

#### GitHub Token の扱い

- `github_token` はセキュリティのため `vars.yml` に永続保存しない。
- 対話式入力されたトークンは非表示で受け取り、モード `0600` の一時 JSON
  extra-vars ファイルへ書き出して `--extra-vars @<file>` で渡す。ファイルは
  `trap` で必ず削除し、コマンド引数や `vars.yml` にトークン値を含めない。
- Deploy Key を登録する Ansible タスクには `no_log: true` を設定し、トークンを Ansible 出力へ記録しない。
- 再実行時は毎回入力を求めるか、操作 PC のローカルな秘密管理（例: Bitwarden CLI）から取得する。

#### 収集する情報

- 実行対象のプレイブック（VPS: `setup.yml` / 物理 PC: `bootstrap.yml`）
- ターゲット PC の IP アドレスまたはホスト名
- 初期接続用 SSH ポート（デフォルト 22）
- 初期接続用 SSH ユーザー
- 初期接続用 SSH 秘密鍵パス（任意）
- 新規作成 / 確認する一般ユーザー名（デフォルト `y_ohi`）
- 操作 PC の SSH 公開鍵パス（デフォルト `~/.ssh/id_ed25519.pub`）
- 変更後の SSH ポート（デフォルト 5310）
- GitHub Personal Access Token（任意）

#### 出力

- `ansible/hosts.ini`
- `ansible/vars.yml`

### 6. 共通ロール `ansible/roles/common-setup/`

#### 責務

`setup.yml` と `bootstrap.yml` から共有される本セットアップタスクを集約する。

#### 含めるタスク

- dotfiles-core のクローン
- 共通パッケージの導入
  - `git`、`make`、`curl`、`jq`、`python3`、`python3-pip`
  - `ansible.builtin.apt` でキャッシュ更新と `state: present` を実行する
  - 導入に失敗した場合は Ansible の通常の失敗処理で play を停止する
- SSH デーモンのセキュリティ設定
- SSH サービスの再起動
- ファイアウォール（UFW）設定
- 新ポート・対象ユーザー・公開鍵認証による SSH 接続とコマンド実行の再確認

## セキュリティ設計

### 配信レイヤー

- HTTPS のみで配信する。
- Cloudflare Workers 経由で GitHub raw URL を隠す。
- Workers 内で簡易整合性チェックを行い、不正な内容が配信されるリスクを減らす。
- クライアント側で `X-Script-SHA256` とダウンロード済みファイルの SHA-256 を比較し、転送中の破損を検出できるようにする。
- 同一 Workers レスポンスから得るハッシュは、侵害された Workers の真正性を保証しない。その脅威を扱うには、別経路で信頼した固定ハッシュまたは署名が必要であり、本設計の範囲外とする。

### ブートストラップレイヤー

- root ログインを禁止する。
- パスワード認証を無効化する。
- GitHub から取得した公開鍵のみを `authorized_keys` に登録する。
- 取得失敗時は即座にエラー終了する。

### Ansible レイヤー

- 操作 PC からの SSH 接続は公開鍵認証のみとする。
- SSH ポートをデフォルトから変更する。
- root ログイン禁止・パスワード認証無効化を再設定する。
- UFW が有効な場合、新しい SSH ポートを許可する。

### GitHub 認証情報

- `github_token` は `vars.yml` やコマンド引数へ保存せず、非表示の対話入力からモード `0600` の一時 extra-vars ファイル経由で渡す。
- トークンのスコープは `repo` の Deploy Key 登録に必要な最小限とする。
- トークン未指定時は手動登録を促す。

## エラー処理

### ブートストラップスクリプト

- 各コマンドの失敗は `set -euo pipefail` で検知する。
- GitHub 鍵取得失敗、ユーザー作成失敗、SSH 再起動失敗時は即座に終了し、原因を表示する。
- root ログイン禁止後に SSH 接続ができなくなることを防ぐため、設定前に `sshd -t` で設定検証を行う。

### Cloudflare Workers

- GitHub raw 取得失敗時は `503` を返す。
- 整合性チェック失敗時は `500` を返す。
- エラーログは Workers のログ機能に記録する。

### Ansible

- SSH ポート変更後の接続確認に失敗した場合、直前の変更をロールバックする方法を検討する。
- ただし、SSH ポート変更は冪等な `lineinfile` で行うため、再実行で復旧可能な場合もある。
- ファイアウォール変更で接続不能になった場合のフォールバックとして、既存の SSH 接続を維持しながら変更する。

## テスト方針

- `scripts/bootstrap.sh` は Docker コンテナ上でテストする。
  - Ubuntu 環境を模倣したコンテナ
  - root 権限で実行
  - 実行後のユーザー作成、SSH 設定、root ログイン禁止を検証
- Cloudflare Workers は `wrangler dev` または Miniflare を用いてローカル検証する。
  - Miniflare の `fetchMock` で GitHub raw 応答を固定し、外部ネットワーク接続を禁止する。
  - 正常系、GitHub 取得失敗、整合性チェック失敗の3パターン
- Ansible プレイブックは `--syntax-check` と `--check` を実行する。
  - 実際のマシンへの適用は検証用 VPS またはローカル VM で行う。

## 今後の拡張（本設計の範囲外）

- 別経路で配布する固定チェックサムまたはスクリプト内容の署名による、配信元の真正性検証。
- ブートストラップ完了後の自動通知（Slack 等）。
- 他のクラウドプロバイダー（AWS EC2、Azure VM 等）への対応。

## 承認

本設計書に基づき、実装計画を作成する。
