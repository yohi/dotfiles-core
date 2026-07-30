#!/usr/bin/env bash
# scripts/select-components.sh
#
# make init / setup 実行時に対話形式で不要なコンポーネントを選択・設定するスクリプト。

set -e

RESOLVED_YAML="${1:-.repos.resolved.yaml}"
ENV_FILE=".env"

# 装飾コード
H_BOLD="\033[1m"
H_BLUE="\033[34m"
H_GREEN="\033[32m"
H_YELLOW="\033[33m"
H_CYAN="\033[36m"
H_MAGENTA="\033[35m"
H_NC="\033[0m"

# コンポーネントの説明辞書
get_description() {
    case "$1" in
        dotfiles-system) echo "システム共通パッケージ・基盤設定" ;;
        dotfiles-zsh)    echo "Zsh シェル環境" ;;
        dotfiles-git)    echo "Git 設定" ;;
        dotfiles-vim)    echo "Vim / Neovim エディタ設定" ;;
        dotfiles-term)   echo "ターミナル (Alacritty/tmux 等) 設定" ;;
        dotfiles-ide)    echo "VS Code / IDE 設定" ;;
        dotfiles-ai)     echo "AI ツール (Claude / OpenCode 等) 設定" ;;
        dotfiles-gnome)  echo "GNOME GUI / デスクトップ環境設定" ;;
        *)               echo "コンポーネント設定" ;;
    esac
}

# ターゲットファイルが存在しない場合は処理終了
if [ ! -f "$RESOLVED_YAML" ]; then
    exit 0
fi

# 非対話環境（TTYなし）や明示的なスキップ要求時は処理を行わない
if [ ! -t 0 ] || [ "$INTERACTIVE" = "0" ] || [ "$NON_INTERACTIVE" = "1" ]; then
    echo -e "${H_YELLOW}非対話環境のため、コンポーネント選択プロンプトをスキップします。${H_NC}"
    exit 0
fi

echo -e "\n${H_BOLD}${H_MAGENTA}============================================================${H_NC}"
echo -e "${H_BOLD} 導入するコンポーネントの要不要を選択してください${H_NC}"
echo -e "${H_BOLD}${H_MAGENTA}============================================================${H_NC}"
echo -e "Enter キーを押すとデフォルト [Y]（有効）を選択します。\n"

# RESOLVED_YAML からコンポーネント名の一覧を取得
components=$(grep -E '^[[:space:]]{2}[a-zA-Z0-9_-]+:' "$RESOLVED_YAML" | sed 's/^[[:space:]]*//;s/://' || true)

if [ -z "$components" ]; then
    exit 0
fi

enabled_components=()
disabled_components=()

# .env が存在しない場合は空ファイルを作成
touch "$ENV_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for comp in $components; do
    desc=$(get_description "$comp")
    
    # GUI判定 (dotfiles-gnome の場合)
    default_prompt="Y/n"
    default_val="y"
    if [ "$comp" = "dotfiles-gnome" ] && [ "$SKIP_GUI" = "1" ]; then
        default_prompt="y/N"
        default_val="n"
    fi

    # 対話プロンプト
    read -r -p "$(echo -e "${H_CYAN}• ${H_BOLD}${comp}${H_NC} (${desc}) [${default_prompt}]: ")" ans || ans=""
    
    if [ -z "$ans" ]; then
        ans="$default_val"
    fi

    var_name="$("$SCRIPT_DIR/component-skip-var.sh" "$comp")"
    case "$ans" in
        [Nn]* )
            disabled_components+=("$comp")
            # .env の SKIP_<NAME> を更新
            # 既存の設定を削除して追加
            sed -i "/^${var_name}=/d" "$ENV_FILE"
            echo "${var_name}=1" >> "$ENV_FILE"
            ;;
        * )
            enabled_components+=("$comp")
            sed -i "/^${var_name}=/d" "$ENV_FILE"
            ;;
    esac
done

echo -e "\n${H_GREEN}${H_BOLD}✔ コンポーネント選択が完了しました。${H_NC}"
echo -e "${H_BLUE}  有効:${H_NC} ${enabled_components[*]:-なし}"
if [ ${#disabled_components[@]} -gt 0 ]; then
    echo -e "${H_YELLOW}  無効:${H_NC} ${disabled_components[*]}"
fi
echo -e "${H_MAGENTA}------------------------------------------------------------${H_NC}\n"
