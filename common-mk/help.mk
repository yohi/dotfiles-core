# Help System Colors
H_RED     := \033[31m
H_GREEN   := \033[32m
H_YELLOW  := \033[33m
H_BLUE    := \033[34m
H_MAGENTA := \033[35m
H_CYAN    := \033[36m
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
	@echo -e "  $(H_CYAN)clean$(H_NC)   : $(H_BOLD)[掃除]$(H_NC) 一時ファイルやセッションの削除"
	@echo -e ""
	@echo -e "$(H_BOLD)🚀 Recommended Sequences (推奨される実行順序):$(H_NC)"
	@echo -e "  1. 新規環境の構築: $(H_GREEN)make init$(H_NC) ➔ $(H_GREEN)make all$(H_NC)"
	@echo -e "  2. 日常的な更新:   $(H_GREEN)make all$(H_NC)"
	@echo -e "  3. 設定微調整後:   $(H_GREEN)make setup$(H_NC)"
	@echo -e "  4. 認証情報更新:   $(H_GREEN)make secrets$(H_NC) ➔ $(H_GREEN)make setup$(H_NC)"
	@echo -e ""
	@echo -e "$(H_BOLD)🎯 All Available Targets (Categorized):$(H_NC)"
	@$(MAKE) -s _print-categorized-help
	@echo -e ""
	@echo -e "$(H_BOLD)Documentation:$(H_NC)"
	@echo -e "  See $(H_BLUE)SPEC.md$(H_NC) or $(H_BLUE)docs/ARCHITECTURE.md$(H_NC) for details."
	@echo -e ""

.PHONY: _print-categorized-help
_print-categorized-help:
	@# Main / Common
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' Makefile _mk/main.mk _mk/variables.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "$(H_YELLOW)$(H_BOLD)[Main / Common]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# Claude
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/claude.mk _mk/superclaude.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Claude Code]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# Gemini
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/gemini.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Gemini CLI]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# OpenCode
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/opencode.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[OpenCode]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# Codex
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/codex.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Codex CLI]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# Antigravity
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/antigravity.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Antigravity]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# IDE Tools
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/ide-cursor.mk _mk/ide-vscode.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[IDE Tools]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# Docker MCP
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/mcp.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Docker MCP Gateway]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# SkillPort
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/skillport.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Skill Management (SkillPort)]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# Agent Sync / Rules
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/sync-agents.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Agent Synchronization & Rules]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
	@# Superpowers
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' _mk/superpowers.mk 2>/dev/null | sort); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Superpowers Workflow]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }'; \
	fi
