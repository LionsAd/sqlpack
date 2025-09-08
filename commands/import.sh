#!/bin/bash

# Database Import Script for Developer Environment
# Imports database dump created by export-database.ps1 into local Azure SQL Edge

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common logging functions
# shellcheck source=./log-common.sh
source "$SCRIPT_DIR/log-common.sh"

# Default values
SQL_SERVER="localhost,1499"
DATABASE=""
USERNAME=""
PASSWORD=""
ARCHIVE_PATH=""
WORK_DIR="./db-import-work"
FORCE_RECREATE=false
SKIP_DATA=false

# Additional wrapper for section headers (maps to log_section)
print_status() {
    log_section "$1"
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
    -h, --help          Show this help message

EXAMPLES:
    # Basic import with Windows auth
    $0 -a db-dump.tar.gz -d MyAppDev

    # Import with SQL auth
    $0 -a db-dump.tar.gz -d MyAppDev -u sa -p MyPassword

    # Force recreate existing database
    $0 -a db-dump.tar.gz -d MyAppDev -f

    # Import schema only
    $0 -a db-dump.tar.gz -d MyAppDev --skip-data

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

# Test database connection
print_status "TESTING CONNECTION"
echo sqlcmd "${SQLCMD_PARAMS[@]}" -Q "SELECT @@VERSION" -h -1
if sqlcmd "${SQLCMD_PARAMS[@]}" -Q "SELECT @@VERSION" -h -1 > /dev/null 2>&1; then
    print_success "Connected to SQL Server: $SQL_SERVER"
else
    print_error "Failed to connect to SQL Server: $SQL_SERVER"
    exit 1
fi

# Check if database exists
print_status "CHECKING DATABASE"
DB_EXISTS=$(sqlcmd "${SQLCMD_PARAMS[@]}" -Q "SELECT COUNT(*) FROM sys.databases WHERE name='$DATABASE'" -h -1 2>/dev/null | tr -d ' \r\n' || echo "0")

if [[ "$DB_EXISTS" == "1" ]]; then
    if [[ "$FORCE_RECREATE" == true ]]; then
        print_warning "Database '$DATABASE' exists. Dropping and recreating..."
        sqlcmd "${SQLCMD_PARAMS[@]}" -Q "
        IF EXISTS (SELECT name FROM sys.databases WHERE name = '$DATABASE')
        BEGIN
            ALTER DATABASE [$DATABASE] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
            DROP DATABASE [$DATABASE];
        END"
        print_success "Database dropped"
    else
        print_error "Database '$DATABASE' already exists. Use -f/--force to recreate it."
        exit 1
    fi
fi

# Create database
print_info "Creating database: $DATABASE"
sqlcmd "${SQLCMD_PARAMS[@]}" -Q "CREATE DATABASE [$DATABASE]"
print_success "Database created"

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
SCHEMA_FILE="$WORK_DIR/schema.sql"
TABLES_FILE="$WORK_DIR/tables.txt"
DATA_DIR="$WORK_DIR/data"

if [[ ! -f "$SCHEMA_FILE" ]]; then
    print_error "Schema file not found: $SCHEMA_FILE"
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
print_info "Executing schema.sql..."

# Modify schema.sql to use the target database
TEMP_SCHEMA="$WORK_DIR/schema_modified.sql"
# Replace USE statements and add database context
{
    echo "USE [$DATABASE];"
    echo "GO"
    # Remove any existing USE statements and database context
    sed -E 's/^USE \[.*\];?//g' "$SCHEMA_FILE" | sed '/^GO$/d'
} > "$TEMP_SCHEMA"

if sqlcmd "${SQLCMD_PARAMS[@]}" -i "$TEMP_SCHEMA" > "$WORK_DIR/schema_import.log" 2>&1; then
    print_success "Schema imported successfully"
else
    print_error "Schema import failed. Check log: $WORK_DIR/schema_import.log"
    tail -20 "$WORK_DIR/schema_import.log"
    exit 1
fi

# Import data
if [[ "$SKIP_DATA" == false ]]; then
    print_status "IMPORTING DATA"

    # Read table list
    mapfile -t TABLES < "$TABLES_FILE"
    IMPORTED_COUNT=0
    FAILED_COUNT=0

    for TABLE_FULL in "${TABLES[@]}"; do
        # Skip empty lines
        [[ -z "$TABLE_FULL" ]] && continue

        # Extract schema and table name from fully qualified name
        # Expected format: Database.Schema.Table
        if [[ "$TABLE_FULL" =~ ^[^.]+\.([^.]+)\.([^.]+)$ ]]; then
            SCHEMA_NAME="${BASH_REMATCH[1]}"
            TABLE_NAME="${BASH_REMATCH[2]}"
            DATA_FILE="$DATA_DIR/$SCHEMA_NAME.$TABLE_NAME.csv"

            if [[ -f "$DATA_FILE" ]]; then
                print_info "Importing data: $SCHEMA_NAME.$TABLE_NAME"

                # Build bcp command for import
                BCP_PARAMS=("bcp" "[$DATABASE].[$SCHEMA_NAME].[$TABLE_NAME]" "in" "$DATA_FILE" "-c" "-t," "-r\\n" "-S" "$SQL_SERVER")

                if [[ -n "$USERNAME" && -n "$PASSWORD" ]]; then
                    BCP_PARAMS+=("-U" "$USERNAME" "-P" "$PASSWORD")
                else
                    BCP_PARAMS+=("-T")
                fi

                if "${BCP_PARAMS[@]}" > "$WORK_DIR/import_${SCHEMA_NAME}_${TABLE_NAME}.log" 2>&1; then
                    print_success "✓ $SCHEMA_NAME.$TABLE_NAME"
                    ((IMPORTED_COUNT++))
                else
                    print_warning "✗ Failed: $SCHEMA_NAME.$TABLE_NAME"
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
    done

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
