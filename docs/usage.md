# Usage Overview

SQLPack provides a unified CLI via `sqlpack` with subcommands for export, import, and data export.

## Quick Examples

```bash
# Bootstrap tools (macOS Homebrew or Ubuntu/Debian apt)
sqlpack install-tools --execute

# Export (creates ./db-export and db-dump.tar.gz)
BASH_LOG=info sqlpack export --server localhost,1433 --database MyApp

# Import into local dev
BASH_LOG=info sqlpack import --archive db-dump.tar.gz --database MyAppDev

# Export data with BCP helper
BASH_LOG=info sqlpack export-data -s "localhost,1499" -d MyDb -D ./data -t ./tables.txt
```

See the individual command pages for flags and environment variables.

Tip: Use `BASH_LOG=trace` to stream all sub-commands and outputs when debugging.
Note: `info` adds progress lines and can bury errors in long outputs; prefer default `error` for CI/long runs. At `info`/`debug`, some tool output is summarized; check the generated logs or switch to `trace` for full console visibility.
