# PXE サーバー（Docker）

Ubuntu Server の無人インストール用 PXE サーバーを Docker コンテナで実行します。既存のネイティブ実行経路は変更しません。

## 前提条件

- Docker Engine と Docker Compose v2
- 操作 PC とインストール対象 PC が同じ LAN に接続されていること
- 操作 PC の SSH 公開鍵ファイル

## 設定と起動

1. リポジトリのルートに環境ファイルを作成します。

   ```bash
   cp scripts/pxe-server/compose.env.example .env
   ```

2. `.env` の `PXE_IFACE`、`PXE_SUBNET`、`PXE_NETMASK`、`OPERATOR_IP`、`SSH_PUBKEY_FILE` を操作環境に合わせて設定します。
   同じ Docker ホスト上で複数のチェックアウトを並行運用する場合は、`COMPOSE_PROJECT_NAME` に固有の名前を設定してください（キャッシュ・イメージの競合を回避します）。

3. 非対話起動では、パスワードハッシュを生成して `.env` の `PASSWORD_HASH` に設定します。`$` を含むハッシュをそのまま保持するため、値は単一引用符で囲みます。

   ```bash
   bash scripts/pxe-server/gen-password-hash.sh
   # PASSWORD_HASH='$6$rounds=5000$...'
   ```

4. サーバーを起動します。`PASSWORD_HASH` を空のままにする場合は、対話可能な端末から実行してください。

   ```bash
   docker compose -f scripts/pxe-server/compose.yaml --env-file .env up --build
   ```

## 手動 PXE テスト

1. 操作 PC と対象 PC が同じ LAN に接続されていることを確認します。
2. 対象 PC を起動し、BIOS/UEFI でネットワークブートを選択します。
3. 対象 PC が ISO、user-data、meta-data を取得し、無人インストールが完了することを確認します。

## 停止とキャッシュ

通常停止では named volume `pxe-cache${COMPOSE_PROJECT_NAME:+-${COMPOSE_PROJECT_NAME}}` を残し、次回の netboot 成果物と ISO の再利用を可能にします。

```bash
docker compose -f scripts/pxe-server/compose.yaml --env-file .env down
```

キャッシュも明示的に破棄する場合だけ、`-v` を付けます。

```bash
docker compose -f scripts/pxe-server/compose.yaml --env-file .env down -v
```

## ネットワークと権限

PXE の DHCP/TFTP 通信のため、Compose はホストネットワークを使用します。追加する capability は `NET_BIND_SERVICE` と `NET_RAW` のみであり、`privileged` は使用しません。SSH 公開鍵はコンテナに read-only でマウントされます。

## 既存のネイティブ実行

ホストに必要な依存関係を導入して直接実行する既存の手順は、そのまま利用できます。

```bash
sudo ./scripts/pxe-server/pxe-serve.sh ...
```
