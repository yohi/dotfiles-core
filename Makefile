# dotfiles-core: Orchestrator Makefile
SHELL := /bin/bash

COMPONENTS_DIR := components
REPOS_YAML := repos.yaml
STOW_TARGET := $(HOME)

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
	sudo apt-get update && sudo apt-get install -y python3-pip jq curl vcstool python3-setuptools
	# vcstool should already be available via apt; installing via pip3 only as fallback or if specifically needed
	# Note: Ubuntu 24.10+ uses PEP 668. Use --break-system-packages or venv if pip is necessary.
	mkdir -p $(COMPONENTS_DIR)
	# PATH inclusion for potential local installs
	export PATH="$(HOME)/.local/bin:$$PATH"; \
	vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)

sync:
	@echo "==> Syncing all components..."
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)
	PATH="$(HOME)/.local/bin:$$PATH" vcs pull $(COMPONENTS_DIR)

link:
	@echo "==> Delegating link to components..."
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		[ -f .bw_session ] && export BW_SESSION=$$(cat .bw_session); \
		fail_count=0; \
		total_count=0; \
		while IFS= read -r -d '' dir; do \
			if [ -f "$$dir/Makefile" ]; then \
				if $(MAKE) -C "$$dir" -n link >/dev/null 2>&1; then \
					total_count=$$((total_count+1)); \
					echo "Running make link in $$dir..."; \
					if ! $(MAKE) -C "$$dir" link; then \
						echo "WARNING: make link failed in $$dir" >&2; \
						fail_count=$$((fail_count+1)); \
					fi; \
				else \
					echo "Skipping $$dir (no link target)"; \
				fi; \
			fi; \
		done < <(find "$(COMPONENTS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0); \
		echo "---"; \
		echo "Summary: $$total_count components attempted, $$fail_count failures."; \
		if [ $$fail_count -gt 0 ]; then exit 1; fi; \
	fi

secrets:
	@echo "==> Resolving secrets via Bitwarden CLI..."
	@if [ "$${WITH_BW:-0}" != "1" ]; then \
		echo "[SKIP] Bitwarden integration is disabled. Set WITH_BW=1 to enable." >&2; \
		exit 0; \
	fi; \
	if ! command -v bw > /dev/null; then \
		echo "Bitwarden CLI (bw) not found. Please install it." >&2; \
		exit 1; \
	fi; \
	if ! command -v jq > /dev/null; then \
		echo "jq is required to parse Bitwarden status. Please install it." >&2; \
		exit 1; \
	fi; \
	status=$$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error"); \
	if [ "$$status" = "unauthenticated" ]; then \
		echo "==> Authenticating Bitwarden..." >&2; \
		bw login; \
		status=$$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "error"); \
	fi; \
	if [ "$$status" = "locked" ]; then \
		echo "==> Unlocking Bitwarden vault..." >&2; \
		session=$$(bw unlock --raw); \
		if [ -n "$$session" ]; then \
			echo "$$session" > .bw_session; \
			chmod 600 .bw_session; \
			echo "[OK] Vault unlocked. Session saved to .bw_session"; \
		else \
			echo "[ERROR] Failed to unlock Bitwarden vault." >&2; \
			exit 1; \
		fi; \
	elif [ "$$status" = "unlocked" ]; then \
		echo "[OK] Bitwarden vault is already unlocked."; \
		if [ -n "$$BW_SESSION" ]; then \
			echo "$$BW_SESSION" > .bw_session; \
			chmod 600 .bw_session; \
		fi; \
	else \
		echo "[ERROR] Bitwarden status error: $$status" >&2; \
		exit 1; \
	fi

setup: init sync secrets link
	@echo "==> Delegating to component-specific setup..."
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		[ -f .bw_session ] && export BW_SESSION=$$(cat .bw_session); \
		fail_count=0; \
		total_count=0; \
		while IFS= read -r -d '' dir; do \
			if [ -f "$$dir/Makefile" ]; then \
				if $(MAKE) -C "$$dir" -n setup >/dev/null 2>&1; then \
					total_count=$$((total_count+1)); \
					echo "Running make setup in $$dir..."; \
					if ! $(MAKE) -C "$$dir" setup; then \
						echo "WARNING: make setup failed in $$dir" >&2; \
						fail_count=$$((fail_count+1)); \
					fi; \
				else \
					echo "Skipping $$dir (no setup target)"; \
				fi; \
			fi; \
		done < <(find "$(COMPONENTS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0); \
		echo "---"; \
		echo "Summary: $$total_count components attempted, $$fail_count failures."; \
		if [ $$fail_count -gt 0 ]; then exit 1; fi; \
	fi
	@echo "==> Setup Complete!"

clean:
	@echo "==> Cleaning up components (CAUTION)..."
	@if [ -z "$(COMPONENTS_DIR)" ] || [ "$(COMPONENTS_DIR)" = "/" ] || [ "$(COMPONENTS_DIR)" = "." ] || [ "$(COMPONENTS_DIR)" = ".." ]; then \
		echo "ERROR: unsafe COMPONENTS_DIR='$(COMPONENTS_DIR)'"; \
		exit 1; \
	elif [ ! -d "$(COMPONENTS_DIR)" ]; then \
		echo "==> Skip clean: directory '$(COMPONENTS_DIR)' not found."; \
	else \
		rm -rf "$(COMPONENTS_DIR)"/*; \
	fi
