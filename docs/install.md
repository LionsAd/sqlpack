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

