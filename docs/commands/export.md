# Export

Exports database schema and data and produces `./db-export` and `db-dump.tar.gz`.

## Examples

```bash
# Minimal (server, database)
sqlpack export --server localhost,1433 --database MyApp

# With credentials and options
DB_ROW_LIMIT=10000 \
DB_SCHEMA_ONLY_TABLES="AuditLog,TempData" \
DB_EXPORT_DIR="./exports" \
DB_ARCHIVE_NAME="myapp-dev-dump.tar.gz" \
sqlpack export --server localhost,1499 --database MyApp --username sa --password MyPassword
```

## Notes
- Default export directory: `./db-export`
- Default archive name: `db-dump.tar.gz` in current directory
- PowerShell exporter uses `dbatools` under the hood (see CI)

