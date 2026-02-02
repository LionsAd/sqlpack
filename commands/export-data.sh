#!/bin/bash

# Export Data Script - Handles bcp operations using native format with format files
# Can be called standalone or by PowerShell export script

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common logging functions
# shellcheck source=./log-common.sh
source "$SCRIPT_DIR/log-common.sh"

# Default values
SERVER=""
DATABASE=""
USERNAME=""
PASSWORD=""
DATA_DIR=""
TABLES_FILE=""
ROW_LIMIT=0
TRUST_CERT=false
SCHEMA_ONLY_TABLES=""

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
    --schema-only-tables Comma-separated list of tables to export schema only (no data)
    --trust-server-certificate  Trust server certificate
    -h, --help          Show this help message

LOGGING:
    Use BASH_LOG environment variable to control output:
    BASH_LOG=error      Only show errors (default)
    BASH_LOG=info       Show info, warnings, and errors
    BASH_LOG=debug      Show debug info + above
    BASH_LOG=trace      Show command execution + above

EXAMPLES:
    # With SQL Server authentication
    $0 -s "localhost,1499" -d "MyDB" -u "sa" -p "password" -D "./data" -t "tables.txt"

    # With trusted connection and row limit
    $0 -s "localhost,1499" -d "MyDB" -D "./data" -t "tables.txt" --row-limit 1000

    # With SSL certificate trust
    $0 -s "localhost,1499" -d "MyDB" -u "sa" -p "password" -D "./data" -t "tables.txt" --trust-server-certificate

    # With schema-only tables (no data export)
    $0 -s "localhost,1499" -d "MyDB" -u "sa" -p "password" -D "./data" -t "tables.txt" --schema-only-tables "AuditLog,TempData,SessionLog"

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
        --schema-only-tables)
            SCHEMA_ONLY_TABLES="$2"
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

log_debug "Parameters validated - Server: $SERVER, Database: $DATABASE"
log_debug "Data directory: $DATA_DIR, Tables file: $TABLES_FILE"
log_debug "Authentication: Username='$USERNAME', Trust cert: $TRUST_CERT, Row limit: $ROW_LIMIT"
log_debug "Schema-only tables: $SCHEMA_ONLY_TABLES"

# Build regex pattern for schema-only tables if specified
SCHEMA_ONLY_PATTERN=""
if [[ -n "$SCHEMA_ONLY_TABLES" ]]; then
    IFS=',' read -ra SCHEMA_ONLY_ARRAY <<< "$SCHEMA_ONLY_TABLES"
    PATTERN_PARTS=()

    for table in "${SCHEMA_ONLY_ARRAY[@]}"; do
        table=$(echo "$table" | xargs)  # Trim whitespace
        # Escape dots for regex and create pattern that matches table name at end
        escaped_table=${table//./"\\."}
        PATTERN_PARTS+=("\\.$escaped_table\$")
    done

    # Join patterns with | for OR matching
    SCHEMA_ONLY_PATTERN=$(printf "|%s" "${PATTERN_PARTS[@]}")
    SCHEMA_ONLY_PATTERN=${SCHEMA_ONLY_PATTERN:1}  # Remove leading |

    log_debug "Schema-only regex pattern: $SCHEMA_ONLY_PATTERN"
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

log_section "GENERATING FORMAT FILES"

# First pass: Generate format files
while IFS= read -r table_line; do
    # Skip empty lines
    [[ -z "$table_line" ]] && continue

    log_debug "Processing table line: $table_line"

    # Extract schema and table name from Database.Schema.Table format
    if [[ "$table_line" =~ ^[^.]+\.([^.]+)\.([^.]+)$ ]]; then
        SCHEMA_NAME="${BASH_REMATCH[1]}"
        TABLE_NAME="${BASH_REMATCH[2]}"
        FULL_TABLE_NAME="$DATABASE.$SCHEMA_NAME.$TABLE_NAME"
        FORMAT_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.fmt"

        log_debug "Creating format file: $SCHEMA_NAME.$TABLE_NAME.fmt"

        # Build format command
        FORMAT_CMD=(
            bcp "$FULL_TABLE_NAME" format nul -n
            -f "$FORMAT_FILE"
            -S "$SERVER"
            "${BCP_AUTH_PARAMS[@]}"
        )

        log_trace "Format command: ${FORMAT_CMD[*]}"

        FORMAT_LOG_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.format.log"
        if log_exec "Generate format file for $SCHEMA_NAME.$TABLE_NAME" "$FORMAT_LOG_FILE" "${FORMAT_CMD[@]}"; then
            log_debug "Created: $SCHEMA_NAME.$TABLE_NAME.fmt"
            # Create empty data file at the same time
            DATA_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.dat"
            touch "$DATA_FILE"
            log_debug "Created empty data file: $SCHEMA_NAME.$TABLE_NAME.dat"
            FORMAT_CREATED=$((FORMAT_CREATED + 1))
        else
            print_warning "Failed to create format file for: $FULL_TABLE_NAME"
            FORMAT_FAILED=$((FORMAT_FAILED + 1))
        fi
    else
        print_warning "Invalid table format: $table_line"
        FORMAT_FAILED=$((FORMAT_FAILED + 1))
    fi
done < "$TABLES_FILE"

print_info ""
print_info "Format files created: $FORMAT_CREATED"
print_info "Format files failed: $FORMAT_FAILED"

log_section "EXPORTING DATA"

# Second pass: Export data using format files (filter out schema-only tables)
if [[ -n "$SCHEMA_ONLY_PATTERN" ]]; then
    log_debug "Filtering schema-only tables with pattern: $SCHEMA_ONLY_PATTERN"
    FILTERED_TABLES=$(grep -Ev "$SCHEMA_ONLY_PATTERN" "$TABLES_FILE")
else
    FILTERED_TABLES=$(<"$TABLES_FILE")
fi

while IFS= read -r table_line; do
    # Skip empty lines
    [[ -z "$table_line" ]] && continue

    log_debug "Processing table line for data export: $table_line"

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
            DATA_FAILED=$((DATA_FAILED + 1))
            continue
        fi

        log_debug "Exporting data: $FULL_TABLE_NAME"

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

        log_trace "Export command: ${EXPORT_CMD[*]}"

        DATA_LOG_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.data.log"
        if log_exec "Export data for $SCHEMA_NAME.$TABLE_NAME" "$DATA_LOG_FILE" "${EXPORT_CMD[@]}"; then
            print_success "Exported: $SCHEMA_NAME.$TABLE_NAME.dat"
            DATA_EXPORTED=$((DATA_EXPORTED + 1))
        else
            print_warning "Failed to export data for: $FULL_TABLE_NAME"
            DATA_FAILED=$((DATA_FAILED + 1))
        fi
    else
        print_warning "Invalid table format: $table_line"
        DATA_FAILED=$((DATA_FAILED + 1))
    fi
done <<< "$FILTERED_TABLES"

log_summary
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
elif [[ $DATA_EXPORTED -gt 0 || $FORMAT_CREATED -gt 0 ]]; then
    print_warning "Some exports failed, but continuing with partial data"
    print_info "Successfully exported $DATA_EXPORTED tables, created $FORMAT_CREATED format files"
    exit 1  # Partial success - continue with archive
else
    print_error "No exports succeeded - aborting"
    exit 2  # Complete failure - abort
fi
