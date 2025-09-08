#!/bin/bash

# run-sqlcmd.sh - Wrapper for sqlcmd with proper error detection
# Usage: run-sqlcmd.sh [sqlcmd arguments...]
#
# Exit codes:
#   0 - Success (no output)
#   1 - Fatal error (sqlcmd failed)
#   2 - Warning (sqlcmd succeeded but produced output)

set -euo pipefail

# Create temporary file for output
TMP_OUTPUT=$(mktemp)
trap 'rm -f "$TMP_OUTPUT"' EXIT

# Run sqlcmd and capture both stdout and stderr
if sqlcmd "$@" > "$TMP_OUTPUT" 2>&1; then
    # sqlcmd succeeded - check if there's any output
    if [[ -s "$TMP_OUTPUT" ]]; then
        # Output exists - this indicates warnings/messages
        cat "$TMP_OUTPUT"  # Show the output
        exit 2  # Warning exit code
    else
        # No output - clean success
        exit 0
    fi
else
    # sqlcmd failed - show output and exit with error
    cat "$TMP_OUTPUT"  # Show the error output
    exit 1  # Fatal error exit code
fi