#!/usr/bin/env bash

# ドキュメント自動生成スクリプト
# 環境構築スクリプト群の各種情報を収集してドキュメントを生成

set -euo pipefail

# Bash 4.0以上が必要（連想配列を使用するため）
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: Bash 4.0 or higher is required for this script." >&2
    exit 1
fi

# 色付きメッセージの定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# ログ用関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 変数定義
# cd失敗を確実に検知
RAW_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$RAW_SCRIPT_DIR" && pwd)" || { echo "Error: Cannot resolve script directory." >&2; exit 1; }
readonly SCRIPT_DIR

DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)" || { echo "Error: Cannot resolve dotfiles root directory." >&2; exit 1; }
readonly DOTFILES_DIR

readonly DOCS_DIR="$DOTFILES_DIR/docs"
readonly GENERATED_DIR="$DOCS_DIR/generated"

# ドキュメント生成ディレクトリの作成
setup_docs_directory() {
    log_step "ドキュメントディレクトリを準備中..."

    mkdir -p "$GENERATED_DIR"

    log_info "ドキュメントディレクトリ: $GENERATED_DIR"
}

# Makefileのターゲット一覧を生成
generate_makefile_targets() {
    log_step "Makefileターゲット一覧を生成中..."

    local output_file="$GENERATED_DIR/makefile-targets.md"
    local makefile="$DOTFILES_DIR/Makefile"

    cat > "$output_file" << 'EOF'
# Makefileターゲット一覧

このファイルは自動生成されます。最新の情報については `make help` を実行してください。

## 利用可能なターゲット

EOF

    cd "$DOTFILES_DIR"

    # Makefileからターゲットを抽出 (target: ## description 形式に対応)
    grep -E "^[a-zA-Z0-9_-]+:.*?##" "$makefile" | sort | while read -r line; do
        local target=$(echo "$line" | cut -d':' -f1)
        local description=$(echo "$line" | sed 's/.*## //')

        echo "- \`make $target\`" >> "$output_file"
        if [[ -n "$description" ]]; then
            echo "  - $description" >> "$output_file"
        fi
        echo "" >> "$output_file"
    done

    log_info "Makefileターゲット一覧を生成しました: $output_file"
}

# Brewfileパッケージ一覧を生成
generate_brewfile_packages() {
    log_step "Brewfileパッケージ一覧を生成中..."

    local output_file="$GENERATED_DIR/brewfile-packages.md"
    local brewfile="$DOTFILES_DIR/Brewfile"

    # Brewfileが存在しない場合はスキップ（dotfiles-systemにある場合を考慮）
    if [[ ! -f "$brewfile" ]]; then
        # components配下も探す
        local components_brewfile="$DOTFILES_DIR/components/dotfiles-system/Brewfile"
        if [[ -f "$components_brewfile" ]]; then
            brewfile="$components_brewfile"
        else
            log_info "Brewfile が見つからないため、パッケージ一覧の生成をスキップします。"
            return
        fi
    fi

    cat > "$output_file" << 'EOF'
# Brewfile パッケージ一覧

このファイルは自動生成されます。

## Homebrew Taps

EOF

    # Taps
    grep '^tap ' "$brewfile" | sed 's/tap "/- /g' | sed 's/"//g' >> "$output_file" || true

    echo "" >> "$output_file"
    echo "## Brew パッケージ" >> "$output_file"
    echo "" >> "$output_file"

    # Brew packages
    grep '^brew ' "$brewfile" | sed 's/brew "/- /g' | sed 's/".*//g' | sort >> "$output_file" || true

    echo "" >> "$output_file"
    echo "## Cask パッケージ" >> "$output_file"
    echo "" >> "$output_file"

    # Cask packages
    grep '^cask ' "$brewfile" | sed 's/cask "/- /g' | sed 's/".*//g' | sort >> "$output_file" || true

    # 統計情報
    local tap_count=$(grep -c '^tap ' "$brewfile" || echo "0")
    local brew_count=$(grep -c '^brew ' "$brewfile" || echo "0")
    local cask_count=$(grep -c '^cask ' "$brewfile" || echo "0")

    cat >> "$output_file" << EOF

## 統計情報

- Taps: $tap_count 個
- Brew パッケージ: $brew_count 個
- Cask パッケージ: $cask_count 個
- 合計: $((tap_count + brew_count + cask_count)) 個

EOF

    log_info "Brewfileパッケージ一覧を生成しました: $output_file ($brewfile を使用)"
}

# VS Code拡張機能一覧を生成
generate_vscode_extensions() {
    log_step "VS Code拡張機能一覧を生成中..."

    local output_file="$GENERATED_DIR/vscode-extensions.md"
    local extensions_file="$DOTFILES_DIR/vscode/extensions.list"

    if [[ ! -f "$extensions_file" ]]; then
        log_info "VS Code拡張機能ファイルが見つかりません: $extensions_file"
        return
    fi

    cat > "$output_file" << 'EOF'
# VS Code 拡張機能一覧

このファイルは自動生成されます。

## インストール対象拡張機能

EOF

    # カテゴリ別に分類
    declare -A categories
    categories["ms-python"]="Python開発"
    categories["ms-vscode"]="Microsoft公式"
    categories["github"]="GitHub関連"
    categories["docker"]="Docker関連"
    categories["ms-azuretools"]="Azure関連"
    categories["ms-toolsai"]="AI・データサイエンス"
    categories["eamodio"]="Git関連"

    # 拡張機能をカテゴリ別に分類
    while IFS= read -r extension; do
        if [[ -n "$extension" && ! "$extension" =~ ^# ]]; then
            local category="その他"
            local publisher=$(echo "$extension" | cut -d'.' -f1)

            if [[ -n "${categories[$publisher]:-}" ]]; then
                category="${categories[$publisher]}"
            fi

            echo "- \`$extension\` ($category)" >> "$output_file"
        fi
    done < "$extensions_file"

    # 統計情報
    local ext_count=$(grep -v '^#' "$extensions_file" | grep -v '^$' | wc -l)

    cat >> "$output_file" << EOF

## 統計情報

- 総拡張機能数: $ext_count 個

EOF

    log_info "VS Code拡張機能一覧を生成しました: $output_file"
}

# ディレクトリ構造を生成
generate_directory_structure() {
    log_step "ディレクトリ構造を生成中..."

    local output_file="$GENERATED_DIR/directory-structure.md"

    cat > "$output_file" << 'EOF'
# ディレクトリ構造

このファイルは自動生成されます。

## プロジェクト構造

```
EOF

    cd "$DOTFILES_DIR"

    # treeコマンドがある場合は使用
    if command -v tree &> /dev/null; then
        tree -a -I '.git|*.tmp|*.cache|*.log' --dirsfirst >> "$output_file"
    else
        # treeがない場合はfindを使用
        find . -type d -name .git -prune -o -type f -print | \
        sed 's|^\./||' | sort | sed 's|^|    |' >> "$output_file"
    fi

    cat >> "$output_file" << 'EOF'
```

## 主要ディレクトリの説明

- `vim/`: Neovim設定ファイル
- `vscode/`: VS Code設定ファイル
- `cursor/`: Cursor IDE設定ファイル
- `zsh/`: Zsh設定ファイル
- `wezterm/`: Wezterm設定ファイル
- `gnome-*/`: GNOME関連設定ファイル
- `scripts/`: ユーティリティスクリプト
- `docs/`: ドキュメント

EOF

    log_info "ディレクトリ構造を生成しました: $output_file"
}

# システム要件を生成
generate_system_requirements() {
    log_step "システム要件を生成中..."

    local output_file="$GENERATED_DIR/system-requirements.md"

    cat > "$output_file" << 'EOF'
# システム要件

このファイルは自動生成されます。

## 対応OS

- Ubuntu 20.04 LTS 以降
- Ubuntu 22.04 LTS (推奨)
- Ubuntu 24.04 LTS
- Ubuntu 25.04 (実験的サポート)

## 必要なシステム要件

### 最小要件

- **RAM**: 4GB以上
- **ストレージ**: 20GB以上の空き容量
- **CPU**: x86_64 または ARM64
- **インターネット接続**: 必須（パッケージダウンロード用）

### 推奨要件

- **RAM**: 8GB以上
- **ストレージ**: 50GB以上の空き容量
- **CPU**: 4コア以上
- **GPU**: 統合GPU以上（GNOME環境用）

## 必要な権限

- **sudo権限**: システムレベルのパッケージインストールに必要
- **インターネットアクセス**: GitHub、APT、Homebrewリポジトリへのアクセス
- **ファイルシステム書き込み**: ホームディレクトリへの書き込み権限

## 前提条件

### 自動インストールされるもの

- git
- curl
- wget
- build-essential
- make

### 手動設定が必要なもの

- GPGキー（Git署名用、オプション）
- SSH鍵（GitHub用、オプション）
- 個人設定（メールアドレス等）

## 対応デスクトップ環境

- **GNOME**: フルサポート
- **Unity**: 基本サポート
- **KDE**: 限定サポート
- **XFCE**: 基本サポート
- **その他**: 未テスト

## 既知の制限事項

- Wayland環境では一部のGNOME拡張機能が制限される場合があります
- ARM64環境では一部のHomebrewパッケージが利用できない場合があります
- 企業ファイアウォール環境では追加の設定が必要な場合があります

EOF

    log_info "システム要件を生成しました: $output_file"
}

# トラブルシューティングガイドを生成
generate_troubleshooting() {
    log_step "トラブルシューティングガイドを生成中..."

    local output_file="$GENERATED_DIR/troubleshooting.md"

    cat > "$output_file" << 'EOF'
# トラブルシューティングガイド

このファイルは自動生成されます。

## よくある問題と解決方法

### 1. パッケージインストールエラー

**症状**: `apt` コマンドでエラーが発生する

**解決方法**:
```bash
# パッケージリストを更新
sudo apt update

# 壊れたパッケージを修復
sudo apt --fix-broken install

# リポジトリをクリーンアップ
make clean
```

### 2. Homebrewインストールエラー

**症状**: Homebrewのインストールが失敗する

**解決方法**:
```bash
# 既存のHomebrewを削除
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

# 再インストール
make init

# PATH設定を確認
echo $PATH | grep -o homebrew
```

### 3. フォント表示問題

**症状**: フォントが正しく表示されない

**解決方法**:
```bash
# フォントキャッシュを更新
fc-cache -f

# インストール済みフォントを確認
fc-list | grep -i "IBM Plex Sans"
fc-list | grep -i "Cica"

# フォントを再インストール
make setup
```

### 4. Neovim設定エラー

**症状**: Neovimでプラグインエラーが発生する

**解決方法**:
```bash
# Neovim設定をリセット
rm -rf ~/.local/share/nvim
rm -rf ~/.cache/nvim

# 設定を再適用
make setup

# Neovim内でプラグインを再インストール
nvim +Lazy +qall
```

### 5. シェル変更エラー

**症状**: デフォルトシェルをZshに変更できない

**解決方法**:
```bash
# 利用可能なシェルを確認
cat /etc/shells

# Zshのパスを確認
which zsh

# デフォルトシェルを変更
chsh -s $(which zsh)

# ログアウト・ログインで変更を反映
```

### 6. Docker権限エラー

**症状**: `docker` コマンドで権限エラーが発生する

**解決方法**:
```bash
# ユーザーをdockerグループに追加
sudo usermod -aG docker $USER

# ログアウト・ログインで変更を反映
# または以下のコマンドでグループを再読み込み
newgrp docker

# Dockerサービスを起動
sudo systemctl start docker
sudo systemctl enable docker
```

### 7. GNOME拡張機能エラー

**症状**: GNOME拡張機能がインストールできない

**解決方法**:
```bash
# GNOME Shell Integration をインストール
sudo apt install chrome-gnome-shell

# ブラウザで GNOME Extensions サイトにアクセス
# https://extensions.gnome.org/

# 手動で拡張機能を有効化
gnome-extensions enable <extension-id>
```

### 8. 日本語入力問題

**症状**: 日本語入力ができない

**解決方法**:
```bash
# 日本語入力パッケージを再インストール
sudo apt install ibus-mozc mozc-utils-gui

# IBusを再起動
ibus restart

# 入力ソースを設定
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'mozc-jp')]"

# ログアウト・ログインで変更を反映
```

## ログの確認方法

### システムログ
```bash
# 全体のシステムログ
journalctl -f

# 特定のサービスのログ
journalctl -u docker
journalctl -u NetworkManager
```

### アプリケーションログ
```bash
# Neovim LSPログ
tail -f ~/.local/share/nvim/lsp.log

# VS Codeログ
tail -f ~/.config/Code/logs/*/main.log
```

### インストールログ
```bash
# APTログ
tail -f /var/log/apt/history.log

# Homebrewログ
brew doctor
```

## 緊急時の復旧方法

### 設定の完全リセット
```bash
# dotfiles設定を削除
rm -rf ~/.config/nvim
rm -rf ~/.config/Code/User
rm -rf ~/.vscode

# 再セットアップ
cd ~/dotfiles
make setup
```

### システム設定の復旧
```bash
# GNOME設定をリセット
dconf reset -f /org/gnome/

# デフォルト設定を復元
make setup
```

## サポート情報

問題が解決しない場合は、以下の情報と共にIssueを作成してください：

1. OS バージョン: `lsb_release -a`
2. 実行したコマンド
3. エラーメッセージ（全文）
4. 環境確認結果: `./scripts/check-setup.sh`

EOF

    log_info "トラブルシューティングガイドを生成しました: $output_file"
}

# インデックスページを生成
generate_index() {
    log_step "インデックスページを生成中..."

    local output_file="$GENERATED_DIR/README.md"

    cat > "$output_file" << EOF
# 生成されたドキュメント

このディレクトリには自動生成されたドキュメントが含まれています。

生成日時: $(date)

## ドキュメント一覧

- [Makefileターゲット一覧](makefile-targets.md) - 利用可能なMakeターゲット
EOF

    if [[ -f "$GENERATED_DIR/brewfile-packages.md" ]]; then
        echo "- [Brewfileパッケージ一覧](brewfile-packages.md) - Homebrewパッケージ詳細" >> "$output_file"
    fi

    cat >> "$output_file" << EOF
- [VS Code拡張機能一覧](vscode-extensions.md) - インストール対象の拡張機能
- [ディレクトリ構造](directory-structure.md) - プロジェクトの構造
- [システム要件](system-requirements.md) - 動作環境の要件
- [トラブルシューティング](troubleshooting.md) - よくある問題と解決方法

## 更新方法

これらのドキュメントを更新するには、以下のコマンドを実行してください：

\`\`\`bash
./scripts/generate-docs.sh
\`\`\`

## 注意事項

- これらのファイルは自動生成されるため、直接編集しないでください
- 最新の情報については、元のソースファイルを参照してください
- 手動で管理されるドキュメントは \`docs/\` ディレクトリ直下に配置してください

EOF

    log_info "インデックスページを生成しました: $output_file"
}

# メイン実行
main() {
    echo "=========================================="
    echo "📚 ドキュメント自動生成スクリプト"
    echo "=========================================="
    echo ""

    log_info "生成開始時刻: $(date)"
    log_info "dotfilesディレクトリ: $DOTFILES_DIR"
    echo ""

    # ドキュメント生成
    setup_docs_directory
    generate_makefile_targets
    generate_brewfile_packages
    generate_vscode_extensions
    generate_directory_structure
    generate_system_requirements
    generate_troubleshooting
    generate_index

    echo ""
    echo "=========================================="
    echo "✅ ドキュメント生成完了"
    echo "=========================================="
    echo ""

    log_info "生成されたファイル:"
    find "$GENERATED_DIR" -name "*.md" | sort | sed 's|^|  - |'

    echo ""
    log_info "生成終了時刻: $(date)"
    log_info "ドキュメントディレクトリ: $GENERATED_DIR"
}

# スクリプト実行
main "$@"
