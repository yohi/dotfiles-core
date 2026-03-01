#!/bin/bash

# Ubuntu開発環境セットアップ確認スクリプト
# 現在の環境構築状態を確認し、問題があれば修正方法を提示

set -euo pipefail

# 色付きメッセージの定義
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# ログ用関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# チェック項目のカウンタ
total_checks=0
passed_checks=0
failed_checks=0
warning_checks=0

# チェック結果を記録
record_result() {
    local status=$1
    local message=$2
    
    total_checks=$((total_checks + 1))
    
    case $status in
        "PASS")
            passed_checks=$((passed_checks + 1))
            log_success "$message"
            ;;
        "FAIL")
            failed_checks=$((failed_checks + 1))
            log_error "$message"
            ;;
        "WARN")
            warning_checks=$((warning_checks + 1))
            log_warn "$message"
            ;;
    esac
}

# システム情報の確認
check_system_info() {
    log_step "システム情報を確認中..."
    
    # OS情報
    local os_name=$(lsb_release -si 2>/dev/null || echo "Unknown")
    local os_version=$(lsb_release -sr 2>/dev/null || echo "Unknown")
    local arch=$(uname -m)
    
    log_info "OS: $os_name $os_version ($arch)"
    
    if [[ "$os_name" == "Ubuntu" ]]; then
        record_result "PASS" "Ubuntuが検出されました"
    else
        record_result "WARN" "Ubuntu以外のOS: $os_name (一部の機能が動作しない可能性があります)"
    fi
}

# 基本コマンドの確認
check_basic_commands() {
    log_step "基本コマンドを確認中..."
    
    # 実際のコマンドをチェック
    local commands=("git" "make" "curl" "wget" "gcc")
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            record_result "PASS" "$cmd がインストールされています"
        else
            record_result "FAIL" "$cmd がインストールされていません - sudo apt install $cmd"
        fi
    done
    
    # build-essentialパッケージの確認（dpkgでパッケージの存在を確認）
    if dpkg -l | grep -q "^ii.*build-essential"; then
        record_result "PASS" "build-essential パッケージがインストールされています"
    else
        record_result "FAIL" "build-essential パッケージがインストールされていません - sudo apt install build-essential"
    fi
}

# Homebrew の確認
check_homebrew() {
    log_step "Homebrewを確認中..."
    
    if command -v brew &> /dev/null; then
        record_result "PASS" "Homebrewがインストールされています"
        
        # Homebrew パッケージの確認
        local brew_packages=("neovim" "zsh" "fzf" "ripgrep" "git-lfs")
        
        for pkg in "${brew_packages[@]}"; do
            if brew list "$pkg" &> /dev/null; then
                record_result "PASS" "Homebrewパッケージ '$pkg' がインストールされています"
            else
                record_result "WARN" "Homebrewパッケージ '$pkg' がインストールされていません"
            fi
        done
    else
        record_result "FAIL" "Homebrewがインストールされていません - make install-homebrew"
    fi
}

# フォントの確認
check_fonts() {
    log_step "フォントを確認中..."
    
    # IBM Plex Sans フォント
    local plex_count=$(fc-list : family | grep -i "IBM Plex Sans" | wc -l)
    if [[ $plex_count -gt 0 ]]; then
        record_result "PASS" "IBM Plex Sans フォントが検出されました ($plex_count 個)"
    else
        record_result "WARN" "IBM Plex Sans フォントが見つかりません - システムセットアップを実行してください"
    fi
    
    # Cica フォント
    local cica_count=$(fc-list : family | grep -i "Cica" | wc -l)
    if [[ $cica_count -gt 0 ]]; then
        record_result "PASS" "Cica フォントが検出されました ($cica_count 個)"
    else
        record_result "WARN" "Cica フォントが見つかりません - make install-cica-fonts"
    fi
    
    # 日本語フォント
    local jp_count=$(fc-list : family | grep -i "Noto.*CJK" | wc -l)
    if [[ $jp_count -gt 0 ]]; then
        record_result "PASS" "日本語フォントが検出されました ($jp_count 個)"
    else
        record_result "WARN" "日本語フォントが見つかりません - システムセットアップを実行してください"
    fi
}

# Neovim設定の確認
check_neovim() {
    log_step "Neovim設定を確認中..."
    
    if command -v nvim &> /dev/null; then
        record_result "PASS" "Neovimがインストールされています"
        
        # 設定ファイルの確認
        local config_dir="$HOME/.config/nvim"
        local dotfiles_dir="${DOTFILES_DIR:-$HOME/dots}/vim"
        
        if [[ -L "$config_dir" ]] && [[ -d "$dotfiles_dir" ]]; then
            record_result "PASS" "Neovim設定がシンボリックリンクされています"
        elif [[ -d "$config_dir" ]]; then
            record_result "WARN" "Neovim設定ディレクトリが存在しますが、dotfilesにリンクされていません"
        else
            record_result "FAIL" "Neovim設定が見つかりません - make setup-vim"
        fi
    else
        record_result "FAIL" "Neovimがインストールされていません - make install-apps"
    fi
}

# VS Code/Cursor設定の確認  
check_editors() {
    log_step "エディタを確認中..."
    
    # VS Code
    if command -v code &> /dev/null; then
        record_result "PASS" "VS Codeがインストールされています"
        
        local vscode_settings="$HOME/.config/Code/User/settings.json"
        if [[ -f "$vscode_settings" ]]; then
            record_result "PASS" "VS Code設定ファイルが存在します"
        else
            record_result "WARN" "VS Code設定ファイルが見つかりません - make setup-vscode"
        fi
    else
        record_result "WARN" "VS Codeがインストールされていません"
    fi
    
    # Cursor
    if command -v cursor &> /dev/null || [[ -f "/opt/cursor/cursor" ]]; then
        record_result "PASS" "Cursorがインストールされています"
    else
        record_result "WARN" "Cursorがインストールされていません"
    fi
}

# シェル環境の確認
check_shell() {
    log_step "シェル環境を確認中..."
    
    # Zsh
    if command -v zsh &> /dev/null; then
        record_result "PASS" "Zshがインストールされています"
        
        # 現在のシェル確認
        if [[ "$SHELL" == */zsh ]]; then
            record_result "PASS" "Zshがデフォルトシェルに設定されています"
        else
            record_result "WARN" "Zshがデフォルトシェルに設定されていません - chsh -s $(which zsh)"
        fi
        
        # Powerlevel10k
        if [[ -f "$HOME/.p10k.zsh" ]]; then
            record_result "PASS" "Powerlevel10k設定が存在します"
        else
            record_result "WARN" "Powerlevel10k設定が見つかりません - make setup-zsh"
        fi
    else
        record_result "FAIL" "Zshがインストールされていません - make install-apps"
    fi
}

# Docker環境の確認
check_docker() {
    log_step "Docker環境を確認中..."
    
    if command -v docker &> /dev/null; then
        record_result "PASS" "Dockerがインストールされています"
        
        # Docker動作確認
        if docker ps &> /dev/null; then
            record_result "PASS" "Dockerが正常に動作しています"
        else
            record_result "WARN" "Dockerが動作していません - sudo systemctl start docker"
        fi
        
        # Docker Compose
        if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
            record_result "PASS" "Docker Composeがインストールされています"
        else
            record_result "WARN" "Docker Composeがインストールされていません"
        fi
    else
        record_result "WARN" "Dockerがインストールされていません"
    fi
}

# 日本語環境の確認
check_japanese() {
    log_step "日本語環境を確認中..."
    
    # ロケール確認
    if locale | grep -q "ja_JP.UTF-8"; then
        record_result "PASS" "日本語ロケールが設定されています"
    else
        record_result "WARN" "日本語ロケールが設定されていません - make system-setup"
    fi
    
    # 入力メソッド確認
    if command -v ibus &> /dev/null; then
        record_result "PASS" "IBus入力メソッドがインストールされています"
        
        # Mozc確認
        if ibus list-engines | grep -q mozc; then
            record_result "PASS" "Mozc(日本語入力)が利用可能です"
        else
            record_result "WARN" "Mozcが見つかりません - make system-setup"
        fi
    else
        record_result "WARN" "IBus入力メソッドがインストールされていません"
    fi
}

# GNOME環境の確認
check_gnome() {
    log_step "GNOME環境を確認中..."
    
    # GNOME確認
    if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
        record_result "PASS" "GNOME環境が検出されました"
        
        # GNOME Tweaks
        if command -v gnome-tweaks &> /dev/null; then
            record_result "PASS" "GNOME Tweaksがインストールされています"
        else
            record_result "WARN" "GNOME Tweaksがインストールされていません"
        fi
        
        # Extension Manager
        if command -v gnome-extensions &> /dev/null; then
            record_result "PASS" "GNOME Extension Managerが利用可能です"
        else
            record_result "WARN" "GNOME Extension Managerが見つかりません"
        fi
    else
        record_result "WARN" "GNOME環境以外のデスクトップ環境です"
    fi
}

# dotfiles設定の確認
check_dotfiles() {
    log_step "dotfiles設定を確認中..."
    
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/dots}"
    
    if [[ -d "$dotfiles_dir" ]]; then
        record_result "PASS" "dotfilesディレクトリが存在します"
        
        # 主要ファイルの確認
        local important_files=("Makefile" "Brewfile" "README.md" "install.sh")
        
        for file in "${important_files[@]}"; do
            if [[ -f "$dotfiles_dir/$file" ]]; then
                record_result "PASS" "$file が存在します"
            else
                record_result "WARN" "$file が見つかりません"
            fi
        done
    else
        record_result "FAIL" "dotfilesディレクトリが見つかりません - インストールスクリプトを実行してください"
    fi
}

# パフォーマンスの確認
check_performance() {
    log_step "システムパフォーマンスを確認中..."
    
    # メモリ使用量（awkで浮動小数点比較を実行）
    local mem_usage_info=$(free | grep Mem | awk '
        {
            mem_used_percent = ($3/$2 * 100.0)
            if (mem_used_percent < 80) {
                printf "PASS %.1f", mem_used_percent
            } else {
                printf "WARN %.1f", mem_used_percent
            }
        }
    ')
    local status=$(echo "$mem_usage_info" | cut -d' ' -f1)
    local mem_used=$(echo "$mem_usage_info" | cut -d' ' -f2)
    
    if [[ "$status" == "PASS" ]]; then
        record_result "PASS" "メモリ使用量: ${mem_used}%"
    else
        record_result "WARN" "メモリ使用量が高い: ${mem_used}%"
    fi
    
    # ディスク使用量
    local disk_used=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
    if [[ $disk_used -lt 80 ]]; then
        record_result "PASS" "ディスク使用量: ${disk_used}%"
    else
        record_result "WARN" "ディスク使用量が高い: ${disk_used}%"
    fi
}

# 修正提案の表示
show_recommendations() {
    echo ""
    log_step "🛠️  修正提案"
    
    if [[ $failed_checks -gt 0 ]]; then
        echo ""
        echo -e "${RED}❌ 失敗したチェックの修正方法:${NC}"
        echo "  1. 基本セットアップ: make system-setup"
        echo "  2. Homebrewインストール: make install-homebrew"
        echo "  3. 全体セットアップ: make setup-all"
    fi
    
    if [[ $warning_checks -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  警告項目の改善方法:${NC}"
        echo "  1. フォントインストール: make install-cica-fonts"
        echo "  2. 個別設定適用: make setup-vim, make setup-zsh"
        echo "  3. GNOME設定適用: make setup-gnome-extensions"
    fi
    
    echo ""
    echo -e "${BLUE}💡 追加の推奨事項:${NC}"
    echo "  1. 定期的な更新: cd ~/dots && git pull && make setup-all"
    echo "  2. 設定バックアップ: make backup-gnome-tweaks"
    echo "  3. 詳細ヘルプ: make help"
}

# メイン実行
main() {
    echo "============================================================"
    echo "🔍 Ubuntu開発環境セットアップ確認スクリプト"
    echo "============================================================"
    echo ""
    
    log_info "確認開始時刻: $(date)"
    echo ""
    
    # 各種確認実行
    check_system_info
    check_basic_commands
    check_homebrew
    check_fonts
    check_neovim
    check_editors
    check_shell
    check_docker
    check_japanese
    check_gnome
    check_dotfiles
    check_performance
    
    # 結果サマリー
    echo ""
    echo "============================================================"
    echo "📊 確認結果サマリー"
    echo "============================================================"
    echo ""
    echo -e "${GREEN}✅ 成功: $passed_checks${NC}"
    echo -e "${YELLOW}⚠️  警告: $warning_checks${NC}"
    echo -e "${RED}❌ 失敗: $failed_checks${NC}"
    echo -e "${BLUE}📈 合計: $total_checks${NC}"
    echo ""
    
    # 全体的な健全性判定
    local success_rate=$(( (passed_checks * 100) / total_checks ))
    
    if [[ $success_rate -ge 90 ]]; then
        echo -e "${GREEN}🎉 環境は非常に良好です! ($success_rate%)${NC}"
    elif [[ $success_rate -ge 70 ]]; then
        echo -e "${YELLOW}👍 環境は概ね良好です ($success_rate%)${NC}"
    else
        echo -e "${RED}🔧 環境に改善が必要です ($success_rate%)${NC}"
    fi
    
    # 修正提案
    show_recommendations
    
    echo ""
    log_info "確認終了時刻: $(date)"
    echo ""
    
    # 終了コード
    if [[ $failed_checks -gt 0 ]]; then
        exit 1
    elif [[ $warning_checks -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# スクリプト実行
main "$@" 