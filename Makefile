.PHONY: help test test-kueue test-shared lint

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "%-20s %s\n", $$1, $$2}'

test: ## Run all sentinel tests
	pytest sentinels/

test-kueue: ## Run Kueue sentinel shell tests
	bash sentinels/kueue/tests/test_sentinel_notify.sh

test-shared: ## Run shared utility tests
	pytest sentinels/shared/tests/

lint: ## Lint GitHub workflow YAML files
	yamllint .github/workflows/
