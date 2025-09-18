# SQLPack

A cross-platform toolkit to export SQL Server databases and import them into developer environments. SQLPack unifies Bash and PowerShell helpers behind a single `sqlpack` CLI for consistent usage on macOS, Linux, and Windows.

## Quick Start

Prerequisites (tools): see Installation for setup. You need `sqlcmd` and `bcp` (mssql-tools18), PowerShell 7+ (`pwsh`), and the dbatools module.

Tip on verbosity: commands are quiet at the default `BASH_LOG=error`. For day‑to‑day runs, `BASH_LOG=info` shows progress; use `BASH_LOG=trace` to see everything (full tool output). At `info`/`debug`, detailed tool output may be summarized; open the referenced logs or use `trace` for full console visibility.

Caution: `info` adds many success/progress lines and can make errors easier to overlook in long runs. The default `error` level is intentional to keep failures obvious; prefer it for CI or longer unattended runs.

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
BASH_LOG=info sqlpack export --server localhost,1433 --database MyApp

# 5) Import into a local dev instance
BASH_LOG=info sqlpack import --archive db-dump.tar.gz --database MyAppDev

# 6) Explore help for flags and env vars
sqlpack help
sqlpack export --help
sqlpack import --help
```

- `sqlpack install-tools` previews or executes tool installation steps.
- Use `sqlpack doctor` before first use or when troubleshooting.
- See [Installation](install.md) to set up tools and environment.
- See [Usage](usage.md) for common flows and quick examples.
- See [Logging](logging.md) for recommended verbosity and tips.
- Commands reference: [Export](commands/export.md), [Import](commands/import.md), [Export Data](commands/export-data.md), [Doctor](commands/doctor.md), [Install Tools](commands/install-tools.md).

## What You Get
- Repeatable exports for CI with schema + data
- Developer-friendly imports with logs in `./logs/`
- Cross-platform scripts with consistent logging and flags

## Links
- Repository: https://github.com/LionsAd/sqlpack
- Issues: https://github.com/LionsAd/sqlpack/issues
