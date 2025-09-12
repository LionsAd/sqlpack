.PHONY: lint test help

SHELL := /bin/bash

SCRIPTS := $(wildcard *.sh)

help:
	@echo "Targets:"
	@echo "  lint  - Run shellcheck on *.sh (if installed)"
	@echo "  test  - Run bats tests in tests/ (if installed)"

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck -x $(SCRIPTS); \
	else \
		echo "shellcheck not found; skipping lint. Install: https://www.shellcheck.net/"; \
	fi

test:
	@if command -v bats >/dev/null 2>&1; then \
		echo "Running bats tests..."; \
		bats -r tests; \
	else \
		echo "bats not found; skipping tests. Install: https://bats-core.readthedocs.io/"; \
	fi
