# Configuration

Environment variables and flags control server, authentication, limits, and output locations.

## Common Environment Variables

| Variable | Description |
|----------|-------------|
| `DB_SERVER` | SQL Server instance (e.g., `localhost,1499`) |
| `DB_NAME` | Database name (required for export) |
| `DB_USERNAME` | SQL Server username (omit for trusted connection) |
| `DB_PASSWORD` | SQL Server password |
| `DB_EXPORT_DIR` | Export directory (default: `./db-export`) |
| `DB_ARCHIVE_NAME` | Archive file name (default: `db-dump.tar.gz`) |
| `DB_ROW_LIMIT` | Max rows per table (export) |
| `DB_SCHEMA_ONLY_TABLES` | Comma-separated list of tables to export schema only |

### Logging Environment Variables

| Variable | Description |
|----------|-------------|
| `BASH_LOG` | Log level: `error` (default), `warn`, `info` (recommended), `debug`, `trace` |
| `BASH_LOG_TIMESTAMP` | `true`/`false` to prefix log lines with timestamps |

## Import Defaults
- Working directory: `./db-import-work`
- Logs directory: `./logs/`

## Security Tips
- Prefer trusted connections where possible
- Avoid printing credentials in logs
- Use `DB_TRUST_SERVER_CERTIFICATE` if needed for development
