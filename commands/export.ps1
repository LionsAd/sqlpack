#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Exports SQL Server database schema and data for development environment setup
.DESCRIPTION
    Exports complete database schema, stored procedures, views, and table data using dbatools and bcp.
    Creates a portable tar.gz file for easy deployment to developer environments.
.PARAMETER SqlInstance
    SQL Server instance (e.g., "localhost,1433" or "server.domain.com")
.PARAMETER Database
    Database name to export
.PARAMETER Username
    SQL Server username (optional, uses Windows auth if not provided)
.PARAMETER Password
    SQL Server password (optional, uses Windows auth if not provided)
.PARAMETER OutputPath
    Base output directory (default: ./output)
.PARAMETER TarFileName
    Name of the final tar.gz file (default: db-dump.tar.gz)
.PARAMETER ExcludeTables
    Array of tables to exclude from data export (schema still exported)
.PARAMETER DataRowLimit
    Maximum rows per table for data export (default: unlimited)
.EXAMPLE
    .\export-database.ps1 -SqlInstance "localhost,1499" -Database "MyApp" -OutputPath "./exports"
.EXAMPLE
    .\export-database.ps1 -SqlInstance "prod.server.com" -Database "MyApp" -Username "dbuser" -Password "mypass" -DataRowLimit 10000
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SqlInstance,

    [Parameter(Mandatory=$true)]
    [string]$Database,

    [string]$Username,
    [string]$Password,
    [string]$OutputPath = "./output",
    [string]$TarFileName = "db-dump.tar.gz",
    [string[]]$ExcludeTables = @(),
    [int]$DataRowLimit = 0,
    [switch]$TrustServerCertificate
)

# PowerShell Logging System
# Supports PS_LOG_LEVEL environment variable and -Verbose/-Debug switches
# Levels: Error, Warning, Information, Verbose, Debug

# Get effective log level based on environment variable and PowerShell preference variables
# Maps to bash levels: -Debug -> debug, -Verbose -> trace
function Get-LogLevel {
    $envLevel = $env:PS_LOG_LEVEL
    if ($DebugPreference -ne 'SilentlyContinue') { return "debug" }
    if ($VerbosePreference -ne 'SilentlyContinue') { return "trace" }
    if ($envLevel) { return $envLevel }
    return "info"
}

# Convert log level to numeric value for comparison
# 1-1 mapping with bash script levels
function Get-LogLevelValue($Level) {
    switch ($Level.ToLower()) {
        "error" { return 1 }
        "warn" { return 2 }
        "warning" { return 2 }  # Legacy support
        "info" { return 3 }
        "information" { return 3 }  # Legacy support
        "debug" { return 4 }
        "trace" { return 5 }
        "verbose" { return 5 }  # Legacy support, maps to trace
        default { return 1 }
    }
}

# Main logging function
function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet("Error", "Warning", "Information", "Debug", "Trace")]
        [string]$Level = "Information",
        [string]$ForegroundColor
    )

    $currentLevel = Get-LogLevel
    $currentLevelValue = Get-LogLevelValue $currentLevel
    $messageLevelValue = Get-LogLevelValue $Level

    if ($currentLevelValue -ge $messageLevelValue) {
        $timestamp = if ($env:PS_LOG_TIMESTAMP -eq "true") {
            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] "
        } else { "" }

        # Format messages consistently with bash scripts
        switch ($Level) {
            "Error" {
                $prefix = "✗ [ERROR]"
                $color = "Red"
                Write-Host "${timestamp}${prefix} $Message" -ForegroundColor $color
            }
            "Warning" {
                $prefix = "⚠ [WARN]"
                $color = "Yellow"
                Write-Host "${timestamp}${prefix} $Message" -ForegroundColor $color
            }
            "Information" {
                $prefix = "[INFO]"
                $color = if ($ForegroundColor) { $ForegroundColor } else { "Blue" }
                Write-Host "${timestamp}${prefix} $Message" -ForegroundColor $color
            }
            "Debug" {
                $prefix = "[DEBUG]"
                $color = "Gray"
                Write-Host "${timestamp}${prefix} $Message" -ForegroundColor $color
            }
            "Trace" {
                $prefix = "[TRACE]"
                $color = "Magenta"
                Write-Host "${timestamp}${prefix} $Message" -ForegroundColor $color
            }
        }
    }
}

# Convenience functions following PowerShell patterns
function Write-LogError($Message) { Write-LogMessage -Message $Message -Level "Error" }
function Write-LogWarning($Message) { Write-LogMessage -Message $Message -Level "Warning" }
function Write-LogInfo($Message, $Color) { Write-LogMessage -Message $Message -Level "Information" -ForegroundColor $Color }
function Write-LogDebug($Message) { Write-LogMessage -Message $Message -Level "Debug" }
function Write-LogTrace($Message) { Write-LogMessage -Message $Message -Level "Trace" }

function Write-LogSection($Title) {
    Write-LogInfo ""
    Write-LogInfo "=== $Title ===" -Color "Cyan"
}

function Write-LogSuccess($Message) { Write-LogInfo "✓ $Message" -Color "Green" }
function Write-LogProgress($Message) { Write-LogInfo "$Message" -Color "Yellow" }

# Initialize logging
$logLevel = Get-LogLevel
Write-LogDebug "PowerShell logging initialized - Level: $logLevel"

# Import required modules
try {
    Import-Module dbatools -ErrorAction Stop
    Write-LogSuccess "dbatools module loaded"
} catch {
    Write-LogError "dbatools module not found. Install with: Install-Module dbatools -Scope CurrentUser"
    exit 1
}

# Create output directories
$schemaPath = Join-Path $OutputPath "schema.sql"
$tablesListPath = Join-Path $OutputPath "tables.txt"
$dataPath = Join-Path $OutputPath "data"

Write-LogProgress "Creating output directories..."
Write-LogDebug "Output path: $OutputPath, Data path: $dataPath"
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
New-Item -ItemType Directory -Path $dataPath -Force | Out-Null

# Build connection parameters for Connect-DbaInstance
$connectParams = @{
    SqlInstance = $SqlInstance
}

if ($Username -and $Password) {
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($Username, $securePassword)
    $connectParams.SqlCredential = $credential
    Write-LogInfo "Using SQL Server authentication" -Color "Blue"
    Write-LogDebug "Username: $Username"
} else {
    Write-LogInfo "Using Windows authentication" -Color "Blue"
}

if ($TrustServerCertificate) {
    $connectParams.TrustServerCertificate = $true
    Write-LogWarning "Trusting server certificate (bypassing SSL validation)"
    Write-LogDebug "TrustServerCertificate parameter added to connection"
}

# Test connection and get server instance
Write-LogProgress "Testing database connection..."
Write-LogDebug "Connection parameters: SqlInstance=$SqlInstance, Database=$Database"
try {
    $server = Connect-DbaInstance @connectParams
    Write-LogTrace "Server connection established"

    $testDatabase = Get-DbaDatabase -SqlInstance $server | Where-Object Name -eq $Database
    if (-not $testDatabase) {
        throw "Database '$Database' not found"
    }
    Write-LogSuccess "Connected to database: $Database"
    Write-LogDebug "Database object retrieved successfully"
} catch {
    Write-LogError "Failed to connect to database: $_"
    exit 1
}

# Build connection parameters for other dbatools commands
$connectionParams = @{
    SqlInstance = $server
    Database = $Database
}

Write-LogSection "EXPORTING SCHEMA"

# Configure scripting options for schema export
$scriptingOptions = New-DbaScriptingOption
$scriptingOptions.ScriptSchema = $true
$scriptingOptions.ScriptData = $false
$scriptingOptions.Indexes = $true          # Include indexes (clustered and non-clustered)
$scriptingOptions.DriForeignKeys = $true   # Include foreign keys
$scriptingOptions.DriAllConstraints = $true  # Include all constraints (primary keys, foreign keys, etc.)
$scriptingOptions.Triggers = $true         # Include triggers
$scriptingOptions.IncludeDatabaseContext = $true
$scriptingOptions.IncludeHeaders = $false
$scriptingOptions.ScriptBatchTerminator = $true
$scriptingOptions.AnsiFile = $true

Write-LogProgress "Exporting database schema..."
Write-LogDebug "Schema export configured with indexes, constraints, and triggers"

# Export complete database schema
try {
    # Determine output method based on log level
    $currentLogLevel = Get-LogLevel
    $isTraceLevel = (Get-LogLevelValue $currentLogLevel) -ge 5

    # Define export configurations
    $exportConfigs = @(
        @{
            Name = "tables"
            Description = "Exporting tables..."
            Command = "Get-DbaDbTable"
            UseScriptingOptions = $true
            IsFirst = $true
        },
        @{
            Name = "stored procedures"
            Description = "Exporting stored procedures..."
            Command = "Get-DbaDbStoredProcedure"
            UseScriptingOptions = $false
            IsFirst = $false
        },
        @{
            Name = "views"
            Description = "Exporting views..."
            Command = "Get-DbaDbView"
            UseScriptingOptions = $false
            IsFirst = $false
        },
        @{
            Name = "user defined functions"
            Description = "Exporting user defined functions..."
            Command = "Get-DbaDbUdf"
            UseScriptingOptions = $false
            IsFirst = $false
        }
    )

    if ($isTraceLevel) {
        Write-LogTrace "Using direct file output (verbose console output enabled)"
    } else {
        Write-LogDebug "Using PassThru method (suppressing verbose console output)"
    }

    # Process each export configuration
    foreach ($config in $exportConfigs) {
        Write-LogProgress $config.Description

        if ($isTraceLevel) {
            # At trace level - direct file output with verbose console
            $exportParams = @{
                FilePath = $schemaPath
                NoPrefix = $true
            }

            if ($config.UseScriptingOptions) {
                $exportParams.ScriptingOptionsObject = $scriptingOptions
            }
            if (-not $config.IsFirst) {
                $exportParams.Append = $true
            }

            & $config.Command @connectionParams | Export-DbaScript @exportParams

        } else {
            # Below trace level - PassThru method to suppress verbose output
            $exportParams = @{
                NoPrefix = $true
                PassThru = $true
            }

            if ($config.UseScriptingOptions) {
                $exportParams.ScriptingOptionsObject = $scriptingOptions
            }

            $scriptContent = & $config.Command @connectionParams | Export-DbaScript @exportParams

            $fileParams = @{
                FilePath = $schemaPath
                Encoding = "UTF8"
            }
            if (-not $config.IsFirst) {
                $fileParams.Append = $true
            }

            $scriptContent | Out-File @fileParams
        }
    }

    Write-LogSuccess "Schema exported to: $schemaPath"
} catch {
    Write-LogError "Failed to export schema: $_"
    exit 1
}

Write-LogSection "EXPORTING TABLE LIST"

# Get all tables and export list
try {
    $tables = Get-DbaDbTable @connectionParams
    $tableList = $tables | ForEach-Object {
        "$($_.Parent.Name).$($_.Schema).$($_.Name)"
    }

    $tableList | Out-File -FilePath $tablesListPath -Encoding UTF8
    Write-LogSuccess "Table list exported to: $tablesListPath"
    Write-LogInfo "Found $($tables.Count) tables" -Color "Blue"
    Write-LogDebug "Table list format: Database.Schema.Table"
} catch {
    Write-LogError "Failed to export table list: $_"
    exit 1
}

Write-LogSection "CALLING EXPORT DATA SCRIPT"

# Prepare parameters for bash script
$bashScriptPath = Join-Path $PSScriptRoot "export-data.sh"
Write-LogDebug "Bash script path: $bashScriptPath"

if (-not (Test-Path $bashScriptPath)) {
    Write-LogError "export-data.sh not found at: $bashScriptPath"
    exit 1
}

# Build parameters for the bash script using proper arguments
$bashArgs = @(
    "-s", "'$SqlInstance'"
    "-d", "'$Database'"
    "-D", "'$dataPath'"
    "-t", "'$tablesListPath'"
)

# Add optional parameters
if ($Username -and $Password) {
    $bashArgs += "-u", "'$Username'"
    $bashArgs += "-p", "'$Password'"
}

if ($DataRowLimit -gt 0) {
    $bashArgs += "--row-limit", $DataRowLimit.ToString()
}

if ($TrustServerCertificate) {
    $bashArgs += "--trust-server-certificate"
}

Write-LogProgress "Calling export-data.sh with arguments..."
Write-LogTrace "Script: $bashScriptPath"
Write-LogDebug "Initial arguments: $($bashArgs -join ' ')"

# Convert relative paths to absolute paths for bash script
$absoluteDataPath = Resolve-Path $dataPath | Select-Object -ExpandProperty Path
$absoluteTablesPath = Resolve-Path $tablesListPath | Select-Object -ExpandProperty Path

# Update bash args with absolute paths
$bashArgs = @(
    "-s", $SqlInstance
    "-d", $Database
    "-D", $absoluteDataPath
    "-t", $absoluteTablesPath
)

# Add optional parameters
if ($Username -and $Password) {
    $bashArgs += "-u", $Username
    $bashArgs += "-p", $Password
}

if ($DataRowLimit -gt 0) {
    $bashArgs += "--row-limit", $DataRowLimit.ToString()
}

if ($TrustServerCertificate) {
    $bashArgs += "--trust-server-certificate"
}

Write-LogDebug "Final arguments with absolute paths: $($bashArgs -join ' ')"

# Execute the bash script with direct output (no capturing)
try {
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        Write-LogTrace "Executing bash command with export-data.sh"
        Write-LogDebug "Full command: bash '$bashScriptPath' $($bashArgs -join ' ')"

        # Execute directly without capturing output - let it pass through
        & bash $bashScriptPath @bashArgs
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-LogSuccess "Data export completed successfully"
        } elseif ($exitCode -eq 1) {
            Write-LogWarning "Data export completed with some failures - continuing with archive creation"
        } else {
            Write-LogError "Data export failed completely with exit code: $exitCode"
            exit $exitCode
        }
    } else {
        Write-LogError "bash command not found. Please ensure bash is installed and in PATH."
        exit 1
    }
} catch {
    Write-LogError "Failed to execute export-data.sh: $_"
    Write-LogDebug "Exception details: $($_.Exception.Message)"
    exit 1
}

Write-LogSection "CREATING ARCHIVE"

# Create tar.gz archive
$tarPath = Join-Path (Split-Path $OutputPath -Parent) $TarFileName

try {
    # Change to output directory for relative paths in tar
    Push-Location $OutputPath

    # Create tar.gz file
    Write-LogDebug "Archive path: $tarPath"
    if (Get-Command tar -ErrorAction SilentlyContinue) {
        Write-LogProgress "Creating tar.gz archive using system tar..."
        Write-LogTrace "Archive contents: schema.sql, tables.txt, data/"
        & tar -czf $tarPath schema.sql tables.txt data/

        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "Archive created: $tarPath"
        } else {
            throw "tar command failed with exit code $LASTEXITCODE"
        }
    } else {
        # Fallback to PowerShell compression (creates .zip instead of .tar.gz)
        $zipPath = $tarPath -replace '\.tar\.gz$', '.zip'
        Write-LogWarning "tar not found, creating ZIP archive instead..."
        Write-LogDebug "ZIP path: $zipPath"
        Compress-Archive -Path "schema.sql", "tables.txt", "data" -DestinationPath $zipPath -Force
        Write-LogSuccess "ZIP archive created: $zipPath"
    }
} catch {
    Write-LogError "Failed to create archive: $_"
    exit 1
} finally {
    Pop-Location
}

Write-LogSection "EXPORT COMPLETE"
Write-LogSuccess "Database export completed successfully!"
Write-LogInfo "Files created:" -Color "Blue"
Write-LogInfo "  - Schema: $schemaPath" -Color "Gray"
Write-LogInfo "  - Tables: $tablesListPath" -Color "Gray"
Write-LogInfo "  - Data: $dataPath" -Color "Gray"
Write-LogInfo "  - Archive: $tarPath" -Color "Gray"
Write-LogDebug "Export process finished with all components"
