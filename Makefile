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
	sudo apt-get update && sudo apt-get install -y python3-pip jq curl
	pip3 install --user vcstool
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)

sync:
	@echo "==> Syncing all components..."
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)
	PATH="$(HOME)/.local/bin:$$PATH" vcs pull $(COMPONENTS_DIR)

link:
	@echo "==> Delegating link to components..."
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		find "$(COMPONENTS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do \
			if [ -f "$$dir/Makefile" ]; then \
				if $(MAKE) -C "$$dir" -n link >/dev/null 2>&1; then \
					echo "Running make link in $$dir..."; \
					$(MAKE) -C "$$dir" link || true; \
				else \
					echo "Skipping $$dir (no link target)"; \
				fi; \
			fi; \
		done; \
	fi

secrets:
	@echo "==> Resolving secrets via Bitwarden CLI..."
	# ここに bw login / unlock などのロジックを実装予定
	@if ! command -v bw > /dev/null; then \
		echo "Bitwarden CLI (bw) not found. Please install it." >&2; \
		exit 1; \
	fi

setup: init sync secrets link
	@echo "==> Delegating to component-specific setup..."
	@if [ -d "$(COMPONENTS_DIR)" ]; then \
		find "$(COMPONENTS_DIR)" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do \
			if [ -f "$$dir/Makefile" ]; then \
				if $(MAKE) -C "$$dir" -n setup >/dev/null 2>&1; then \
					echo "Running make setup in $$dir..."; \
					$(MAKE) -C "$$dir" setup || true; \
				else \
					echo "Skipping $$dir (no setup target)"; \
				fi; \
			fi; \
		done; \
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
