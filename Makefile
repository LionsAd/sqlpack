.PHONY: lint test install uninstall help

SHELL := /bin/bash

SCRIPTS := $(wildcard *.sh)
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib

help:
	@echo "Targets:"
	@echo "  install   - Install sqlpack to $(BINDIR) (may need sudo)"
	@echo "  uninstall - Remove sqlpack from $(BINDIR) (may need sudo)"
	@echo "  lint      - Run shellcheck on *.sh (if installed)"
	@echo "  test      - Run bats tests in tests/ (if installed)"

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck -x $(SCRIPTS); \
	else \
		echo "shellcheck not found; skipping lint. Install: https://www.shellcheck.net/"; \
	fi

install:
	@echo "Installing sqlpack to $(BINDIR)..."
	install -d $(BINDIR)
	install -m 755 sqlpack $(BINDIR)/sqlpack
	install -d $(LIBDIR)/sqlpack
	cp -r commands $(LIBDIR)/sqlpack/
	@echo "SQLPack installed successfully!"
	@echo "Run 'sqlpack help' to get started."

uninstall:
	@echo "Removing sqlpack from $(BINDIR)..."
	rm -f $(BINDIR)/sqlpack
	rm -rf $(LIBDIR)/sqlpack
	@echo "SQLPack uninstalled successfully!"

test:
	@if command -v bats >/dev/null 2>&1; then \
		echo "Running bats tests..."; \
		bats -r tests; \
	else \
		echo "bats not found; skipping tests. Install: https://bats-core.readthedocs.io/"; \
	fi
