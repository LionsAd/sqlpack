# CI/CD

## GitHub Actions: Export Example

```yaml
name: Database Export
on:
  schedule:
    - cron: '0 2 * * *'
  workflow_dispatch:

jobs:
  export:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install PowerShell
        run: |
          sudo apt-get update
          sudo apt-get install -y powershell

      - name: Install dbatools
        run: pwsh -c "Install-Module dbatools -Force -Scope CurrentUser"

      - name: Export Database
        env:
          DB_SERVER: ${{ secrets.DB_SERVER }}
          DB_NAME: ${{ secrets.DB_NAME }}
          DB_USERNAME: ${{ secrets.DB_USERNAME }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
          # BASH_LOG: info   # uncomment for progress-level logs in CI
          # BASH_LOG: trace  # uncomment to stream all commands and outputs
        run: ./sqlpack export

      - name: Upload Artifact
        uses: actions/upload-artifact@v4
        with:
          name: database-dump
          path: db-dump.tar.gz
```

## GitHub Pages Docs
Docs are built with MkDocs Material and deployed to `gh-pages`. See workflow in `.github/workflows/docs.yml`.
