# dotfiles-core: Orchestrator Makefile
SHELL := /bin/bash

COMPONENTS_DIR := components
REPOS_YAML := repos.yaml
STOW_TARGET := $(HOME)

# Reusable macro to dispatch a target to all components
define dispatch
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		if [ -f .bw_session ]; then export BW_SESSION=$$(cat .bw_session); fi; \
		fail_count=0; \
		total_count=0; \
		while IFS= read -r -d '' dir; do \
			if [ -f "$$dir/Makefile" ]; then \
				if $(MAKE) -C "$$dir" -n $(1) >/dev/null 2>&1; then \
					total_count=$$((total_count+1)); \
					echo "Running make $(1) in $$dir..."; \
					if ! $(MAKE) -C "$$dir" $(1); then \
						echo "WARNING: make $(1) failed in $$dir" >&2; \
						fail_count=$$((fail_count+1)); \
					fi; \
				else \
					echo "Skipping $$dir (no $(1) target)"; \
				fi; \
			fi; \
		done < <(find "$(COMPONENTS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0); \
		echo "---"; \
		echo "Summary for $(1): $$total_count components attempted, $$fail_count failures."; \
		if [ $$fail_count -gt 0 ]; then exit 1; fi; \
	fi
endef

.PHONY: help init sync link secrets setup clean

help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  init     Install dependencies (vcstool, jq, curl) and clone repos"
	@echo "  sync     Update all components using vcstool"
	@echo "  link     Apply symbolic links (delegated to components)"
	@echo "  secrets  Fetch credentials from Bitwarden"
	@echo "  setup    Run full setup sequence including component delegation"
	@echo "  clean    Remove generated files and reset state"

init:
	@echo "==> Initializing dependencies..."
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y python3-pip jq curl python3-setuptools; \
	fi
	@if ! command -v vcs >/dev/null 2>&1; then \
		sudo apt-get install -y vcstool 2>/dev/null || pip3 install --user vcstool || { echo "ERROR: failed to install vcstool" >&2; exit 1; }; \
	fi
	# Note: Ubuntu 24.10+ uses PEP 668. Use --break-system-packages or venv if pip is necessary.
	mkdir -p $(COMPONENTS_DIR)
	# PATH inclusion for potential local installs
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)

sync:
	@echo "==> Syncing all components..."
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)
	PATH="$(HOME)/.local/bin:$$PATH" vcs pull $(COMPONENTS_DIR)

link:
	@echo "==> Delegating link to components..."
	$(call dispatch,link)

secrets: _check_bw_tools _ensure_bw_auth _unlock_bw

_check_bw_tools:
	@if [ "$${WITH_BW:-0}" != "1" ]; then \
		echo "[SKIP] Bitwarden integration is disabled. Set WITH_BW=1 to enable." >&2; \
		exit 0; \
	fi
	@command -v bw >/dev/null 2>&1 || { echo "Bitwarden CLI (bw) not found." >&2; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo "jq not found." >&2; exit 1; }

_ensure_bw_auth:
	@echo "==> Verifying Bitwarden authentication..."
	@status_json=$$(bw status 2>/dev/null) || { echo "[ERROR] Bitwarden CLI 'bw status' failed." >&2; exit 1; }; \
	status=$$(echo "$$status_json" | jq -r '.status' 2>/dev/null || echo "error"); \
	if [ "$$status" = "error" ]; then \
		echo "[ERROR] Failed to parse Bitwarden status. Check your installation." >&2; \
		exit 1; \
	fi; \
	if [ "$$status" = "unauthenticated" ]; then \
		echo "==> Authenticating Bitwarden..." >&2; \
		bw login || { echo "[ERROR] Bitwarden login failed" >&2; exit 1; }; \
	fi

_unlock_bw:
	@status=$$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error"); \
	if [ "$$status" = "locked" ]; then \
		echo "==> Unlocking Bitwarden vault..." >&2; \
		session=$$(bw unlock --raw) || { echo "[ERROR] Bitwarden unlock failed or timed out." >&2; exit 1; }; \
		if [ -n "$$session" ]; then \
			echo "$$session" > .bw_session && chmod 600 .bw_session || { echo "[ERROR] Failed to save session" >&2; exit 1; }; \
			echo "[OK] Vault unlocked. Session saved to .bw_session"; \
		else \
			echo "[ERROR] Failed to obtain Bitwarden session key." >&2; exit 1; \
		fi; \
	elif [ "$$status" = "unlocked" ]; then \
		echo "[OK] Bitwarden vault is already unlocked."; \
		if [ -z "$$BW_SESSION" ]; then \
			echo "[WARN] BW_SESSION not set, obtaining session..."; \
			BW_SESSION=$$(bw unlock --raw) || { echo "[ERROR] failed to obtain BW_SESSION"; exit 1; }; \
		fi; \
		echo "$$BW_SESSION" > .bw_session && chmod 600 .bw_session || { echo "[ERROR] Failed to update session" >&2; exit 1; }; \
	fi

setup: init sync secrets
	@echo "==> Delegating to component-specific setup..."
	$(call dispatch,setup)
	@echo "==> Setup Complete!"

clean:
	@echo "==> Cleaning up components (CAUTION)..."
	@rm -f .bw_session
	@if [ -z "$(COMPONENTS_DIR)" ] || [ "$(COMPONENTS_DIR)" = "/" ] || [ "$(COMPONENTS_DIR)" = "." ] || [ "$(COMPONENTS_DIR)" = ".." ]; then \
		echo "ERROR: unsafe COMPONENTS_DIR='$(COMPONENTS_DIR)'"; \
		exit 1; \
	elif [ ! -d "$(COMPONENTS_DIR)" ]; then \
		echo "==> Skip clean: directory '$(COMPONENTS_DIR)' not found."; \
	else \
		rm -rf "$(COMPONENTS_DIR)"/*; \
	fi
