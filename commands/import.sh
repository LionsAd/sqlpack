#!/bin/bash

# Database Import Script for Developer Environment
# Imports database dump created by export-database.ps1 into local Azure SQL Edge

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common logging functions
# shellcheck source=./log-common.sh
source "$SCRIPT_DIR/log-common.sh"

# Default values - some can be overridden by environment variables
SQL_SERVER="localhost,1499"
DATABASE=""
USERNAME="${DB_USERNAME:-}"
PASSWORD="${DB_PASSWORD:-}"
ARCHIVE_PATH=""
WORK_DIR="./db-import-work"
FORCE_RECREATE=false
SKIP_DATA=false
TRUST_SERVER_CERTIFICATE=false

# Additional wrapper for section headers (maps to log_section)
print_status() {
    log_section "$1"
}

# Common log file for SQL operations
SQLCMD_LOG="./logs/import-sqlcmd.log"

# Ensure logs directory exists
mkdir -p logs

# Helper function to drop database
drop_database() {
    local database="$1"

    print_warning "Database '$database' exists. Dropping..."

    local drop_sql="IF EXISTS (SELECT name FROM sys.databases WHERE name = '$database') BEGIN ALTER DATABASE [$database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$database]; END"

    if log_exec "Drop existing database" "$SQLCMD_LOG" sqlcmd "${SQLCMD_PARAMS[@]}" -Q "$drop_sql"; then
        print_success "Database dropped"
    else
        print_error "Failed to drop existing database"
        cat "$SQLCMD_LOG"
        exit 1
    fi
}

# Helper function to create database
create_database() {
    local database="$1"

    print_info "Creating database: $database"
    if log_exec "Create database $database" "$SQLCMD_LOG" sqlcmd "${SQLCMD_PARAMS[@]}" -Q "CREATE DATABASE [$database]"; then
        print_success "Database created successfully"
    else
        print_error "Failed to create database '$database'"
        cat "$SQLCMD_LOG"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Database Import Script

USAGE:
    $0 -a <archive_path> -d <database> [OPTIONS]

REQUIRED:
    -a, --archive       Path to db-dump.tar.gz file
    -d, --database      Target database name

OPTIONS:
    -s, --server        SQL Server instance (default: localhost,1499)
    -u, --username      SQL Server username (uses trusted connection if not provided)
    -p, --password      SQL Server password
    -w, --work-dir      Working directory for extraction (default: ./db-import-work)
    -f, --force         Force recreate database if it exists
    --skip-data         Import schema only, skip data import
    --trust-server-certificate  Trust server certificate (bypass SSL validation)
    -h, --help          Show this help message

ENVIRONMENT VARIABLES:
    DB_USERNAME         Default SQL Server username
    DB_PASSWORD         Default SQL Server password

EXAMPLES:
    # Basic import with Windows auth
    $0 -a db-dump.tar.gz -d MyAppDev

    # Import with SQL auth
    $0 -a db-dump.tar.gz -d MyAppDev -u sa -p MyPassword

    # Force recreate existing database
    $0 -a db-dump.tar.gz -d MyAppDev -f

    # Import schema only
    $0 -a db-dump.tar.gz -d MyAppDev --skip-data

    # Using environment variables for credentials
    export DB_USERNAME="sa"
    export DB_PASSWORD="MyPassword"
    $0 -a db-dump.tar.gz -d MyAppDev

    # With SSL certificate trust (for self-signed certificates)
    $0 -a db-dump.tar.gz -d MyAppDev -u sa -p MyPassword --trust-server-certificate

LOGGING:
    Use BASH_LOG environment variable to control output:
    BASH_LOG=error      Only show errors (default)
    BASH_LOG=info       Show info, warnings, and errors
    BASH_LOG=debug      Show debug info + above
    BASH_LOG=trace      Show command execution + above

PREREQUISITES:
    - sqlcmd must be installed and in PATH
    - Target SQL Server must be running and accessible
    - Sufficient permissions to create/modify databases
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--archive)
            ARCHIVE_PATH="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2
            ;;
        -s|--server)
            SQL_SERVER="$2"
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
        -w|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_RECREATE=true
            shift
            ;;
        --skip-data)
            SKIP_DATA=true
            shift
            ;;
        --trust-server-certificate)
            TRUST_SERVER_CERTIFICATE=true
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
if [[ -z "$ARCHIVE_PATH" ]]; then
    print_error "Archive path is required"
    show_usage
    exit 1
fi

if [[ -z "$DATABASE" ]]; then
    print_error "Database name is required"
    show_usage
    exit 1
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
    print_error "Archive file not found: $ARCHIVE_PATH"
    exit 1
fi

# Check prerequisites
print_status "CHECKING PREREQUISITES"

if ! command -v sqlcmd &> /dev/null; then
    print_error "sqlcmd not found. Please install SQL Server command line tools."
    exit 1
fi
print_success "sqlcmd found"

if ! command -v tar &> /dev/null; then
    print_error "tar not found. Please install tar utility."
    exit 1
fi
print_success "tar found"

# Build sqlcmd connection parameters
SQLCMD_PARAMS=("-S" "$SQL_SERVER")
if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
    SQLCMD_PARAMS+=("-U" "$USERNAME" "-P" "$PASSWORD")
    print_info "Using SQL Server authentication"
else
    SQLCMD_PARAMS+=("-E")
    print_info "Using trusted connection"
fi

# Add trust server certificate if specified
if [[ "$TRUST_SERVER_CERTIFICATE" == "true" ]]; then
    SQLCMD_PARAMS+=("-C")
    print_warning "Trusting server certificate (bypassing SSL validation)"
fi

# Test database connection
print_status "TESTING CONNECTION"
log_debug "Testing connection with: sqlcmd ${SQLCMD_PARAMS[*]} -Q 'SELECT @@VERSION' -h -1"
if log_exec "Testing SQL Server connection" "$SQLCMD_LOG" sqlcmd "${SQLCMD_PARAMS[@]}" -Q "SELECT @@VERSION" -h -1; then
    print_success "Connected to SQL Server: $SQL_SERVER"
else
    print_error "Failed to connect to SQL Server: $SQL_SERVER"
    print_error "Check server address, port, and authentication settings"
    exit 1
fi

# Check if database exists and handle appropriately
print_status "CHECKING DATABASE"

log_debug "Checking if database '$DATABASE' exists"
# Use direct sqlcmd execution to capture result (can't use log_exec as it removes the file)
if sqlcmd "${SQLCMD_PARAMS[@]}" -Q "SELECT COUNT(*) FROM sys.databases WHERE name='$DATABASE'" -h -1 > "$SQLCMD_LOG" 2>&1; then
    # Read the result from the log file and extract just the number
    DB_EXISTS=$(cat "$SQLCMD_LOG" 2>/dev/null | grep -E "^\s*[0-9]+\s*$" | head -1 | tr -d ' \r\n' || echo "0")
    log_debug "Database existence check result: '$DB_EXISTS'"

    if [[ "$DB_EXISTS" == "1" ]]; then
        if [[ "$FORCE_RECREATE" == true ]]; then
            drop_database "$DATABASE"
            create_database "$DATABASE"
        else
            print_error "Database '$DATABASE' already exists. Use -f/--force to recreate it."
            exit 1
        fi
    else
        create_database "$DATABASE"
    fi
else
    print_error "Failed to check database existence"
    cat "$SQLCMD_LOG"
    exit 1
fi

# Extract archive
print_status "EXTRACTING ARCHIVE"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

print_info "Extracting $ARCHIVE_PATH to $WORK_DIR"
if [[ "$ARCHIVE_PATH" == *.tar.gz ]]; then
    tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR"
elif [[ "$ARCHIVE_PATH" == *.zip ]]; then
    if command -v unzip &> /dev/null; then
        unzip -q "$ARCHIVE_PATH" -d "$WORK_DIR"
    else
        print_error "Archive is ZIP format but unzip not found"
        exit 1
    fi
else
    print_error "Unsupported archive format. Expected .tar.gz or .zip"
    exit 1
fi

print_success "Archive extracted"

# Verify extracted files
SCHEMAS_FILE="$WORK_DIR/schemas.txt"
TABLES_FILE="$WORK_DIR/tables.txt"
DATA_DIR="$WORK_DIR/data"

if [[ ! -f "$SCHEMAS_FILE" ]]; then
    print_error "Schemas file not found: $SCHEMAS_FILE"
    exit 1
fi

if [[ ! -f "$TABLES_FILE" ]]; then
    print_error "Tables file not found: $TABLES_FILE"
    exit 1
fi

if [[ ! -d "$DATA_DIR" ]] && [[ "$SKIP_DATA" == false ]]; then
    print_error "Data directory not found: $DATA_DIR"
    exit 1
fi

print_success "All required files found"

# Import schema
print_status "IMPORTING SCHEMA"

# Extract and create schemas first
print_info "Creating database schemas..."
log_debug "Reading tables from: $TABLES_FILE"

# Check if tables file has content
if [[ ! -s "$TABLES_FILE" ]]; then
    print_error "Tables file is empty: $TABLES_FILE"
    exit 1
fi

# Extract schemas with better error handling
log_debug "Extracting schema names from tables file"
SCHEMAS=$(cut -d. -f2 "$TABLES_FILE" | sort -u || true)

if [[ -z "$SCHEMAS" ]]; then
    print_warning "No schemas found in tables file, checking file format..."
    log_debug "First few lines of tables file:"
    head -5 "$TABLES_FILE" || true
    print_info "Continuing without creating additional schemas (assuming dbo only)"
else
    log_debug "Found schemas: $SCHEMAS"

    for schema in $SCHEMAS; do
        if [[ "$schema" != "dbo" ]]; then
            print_info "Creating schema: $schema"
            if log_exec "Create schema $schema" "$SQLCMD_LOG" sqlcmd "${SQLCMD_PARAMS[@]}" -d "$DATABASE" -Q "CREATE SCHEMA [$schema]"; then
                log_debug "Schema $schema created successfully"
            else
                print_warning "Failed to create schema $schema"
            fi
        fi
    done
fi

print_info "Importing schema files in dependency order..."

# Check if schemas file has content
if [[ ! -s "$SCHEMAS_FILE" ]]; then
    print_error "Schemas file is empty: $SCHEMAS_FILE"
    exit 1
fi

# Import each schema file in order
# Use cat | while to avoid stdin issues with sqlcmd
cat "$SCHEMAS_FILE" | while read -r schema_file; do
    # Skip empty lines and clean up whitespace
    schema_file=$(echo "$schema_file" | xargs)
    [[ -z "$schema_file" ]] && continue

    log_debug "Processing schema file: '$schema_file'"

    SCHEMA_PATH="$WORK_DIR/$schema_file"

    if [[ ! -f "$SCHEMA_PATH" ]]; then
        print_warning "Schema file not found: $schema_file"
        continue
    fi

    print_info "Importing schema: $schema_file"

    SCHEMA_LOG="logs/import_$(basename "$schema_file" .sql).log"

    # Use run-sqlcmd.sh wrapper with log_exec for proper error detection
    exit_code=0
    log_exec "Import schema file $schema_file" "$SCHEMA_LOG" "$SCRIPT_DIR/run-sqlcmd.sh" "${SQLCMD_PARAMS[@]}" -d "$DATABASE" -i "$SCHEMA_PATH" || exit_code=$?

    case $exit_code in
        0)
            print_success "$schema_file"
            ;;
        2)
            print_warning "$schema_file (with warnings)"
            ;;
        1|*)
            print_error "✗ Failed: $schema_file"
            ;;
    esac

done

print_status "SCHEMA IMPORT COMPLETE"
print_info "Schema import logs are available in: ./logs/"

# Import data
if [[ "$SKIP_DATA" == false ]]; then
    print_status "IMPORTING DATA"

    # Import data for each table
    IMPORTED_COUNT=0
    FAILED_COUNT=0

    while read -r TABLE_FULL; do
        # Skip empty lines
        [[ -z "$TABLE_FULL" ]] && continue

        # Extract schema and table name from fully qualified name
        # Expected format: Database.Schema.Table
        if [[ "$TABLE_FULL" =~ ^[^.]+\.([^.]+)\.([^.]+)$ ]]; then
            SCHEMA_NAME="${BASH_REMATCH[1]}"
            TABLE_NAME="${BASH_REMATCH[2]}"
            DATA_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.dat"
            FORMAT_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.fmt"

            if [[ -f "$DATA_FILE" && -f "$FORMAT_FILE" ]]; then
                # Check if data file is empty - skip if so
                if [[ ! -s "$DATA_FILE" ]]; then
                    log_debug "Skipping empty data file: $SCHEMA_NAME.$TABLE_NAME"
                    ((IMPORTED_COUNT++))
                    continue
                fi

                log_debug "Importing data: $SCHEMA_NAME.$TABLE_NAME"

                # Build bcp command for import using format file with quoted identifiers
                # With -q flag, use dot notation instead of bracket notation
                BCP_PARAMS=("bcp" "$SCHEMA_NAME.$TABLE_NAME" "in" "$DATA_FILE" "-f" "$FORMAT_FILE" "-S" "$SQL_SERVER" "-d" "$DATABASE" "-q")

                if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
                    BCP_PARAMS+=("-U" "$USERNAME" "-P" "$PASSWORD")
                else
                    BCP_PARAMS+=("-T")
                fi

                # Add trust server certificate if specified
                if [[ "$TRUST_SERVER_CERTIFICATE" == "true" ]]; then
                    BCP_PARAMS+=("-u")
                fi

                BCP_LOG_FILE="$WORK_DIR/import_${SCHEMA_NAME}_${TABLE_NAME}.log"
                if log_exec "Import data for $SCHEMA_NAME.$TABLE_NAME" "$BCP_LOG_FILE" "${BCP_PARAMS[@]}"; then
                    print_success "$SCHEMA_NAME.$TABLE_NAME"
                    ((IMPORTED_COUNT++))
                else
                    print_error "Failed: $SCHEMA_NAME.$TABLE_NAME"
                    ((FAILED_COUNT++))
                    # Show last few lines of error log
                    tail -5 "$WORK_DIR/import_${SCHEMA_NAME}_${TABLE_NAME}.log" | sed 's/^/    /'
                fi
            else
                print_warning "Data file not found: $DATA_FILE"
                ((FAILED_COUNT++))
            fi
        else
            print_warning "Invalid table format: $TABLE_FULL"
            ((FAILED_COUNT++))
        fi
    done < "$TABLES_FILE"

    print_status "DATA IMPORT SUMMARY"
    print_success "Tables imported: $IMPORTED_COUNT"
    if [[ $FAILED_COUNT -gt 0 ]]; then
        print_warning "Tables failed: $FAILED_COUNT"
    else
        print_success "Tables failed: $FAILED_COUNT"
    fi
else
    print_info "Skipping data import (--skip-data specified)"
fi

# Clean up
print_status "CLEANING UP"
print_info "Removing working directory: $WORK_DIR"
rm -rf "$WORK_DIR"
print_success "Cleanup complete"

# Final status
print_status "IMPORT COMPLETE"
print_success "Database '$DATABASE' has been successfully imported!"
print_info "Connection string: Server=$SQL_SERVER;Database=$DATABASE"

if [[ -n "$USERNAME" ]]; then
    print_info "Authentication: SQL Server ($USERNAME)"
else
    print_info "Authentication: Windows/Trusted"
fi

print_info ""
print_info "You can now connect to your database using:"
print_info "sqlcmd ${SQLCMD_PARAMS[*]} -d $DATABASE"
