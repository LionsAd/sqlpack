# Doctor

Validates your environment for SQLPack export/import workflows.

## Usage

```bash
# Shows diagnostic output by default
sqlpack doctor

# Adjust verbosity if needed
BASH_LOG=debug sqlpack doctor
BASH_LOG=error sqlpack doctor

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

Note: `doctor` shows info-level diagnostics by default. You can still override verbosity via `BASH_LOG` (e.g., `debug`, `error`).
