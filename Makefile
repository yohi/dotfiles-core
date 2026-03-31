# dotfiles-core: Orchestrator Makefile
SHELL := /bin/bash

COMPONENTS_DIR := components
REPOS_YAML := repos.yaml
REPOS_YAML_RESOLVED := .repos.resolved.yaml
STOW_TARGET := $(HOME)

# Path for storing Bitwarden session key (outside repository)
BW_SESSION_FILE ?= $(shell echo $${XDG_RUNTIME_DIR:-$$HOME/.cache}/bw_session)

# Timezone for non-interactive setup
TZ_OVERRIDE ?= Asia/Tokyo

# Colors
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

# Standard help and core rules (direct inclusion in root)
include common-mk/help.mk

# Reusable macro to dispatch a target to all components
define dispatch
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		if [ -f "$(BW_SESSION_FILE)" ]; then export BW_SESSION=$$(cat "$(BW_SESSION_FILE)"); fi; \
		fail_count=0; \
		total_count=0; \
		for dir in "$(COMPONENTS_DIR)"/*; do \
			if [ -d "$$dir" ] && [ -f "$$dir/Makefile" ]; then \
				err_out=$$( ( cd "$$dir" && $(LOAD_ENV) && $(MAKE) -n $(1) ) 2>&1 >/dev/null ); \
				ret=$$?; \
				if [ $$ret -ne 0 ] && ! echo "$$err_out" | grep -iqe "No rule to make target" -e "を make するルールがありません"; then \
					echo -e "$(RED)[ERROR] Target detection failed in $$dir:$(NC)" >&2; \
					echo "$$err_out" | sed 's/^/  /' >&2; \
					fail_count=$$((fail_count+1)); \
					continue; \
				fi; \
				if [ $$ret -eq 0 ]; then \
					total_count=$$((total_count+1)); \
					echo -e "$(BLUE)==> Running make $(1) in $$dir...$(NC)"; \
					if ! ( cd "$$dir" && $(LOAD_ENV) && $(MAKE) $(1) ); then \
						echo -e "$(RED)[ERROR] make $(1) failed in $$dir$(NC)" >&2; \
						fail_count=$$((fail_count+1)); \
					else \
						echo -e "$(GREEN)[SUCCESS] make $(1) completed in $$dir$(NC)"; \
					fi; \
				else \
					echo -e "$(YELLOW)[SKIP] $$dir (no $(1) target)$(NC)"; \
				fi; \
			fi; \
		done; \
		echo "---"; \
		if [ $$fail_count -gt 0 ]; then \
			echo -e "$(RED)Summary for $(1): $$total_count attempted, $$fail_count failures.$(NC)"; \
			exit 1; \
		else \
			echo -e "$(GREEN)Summary for $(1): $$total_count attempted, all succeeded.$(NC)"; \
		fi; \
	fi
endef

# Load .env file and export variables, handling potential parsing errors safely without eval
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
			echo "[ERROR] Failed to parse .env in $$(pwd): invalid format" >&2; \
			exit 1; \
		fi; \
	done < .env; \
fi

.PHONY: init sync status diff secrets setup all clean test .clean-safety _inject_common_mk _check_bw_tools _ensure_bw_auth _unlock_bw _skip_secrets

all: ## すべてのコンポーネントの全行程（インストール・セットアップ）を実行します
	$(call dispatch,all)

init: $(REPOS_YAML_RESOLVED) ## 依存関係のインストールとリポジトリのクローンを行います
	@echo -e "$(BLUE)==> Initializing dependencies...$(NC)"
	@if command -v apt-get >/dev/null 2>&1; then \
		SUDO=$$(command -v sudo || true); \
		$$SUDO DEBIAN_FRONTEND=noninteractive apt-get update && $$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata python3-pip jq curl git openssh-client ca-certificates python3-setuptools; \
		if [ ! -e "/usr/share/zoneinfo/$(TZ_OVERRIDE)" ]; then \
			echo -e "$(RED)[ERROR] Timezone '$(TZ_OVERRIDE)' not found in /usr/share/zoneinfo/$(NC)" >&2; \
			exit 1; \
		fi; \
		$$SUDO ln -fs /usr/share/zoneinfo/$(TZ_OVERRIDE) /etc/localtime || { \
			echo -e "$(RED)[ERROR] Failed to set /etc/localtime to $(TZ_OVERRIDE)$(NC)" >&2; \
			exit 1; \
		}; \
	fi
	@if ! command -v vcs >/dev/null 2>&1; then \
		SUDO=$$(command -v sudo || true); \
		$$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y vcstool 2>/dev/null || pip3 install --user vcstool --break-system-packages || { echo -e "$(RED)ERROR: failed to install vcstool$(NC)" >&2; exit 1; }; \
	fi
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML_RESOLVED)

sync: init $(REPOS_YAML_RESOLVED) ## コンポーネントのソースコードを最新化します
	@echo -e "$(BLUE)==> Syncing all components...$(NC)"
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML_RESOLVED)
	PATH="$(HOME)/.local/bin:$$PATH" vcs pull $(COMPONENTS_DIR)

status: ## すべてのコンポーネントのGitステータスを確認します
	@echo -e "$(BLUE)==> Checking status of all components...$(NC)"
	@PATH="$(HOME)/.local/bin:$$PATH" vcs status $(COMPONENTS_DIR)

diff: ## すべてのコンポーネントのGit差分を確認します
	@echo -e "$(BLUE)==> Checking diff of all components...$(NC)"
	@PATH="$(HOME)/.local/bin:$$PATH" vcs diff $(COMPONENTS_DIR)

_inject_common_mk:
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
	        echo -e "$(BLUE)==> Injecting common-mk into components...$(NC)"; \
	        for dir in "$(COMPONENTS_DIR)"/*; do \
	                if [ -d "$$dir" ] && [ -f "$$dir/Makefile" ]; then \
	                        mkdir -p "$$dir/_mk"; \
	                        ln -sf ../../../common-mk/idempotency.mk "$$dir/_mk/idempotency.mk"; \
	                        ln -sf ../../../common-mk/help.mk "$$dir/_mk/help.mk"; \
	                        ln -sf ../../../common-mk/core.mk "$$dir/_mk/core.mk"; \
	                        ln -sf ../../common-mk/DOTFILES_COMMON_RULES.md "$$dir/DOTFILES_COMMON_RULES.md"; \
	                fi; \
	        done; \
        fi

secrets: init $(SECRETS_DEPS) ## Bitwardenからシークレット情報を取得します

setup: sync secrets _inject_common_mk ## すべてのコンポーネントのセットアップ（設定適用）を実行します
	@echo -e "$(BLUE)==> Delegating to component-specific setup...$(NC)"
	$(call dispatch,setup)
	@echo -e "$(GREEN)==> Setup Complete!$(NC)"

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
