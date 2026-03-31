# Core rules for all components and the orchestrator

.DEFAULT_GOAL := help

# Standard target for doing everything
.PHONY: all
all: install setup ## インストールとセットアップを全て実行します

# Placeholder targets (individual Makefiles should extend these)
.PHONY: install setup
install: ## 依存パッケージのインストールを実行します
setup: ## 設定の適用（シンボリックリンク作成など）を実行します
