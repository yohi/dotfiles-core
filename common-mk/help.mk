# Help System Colors
H_MAGENTA := \033[35m
H_CYAN    := \033[36m
H_YELLOW  := \033[33m
H_BLUE    := \033[34m
H_GREEN   := \033[32m
H_BOLD    := \033[1m
H_NC      := \033[0m

.PHONY: help
help: ## 利用可能なターゲットの一覧を表示します
	@echo -e "$(H_MAGENTA)$(H_BOLD)┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓$(H_NC)"
	@echo -e "$(H_MAGENTA)$(H_BOLD)┃ ✨ Dotfiles Manager Help ✨                                ┃$(H_NC)"
	@echo -e "$(H_MAGENTA)$(H_BOLD)┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛$(H_NC)"
	@echo -e "Usage: make $(H_CYAN)[target]$(H_NC)"
	@echo -e ""
	@echo -e "$(H_BOLD)🛠️  Workflow Guide (ターゲットの使い分け):$(H_NC)"
	@echo -e "  $(H_CYAN)init$(H_NC)    : $(H_BOLD)[初回]$(H_NC) 依存パッケージのインストールとリポジトリのクローン"
	@echo -e "  $(H_CYAN)sync$(H_NC)    : $(H_BOLD)[更新]$(H_NC) 全コンポーネントのリポジトリを最新状態に同期"
	@echo -e "  $(H_CYAN)secrets$(H_NC) : $(H_BOLD)[機密]$(H_NC) BitwardenからAPIキー等の機密情報を取得"
	@echo -e "  $(H_CYAN)setup$(H_NC)   : $(H_BOLD)[設定]$(H_NC) シンボリックリンクの配備など設定の適用を実行"
	@echo -e "  $(H_CYAN)all$(H_NC)     : $(H_BOLD)[一括]$(H_NC) sync -> secrets -> setup を全コンポーネントで実行"
	@echo -e "  $(H_CYAN)status$(H_NC)  : $(H_BOLD)[確認]$(H_NC) 全コンポーネントのGitステータスを一括表示"
	@echo -e ""
	@echo -e "$(H_BOLD)🚀 Recommended Sequences (推奨される実行順序):$(H_NC)"
	@echo -e "  1. $(H_BOLD)新規環境の構築:$(H_NC)"
	@echo -e "     $(H_GREEN)make init$(H_NC) ➔ $(H_GREEN)make all$(H_NC)"
	@echo -e "  2. $(H_BOLD)日常的な更新 (コードと設定を最新にする):$(H_NC)"
	@echo -e "     $(H_GREEN)make all$(H_NC)"
	@echo -e "  3. $(H_BOLD)設定の微調整後 (シンボリックリンクのみ再作成):$(H_NC)"
	@echo -e "     $(H_GREEN)make setup$(H_NC)"
	@echo -e "  4. $(H_BOLD)パスワードやAPIキーが変わった場合:$(H_NC)"
	@echo -e "     $(H_GREEN)make secrets$(H_NC) ➔ $(H_GREEN)make setup$(H_NC)"
	@echo -e ""
	@echo -e "$(H_BOLD)🎯 All Available Targets:$(H_NC)"
	@grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; { \
		printf "  $(H_CYAN)%-18s$(H_NC) %s\n", $$1, $$2 \
	}'
	@echo -e ""
	@echo -e "$(H_BOLD)Documentation:$(H_NC)"
	@echo -e "  See $(H_BLUE)SPEC.md$(H_NC) or $(H_BLUE)docs/ARCHITECTURE.md$(H_NC) for details."
	@echo -e ""
