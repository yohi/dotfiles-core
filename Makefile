# dotfiles-core: Orchestrator Makefile
SHELL := /bin/bash

# ==============================================================================
# Usage Guide (各ターゲットの使い分け)
# ==============================================================================
#  make init    : [初回] 依存パッケージのインストールとリポジトリのクローン。
#  make sync    : [更新] 全コンポーネントのリポジトリを最新状態に同期。
#  make secrets : [機密] BitwardenからAPIキー等の機密情報を取得。
#  make setup   : [設定] シンボリックリンクの配備など設定の適用を実行。
#  make all     : [一括] sync -> secrets -> setup を全コンポーネントで実行。
#  make status  : [確認] 全コンポーネントのGitステータスを一括表示。
#  make clean   : [掃除] 一時ファイルやセッションの削除。
# ==============================================================================

# Default target
.DEFAULT_GOAL := help

COMPONENTS_DIR := components
REPOS_YAML := repos.yaml
REPOS_YAML_RESOLVED := .repos.resolved.yaml
STOW_TARGET := $(HOME)

# Standard help and core rules
include common-mk/help.mk

# Path for storing Bitwarden session key (outside repository)
BW_SESSION_FILE ?= $(shell echo $${XDG_RUNTIME_DIR:-$$HOME/.cache}/bw_session)

# Timezone for non-interactive setup
TZ_OVERRIDE ?= Asia/Tokyo

# Colors and Symbols
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
MAGENTA:= \033[0;35m
CYAN   := \033[0;36m
BOLD   := \033[1m
NC     := \033[0m # No Color

T_START := $(BLUE)$(BOLD)▶$(NC)
T_OK    := $(GREEN)$(BOLD)✔$(NC)
T_ERR   := $(RED)$(BOLD)✘$(NC)
T_SKIP  := $(YELLOW)$(BOLD)➖$(NC)
T_ITEM  := $(CYAN)$(BOLD)•$(NC)

# Reusable macro to dispatch a target to all components
define dispatch
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		if [ -f "$(BW_SESSION_FILE)" ]; then export BW_SESSION=$$(cat "$(BW_SESSION_FILE)"); fi; \
		fail_count=0; \
		total_count=0; \
		echo -e "$(MAGENTA)$(BOLD)┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓$(NC)"; \
		echo -e "$(MAGENTA)$(BOLD)┃ Dispatching '$(1)' to all components...$(NC)"; \
		echo -e "$(MAGENTA)$(BOLD)┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛$(NC)"; \
		for dir in "$(COMPONENTS_DIR)"/*; do \
			if [ -d "$$dir" ] && [ -f "$$dir/Makefile" ]; then \
				component=$$(basename "$$dir"); \
				err_out=$$( ( cd "$$dir" && $(LOAD_ENV) && $(MAKE) -n $(1) ) 2>&1 >/dev/null ); \
				ret=$$?; \
				if [ $$ret -ne 0 ] && ! echo "$$err_out" | grep -iqe "No rule to make target" -e "を make するルールがありません"; then \
					echo -e "  $(T_ERR) $(RED)$(BOLD)$$component:$(NC) Target detection failed"; \
					echo "$$err_out" | sed 's/^/      /' >&2; \
					fail_count=$$((fail_count+1)); \
					continue; \
				fi; \
				if [ $$ret -eq 0 ]; then \
					total_count=$$((total_count+1)); \
					echo -e "  $(T_START) $(BLUE)Executing '$(1)' in $(BOLD)$$component$(NC)..."; \
					if ! ( cd "$$dir" && $(LOAD_ENV) && $(MAKE) --no-print-directory $(1) ); then \
						echo -e "  $(T_ERR) $(RED)$(BOLD)$$component:$(NC) $(RED)FAILED$(NC)"; \
						fail_count=$$((fail_count+1)); \
					else \
						echo -e "  $(T_OK) $(GREEN)$(BOLD)$$component:$(NC) $(GREEN)SUCCESS$(NC)"; \
					fi; \
				else \
					echo -e "  $(T_SKIP) $(YELLOW)$$component:$(NC) skipped (no '$(1)' target)"; \
				fi; \
			fi; \
		done; \
		echo -e "$(MAGENTA)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		if [ $$fail_count -gt 0 ]; then \
			echo -e "$(RED)$(BOLD)  SUMMARY: $$total_count attempted, $$fail_count failed.$(NC)"; \
			exit 1; \
		else \
			echo -e "$(GREEN)$(BOLD)  SUMMARY: All $$total_count components succeeded! ✨$(NC)"; \
		fi; \
	fi
endef

# Load .env file and export variables
LOAD_ENV = if [ -f .env ]; then \
	while IFS= read -r line || [ -n "$$line" ]; do \
		[[ "$$line" =~ ^[[:space:]]*(\#.*)?$$ ]] && continue; \
		if [[ "$$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$$ ]]; then \
			key="$${BASH_REMATCH[1]}"; \
			val="$${BASH_REMATCH[2]}"; \
			if [[ "$$val" =~ ^\"(.*)\"$$ ]] || [[ "$$val" =~ ^\x27(.*)\x27$$ ]]; then \
				val="$${BASH_REMATCH[1]}"; \
			fi; \
			printf -v "$$key" "%s" "$$val"; \
			export "$$key"; \
		else \
			echo -e "$(T_ERR) $(RED)[ERROR] Failed to parse .env in $$(pwd): invalid format$(NC)" >&2; \
			exit 1; \
		fi; \
	done < .env; \
fi

.PHONY: init sync status diff secrets setup all clean test .clean-safety _inject_common_mk _install-deps _set-timezone _install-vcstool _unlock_bw _ensure_bw_auth _check_bw_tools _skip_secrets test-dispatch _check_docker

ifeq ($(WITH_BW),1)
SECRETS_DEPS := _unlock_bw
endif

all: ## すべてのコンポーネントの全行程（インストール・セットアップ）を実行します
	$(call dispatch,all)

SSH_CONNECT_TIMEOUT ?= 3

$(REPOS_YAML_RESOLVED): $(REPOS_YAML) ## リポジトリ設定ファイルのURLを解決（SSH/HTTPS）します
	@cp $(REPOS_YAML) $@ || { \
		ret=$$?; \
		echo -e "$(RED)[ERROR] Failed to copy $(REPOS_YAML) to $@ (exit $$ret)$(NC)" >&2; \
		exit $$ret; \
	}
	@if [ "$(USE_HTTPS)" = "1" ]; then \
		echo -e "$(BLUE)==> Forcing HTTPS as requested...$(NC)"; \
		sed -i -e 's|ssh://git@github.com/|https://github.com/|g' -e 's|git@github.com:|https://github.com/|g' -e 's|git@github.com/|https://github.com/|g' $@ || { \
			echo -e "$(RED)[ERROR] Failed to update URLs to HTTPS in $@$(NC)" >&2; \
			exit 1; \
		}; \
	else \
		echo -e "$(BLUE)==> Checking SSH connectivity to GitHub...$(NC)"; \
		ssh -o ConnectTimeout=$(SSH_CONNECT_TIMEOUT) -o BatchMode=yes -T git@github.com >/dev/null 2>&1; \
		ret=$$?; \
		if [ $$ret -ne 0 ] && [ $$ret -ne 1 ]; then \
			echo -e "$(YELLOW)    SSH connection failed (code $$ret), falling back to HTTPS...$(NC)"; \
			sed -i -e 's|ssh://git@github.com/|https://github.com/|g' -e 's|git@github.com:|https://github.com/|g' -e 's|git@github.com/|https://github.com/|g' $@ || { \
				echo -e "$(RED)[ERROR] Failed to update URLs to HTTPS in $@$(NC)" >&2; \
				exit 1; \
			}; \
		else \
			echo -e "$(GREEN)    SSH connection successful (code $$ret).$(NC)"; \
		fi; \
	fi

_install-deps:
	@if command -v apt-get >/dev/null 2>&1; then \
		SUDO=$$(command -v sudo || true); \
		$$SUDO DEBIAN_FRONTEND=noninteractive apt-get update || { echo "Failed to apt-get update in _install-deps"; exit 1; }; \
		$$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata python3-pip jq curl git openssh-client ca-certificates python3-setuptools || { echo "Failed to install packages in _install-deps"; exit 1; }; \
	fi

_set-timezone:
	@if command -v apt-get >/dev/null 2>&1; then \
		SUDO=$$(command -v sudo || true); \
		if [ ! -e "/usr/share/zoneinfo/$(TZ_OVERRIDE)" ]; then \
			echo -e "$(RED)[ERROR] Timezone '$(TZ_OVERRIDE)' not found in /usr/share/zoneinfo/$(NC)" >&2; \
			exit 1; \
		fi; \
		$$SUDO ln -fs /usr/share/zoneinfo/$(TZ_OVERRIDE) /etc/localtime || { \
			echo -e "$(RED)[ERROR] Failed to set /etc/localtime to $(TZ_OVERRIDE)$(NC)" >&2; \
			exit 1; \
		}; \
	fi

_install-vcstool:
	@if ! command -v vcs >/dev/null 2>&1; then \
		SUDO=$$(command -v sudo || true); \
		$$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y vcstool 2>/dev/null || pip3 install --user vcstool --break-system-packages || { echo -e "$(RED)ERROR: failed to install vcstool$(NC)" >&2; exit 1; }; \
	fi

init: $(REPOS_YAML_RESOLVED) _install-deps _set-timezone _install-vcstool ## 依存関係のインストールとリポジトリのクローンを行います
	@echo -e "$(T_START) $(BLUE)Initializing dependencies and importing components...$(NC)"
	@mkdir -p $(COMPONENTS_DIR)
	@PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML_RESOLVED)
	@echo -e "$(T_OK) $(GREEN)Initialization complete!$(NC)"

sync: init $(REPOS_YAML_RESOLVED) ## コンポーネントのソースコードを最新化します
	@echo -e "$(T_START) $(BLUE)Syncing all components...$(NC)"
	@mkdir -p $(COMPONENTS_DIR)
	@PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML_RESOLVED)
	@PATH="$(HOME)/.local/bin:$$PATH" vcs pull $(COMPONENTS_DIR)
	@echo -e "$(T_OK) $(GREEN)Sync complete!$(NC)"

status: ## すべてのコンポーネントのGitステータスを確認します
	@echo -e "$(T_START) $(BLUE)Checking status of all components...$(NC)"
	@PATH="$(HOME)/.local/bin:$$PATH" vcs status $(COMPONENTS_DIR)

diff: ## すべてのコンポーネントのGit差分を確認します
	@echo -e "$(T_START) $(BLUE)Checking diff of all components...$(NC)"
	@PATH="$(HOME)/.local/bin:$$PATH" vcs diff $(COMPONENTS_DIR)

_inject_common_mk:
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
	        echo -e "$(T_START) $(BLUE)Injecting common-mk into components...$(NC)"; \
	        for dir in "$(COMPONENTS_DIR)"/*; do \
	                if [ -d "$$dir" ] && [ -f "$$dir/Makefile" ]; then \
	                        mkdir -p "$$dir/_mk"; \
	                        ln -sf ../../../common-mk/idempotency.mk "$$dir/_mk/idempotency.mk"; \
	                        ln -sf ../../../common-mk/help.mk "$$dir/_mk/help.mk"; \
	                        ln -sf ../../../common-mk/core.mk "$$dir/_mk/core.mk"; \
	                        ln -sf ../../common-mk/DOTFILES_COMMON_RULES.md "$$dir/DOTFILES_COMMON_RULES.md"; \
	                fi; \
	        done; \
	        echo -e "$(T_OK) $(GREEN)Common-mk injection complete.$(NC)"; \
        fi

_skip_secrets:
	@echo -e "  $(T_SKIP) $(YELLOW)Bitwarden integration is disabled. Set WITH_BW=1 to enable.$(NC)"

_check_bw_tools: init
	@command -v bw >/dev/null 2>&1 || { echo -e "  $(T_ERR) $(RED)Bitwarden CLI (bw) not found.$(NC)" >&2; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo -e "  $(T_ERR) $(RED)jq not found.$(NC)" >&2; exit 1; }

_ensure_bw_auth: _check_bw_tools
	@echo -e "  $(T_START) $(BLUE)Verifying Bitwarden authentication...$(NC)"
	@status_json=$$(bw status 2>/dev/null) || { echo -e "  $(T_ERR) $(RED)[ERROR] Bitwarden CLI 'bw status' failed.$(NC)" >&2; exit 1; }; \
	status=$$(echo "$$status_json" | jq -r '.status' 2>/dev/null || echo "error"); \
	if [ "$$status" = "error" ]; then \
		echo -e "  $(T_ERR) $(RED)[ERROR] Failed to parse Bitwarden status.$(NC)" >&2; \
		exit 1; \
	fi; \
	if [ "$$status" = "unauthenticated" ]; then \
		echo -e "  $(T_START) $(YELLOW)Authenticating Bitwarden...$(NC)" >&2; \
		bw login || { echo -e "  $(T_ERR) $(RED)[ERROR] Bitwarden login failed$(NC)" >&2; exit 1; }; \
	fi

_unlock_bw: _ensure_bw_auth
	@status=$$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error"); \
	if [ "$$status" = "locked" ]; then \
		echo -e "  $(T_START) $(BLUE)Unlocking Bitwarden vault...$(NC)" >&2; \
		session=$$(bw unlock --raw) || { echo -e "  $(T_ERR) $(RED)[ERROR] Bitwarden unlock failed.$(NC)" >&2; exit 1; }; \
		if [ -n "$$session" ]; then \
			mkdir -p "$$(dirname "$(BW_SESSION_FILE)")"; \
			echo "$$session" > "$(BW_SESSION_FILE)" && chmod 600 "$(BW_SESSION_FILE)" || { echo -e "  $(T_ERR) $(RED)[ERROR] Failed to save session$(NC)" >&2; exit 1; }; \
			echo -e "  $(T_OK) $(GREEN)Vault unlocked. Session saved.$(NC)"; \
		else \
			echo -e "  $(T_ERR) $(RED)[ERROR] Failed to obtain Bitwarden session key.$(NC)" >&2; exit 1; \
		fi; \
	elif [ "$$status" = "unlocked" ]; then \
		echo -e "  $(T_OK) $(GREEN)Bitwarden vault is already unlocked.$(NC)"; \
		if [ -z "$$BW_SESSION" ]; then \
			echo -e "  $(T_ITEM) $(YELLOW)BW_SESSION not set, obtaining session...$(NC)"; \
			BW_SESSION=$$(bw unlock --raw) || { echo -e "  $(T_ERR) $(RED)failed to obtain BW_SESSION$(NC)" >&2; exit 1; }; \
		fi; \
		mkdir -p "$$(dirname "$(BW_SESSION_FILE)")"; \
		echo "$$BW_SESSION" > "$(BW_SESSION_FILE)" && chmod 600 "$(BW_SESSION_FILE)" || { echo -e "  $(T_ERR) $(RED)[ERROR] Failed to update session$(NC)" >&2; exit 1; }; \
	else \
		echo -e "  $(T_ERR) $(RED)[ERROR] Unexpected Bitwarden status: $$status$(NC)" >&2; \
		exit 1; \
	fi

secrets: init $(SECRETS_DEPS) ## Bitwardenからシークレット情報を取得します

setup: sync secrets _inject_common_mk ## すべてのコンポーネントのセットアップ（設定適用）を実行します
	@echo -e "$(T_START) $(BLUE)Delegating to component-specific setup...$(NC)"
	$(call dispatch,setup)
	@echo -e "$(T_OK) $(GREEN)$(BOLD)Setup Process Complete! ✨$(NC)"

# Internal target for testing the dispatch macro
test-dispatch:
	$(call dispatch,$(TARGET))

_check_docker:

	@command -v docker >/dev/null 2>&1 || { echo -e "$(RED)[ERROR] Docker is not available on PATH.$(NC)" >&2; exit 1; }

test: _check_docker
	@echo -e "$(BLUE)==> Building test container...$(NC)"
	docker build -t dotfiles-core-test -f tests/Dockerfile.test .
	@echo -e "$(BLUE)==> Running tests...$(NC)"
	docker run --rm \
		-v "$$(pwd):/home/testuser/dotfiles-core" \
		dotfiles-core-test ./tests/integration_test.sh

clean:
	@echo -e "$(YELLOW)==> Cleaning up session and components...$(NC)"
	@rm -f "$(BW_SESSION_FILE)" $(REPOS_YAML_RESOLVED)
	@$(MAKE) .clean-safety

.clean-safety:
	@if [ -z "$(COMPONENTS_DIR)" ] || [ "$(COMPONENTS_DIR)" = "/" ] || [ "$(COMPONENTS_DIR)" = "." ] || [ "$(COMPONENTS_DIR)" = ".." ]; then \
		echo "ERROR: unsafe COMPONENTS_DIR='$(COMPONENTS_DIR)'"; \
		exit 1; \
	elif [ ! -d "$(COMPONENTS_DIR)" ]; then \
		echo "==> Skip component clean: directory '$(COMPONENTS_DIR)' not found."; \
	else \
		rm -rf "$(COMPONENTS_DIR)"/*; \
	fi
