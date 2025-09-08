#!/bin/bash

# Export Data Script - Handles bcp operations using native format with format files
# Can be called standalone or by PowerShell export script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}$1${NC}"
}

print_debug() {
    echo -e "${GRAY}$1${NC}"
}

# Default values
SERVER=""
DATABASE=""
USERNAME=""
PASSWORD=""
DATA_DIR=""
TABLES_FILE=""
ROW_LIMIT=0
TRUST_CERT=false

# Function to show usage
show_usage() {
    cat << EOF
BCP Data Export Script

USAGE:
    $0 [OPTIONS]

REQUIRED OPTIONS:
    -s, --server        SQL Server instance (e.g., localhost,1499)
    -d, --database      Database name
    -D, --data-dir      Directory for data files
    -t, --tables-file   File containing table list (one per line)

OPTIONAL:
    -u, --username      SQL Server username (uses trusted connection if not provided)
    -p, --password      SQL Server password
    --row-limit         Maximum rows per table (default: 0=unlimited)
    --trust-server-certificate  Trust server certificate
    -h, --help          Show this help message

EXAMPLES:
    # With SQL Server authentication
    $0 -s "localhost,1499" -d "MyDB" -u "sa" -p "password" -D "./data" -t "tables.txt"

    # With trusted connection and row limit
    $0 -s "localhost,1499" -d "MyDB" -D "./data" -t "tables.txt" --row-limit 1000

    # With SSL certificate trust
    $0 -s "localhost,1499" -d "MyDB" -u "sa" -p "password" -D "./data" -t "tables.txt" --trust-server-certificate

NOTES:
    - The tables file should contain one table per line in format: Database.Schema.Table
    - The script generates format files first, then exports data using native bcp format
    - Data files are saved as Schema.Table.dat with corresponding Schema.Table.fmt format files
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            SERVER="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -u|--username)
            USERNAME="$2"
            shift 2
            ;;
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -D|--data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        -t|--tables-file)
            TABLES_FILE="$2"
            shift 2
            ;;
        --row-limit)
            ROW_LIMIT="$2"
            shift 2
            ;;
        --trust-server-certificate)
            TRUST_CERT=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$SERVER" ]]; then
    print_error "Server is required. Use -s/--server option."
    exit 1
fi

if [[ -z "$DATABASE" ]]; then
    print_error "Database is required. Use -d/--database option."
    exit 1
fi

if [[ -z "$DATA_DIR" ]]; then
    print_error "Data directory is required. Use -D/--data-dir option."
    exit 1
fi

if [[ -z "$TABLES_FILE" ]]; then
    print_error "Tables file is required. Use -t/--tables-file option."
    exit 1
fi

# Validate inputs
if [[ ! -f "$TABLES_FILE" ]]; then
    print_error "Tables file not found: $TABLES_FILE"
    exit 1
fi

if [[ ! -d "$DATA_DIR" ]]; then
    print_error "Data directory not found: $DATA_DIR"
    exit 1
fi

# Check if bcp is available
if ! command -v bcp &> /dev/null; then
    print_error "bcp command not found. Please install SQL Server command line tools."
    exit 1
fi

print_info "Starting BCP export process..."
print_info "Server: $SERVER"
print_info "Database: $DATABASE"
print_info "Data directory: $DATA_DIR"
print_info "Tables file: $TABLES_FILE"

# Build base bcp parameters
BCP_AUTH_PARAMS=()
if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
    BCP_AUTH_PARAMS+=("-U" "$USERNAME" "-P" "$PASSWORD")
else
    BCP_AUTH_PARAMS+=("-T")  # Trusted connection
fi

# Add trust server certificate if needed
if [[ "$TRUST_CERT" == "true" ]]; then
    BCP_AUTH_PARAMS+=("-u")
fi

# Counters
FORMAT_CREATED=0
FORMAT_FAILED=0
DATA_EXPORTED=0
DATA_FAILED=0

print_info ""
print_info "=== GENERATING FORMAT FILES ==="

# First pass: Generate format files
while IFS= read -r table_line; do
    # Skip empty lines
    [[ -z "$table_line" ]] && continue

    # Extract schema and table name from Database.Schema.Table format
    if [[ "$table_line" =~ ^[^.]+\.([^.]+)\.([^.]+)$ ]]; then
        SCHEMA_NAME="${BASH_REMATCH[1]}"
        TABLE_NAME="${BASH_REMATCH[2]}"
        FULL_TABLE_NAME="$DATABASE.$SCHEMA_NAME.$TABLE_NAME"
        FORMAT_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.fmt"

        print_info "Creating format file: $SCHEMA_NAME.$TABLE_NAME.fmt"

        # Build format command
        FORMAT_CMD=(
            bcp "$FULL_TABLE_NAME" format nul -n
            -f "$FORMAT_FILE"
            -S "$SERVER"
            "${BCP_AUTH_PARAMS[@]}"
        )

        print_debug "Executing: ${FORMAT_CMD[*]}"

        if "${FORMAT_CMD[@]}" >/dev/null 2>&1; then
            print_success "Created: $SCHEMA_NAME.$TABLE_NAME.fmt"
            ((FORMAT_CREATED++))
        else
            print_warning "Failed to create format file for: $FULL_TABLE_NAME"
            ((FORMAT_FAILED++))
        fi
    else
        print_warning "Invalid table format: $table_line"
        ((FORMAT_FAILED++))
    fi
done < "$TABLES_FILE"

print_info ""
print_info "Format files created: $FORMAT_CREATED"
print_info "Format files failed: $FORMAT_FAILED"

print_info ""
print_info "=== EXPORTING DATA ==="

# Second pass: Export data using format files
while IFS= read -r table_line; do
    # Skip empty lines
    [[ -z "$table_line" ]] && continue

    # Extract schema and table name
    if [[ "$table_line" =~ ^[^.]+\.([^.]+)\.([^.]+)$ ]]; then
        SCHEMA_NAME="${BASH_REMATCH[1]}"
        TABLE_NAME="${BASH_REMATCH[2]}"
        FULL_TABLE_NAME="$DATABASE.$SCHEMA_NAME.$TABLE_NAME"
        FORMAT_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.fmt"
        DATA_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.dat"

        # Check if format file exists
        if [[ ! -f "$FORMAT_FILE" ]]; then
            print_warning "Format file not found for $FULL_TABLE_NAME, skipping"
            ((DATA_FAILED++))
            continue
        fi

        print_info "Exporting data: $FULL_TABLE_NAME"

        # Build export command
        EXPORT_CMD=(
            bcp "$FULL_TABLE_NAME" out "$DATA_FILE"
            -S "$SERVER"
            -f "$FORMAT_FILE"
            "${BCP_AUTH_PARAMS[@]}"
        )

        # Add row limit if specified
        if [[ "$ROW_LIMIT" -gt 0 ]]; then
            EXPORT_CMD+=("-L" "$ROW_LIMIT")
        fi

        print_debug "Executing: ${EXPORT_CMD[*]}"

        if "${EXPORT_CMD[@]}" >/dev/null 2>&1; then
            print_success "Exported: $SCHEMA_NAME.$TABLE_NAME.dat"
            ((DATA_EXPORTED++))
        else
            print_warning "Failed to export data for: $FULL_TABLE_NAME"
            ((DATA_FAILED++))
        fi
    else
        print_warning "Invalid table format: $table_line"
        ((DATA_FAILED++))
    fi
done < "$TABLES_FILE"

print_info ""
print_info "=== EXPORT SUMMARY ==="
print_success "Format files created: $FORMAT_CREATED"
if [[ $FORMAT_FAILED -gt 0 ]]; then
    print_warning "Format files failed: $FORMAT_FAILED"
else
    print_success "Format files failed: $FORMAT_FAILED"
fi

print_success "Data files exported: $DATA_EXPORTED"
if [[ $DATA_FAILED -gt 0 ]]; then
    print_warning "Data exports failed: $DATA_FAILED"
else
    print_success "Data exports failed: $DATA_FAILED"
fi

print_info ""
if [[ $FORMAT_FAILED -eq 0 && $DATA_FAILED -eq 0 ]]; then
    print_success "All exports completed successfully!"
    exit 0
else
    print_warning "Some exports failed. Check the output above for details."
    exit 1
fi
