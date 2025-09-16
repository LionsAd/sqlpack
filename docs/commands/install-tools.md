# Install Tools

Bootstraps required tools for SQLPack workflows. Detects the OS and prints or executes the appropriate install commands for:
- mssql-tools18 (`sqlcmd`, `bcp`)
- PowerShell (`pwsh`)
- dbatools PowerShell module

## Usage

```bash
# Preview required commands for your OS
sqlpack install-tools

# Execute install commands (macOS Homebrew or Ubuntu/Debian apt)
sqlpack install-tools --execute

# Help
sqlpack install-tools --help
```

## Options
- `--execute` – Run the printed commands in order. Without this flag, the script only prints the commands.

## Supported Systems
- macOS (Homebrew)
- Ubuntu/Debian (apt)

For other distributions, follow the manual steps in Installation.

## Notes
- On macOS, Homebrew commands accept the Microsoft EULA for `msodbcsql18`/`mssql-tools18`.
- On Ubuntu/Debian, `sudo` is required for `apt` commands.
- Re-run `sqlpack doctor` after install to verify tools are available on `PATH`.
- Increase verbosity with `BASH_LOG=debug sqlpack install-tools --execute`.

## Exit Codes
- 0 – Success (printed or executed)
- 1 – Unsupported OS or execution failure
- 2 – Usage error

