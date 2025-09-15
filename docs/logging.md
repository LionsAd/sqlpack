# Logging

SQLPack scripts support configurable logging for both Bash and PowerShell wrappers.

## Bash Scripts

Use `BASH_LOG` to control verbosity and `BASH_LOG_TIMESTAMP=true` to add timestamps.

```bash
# Default: errors only
sqlpack export

# Info level
BASH_LOG=info sqlpack export

# Debug/trace
BASH_LOG=debug sqlpack export-data
BASH_LOG=trace sqlpack import

# Add timestamps
BASH_LOG_TIMESTAMP=true BASH_LOG=debug sqlpack export
```

Log files for import are written to `./logs/`.

## PowerShell (export.ps1)

Use `-Verbose`, `-Debug`, or `PS_LOG_LEVEL`.

```powershell
# Verbose
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db" -Verbose

# Debug
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db" -Debug

# Environment variable
$env:PS_LOG_LEVEL = "Debug"
pwsh ./commands/export.ps1 -SqlInstance "server" -Database "db"
```

