# Import

Imports a previously created `db-dump.tar.gz` archive into a target database.

## Examples

```bash
# Basic import into local dev instance
sqlpack import --archive db-dump.tar.gz --database MyAppDev

# Custom server/auth and force recreate
sqlpack import \
  --archive db-dump.tar.gz \
  --database MyAppDev \
  --server "localhost,1499" \
  --username sa \
  --password MyPassword \
  --force
```

### Common Scenarios

```bash
# Use trusted connection on default port
sqlpack import --archive db-dump.tar.gz --database MyAppDev --server "corp-sql01,1433"

# Force recreate if DB exists
sqlpack import --archive db-dump.tar.gz --database MyAppDev --force

# Import schema only (skip data)
sqlpack import --archive db-dump.tar.gz --database MyAppDev --skip-data

# Trust self-signed certificates
sqlpack import --archive db-dump.tar.gz --database MyAppDev \
  --server "staging.company.net,1433" --trust-server-certificate

# Customize the working directory used during extraction
sqlpack import --archive db-dump.tar.gz --database MyAppDev --work-dir ./tmp/import-work

# Increase logging for troubleshooting
BASH_LOG=trace sqlpack import --archive db-dump.tar.gz --database MyAppDev
```

### After Import

```bash
# Connect with sqlcmd (trusted connection shown)
sqlcmd -S "localhost,1499" -d MyAppDev -Q "SELECT TOP 5 name FROM sys.tables"

# Connect with SQL auth
sqlcmd -S "localhost,1499" -U sa -P "YourPassword123" -d MyAppDev -Q "SELECT 1"
```

Logs are written under `./logs/`. For schema imports, see `./logs/import_<filename>.log`. The sqlcmd wrapper log is `./logs/import-sqlcmd.log`.

## Notes
- Working directory: `./db-import-work`
- Logs written to: `./logs/`
- Use `--skip-data` to import schema only

Tip: Ensure prerequisites are installed. If not, run `sqlpack install-tools --execute` and verify with `sqlpack doctor`.
