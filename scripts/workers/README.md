# dotfiles-bootstrap Worker

`scripts/bootstrap.sh` を GitHub raw から取得し、SHA-256 整合性ヘッダ (`X-Script-SHA256`) を付与して HTTPS 配信する Cloudflare Worker。`GET /install.sh` のみ受理する。

## テスト

```bash
npm test
```

- `npm test` は `scripts/workers/` で実行する (`npm --prefix scripts/workers test` でリポジトリルートからも実行可)。
- テストのスクリプトパスは `import.meta.url` 基準で解決するため実行時の cwd に依存せず、`node install.test.js` を `scripts/workers/` からでもリポジトリルートからでも実行できる。
- 各テストは Miniflare インスタンスを `dispose()` するため、プロセスは数秒で自然終了する (`timeout` ラッパー不要)。

## 設定

Worker は以下の環境変数を参照する。既定値は `wrangler.toml` の `[vars]` セクションで設定変更できる。

| 変数 | 例 | 説明 |
| :--- | :--- | :--- |
| `GITHUB_REPO` | `yohi/dotfiles-core` | 取得元リポジトリ (`owner/repo`) |
| `GITHUB_REF` | `master` | ブランチ / タグ |
| `SCRIPT_PATH` | `scripts/bootstrap.sh` | 取得対象のファイルパス |
| `EXPECTED_PREFIX` | `#!/bin/bash` | 整合性検証: スクリプト先頭の一致確認 |
| `EXPECTED_MARKER` | `# dotfiles-bootstrap` | 整合性検証: 含有マーカー |
