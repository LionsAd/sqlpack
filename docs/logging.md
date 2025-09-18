# Logging

SQLPack scripts support configurable logging for both Bash and PowerShell wrappers.

Recommended defaults:
- Default is `error` to keep failures highly visible (minimal noise).
- Use `info` during interactive runs to see progress, but be aware it can drown out errors in long runs.
- Use `trace` to stream every command and full output for troubleshooting.

Note on error visibility:
- Full tool output is not printed at `error`/`info`/`debug` levels; commands write detailed logs to files and show summaries on failure.
- `error` keeps console output concise so failures stand out (fewer success lines to bury errors).
- `info` adds many success/progress lines, which can make errors easier to miss in long runs. Prefer `error` for CI/long runs; switch to `trace` when you need full, live context.

## Bash Scripts

Use `BASH_LOG` to control verbosity and `BASH_LOG_TIMESTAMP=true` to add timestamps.

```bash
# Default: errors only (quiet)
sqlpack export

# Info level
BASH_LOG=info sqlpack export

# Debug and trace
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

Tip: `sqlpack export`/`commands/export.sh` propagate `BASH_LOG` to PowerShell via `PS_LOG_LEVEL` automatically when set.
```
