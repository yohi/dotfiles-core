# dotfiles-core: Orchestrator Makefile

COMPONENTS_DIR := components
REPOS_YAML := repos.yaml
STOW_TARGET := $(HOME)

.PHONY: help init sync link secrets setup clean

help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  init     Install dependencies (vcstool, stow, jq) and clone repos"
	@echo "  sync     Update all components using vcstool"
	@echo "  link     Apply symbolic links using GNU Stow"
	@echo "  secrets  Fetch credentials from Bitwarden"
	@echo "  setup    Run full setup sequence including component delegation"
	@echo "  clean    Remove generated files and reset state"

init:
	@echo "==> Initializing dependencies..."
	sudo apt-get update && sudo apt-get install -y python3-pip stow jq curl
	pip3 install --user vcstool
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)

sync:
	@echo "==> Syncing all components..."
	mkdir -p $(COMPONENTS_DIR)
	PATH="$(HOME)/.local/bin:$$PATH" vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)
	PATH="$(HOME)/.local/bin:$$PATH" vcs pull $(COMPONENTS_DIR)

link:
	@echo "==> Linking components with GNU Stow..."
	@for dir in $(COMPONENTS_DIR)/*; do \
		[ -d "$$dir" ] || continue; \
		name=$$(basename "$$dir"); \
		echo "Stowing $$name..."; \
		stow --restow --target=$(STOW_TARGET) --dir=$(COMPONENTS_DIR) "$$name"; \
	done

secrets:
	@echo "==> Resolving secrets via Bitwarden CLI..."
	# ここに bw login / unlock などのロジックを実装予定
	@if ! command -v bw > /dev/null; then \
		echo "Bitwarden CLI (bw) not found. Please install it." >&2; \
		exit 1; \
	fi

setup: init sync secrets link
	@echo "==> Delegating to component-specific setup..."
	@for dir in $$(find $(COMPONENTS_DIR) -maxdepth 1 -mindepth 1 -type d); do \
		if [ -f "$$dir/Makefile" ]; then \
			if $(MAKE) -C "$$dir" -n setup >/dev/null 2>&1; then \
				echo "Running make setup in $$dir..."; \
				$(MAKE) -C "$$dir" setup; \
			else \
				echo "Skipping $$dir (no setup target)"; \
			fi; \
		fi; \
	done
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
