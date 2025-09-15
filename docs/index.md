# SQLPack

A cross-platform toolkit to export SQL Server databases and import them into developer environments. SQLPack unifies Bash and PowerShell helpers behind a single `sqlpack` CLI for consistent usage on macOS, Linux, and Windows.

## Quick Start

```bash
# Install to /usr/local (requires sudo)
sudo make install

# Export a database (creates ./db-export and db-dump.tar.gz)
sqlpack export --server localhost,1433 --database MyApp

# Import into a local dev instance
sqlpack import --archive db-dump.tar.gz --database MyAppDev

# Help
sqlpack help
sqlpack export --help
```

- See Installation for system and dev setup.
- See Usage for an overview and common flows.
- See Commands for detailed options per subcommand.

## What You Get
- Repeatable exports for CI with schema + data
- Developer-friendly imports with logs in `./logs/`
- Cross-platform scripts with consistent logging and flags

## Links
- Repository: https://github.com/LionsAd/sqlpack
- Issues: https://github.com/LionsAd/sqlpack/issues

