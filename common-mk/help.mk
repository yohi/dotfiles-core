.PHONY: help
help: ## 利用可能なターゲットの一覧を表示します
	@echo "使用法: make [ターゲット]"
	@echo ""
	@echo "ターゲット:"
	@grep -Eh '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'
