# Development

## Lint and Tests

```bash
# Lint Bash scripts
make lint

# Run tests (bats)
make test
```

## Useful Commands

```bash
# Help
./sqlpack help

# Export
./sqlpack export --server localhost,1433 --database MyDb

# Import
./sqlpack import --archive db-dump.tar.gz --database MyDbDev

# Export Data (BCP)
./sqlpack export-data -s "localhost,1499" -d MyDb -D ./data -t ./tables.txt
```

## Guidelines
- Bash: `#!/bin/bash` + `set -euo pipefail`, quote vars, prefer arrays
- PowerShell: explicit parameters, use `[switch]` flags, map to `-Verbose`/`-Debug`
- Filenames: lowercase kebab-case; functions: lower_snake_case

