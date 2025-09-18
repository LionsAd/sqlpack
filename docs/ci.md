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
Docs are built with MkDocs Material and deployed to the `gh-pages` branch via GitHub Actions. See workflow in `.github/workflows/docs.yml`.

### First-Time Setup (GitHub Pages)
- Merge the workflow to `main`. The first successful run creates/updates the `gh-pages` branch.
- In GitHub: Settings → Pages → Build and deployment:
  - Source: Deploy from a branch
  - Branch: `gh-pages` and Folder: `/ (root)`
  - Save. Pages will publish within a minute or two.
- Your site URL will be `https://<user-or-org>.github.io/<repo>/` (e.g., `https://lionsad.github.io/sqlpack/`).

Optional:
- Use a custom domain under Settings → Pages → Custom domain.
- Preview locally with `pip install mkdocs mkdocs-material` then `mkdocs serve`.
