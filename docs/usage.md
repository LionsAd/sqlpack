# Usage Overview

SQLPack provides a unified CLI via `sqlpack` with subcommands for export, import, and data export.

## Quick Examples

```bash
# Export (creates ./db-export and db-dump.tar.gz)
sqlpack export --server localhost,1433 --database MyApp

# Import into local dev
sqlpack import --archive db-dump.tar.gz --database MyAppDev

# Export data with BCP helper
sqlpack export-data -s "localhost,1499" -d MyDb -D ./data -t ./tables.txt
```

See the individual command pages for flags and environment variables.

