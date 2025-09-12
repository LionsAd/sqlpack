# Database Export/Import Scripts

[![CI](https://github.com/LionsAd/sqlpack/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/LionsAd/sqlpack/actions/workflows/ci.yml)

A comprehensive cross-platform solution for exporting SQL Server databases and importing them into developer environments.

## Overview

This toolkit provides:
- **export.ps1**: PowerShell script that exports complete database schema and data
- **import.sh**: Shell script for importing the database into local development environments
- **export.sh**: CI-friendly wrapper script for automated exports
- **export-data.sh**: Data export script using bcp with native format files

## Files Created

```
output/
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
└── db-dump.tar.gz          # Compressed archive of all files
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

## Export Usage

### Basic Export
```powershell
# Using PowerShell directly
.\export.ps1 -SqlInstance "prod.server.com" -Database "MyApplication"

# Using CI wrapper (recommended for automation)
export DB_SERVER="prod.server.com"
export DB_NAME="MyApplication"
export DB_USERNAME="backup_user"
export DB_PASSWORD="secret123"
./export.sh
```

### Advanced Export Options
```powershell
# Export with row limits and schema-only tables
.\export.ps1 `
    -SqlInstance "localhost,1499" `
    -Database "MyApp" `
    -Username "sa" `
    -Password "MyPassword" `
    -DataRowLimit 10000 `
    -SchemaOnlyTables @("AuditLog", "TempData") `
    -OutputPath "./exports" `
    -TarFileName "myapp-dev-dump.tar.gz"
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
        run: ./export.sh

      - name: Upload Artifact
        uses: actions/upload-artifact@v3
        with:
          name: database-dump
          path: db-dump.tar.gz
```

## Import Usage

### Basic Import
```bash
# Import to local SQL Server
./import.sh -a db-dump.tar.gz -d MyAppDev

# Import with custom server/auth
./import.sh \
    -a db-dump.tar.gz \
    -d MyAppDev \
    -s "localhost,1499" \
    -u sa \
    -p MyPassword
```

### Developer Workflow
```bash
# 1. Download the database dump from CI
curl -o db-dump.tar.gz "https://your-ci-system/artifacts/db-dump.tar.gz"

# 2. Start Azure SQL Edge (if not running)
docker run -e "ACCEPT_EULA=1" -e "MSSQL_SA_PASSWORD=YourPassword123" \
    -p 1499:1433 -d mcr.microsoft.com/azure-sql-edge

# 3. Import the database
./import.sh -a db-dump.tar.gz -d MyAppDev -s "localhost,1499" -u sa -p "YourPassword123"

# 4. Connect and develop
sqlcmd -S "localhost,1499" -U sa -P "YourPassword123" -d MyAppDev
```

## Logging Configuration

All scripts support configurable logging levels for better debugging and monitoring.

### Bash Scripts Logging

Use the `BASH_LOG` environment variable to control output verbosity:

```bash
# Default - only show errors
./export.sh

# Show informational messages
BASH_LOG=info ./export.sh

# Show debug information (parameter parsing, decisions)
BASH_LOG=debug ./export-data.sh

# Show all command executions (useful for troubleshooting)
BASH_LOG=trace ./import.sh

# Add timestamps to log messages
BASH_LOG_TIMESTAMP=true BASH_LOG=debug ./export.sh
```

**Log Levels (in order of verbosity):**
- `error` - Only errors (default)
- `warn` - Warnings and errors
- `info` - Informational messages, warnings, and errors
- `debug` - Debug info plus all above levels
- `trace` - Command execution details plus all above levels

### PowerShell Logging

Use the `PS_LOG_LEVEL` environment variable or command-line switches:

```powershell
# Default - informational level
.\export.ps1 -SqlInstance "server" -Database "db"

# Verbose output
.\export.ps1 -SqlInstance "server" -Database "db" -Verbose

# Debug output
.\export.ps1 -SqlInstance "server" -Database "db" -Debug

# Environment variable approach
$env:PS_LOG_LEVEL = "Debug"
.\export.ps1 -SqlInstance "server" -Database "db"

# Add timestamps
$env:PS_LOG_TIMESTAMP = "true"
.\export.ps1 -SqlInstance "server" -Database "db" -Verbose
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
| `-OutputPath` | No | Output directory (default: "./output") |
| `-TarFileName` | No | Archive filename (default: "db-dump.tar.gz") |
| `-SchemaOnlyTables` | No | Array of tables to export schema only (no data) |
| `-DataRowLimit` | No | Maximum rows per table (default: unlimited) |

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

## Performance Considerations

### Export Performance
- Use `DataRowLimit` for large tables in development environments
- Exclude unnecessary tables (logs, temp data) with `ExcludeTables`
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
./import.sh -a db-dump.tar.gz -d MyAppDev -f
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
