# Core rules for all components and the orchestrator

.DEFAULT_GOAL := help

# Standard target for doing everything
.PHONY: all
all: install setup ## インストールとセットアップを全て実行します

# Placeholder targets (individual Makefiles should extend these)
# Gate messages behind VERBOSE=1 or V=1 for debugging
.PHONY: install setup
install: ## 依存パッケージのインストールを実行します
ifneq ($(filter 1,$(VERBOSE) $(V)),)
	@echo "skip: install not implemented (placeholder)"
endif

setup: ## 設定の適用（シンボリックリンク作成など）を実行します
ifneq ($(filter 1,$(VERBOSE) $(V)),)
	@echo "skip: setup not implemented (placeholder)"
endif
