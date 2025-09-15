# Import

Imports a previously created `db-dump.tar.gz` archive into a target database.

## Examples

```bash
# Basic import into local dev instance
sqlpack import --archive db-dump.tar.gz --database MyAppDev

# Custom server/auth and force recreate
sqlpack import \
  --archive db-dump.tar.gz \
  --database MyAppDev \
  --server "localhost,1499" \
  --username sa \
  --password MyPassword \
  --force
```

## Notes
- Working directory: `./db-import-work`
- Logs written to: `./logs/`
- Use `--skip-data` to import schema only

