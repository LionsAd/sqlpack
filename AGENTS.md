# Repository Guidelines

## Project Structure & Module Organization
- Entry point: `sqlpack` (unified CLI dispatcher for subcommands).
- Subcommands and utilities live under `./commands/`:
  - `export.sh` (CI wrapper) → calls `export.ps1`
  - `export.ps1` (PowerShell exporter using dbatools)
  - `import.sh` (developer import)
  - `export-data.sh` (BCP helper; native format + .fmt files)
  - `run-sqlcmd.sh` (sqlcmd wrapper), `log-common.sh` (logging utils)
- Installed layout: `sqlpack` in `/usr/local/bin` and scripts in `/usr/local/lib/sqlpack/commands` (via `make install`).
- Outputs: default export dir `./db-export` and archive `db-dump.tar.gz` when using `sqlpack export`/`commands/export.sh`. Import uses `./db-import-work` and writes logs to `./logs/`.

## Build, Test, and Development Commands
- Use CLI: `./sqlpack help`, `./sqlpack export ...`, `./sqlpack import ...`, `./sqlpack export-data ...`.
- Install/uninstall: `sudo make install`, `sudo make uninstall` (or set `PREFIX=$HOME/.local`).
- Lint Bash: `make lint` (uses `shellcheck -x` if available).
- Run Bats tests: `make test` (runs tests in `tests/` if `bats` is installed).
- Direct scripts (advanced):
  - PowerShell exporter: `pwsh ./commands/export.ps1 -SqlInstance "localhost,1433" -Database "MyDb" -OutputPath ./output`
  - CI wrapper: `./commands/export.sh --database MyDb --server "localhost,1433" --row-limit 10000`
  - Data export helper: `./sqlpack export-data -s "localhost,1499" -d MyDb -D ./data -t ./tables.txt`
- Logging verbosity: `BASH_LOG=debug ./sqlpack import ...` or `PS_LOG_LEVEL=trace pwsh ./commands/export.ps1 ...`.

## Coding Style & Naming Conventions
- Bash: `#!/bin/bash` with `set -euo pipefail`; 2–4 space indentation; quote all variables; prefer arrays for command args; use `log_*` helpers from `log-common.sh`.
- PowerShell: parameters explicit; use `[switch]` flags and map verbose/debug to `PS_LOG_LEVEL`/`-Verbose`/`-Debug`.
- Filenames: lowercase kebab-case (`export-data.sh`); functions lower_snake_case.
- Env/config names: SCREAMING_SNAKE_CASE (e.g., `DB_SERVER`, `DB_ROW_LIMIT`).

## Testing Guidelines
- Lint Bash with `make lint` or `shellcheck -x *.sh` (fix warnings before submitting).
- Smoke test with safe queries via `run-sqlcmd.sh` (e.g., `-Q "SELECT 1"`).
- Optional: add Bats tests under `tests/` for script exit codes and logging; keep fixtures minimal and offline.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects (e.g., "Fix commands", "Cleanup logging"); include a focused body when changing behavior.
- PRs: describe purpose, include run examples (`sqlpack` commands used), expected outputs/artifacts, and any screenshots of logs; note breaking changes and required env vars; link related issues.

## Security & Configuration Tips
- Do not commit secrets. Use env vars: `DB_USERNAME`, `DB_PASSWORD`, `DB_TRUST_SERVER_CERTIFICATE`.
- Avoid leaking credentials in logs; prefer trusted connections when possible.
- Document server/port assumptions (e.g., `localhost,1499`) in PRs when relevant.

## Agent-Specific Instructions
- Prefer the `sqlpack` entrypoint; keep changes minimal and cross‑platform (macOS/Linux Bash, PowerShell Core).
- Reuse logging and wrappers; avoid ad‑hoc `echo` or raw `sqlcmd` without `run-sqlcmd.sh` when capturing output matters.
- Update README usage snippets if interfaces change.
