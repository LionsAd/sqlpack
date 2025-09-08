#!/bin/bash

# CI Database Export Wrapper
# Simple wrapper script for CI environments to export database

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Default configuration - override with environment variables
SQL_SERVER="${DB_SERVER:-localhost,1433}"
DATABASE="${DB_NAME:-}"
USERNAME="${DB_USERNAME:-}"
PASSWORD="${DB_PASSWORD:-}"
OUTPUT_DIR="${DB_EXPORT_DIR:-./db-export}"
ARCHIVE_NAME="${DB_ARCHIVE_NAME:-db-dump.tar.gz}"
DATA_ROW_LIMIT="${DB_ROW_LIMIT:-0}"

# Parse command line args (optional overrides)
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            SQL_SERVER="$2"
            shift 2
            ;;
        --database)
            DATABASE="$2"
            shift 2
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --archive-name)
            ARCHIVE_NAME="$2"
            shift 2
            ;;
        --row-limit)
            DATA_ROW_LIMIT="$2"
            shift 2
            ;;
        -h|--help)
            cat << EOF
CI Database Export Wrapper

USAGE:
    $0 [OPTIONS]

CONFIGURATION:
    Set via environment variables or command line options:

    DB_SERVER (--server)          SQL Server instance (default: localhost,1433)
    DB_NAME (--database)          Database name (REQUIRED)
    DB_USERNAME (--username)      SQL Server username (optional)
    DB_PASSWORD (--password)      SQL Server password (optional)
    DB_EXPORT_DIR (--output-dir)  Export directory (default: ./db-export)
    DB_ARCHIVE_NAME (--archive-name) Archive filename (default: db-dump.tar.gz)
    DB_ROW_LIMIT (--row-limit)    Max rows per table (default: 0=unlimited)

EXAMPLES:
    # Using environment variables
    export DB_SERVER="prod.server.com"
    export DB_NAME="MyApplication"
    export DB_USERNAME="backup_user"
    export DB_PASSWORD="secret123"
    $0

    # Using command line
    $0 --server "localhost,1499" --database "MyApp" --row-limit 50000

OUTPUTS:
    - {OUTPUT_DIR}/schema.sql      Complete database schema
    - {OUTPUT_DIR}/tables.txt      List of all tables
    - {OUTPUT_DIR}/data/*.csv      Table data files
    - {ARCHIVE_NAME}               Compressed archive ready for distribution
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$DATABASE" ]]; then
    print_error "Database name is required. Set DB_NAME environment variable or use --database option."
    exit 1
fi

print_info "Starting database export..."
print_info "Server: $SQL_SERVER"
print_info "Database: $DATABASE"
print_info "Output: $OUTPUT_DIR"
print_info "Archive: $ARCHIVE_NAME"

# Check if PowerShell is available
if ! command -v pwsh &> /dev/null && ! command -v powershell &> /dev/null; then
    print_error "PowerShell not found. Please install PowerShell Core (pwsh) or Windows PowerShell."
    print_info "Install PowerShell Core: https://github.com/PowerShell/PowerShell"
    exit 1
fi

# Determine PowerShell command
PWSH_CMD="pwsh"
if ! command -v pwsh &> /dev/null; then
    PWSH_CMD="powershell"
fi

print_success "Found PowerShell: $PWSH_CMD"

# Build PowerShell command
PS_SCRIPT="./export.ps1"
PS_ARGS=(
    "-SqlInstance" "$SQL_SERVER"
    "-Database" "$DATABASE"
    "-OutputPath" "$OUTPUT_DIR"
    "-TarFileName" "$ARCHIVE_NAME"
)

if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
    PS_ARGS+=("-Username" "$USERNAME" "-Password" "$PASSWORD")
fi

if [[ "$DATA_ROW_LIMIT" != "0" ]]; then
    PS_ARGS+=("-DataRowLimit" "$DATA_ROW_LIMIT")
fi

# Check if export script exists
if [[ ! -f "$PS_SCRIPT" ]]; then
    print_error "Export script not found: $PS_SCRIPT"
    print_info "Make sure export-database.ps1 is in the current directory."
    exit 1
fi

# Run the export
print_info "Executing PowerShell export script..."
print_info "Command: $PWSH_CMD $PS_SCRIPT ${PS_ARGS[*]}"

if "$PWSH_CMD" "$PS_SCRIPT" "${PS_ARGS[@]}"; then
    print_success "Database export completed successfully!"

    # Check if archive was created
    if [[ -f "$ARCHIVE_NAME" ]]; then
        ARCHIVE_SIZE=$(du -h "$ARCHIVE_NAME" | cut -f1)
        print_success "Archive created: $ARCHIVE_NAME ($ARCHIVE_SIZE)"

        # Set output for CI systems
        if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
            echo "archive_path=$ARCHIVE_NAME" >> "$GITHUB_OUTPUT"
            echo "archive_size=$ARCHIVE_SIZE" >> "$GITHUB_OUTPUT"
        fi

        if [[ -n "${CI:-}" ]]; then
            print_info "Archive artifact ready for CI pipeline"
        fi
    else
        print_warning "Archive file not found: $ARCHIVE_NAME"
        exit 1
    fi
else
    print_error "Database export failed!"
    exit 1
fi

print_info "Export process completed."
