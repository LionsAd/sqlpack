# Repository Guidelines

## Project Structure & Module Organization
- Root scripts: `export.sh` (CI wrapper), `export.ps1` (PowerShell exporter), `export-data.sh` (BCP helper), `import.sh` (developer import), `run-sqlcmd.sh` (sqlcmd wrapper), `log-common.sh` (logging utils).
- Outputs: default export dir `./db-export` and archive `db-dump.tar.gz`; import uses `./db-import-work` and writes logs to `./logs/` and `/tmp` as noted.
- No build system; this repo is a set of Bash/PowerShell utilities.

## Build, Test, and Development Commands
- Run export (Bash wrapper): `./export.sh --database MyDb --server "localhost,1433" --row-limit 10000`
- Run exporter directly (PowerShell): `pwsh ./export.ps1 -SqlInstance "localhost,1433" -Database "MyDb" -OutputPath ./output`
- Import to local dev: `./import.sh -a db-dump.tar.gz -d MyDbDev -s "localhost,1499" -f`
- Data export helper: `./export-data.sh -s "localhost,1499" -d MyDb -D ./data -t ./tables.txt`
- Logging verbosity: `BASH_LOG=debug ./import.sh ...` or `PS_LOG_LEVEL=trace pwsh ./export.ps1 ...`

## Coding Style & Naming Conventions
- Bash: `#!/bin/bash` with `set -euo pipefail`; 2–4 space indentation; quote all variables; prefer arrays for command args; use `log_*` helpers from `log-common.sh`.
- PowerShell: parameters explicit; use `[switch]` flags and verbose/debug mapped to `PS_LOG_LEVEL`.
- Filenames: lowercase kebab-case (`export-data.sh`); functions lower_snake_case.
- Env/config names: SCREAMING_SNAKE_CASE (e.g., `DB_SERVER`, `DB_ROW_LIMIT`).

## Testing Guidelines
- Lint Bash: `shellcheck *.sh` (fix warnings before submitting).
- Smoke test commands with safe targets (e.g., `-Q "SELECT 1"` via `run-sqlcmd.sh`).
- Optional: add Bats tests under `tests/` for script exit codes and logging; keep fixtures minimal and offline.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (e.g., "Fix commands", "Cleanup logging"); include a focused body when changing behavior.
- PRs: describe purpose, include run examples (commands used), expected outputs/artefacts, and any screenshots of logs; note breaking changes and required env vars; link related issues.

## Security & Configuration Tips
- Do not commit secrets. Use env vars: `DB_USERNAME`, `DB_PASSWORD`, `DB_TRUST_SERVER_CERTIFICATE`.
- Avoid leaking credentials in logs; prefer trusted connections when possible.
- Document server/port assumptions (e.g., `localhost,1499`) in PRs when relevant.

## Agent-Specific Instructions
- Keep changes minimal and cross-platform (macOS/Linux Bash, PowerShell Core on all platforms).
- Reuse logging and wrappers; avoid ad-hoc `echo` or raw `sqlcmd` without `run-sqlcmd.sh` when capturing output matters.
- Update README usage snippets if interfaces change.
