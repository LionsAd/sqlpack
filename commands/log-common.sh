#!/bin/bash

# Common Logging Functions for Database Export Scripts
# Inspired by Rust's env_logger - configurable via BASH_LOG environment variable
#
# Log Levels (in order of verbosity):
#   error  - Only errors (default)
#   warn   - Warnings and errors
#   info   - Info, warnings, and errors
#   debug  - Debug, info, warnings, and errors
#   trace  - All output including command execution
#
# Usage:
#   BASH_LOG=info ./export.sh
#   BASH_LOG=debug ./export-data.sh
#
# Optional features:
#   BASH_LOG_TIMESTAMP=true  - Add timestamps to log messages

# Default log level
LOG_LEVEL="${BASH_LOG:-error}"
LOG_TIMESTAMP="${BASH_LOG_TIMESTAMP:-false}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;37m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Convert log level name to number
level_to_number() {
    local level
    level=$(echo "$1" | tr '[:upper:]' '[:lower:]') # Convert to lowercase
    case "$level" in
        error) echo 1 ;;
        warn) echo 2 ;;
        info) echo 3 ;;
        debug) echo 4 ;;
        trace) echo 5 ;;
        *) echo 1 ;; # Default to error level
    esac
}

# Get current configured log level number
get_log_level() {
    level_to_number "$LOG_LEVEL"
}

# Get timestamp if enabled
get_timestamp() {
    if [[ "$LOG_TIMESTAMP" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] "
    fi
}

# Internal logging function
_log() {
    local level="$1"
    local color="$2"
    local prefix="$3"
    local message="$4"

    # Get minimum level required for this log type and current configured level
    local min_level
    min_level=$(level_to_number "$level")
    local current_level
    current_level=$(get_log_level)

    # Only show this message if current level is >= minimum required level
    if [[ $current_level -ge $min_level ]]; then
        local timestamp
        timestamp=$(get_timestamp)
        # Errors go to stderr, everything else to stdout
        if [[ "$level" == "error" ]]; then
            echo -e "${timestamp}${color}${prefix} ${message}${NC}" >&2
        else
            echo -e "${timestamp}${color}${prefix} ${message}${NC}"
        fi
    fi
}

# Public logging functions
log_error() {
    _log "error" "$RED" "✗ [ERROR]" "$*"
}

log_warn() {
    _log "warn" "$YELLOW" "⚠ [WARN]" "$*"
}

log_info() {
    _log "info" "$BLUE" "[INFO]" "$*"
}

log_success() {
    _log "info" "$GREEN" "✓" "$*"
}

log_debug() {
    # Get calling function name for debug logs
    local caller="${FUNCNAME[2]:-main}"
    _log "debug" "$GRAY" "[DEBUG:$caller]" "$*"
}

log_trace() {
    local caller="${FUNCNAME[2]:-main}"
    _log "trace" "$PURPLE" "[TRACE:$caller]" "$*"
}

# Special function for command execution with logging
log_exec() {
    local description="$1"
    shift
    local cmd=("$@")

    log_trace "Executing: ${cmd[*]}"

    if [[ $(get_log_level) -ge 5 ]]; then
        # At trace level, show command output
        log_debug "Running: $description"
        "${cmd[@]}"
    else
        # At other levels, suppress command output
        "${cmd[@]}" >/dev/null 2>&1
    fi
}

# Convenience functions for sections (like the current === headers ===)
log_section() {
    log_info ""
    log_info "=== $* ==="
}

log_subsection() {
    log_info "--- $* ---"
}

# Summary functions
log_summary() {
    log_info ""
    log_info "=== SUMMARY ==="
}

# Backward compatibility wrapper functions
# These maintain the existing function names used in the scripts
print_info() {
    log_info "$*"
}

print_success() {
    log_success "$*"
}

print_warning() {
    log_warn "$*"
}

print_error() {
    log_error "$*"
}

print_debug() {
    log_debug "$*"
}

# Export functions for use by other scripts
export -f log_error log_warn log_info log_success log_debug log_trace
export -f log_exec log_section log_subsection log_summary
export -f print_info print_success print_warning print_error print_debug
export -f get_log_level get_timestamp

# Print logging configuration if debug level or higher
if [[ $(get_log_level) -ge 4 ]]; then
    log_debug "Logging initialized - Level: $LOG_LEVEL ($(get_log_level)), Timestamp: $LOG_TIMESTAMP"
fi