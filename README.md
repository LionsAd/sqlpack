# SQLPack - Database Export/Import Utility

[![CI](https://github.com/LionsAd/sqlpack/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/LionsAd/sqlpack/actions/workflows/ci.yml)

A comprehensive cross-platform solution for exporting SQL Server databases and importing them into developer environments.

## Overview

SQLPack provides a unified command-line interface for database operations:
- **sqlpack export**: Export complete database schema and data
- **sqlpack import**: Import database from archive into local environments
- **sqlpack export-data**: Advanced data export using BCP with native format files
- **sqlpack doctor**: Validate required tools and environment
- **sqlpack install-tools**: Print or execute dependency install commands (macOS/Debian)

The tool combines PowerShell and Bash scripts for maximum cross-platform compatibility.

## Documentation

- Online Docs (GitHub Pages): https://lionsad.github.io/sqlpack/
- Local preview: `pip install mkdocs mkdocs-material && mkdocs serve`
- First-time setup for GitHub Pages: merge to main, then in GitHub → Settings → Pages set Source to "Deploy from a branch" with Branch `gh-pages` and Folder `/ (root)`.

## Quick Start

```bash
# Install SQLPack
sudo make install

# Validate your environment
sqlpack install-tools           # Preview install commands for missing deps
sqlpack install-tools --execute # Run the commands
sqlpack doctor

# Export a database
sqlpack export --server localhost,1433 --database MyApp

# Import to development environment
sqlpack import --archive db-dump.tar.gz --database MyAppDev

# Get help for any command
sqlpack help
sqlpack export --help
```

## Prerequisites (Tools)

See installation steps in [docs/install.md](docs/install.md).

Ensure these tools are installed and on PATH:
- sqlcmd and bcp (mssql-tools18)
- PowerShell 7+ (`pwsh`)
- dbatools PowerShell module (see https://docs.dbatools.io/)
- tar utility (macOS/Linux)

## Files Created

Default output directory for exports is `./db-export`.

```
db-export/
├── schemas.txt             # Ordered list of schema files for import
├── schema-tables.sql       # Database tables
├── schema-constraints.sql  # Foreign keys and constraints
├── schema-procedures.sql   # Stored procedures
├── schema-functions.sql    # User defined functions
├── schema-views.sql        # Views
├── tables.txt              # List of all tables (Database.Schema.Table format)
├── data/                   # Directory containing table data
│   ├── dbo.Users.dat       # Native format data files
│   ├── dbo.Users.fmt       # BCP format files
│   └── ...

db-dump.tar.gz              # Compressed archive of files above (created in CWD)
```

## Prerequisites

### For Export (CI/Build Server)
- PowerShell Core (pwsh) or Windows PowerShell
- dbatools PowerShell module: `Install-Module dbatools -Scope CurrentUser`
- SQL Server with bcp utility
- Access to source database

### For Import (Developer Machine)
- sqlcmd (SQL Server command line tools)
- tar utility (usually pre-installed on Linux/macOS)
- Azure SQL Edge or SQL Server running locally

## Installation

### System-wide Installation
```bash
# Install to /usr/local (requires sudo)
sudo make install

# Install to custom location (e.g., ~/.local)
PREFIX=$HOME/.local make install

# Make sure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

### Development Usage
```bash
# Run directly from source
./sqlpack help
```

### Uninstall
```bash
# Remove from system
sudo make uninstall

# Remove from custom location
PREFIX=$HOME/.local make uninstall
```

## Usage

### Basic Export
```bash
# Export using environment variables
export DB_SERVER="prod.server.com"
export DB_NAME="MyApplication"
export DB_USERNAME="backup_user"
export DB_PASSWORD="secret123"
sqlpack export

# Export with command-line options
sqlpack export --server prod.server.com --database MyApplication
```

### Advanced Export Options
```bash
# Export with row limits and schema-only tables
DB_ROW_LIMIT=10000 \
DB_SCHEMA_ONLY_TABLES="AuditLog,TempData" \
DB_EXPORT_DIR="./exports" \
DB_ARCHIVE_NAME="myapp-dev-dump.tar.gz" \
DB_TRUST_SERVER_CERTIFICATE=true \
sqlpack export --server localhost,1499 --database MyApp --username sa --password MyPassword
```

### CI/CD Integration

#### GitHub Actions Example
```yaml
name: Database Export
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  workflow_dispatch:

jobs:
  export:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install PowerShell
        run: |
          wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo apt-key add -
          sudo add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -rs)-prod $(lsb_release -cs) main"
          sudo apt-get update
          sudo apt-get install -y powershell

      - name: Install dbatools
        run: pwsh -c "Install-Module dbatools -Force -Scope CurrentUser"

      - name: Export Database
        env:
          DB_SERVER: ${{ secrets.DB_SERVER }}
          DB_NAME: ${{ secrets.DB_NAME }}
          DB_USERNAME: ${{ secrets.DB_USERNAME }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
          # BASH_LOG: info   # uncomment for progress-level logs in CI
          # BASH_LOG: trace  # uncomment to stream all commands and outputs
        run: ./sqlpack export

      - name: Upload Artifact
        uses: actions/upload-artifact@v3
        with:
          name: database-dump
          path: db-dump.tar.gz
```

### Basic Import
```bash
# Import to local SQL Server
sqlpack import --archive db-dump.tar.gz --database MyAppDev

# Import with custom server/auth
sqlpack import \
    --archive db-dump.tar.gz \
    --database MyAppDev \
    --server "localhost,1499" \
    --username sa \
    --password MyPassword
```

### Developer Workflow
```bash
# 1. Download the database dump from CI
curl -o db-dump.tar.gz "https://your-ci-system/artifacts/db-dump.tar.gz"

# 2. Start Azure SQL Edge (if not running)
docker run -e "ACCEPT_EULA=1" -e "MSSQL_SA_PASSWORD=YourPassword123" \
    -p 1499:1433 -d mcr.microsoft.com/azure-sql-edge

# 3. Import the database
sqlpack import --archive db-dump.tar.gz --database MyAppDev --server "localhost,1499" --username sa --password "YourPassword123"

# 4. Connect and develop
sqlcmd -S "localhost,1499" -U sa -P "YourPassword123" -d MyAppDev
```

## Logging Configuration

All scripts support configurable logging levels for better debugging and monitoring.

### Bash Scripts Logging

Use the `BASH_LOG` environment variable to control output verbosity:

```bash
# Default - only show errors
sqlpack export

# Show informational messages
BASH_LOG=info sqlpack export

# Show debug information (parameter parsing, decisions)
BASH_LOG=debug sqlpack export-data

# Show all command executions (useful for troubleshooting)
BASH_LOG=trace sqlpack import

# Add timestamps to log messages
BASH_LOG_TIMESTAMP=true BASH_LOG=debug sqlpack export
```

Notes on visibility and CI:
- `error` (default) keeps console output minimal so failures stand out. Prefer for CI or long unattended runs.
- `info` shows progress/success lines and can bury errors in long outputs; use interactively with care.
- `trace` streams all sub-commands and their output for full context; otherwise, detailed tool output is captured to log files and summarized on failure.

**Log Levels (in order of verbosity):**
- `error` - Only errors (default)
- `warn` - Warnings and errors
- `info` - Informational messages, warnings, and errors
- `debug` - Debug info plus all above levels
- `trace` - Command execution details plus all above levels

**Log Files:**
- Import operations write detailed logs to `./logs/` directory
- Individual schema import logs: `./logs/import_<filename>.log`
- SQL command logs: `./logs/import-sqlcmd.log`

### PowerShell Logging

Use the `PS_LOG_LEVEL` environment variable or command-line switches:

```powershell
# Default - informational level
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db"

# Verbose output
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db" -Verbose

# Debug output
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db" -Debug

# Environment variable approach
$env:PS_LOG_LEVEL = "Debug"
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db"

# Add timestamps
$env:PS_LOG_TIMESTAMP = "true"
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db" -Verbose
```

**PowerShell Log Levels:**
- `Error` - Only errors
- `Warning` - Warnings and errors
- `Information` - Standard output (default)
- `Verbose` - Detailed progress information
- `Debug` - Internal debugging details

## Script Options

### export.ps1
| Parameter | Required | Description |
|-----------|----------|-------------|
| `-SqlInstance` | Yes | SQL Server instance (e.g., "localhost,1499") |
| `-Database` | Yes | Database name to export |
| `-Username` | No | SQL Server username (uses Windows auth if omitted) |
| `-Password` | No | SQL Server password |
| `-OutputPath` | No | Output directory (default: "./db-export") |
| `-TarFileName` | No | Archive filename (default: "db-dump.tar.gz") |
| `-SchemaOnlyTables` | No | Array of tables to export schema only (no data) |
| `-DataRowLimit` | No | Maximum rows per table (default: unlimited) |
| `-TrustServerCertificate` | No | Trust server certificate (bypass SSL validation) |

### import.sh
| Parameter | Required | Description |
|-----------|----------|-------------|
| `-a, --archive` | Yes | Path to db-dump.tar.gz file |
| `-d, --database` | Yes | Target database name |
| `-s, --server` | No | SQL Server instance (default: "localhost,1499") |
| `-u, --username` | No | SQL Server username (uses trusted connection if omitted) |
| `-p, --password` | No | SQL Server password |
| `-f, --force` | No | Force recreate database if exists |
| `--skip-data` | No | Import schema only, skip data |
| `-w, --work-dir` | No | Working directory for extraction (default: "./db-import-work") |
| `--trust-server-certificate` | No | Trust server certificate (bypass SSL validation) |

### export.sh Environment Variables
| Variable | Description |
|----------|-------------|
| `DB_SERVER` | SQL Server instance |
| `DB_NAME` | Database name (required) |
| `DB_USERNAME` | SQL Server username |
| `DB_PASSWORD` | SQL Server password |
| `DB_EXPORT_DIR` | Export directory |
| `DB_ARCHIVE_NAME` | Archive filename |
| `DB_ROW_LIMIT` | Maximum rows per table |
| `DB_TRUST_SERVER_CERTIFICATE` | Trust server certificate (true/false) |

## Performance Considerations

### Export Performance
- Use `DataRowLimit` for large tables in development environments
- For large or nonessential tables, prefer `SchemaOnlyTables` to export only schema (no data)
- Run exports during off-peak hours
- Consider network bandwidth between CI and database server

### Import Performance
- Azure SQL Edge performs well on ARM64 (Apple Silicon)
- Use SSD storage for better I/O performance
- Allocate sufficient memory to container/service
- Consider importing schema first, then data in parallel

## Troubleshooting

### Common Export Issues

**dbatools module not found**
```powershell
Install-Module dbatools -Scope CurrentUser -Force
```

**bcp command not found**
- Install SQL Server command line tools
- Ensure bcp is in system PATH

**Connection timeout**
- Check firewall settings
- Verify SQL Server is accepting remote connections
- Test connection with sqlcmd first

### Common Import Issues

**Database already exists**
```bash
# Use force flag to recreate
sqlpack import --archive db-dump.tar.gz --database MyAppDev --force
```

**Permission denied**
- Ensure user has CREATE DATABASE permissions
- For Azure SQL Edge, use 'sa' account or create user with sufficient rights

**Data import failures**
- Check data file encoding (should be UTF-8)
- Verify table structure matches exported schema
- Check for constraint violations in data

## Security Considerations

- Use environment variables for passwords in CI/CD
- Limit database user permissions to minimum required
- Consider encrypting database dumps for sensitive data
- Rotate database credentials regularly
- Use secure networks for database connections

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Development

- Run from source: `./sqlpack help`
- Lint Bash scripts: `make lint` (uses shellcheck if available)
- Run tests: `make test` (runs Bats tests in `tests/` if installed)
- Increase logging during local runs: `BASH_LOG=trace ./sqlpack import ...` or `PS_LOG_LEVEL=trace pwsh ./commands/export.ps1 ...`
