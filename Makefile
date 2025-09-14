.PHONY: all clean lint test install uninstall help

SHELL := /bin/bash

# Define all scripts to lint
MAIN_SCRIPT := sqlpack
COMMAND_SCRIPTS := $(wildcard commands/*.sh)
ALL_SCRIPTS := $(MAIN_SCRIPT) $(COMMAND_SCRIPTS)

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib

all: lint test

help:
	@echo "Targets:"
	@echo "  all       - Run lint and test"
	@echo "  clean     - Remove generated files"
	@echo "  install   - Install sqlpack to $(BINDIR) (may need sudo)"
	@echo "  uninstall - Remove sqlpack from $(BINDIR) (may need sudo)"
	@echo "  lint      - Run shellcheck on all scripts (if installed)"
	@echo "  test      - Run bats tests in tests/ (if installed)"

clean:
	rm -f db-dump.tar.gz
	rm -rf db-export/

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck -x $(MAIN_SCRIPT); \
		(cd commands && shellcheck -x *.sh); \
	else \
		echo "shellcheck not found; skipping lint. Install: https://www.shellcheck.net/"; \
	fi

install:
	@echo "Installing sqlpack to $(BINDIR)..."
	install -d $(BINDIR)
	install -d $(LIBDIR)/sqlpack/commands
	install -m 755 sqlpack $(BINDIR)/sqlpack
	for script in $(COMMAND_SCRIPTS); do \
		install -m 755 "$$script" $(LIBDIR)/sqlpack/commands/; \
	done
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
