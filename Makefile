# dotfiles-core: Orchestrator Makefile
SHELL := /bin/bash

COMPONENTS_DIR := components
REPOS_YAML := repos.yaml
REPOS_YAML_RESOLVED := .repos.resolved.yaml
STOW_TARGET := $(HOME)

# Path for storing Bitwarden session key (outside repository)
BW_SESSION_FILE ?= $(shell echo $${XDG_RUNTIME_DIR:-$$HOME/.cache}/bw_session)

# Colors
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[0;33m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

# Reusable macro to dispatch a target to all components
define dispatch
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		if [ -f "$(BW_SESSION_FILE)" ]; then export BW_SESSION=$$(cat "$(BW_SESSION_FILE)"); fi; \
		fail_count=0; \
		total_count=0; \
		while IFS= read -r -d '' dir; do \
			if [ -f "$$dir/Makefile" ]; then \
				if $(MAKE) -C "$$dir" -n $(1) >/dev/null 2>&1; then \
					total_count=$$((total_count+1)); \
					echo -e "$(BLUE)==> Running make $(1) in $$dir...$(NC)"; \
					if ! $(MAKE) -C "$$dir" $(1); then \
						echo -e "$(RED)[ERROR] make $(1) failed in $$dir$(NC)" >&2; \
						fail_count=$$((fail_count+1)); \
					else \
						echo -e "$(GREEN)[SUCCESS] make $(1) completed in $$dir$(NC)"; \
					fi; \
				else \
					echo -e "$(YELLOW)[SKIP] $$dir (no $(1) target)$(NC)"; \
				fi; \
			fi; \
		done < <(find "$(COMPONENTS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0); \
		echo "---"; \
		if [ $$fail_count -gt 0 ]; then \
			echo -e "$(RED)Summary for $(1): $$total_count attempted, $$fail_count failures.$(NC)"; \
			exit 1; \
		else \
			echo -e "$(GREEN)Summary for $(1): $$total_count attempted, all succeeded.$(NC)"; \
		fi; \
	fi
endef

.PHONY: help init sync link secrets setup clean test \
        _skip_secrets _check_bw_tools _ensure_bw_auth _unlock_bw _inject_common_mk _check_docker .clean-safety

help:
	@echo -e "$(BLUE)Usage: make [target]$(NC)"
	@echo "Targets:"
	@echo "  init     Install dependencies (vcstool, jq, curl) and clone repos"
	@echo "  sync     Update all components using vcstool"
	@echo "  link     Apply symbolic links (delegated to components)"
	@echo "  secrets  Fetch credentials from Bitwarden"
	@echo "  setup    Run full setup sequence including component delegation"
	@echo "  test     Run integration tests using Docker"
	@echo "  clean    Remove generated files and reset state"

SSH_CONNECT_TIMEOUT ?= 3

$(REPOS_YAML_RESOLVED): $(REPOS_YAML)
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

init: $(REPOS_YAML_RESOLVED)
	@echo -e "$(BLUE)==> Initializing dependencies...$(NC)"
	@if command -v apt-get >/dev/null 2>&1; then \
		SUDO=$$(command -v sudo || true); \
		$$SUDO ln -fs /usr/share/zoneinfo/Asia/Tokyo /etc/localtime; \
		$$SUDO DEBIAN_FRONTEND=noninteractive apt-get update && $$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip jq curl git openssh-client ca-certificates python3-setuptools; \
	fi
	@if ! command -v vcs >/dev/null 2>&1; then \
		SUDO=$$(command -v sudo || true); \
		$$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y vcstool 2>/dev/null || pip3 install --user vcstool --break-system-packages || { echo -e "$(RED)ERROR: failed to install vcstool$(NC)" >&2; exit 1; }; \
	fi
	# Note: Ubuntu 24.10+ uses PEP 668. Use --break-system-packages or venv if pip is necessary.
	mkdir -p $(COMPONENTS_DIR)
	# PATH inclusion for potential local installs
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML_RESOLVED)

sync: init $(REPOS_YAML_RESOLVED)
	@echo -e "$(BLUE)==> Syncing all components...$(NC)"
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML_RESOLVED)
	PATH="$(HOME)/.local/bin:$$PATH" vcs pull $(COMPONENTS_DIR)

_inject_common_mk:
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		echo -e "$(BLUE)==> Injecting common-mk into components...$(NC)"; \
		while IFS= read -r -d '' dir; do \
			if [ -f "$$dir/Makefile" ]; then \
				mkdir -p "$$dir/_mk"; \
				cp common-mk/idempotency.mk "$$dir/_mk/" || { \
					echo -e "$(RED)[ERROR] Failed to inject into $$dir$(NC)" >&2; \
					exit 1; \
				}; \
			fi; \
		done < <(find "$(COMPONENTS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0); \
	fi

link: _inject_common_mk
	@echo -e "$(BLUE)==> Delegating link to components...$(NC)"
	$(call dispatch,link)

ifeq ($(WITH_BW),1)
SECRETS_DEPS := _unlock_bw
else
SECRETS_DEPS := _skip_secrets
endif

secrets: init $(SECRETS_DEPS)

_skip_secrets:
	@echo -e "$(YELLOW)[SKIP] Bitwarden integration is disabled. Set WITH_BW=1 to enable.$(NC)"

_check_bw_tools: init
	@command -v bw >/dev/null 2>&1 || { echo -e "$(RED)Bitwarden CLI (bw) not found.$(NC)" >&2; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo -e "$(RED)jq not found.$(NC)" >&2; exit 1; }

_ensure_bw_auth: _check_bw_tools
	@echo -e "$(BLUE)==> Verifying Bitwarden authentication...$(NC)"
	@status_json=$$(bw status 2>/dev/null) || { echo -e "$(RED)[ERROR] Bitwarden CLI 'bw status' failed.$(NC)" >&2; exit 1; }; \
	status=$$(echo "$$status_json" | jq -r '.status' 2>/dev/null || echo "error"); \
	if [ "$$status" = "error" ]; then \
		echo -e "$(RED)[ERROR] Failed to parse Bitwarden status. Check your installation.$(NC)" >&2; \
		exit 1; \
	fi; \
	if [ "$$status" = "unauthenticated" ]; then \
		echo -e "$(YELLOW)==> Authenticating Bitwarden...$(NC)" >&2; \
		bw login || { echo -e "$(RED)[ERROR] Bitwarden login failed$(NC)" >&2; exit 1; }; \
	fi

_unlock_bw: _ensure_bw_auth
	@status=$$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error"); \
	if [ "$$status" = "locked" ]; then \
		echo -e "$(BLUE)==> Unlocking Bitwarden vault...$(NC)" >&2; \
		session=$$(bw unlock --raw) || { echo -e "$(RED)[ERROR] Bitwarden unlock failed or timed out.$(NC)" >&2; exit 1; }; \
		if [ -n "$$session" ]; then \
			mkdir -p "$$(dirname "$(BW_SESSION_FILE)")"; \
			echo "$$session" > "$(BW_SESSION_FILE)" && chmod 600 "$(BW_SESSION_FILE)" || { echo -e "$(RED)[ERROR] Failed to save session$(NC)" >&2; exit 1; }; \
			echo -e "$(GREEN)[OK] Vault unlocked. Session saved to $(BW_SESSION_FILE)$(NC)"; \
		else \
			echo -e "$(RED)[ERROR] Failed to obtain Bitwarden session key.$(NC)" >&2; exit 1; \
		fi; \
	elif [ "$$status" = "unlocked" ]; then \
		echo -e "$(GREEN)[OK] Bitwarden vault is already unlocked.$(NC)"; \
		if [ -z "$$BW_SESSION" ]; then \
			echo -e "$(YELLOW)[WARN] BW_SESSION not set, obtaining session...$(NC)"; \
			BW_SESSION=$$(bw unlock --raw) || { echo -e "$(RED)[ERROR] failed to obtain BW_SESSION$(NC)" >&2; exit 1; }; \
		fi; \
		mkdir -p "$$(dirname "$(BW_SESSION_FILE)")"; \
		echo "$$BW_SESSION" > "$(BW_SESSION_FILE)" && chmod 600 "$(BW_SESSION_FILE)" || { echo -e "$(RED)[ERROR] Failed to update session$(NC)" >&2; exit 1; }; \
	else \
		echo -e "$(RED)[ERROR] Unexpected Bitwarden status: $$status$(NC)" >&2; \
		exit 1; \
	fi

setup: sync secrets _inject_common_mk
	@echo -e "$(BLUE)==> Delegating to component-specific setup...$(NC)"
	$(call dispatch,setup)
	@echo -e "$(GREEN)==> Setup Complete!$(NC)"

_check_docker:
	@command -v docker >/dev/null 2>&1 || { echo -e "$(RED)[ERROR] Docker is not available on PATH.$(NC)" >&2; exit 1; }

test: _check_docker
	@echo -e "$(BLUE)==> Building test container...$(NC)"
	docker build -t dotfiles-core-test -f tests/Dockerfile.test .
	@echo -e "$(BLUE)==> Running tests...$(NC)"
	docker run --rm \
		--privileged \
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
