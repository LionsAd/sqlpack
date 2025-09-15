# Installation

## System-wide Install

```bash
# Install to /usr/local (requires sudo)
sudo make install

# Or install to a custom prefix (no sudo)
PREFIX=$HOME/.local make install
export PATH="$HOME/.local/bin:$PATH"
```

## Development Usage

```bash
# Run directly from source
./sqlpack help
```

## Uninstall

```bash
sudo make uninstall

# Or for custom prefix
PREFIX=$HOME/.local make uninstall
```

## Prerequisites
- PowerShell Core for export in CI (dbatools module)
- SQL Server client tools (`sqlcmd`, `bcp` as needed)
- tar utility (usually available on macOS/Linux)

## Install sqlcmd and bcp (mssql-tools18)

### macOS (Homebrew)

```bash
# Tap Microsoft's Homebrew repo
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release

# Accept EULA and install ODBC + tools
ACCEPT_EULA=Y brew install msodbcsql18 mssql-tools18

# Add mssql-tools18 to PATH (Apple Silicon)
echo 'export PATH="/opt/homebrew/opt/mssql-tools18/bin:$PATH"' >> ~/.zshrc

# For Intel Macs use:
# echo 'export PATH="/usr/local/opt/mssql-tools18/bin:$PATH"' >> ~/.zshrc

# Reload shell config (or open a new terminal)
source ~/.zshrc

# Verify
sqlcmd -?
bcp -?
```

If you run into issues or use a different OS, see Microsoft’s official docs for installing SQL Server tools.

### Ubuntu/Debian (summary)

Follow Microsoft’s instructions to add the package repo, then install:

```bash
sudo apt-get update
sudo apt-get install -y msodbcsql18 mssql-tools18
echo 'export PATH="/opt/mssql-tools18/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
sqlcmd -?
```

## Install PowerShell and dbatools

### macOS

```bash
# Install PowerShell
brew install --cask powershell

# Verify
pwsh -v

# Install dbatools module (current user scope)
pwsh -NoLogo -NoProfile -Command "Install-Module dbatools -Scope CurrentUser -Force"

# Verify module loads
pwsh -NoLogo -NoProfile -Command "Import-Module dbatools; Get-Module dbatools"
```

### Ubuntu/Debian (summary)

```bash
sudo apt-get update && sudo apt-get install -y powershell
pwsh -NoLogo -NoProfile -Command "Install-Module dbatools -Scope CurrentUser -Force"
```
