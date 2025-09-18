#!/bin/bash

# sqlpack install - Minimal install helper
# Detects OS, checks for missing tools, prints or executes install commands.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./log-common.sh
source "$SCRIPT_DIR/log-common.sh"
# Import doctor helpers without running its main/side effects
# shellcheck source=./doctor.sh
DOCTOR_LIBRARY_MODE=1 source "$SCRIPT_DIR/doctor.sh"

# Default: show useful output
BASH_LOG="${BASH_LOG:-info}"

show_usage() {
    cat << EOF
SQLPack Install Helper

USAGE:
    $(basename "$0") [--execute] [--help]

DESCRIPTION:
    Prints (default) or executes the required OS-specific commands to install
    missing dependencies: mssql-tools18 (sqlcmd, bcp), PowerShell (pwsh), and
    the dbatools PowerShell module.

OPTIONS:
    --execute   Run the printed commands in order
    --help      Show this help message

EXIT CODES:
    0 - Success (printed or executed)
    1 - Unsupported OS or execution failure
    2 - Usage error
EOF
}

detect_os() {
    local uname_out os="unsupported"
    uname_out=$(uname -s 2>/dev/null || echo unknown)
    case "$uname_out" in
        Darwin)
            os="macos" ;;
        Linux)
            if [[ -r /etc/os-release ]]; then
                # shellcheck disable=SC1091
                . /etc/os-release
                # Prefer ID_LIKE for derivatives (ubuntu, debian)
                if echo "${ID_LIKE:-$ID}" | tr '[:upper:]' '[:lower:]' | grep -Eq '(debian|ubuntu)'; then
                    os="debian"
                fi
            fi
            ;;
    esac
    echo "$os"
}

# Determine which components are available (HAVE_* = 1 present, 0 missing)
HAVE_MSSQL_TOOLS=1
HAVE_PWSH=1
HAVE_DBATOOLS=1

check_missing_tools() {
    # Reset defaults assuming present; mark missing on failure
    HAVE_MSSQL_TOOLS=1
    HAVE_PWSH=1
    HAVE_DBATOOLS=1

    if ! check_cmd sqlcmd; then HAVE_MSSQL_TOOLS=0; fi
    if ! check_cmd bcp; then HAVE_MSSQL_TOOLS=0; fi
    if ! check_cmd pwsh; then HAVE_PWSH=0; fi
    if ! check_dbatools; then HAVE_DBATOOLS=0; fi
}

# Build list of commands to install missing components for the detected OS
build_commands() {
    local os="$1"
    local -a cmds=()

    case "$os" in
        macos)
            if [[ $HAVE_MSSQL_TOOLS -eq 0 ]]; then
                cmds+=("brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release")
                cmds+=("ACCEPT_EULA=Y brew install msodbcsql18 mssql-tools18")
            fi
            if [[ $HAVE_PWSH -eq 0 ]]; then
                cmds+=("brew install --cask powershell")
            fi
            if [[ $HAVE_DBATOOLS -eq 0 ]]; then
                cmds+=("pwsh -NoLogo -NoProfile -Command \"Install-Module dbatools -Scope CurrentUser -Force\"")
            fi
            ;;
        debian)
            if [[ $HAVE_MSSQL_TOOLS -eq 0 || $HAVE_PWSH -eq 0 ]]; then
                cmds+=("sudo apt-get update")
            fi
            if [[ $HAVE_MSSQL_TOOLS -eq 0 ]]; then
                cmds+=("sudo apt-get install -y msodbcsql18 mssql-tools18")
            fi
            if [[ $HAVE_PWSH -eq 0 ]]; then
                cmds+=("sudo apt-get install -y powershell")
            fi
            if [[ $HAVE_DBATOOLS -eq 0 ]]; then
                cmds+=("pwsh -NoLogo -NoProfile -Command \"Install-Module dbatools -Scope CurrentUser -Force\"")
            fi
            ;;
        *) ;;
    esac

    printf '%s\n' "${cmds[@]}"
}

execute_commands_stream() {
    local i=0
    # Read commands line-by-line and execute; avoid arrays for portability
    while IFS= read -r c; do
        # Skip empty lines defensively
        [[ -z "$c" ]] && continue
        i=$((i+1))
        log_trace "Running [$i]: $c"
        # Run via bash -lc to support inner quoted commands
        if ! bash -lc "$c"; then
            log_error "Command failed: $c"
            return 1
        fi
    done
}

main() {
    local do_execute=false
    if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
        show_usage
        exit 0
    elif [[ $# -eq 0 ]]; then
        do_execute=false
    elif [[ $# -eq 1 && ${1:-} == "--execute" ]]; then
        do_execute=true
    else
        show_usage
        exit 2
    fi

    log_section "SQLPack Install"
    local os
    os=$(detect_os)
    if [[ $os == "unsupported" ]]; then
        log_error "Unsupported OS. Only macOS and Ubuntu/Debian are supported."
        exit 1
    fi
    log_info "Detected OS: $os"

    check_missing_tools

    if [[ $HAVE_MSSQL_TOOLS -eq 1 && $HAVE_PWSH -eq 1 && $HAVE_DBATOOLS -eq 1 ]]; then
        log_success "All required tools are present. Nothing to install."
        exit 0
    fi

    # Show commands
    log_section "Install Commands (${os})"
    build_commands "$os"

    if [[ $do_execute == true ]]; then
        log_info "Executing install commands..."
        if ! build_commands "$os" | execute_commands_stream; then
            log_error "One or more install commands failed."
            exit 1
        fi
        log_success "Install commands completed. Re-run 'sqlpack doctor' to verify."
    else
        log_info "Preview only. Run with --execute to apply."
    fi
}

main "$@"

