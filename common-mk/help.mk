# Help System Colors
H_RED     := \033[31m
H_GREEN   := \033[32m
H_YELLOW  := \033[33m
H_BLUE    := \033[34m
H_MAGENTA := \033[35m
H_CYAN    := \033[36m
H_BOLD    := \033[1m
H_NC      := \033[0m

# Directory for Makefile fragments (default to _mk for components)
_MK_DIR ?= _mk

.PHONY: help
help: ## 利用可能なターゲットの一覧を表示します
	@echo -e "$(H_MAGENTA)$(H_BOLD)┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓$(H_NC)"
	@echo -e "$(H_MAGENTA)$(H_BOLD)┃ ✨ Dotfiles Manager Help ✨                                ┃$(H_NC)"
	@echo -e "$(H_MAGENTA)$(H_BOLD)┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛$(H_NC)"
	@echo -e "Usage: make $(H_CYAN)[target]$(H_NC)"
	@echo -e ""
	@echo -e "$(H_BOLD)🛠️  Workflow Guide (ターゲットの使い分け):$(H_NC)"
	@echo -e "  $(H_CYAN)init$(H_NC)    : 依存パッケージのインストールとリポジトリの準備"
	@echo -e "  $(H_CYAN)sync$(H_NC)    : リポジトリを最新状態に同期"
	@echo -e "  $(H_CYAN)secrets$(H_NC) : 機密情報の取得と復号"
	@echo -e "  $(H_CYAN)setup$(H_NC)   : 設定の適用（シンボリックリンク配備等）"
	@echo -e "  $(H_CYAN)all$(H_NC)     : sync ➔ secrets ➔ setup を一括実行"
	@echo -e ""
	@echo -e "$(H_BOLD)🚀 Recommended Sequences (推奨される実行順序):$(H_NC)"
	@echo -e "  1. 新規構築: $(H_GREEN)make init$(H_NC) ➔ $(H_GREEN)make all$(H_NC)"
	@echo -e "  2. 日常更新: $(H_GREEN)make all$(H_NC)"
	@echo -e ""
	@echo -e "$(H_BOLD)🎯 Available Targets (Categorized):$(H_NC)"
	@$(MAKE) -s _print-categorized-help
	@echo -e ""
	@echo -e "$(H_BOLD)Documentation:$(H_NC)"
	@echo -e "  See $(H_BLUE)SPEC.md$(H_NC) or $(H_BLUE)docs/ARCHITECTURE.md$(H_NC) for details."
	@echo -e ""

.PHONY: _print-categorized-help
_print-categorized-help:
	@# Main / Common
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' Makefile $(_MK_DIR)/main.mk $(_MK_DIR)/variables.mk $(_MK_DIR)/core.mk 2>/dev/null); \
	if [ -n "$$targets" ]; then \
		echo -e "$(H_YELLOW)$(H_BOLD)[Main / Common]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; !seen[$$1]++ { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }' | sort; \
	fi
	@# AI Tools & Agents
	@for category in Claude Gemini OpenCode Codex Antigravity; do \
		file_pat=$$(echo $$category | tr '[:upper:]' '[:lower:]'); \
		targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(_MK_DIR)/$${file_pat}.mk $(_MK_DIR)/super$${file_pat}.mk 2>/dev/null); \
		if [ -n "$$targets" ]; then \
			echo -e "\n$(H_YELLOW)$(H_BOLD)[$$category]$(H_NC)"; \
			echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; !seen[$$1]++ { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }' | sort; \
		fi; \
	done
	@# Specialized Categories
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(_MK_DIR)/ide-*.mk $(_MK_DIR)/test-ide-*.mk 2>/dev/null); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[IDE Tools & Testing]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; !seen[$$1]++ { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }' | sort; \
	fi
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(_MK_DIR)/mcp.mk 2>/dev/null); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Docker MCP Gateway]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; !seen[$$1]++ { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }' | sort; \
	fi
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(_MK_DIR)/skillport.mk 2>/dev/null); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Skill Management (SkillPort)]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; !seen[$$1]++ { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }' | sort; \
	fi
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(_MK_DIR)/sync-agents.mk 2>/dev/null); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Agent Synchronization & Rules]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }' | sort; \
	fi
	@targets=$$(grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(_MK_DIR)/superpowers.mk 2>/dev/null); \
	if [ -n "$$targets" ]; then \
		echo -e "\n$(H_YELLOW)$(H_BOLD)[Superpowers Workflow]$(H_NC)"; \
		echo "$$targets" | awk 'BEGIN {FS = ":.*?## "}; !seen[$$1]++ { printf "  $(H_CYAN)%-25s$(H_NC) %s\n", $$1, $$2 }' | sort; \
	fi


