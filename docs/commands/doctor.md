# Doctor

Validates your environment for SQLPack export/import workflows.

## Usage

```bash
# Shows info-level diagnostics by default (recommended)
sqlpack doctor

# Increase or decrease verbosity
BASH_LOG=debug sqlpack doctor
BASH_LOG=error sqlpack doctor

# Stream every check and command output (trace)
BASH_LOG=trace sqlpack doctor

# Show help
sqlpack doctor --help
```

## What It Checks
- PowerShell (`pwsh`) presence and version
- dbatools PowerShell module is importable
- SQL Server tools: `sqlcmd` and `bcp` on PATH

## Exit Codes
- 0 – All required tools are present
- 1 – One or more checks failed

## Example Output (success)
```text
[INFO]
[INFO] === SQLPack Doctor ===
✓ pwsh: found (/usr/local/bin/pwsh)
✓ dbatools: importable in PowerShell
✓ sqlcmd: found (/opt/homebrew/bin/sqlcmd)
✓ bcp: found (/opt/homebrew/bin/bcp)
[INFO]
[INFO] === SUMMARY ===
✓ All required tools are present.
```

If dbatools is missing, see the Installation guide and dbatools docs at https://docs.dbatools.io/.

Note: `doctor` shows info-level diagnostics by default. Override via `BASH_LOG` as needed (use `trace` for deep debugging).

Tip: If any tools are missing, run `sqlpack install-tools` to preview or `sqlpack install-tools --execute` to automatically install them (macOS Homebrew or Ubuntu/Debian), then re-run `sqlpack doctor`.
