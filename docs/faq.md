# FAQ

## Common Export Issues
- dbatools not found: `Install-Module dbatools -Scope CurrentUser -Force`
- `bcp` not found: install SQL Server command line tools and ensure PATH
- Connection timeouts: verify firewall, remote connections, test with `sqlcmd`

## Common Import Issues
- Database exists: use `--force` to recreate
- Permission denied: ensure user has CREATE DATABASE rights
- Data mismatches: check schema alignment and constraints

## Where are logs?
- Import logs under `./logs/` with per-file details

