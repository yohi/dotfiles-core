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

init:
	@echo "==> Initializing dependencies..."
	sudo apt-get update && sudo apt-get install -y python3-pip stow jq curl
	pip3 install --user vcstool
	mkdir -p $(COMPONENTS_DIR)
	vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)

sync:
	@echo "==> Syncing all components..."
	vcs import $(COMPONENTS_DIR) < $(REPOS_YAML)
	vcs pull $(COMPONENTS_DIR)

link:
	@echo "==> Linking components with GNU Stow..."
	@for dir in $(shell find $(COMPONENTS_DIR) -maxdepth 1 -mindepth 1 -type d); do 
		name=$$(basename $$dir); 
		echo "Stowing $$name..."; 
		stow --restow --target=$(STOW_TARGET) --dir=$(COMPONENTS_DIR) $$name; 
	done

secrets:
	@echo "==> Resolving secrets via Bitwarden CLI..."
	# ここに bw login / unlock などのロジックを実装予定
	@if ! command -v bw > /dev/null; then 
		echo "Bitwarden CLI (bw) not found. Please install it."; 
	fi

setup: init sync secrets link
	@echo "==> Delegating to component-specific setup..."
	@for dir in $(shell find $(COMPONENTS_DIR) -maxdepth 1 -mindepth 1 -type d); do 
		if [ -f "$$dir/Makefile" ]; then 
			echo "Found Makefile in $$dir, checking for setup target..."; 
			if grep -q "^setup:" "$$dir/Makefile"; then 
				$(MAKE) -C "$$dir" setup; 
			fi; 
		fi; 
	done
	@echo "==> Setup Complete!"

clean:
	@echo "==> Cleaning up components (CAUTION)..."
	rm -rf $(COMPONENTS_DIR)/*
