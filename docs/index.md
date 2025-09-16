# SQLPack

A cross-platform toolkit to export SQL Server databases and import them into developer environments. SQLPack unifies Bash and PowerShell helpers behind a single `sqlpack` CLI for consistent usage on macOS, Linux, and Windows.

## Quick Start

Prerequisites (tools): see Installation for setup. You need `sqlcmd` and `bcp` (mssql-tools18), PowerShell 7+ (`pwsh`), and the dbatools module.

```bash
# 1) Install SQLPack (to /usr/local; use PREFIX for custom path)
sudo make install

# 2) Install required tools (preview or execute)
# Preview the commands for your OS
sqlpack install-tools
# Execute them automatically (macOS Homebrew or Ubuntu/Debian apt)
sqlpack install-tools --execute

# 3) Validate your environment (PowerShell, dbatools, sqlcmd, bcp)
sqlpack doctor

# 4) Export a database (creates ./db-export and db-dump.tar.gz)
sqlpack export --server localhost,1433 --database MyApp

# 5) Import into a local dev instance
sqlpack import --archive db-dump.tar.gz --database MyAppDev

# 6) Explore help for flags and env vars
sqlpack help
sqlpack export --help
sqlpack import --help
```

- `sqlpack install-tools` previews or executes tool installation steps.
- Use `sqlpack doctor` before first use or when troubleshooting.
- See [Installation](install.md) to set up tools and environment.
- See [Usage](usage.md) for common flows and quick examples.
- See [Commands] for detailed flags: [Export](commands/export.md), [Import](commands/import.md), [Export Data](commands/export-data.md), [Doctor](commands/doctor.md).

## What You Get
- Repeatable exports for CI with schema + data
- Developer-friendly imports with logs in `./logs/`
- Cross-platform scripts with consistent logging and flags

## Links
- Repository: https://github.com/LionsAd/sqlpack
- Issues: https://github.com/LionsAd/sqlpack/issues
