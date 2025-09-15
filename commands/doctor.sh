#!/bin/bash

# sqlpack doctor
# Checks for presence of required tools: pwsh, dbatools, sqlcmd, bcp

# Resolve script dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    cat << EOF
SQLPack Doctor

USAGE:
    $(basename "$0") [--help]

DESCRIPTION:
    Verifies the presence of required tools for SQLPack workflows.
    Checks for: pwsh, dbatools (PowerShell module), sqlcmd, and bcp.

EXIT CODES:
    0 - All required tools found
    1 - One or more tools missing
EOF
}

check_cmd() {
    local name="$1" path
    log_debug "Checking for command: $name"
    path=$(command -v "$name" 2>/dev/null)
    if [[ -n "$path" ]]; then
        log_success "$name: found ($path)"
        log_trace "Command check: command -v $name -> $path"
        return 0
    else
        log_error "$name: NOT found on PATH"
        log_trace "Command check: command -v $name -> not found"
        return 1
    fi
}

check_dbatools() {
    log_debug "Checking dbatools PowerShell module"
    # Requires pwsh
    if ! command -v pwsh >/dev/null 2>&1; then
        log_error "dbatools: cannot check (pwsh not found)"
        return 1
    fi

    # Try to import dbatools quietly; suppress any shell abort noise
    local ps_cmd rc=0
    ps_cmd='try { Import-Module dbatools -ErrorAction Stop; $true } catch { $false }'
    log_trace "PowerShell command: pwsh -NoLogo -NoProfile -Command \"$ps_cmd\""

    # Run in subshell with trap to catch SIGABRT and convert to exit code
    # Use an inner bash -c so any abort message is emitted by the inner shell
    (
        trap 'exit 134' ABRT  # Convert SIGABRT to exit code 134
        bash -c 'pwsh -NoLogo -NoProfile -Command "$1"' _ "$ps_cmd"
    ) >/dev/null 2>&1 || rc=$?

    log_trace "PowerShell command exit code: $rc"
    if [[ $rc -eq 0 ]]; then
        log_success "dbatools: importable in PowerShell"
        return 0
    else
        log_error "dbatools: NOT importable. Install the dbatools module."
        log_info "See: https://docs.dbatools.io/"
        return 1
    fi
}

main() {
    if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
        show_usage
        exit 0
    fi

    log_section "SQLPack Doctor"

    local failures=0

    # sqlcmd
    if ! check_cmd "sqlcmd"; then
        failures=$((failures+1))
    fi

    # bcp
    if ! check_cmd "bcp"; then
        failures=$((failures+1))
    fi

    # pwsh
    if ! check_cmd "pwsh"; then
        failures=$((failures+1))
    fi

    # dbatools module
    if ! check_dbatools; then
        failures=$((failures+1))
    fi

    log_summary
    if [[ $failures -eq 0 ]]; then
        log_success "All required tools are present."
        exit 0
    else
        log_error "$failures check(s) failed. Please install missing tools."
        exit 1
    fi
}

# Gate side effects behind library mode check
if [ -z "${DOCTOR_LIBRARY_MODE:-}" ]; then
    set -euo pipefail
    # shellcheck source=./log-common.sh
    source "$SCRIPT_DIR/log-common.sh"
    # Default to info level for doctor command (diagnostic output should be visible)
    BASH_LOG="${BASH_LOG:-info}"
    main "$@"
fi
