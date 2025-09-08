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

# Import required modules
try {
    Import-Module dbatools -ErrorAction Stop
    Write-Host "✓ dbatools module loaded" -ForegroundColor Green
} catch {
    Write-Error "dbatools module not found. Install with: Install-Module dbatools -Scope CurrentUser"
    exit 1
}

# Create output directories
$schemaPath = Join-Path $OutputPath "schema.sql"
$tablesListPath = Join-Path $OutputPath "tables.txt"
$dataPath = Join-Path $OutputPath "data"

Write-Host "Creating output directories..." -ForegroundColor Yellow
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
    Write-Host "Using SQL Server authentication" -ForegroundColor Blue
} else {
    Write-Host "Using Windows authentication" -ForegroundColor Blue
}

if ($TrustServerCertificate) {
    $connectParams.TrustServerCertificate = $true
    Write-Host "Trusting server certificate (bypassing SSL validation)" -ForegroundColor Yellow
}

# Test connection and get server instance
Write-Host "Testing database connection..." -ForegroundColor Yellow
try {
    $server = Connect-DbaInstance @connectParams
    $testDatabase = Get-DbaDatabase -SqlInstance $server | Where-Object Name -eq $Database
    if (-not $testDatabase) {
        throw "Database '$Database' not found"
    }
    Write-Host "✓ Connected to database: $Database" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to database: $_"
    exit 1
}

# Build connection parameters for other dbatools commands
$connectionParams = @{
    SqlInstance = $server
    Database = $Database
}

Write-Host "`n=== EXPORTING SCHEMA ===" -ForegroundColor Cyan

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

Write-Host "Exporting database schema..." -ForegroundColor Yellow

# Export complete database schema
try {
    # Export tables (schema only)
    Write-Host "Exporting tables..." -ForegroundColor Yellow
    Get-DbaDbTable @connectionParams | Export-DbaScript -ScriptingOptionsObject $scriptingOptions -FilePath $schemaPath -NoPrefix

    # Export stored procedures
    Write-Host "Exporting stored procedures..." -ForegroundColor Yellow
    Get-DbaDbStoredProcedure @connectionParams | Export-DbaScript -FilePath $schemaPath -Append -NoPrefix

    # Export views
    Write-Host "Exporting views..." -ForegroundColor Yellow
    Get-DbaDbView @connectionParams | Export-DbaScript -FilePath $schemaPath -Append -NoPrefix

    # Export user defined functions
    Write-Host "Exporting user defined functions..." -ForegroundColor Yellow
    Get-DbaDbUdf @connectionParams | Export-DbaScript -FilePath $schemaPath -Append -NoPrefix

    Write-Host "✓ Schema exported to: $schemaPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to export schema: $_"
    exit 1
}

Write-Host "`n=== EXPORTING TABLE LIST ===" -ForegroundColor Cyan

# Get all tables and export list
try {
    $tables = Get-DbaDbTable @connectionParams | Where-Object { -not $_.IsSystemObject }
    $tableList = $tables | ForEach-Object {
        "$($_.Parent.Name).$($_.Schema).$($_.Name)"
    }

    $tableList | Out-File -FilePath $tablesListPath -Encoding UTF8
    Write-Host "✓ Table list exported to: $tablesListPath" -ForegroundColor Green
    Write-Host "Found $($tables.Count) tables" -ForegroundColor Blue
} catch {
    Write-Error "Failed to export table list: $_"
    exit 1
}

Write-Host "`n=== EXPORTING DATA ===" -ForegroundColor Cyan

# Prepare bcp command parameters
$bcpParams = @()
if ($Username -and $Password) {
    $bcpParams += "-U", $Username, "-P", $Password
} else {
    $bcpParams += "-T"  # Trusted connection
}

# Export data for each table using bcp
$exportedTables = 0
$failedTables = 0

foreach ($table in $tables) {
    $tableName = $table.Name
    $schemaName = $table.Schema
    $fullTableName = "[$Database].[$schemaName].[$tableName]"
    $fileName = "$schemaName.$tableName.csv"
    $filePath = Join-Path $dataPath $fileName

    # Skip excluded tables
    if ($ExcludeTables -contains $tableName -or $ExcludeTables -contains "$schemaName.$tableName") {
        Write-Host "Skipping excluded table: $fullTableName" -ForegroundColor DarkYellow
        continue
    }

    Write-Host "Exporting data: $fullTableName" -ForegroundColor Yellow

    try {
        # Build bcp command
        $query = "SELECT * FROM $fullTableName"
        if ($DataRowLimit -gt 0) {
            $query = "SELECT TOP $DataRowLimit * FROM $fullTableName"
        }

        # Use bcp to export data
        $bcpCommand = @(
            "bcp"
            "`"$query`""
            "queryout"
            "`"$filePath`""
            "-c"  # Character format
            "-t,"  # Field terminator (comma)
            "-r\n"  # Row terminator
            "-S"
            $SqlInstance
        ) + $bcpParams

        $result = & $bcpCommand[0] $bcpCommand[1..($bcpCommand.Length-1)] 2>&1

        if ($LASTEXITCODE -eq 0) {
            $exportedTables++
            Write-Host "✓ Exported: $fileName" -ForegroundColor Green
        } else {
            $failedTables++
            Write-Warning "Failed to export $fullTableName`: $result"
        }
    } catch {
        $failedTables++
        Write-Warning "Failed to export $fullTableName`: $_"
    }
}

Write-Host "`n=== EXPORT SUMMARY ===" -ForegroundColor Cyan
Write-Host "Tables exported: $exportedTables" -ForegroundColor Green
Write-Host "Tables failed: $failedTables" -ForegroundColor $(if ($failedTables -gt 0) { "Red" } else { "Green" })

Write-Host "`n=== CREATING ARCHIVE ===" -ForegroundColor Cyan

# Create tar.gz archive
$tarPath = Join-Path (Split-Path $OutputPath -Parent) $TarFileName

try {
    # Change to output directory for relative paths in tar
    Push-Location $OutputPath

    # Create tar.gz file
    if (Get-Command tar -ErrorAction SilentlyContinue) {
        Write-Host "Creating tar.gz archive using system tar..." -ForegroundColor Yellow
        & tar -czf $tarPath schema.sql tables.txt data/

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Archive created: $tarPath" -ForegroundColor Green
        } else {
            throw "tar command failed with exit code $LASTEXITCODE"
        }
    } else {
        # Fallback to PowerShell compression (creates .zip instead of .tar.gz)
        $zipPath = $tarPath -replace '\.tar\.gz$', '.zip'
        Write-Host "tar not found, creating ZIP archive instead..." -ForegroundColor Yellow
        Compress-Archive -Path "schema.sql", "tables.txt", "data" -DestinationPath $zipPath -Force
        Write-Host "✓ ZIP archive created: $zipPath" -ForegroundColor Green
    }
} catch {
    Write-Error "Failed to create archive: $_"
    exit 1
} finally {
    Pop-Location
}

Write-Host "`n=== EXPORT COMPLETE ===" -ForegroundColor Green
Write-Host "Database export completed successfully!" -ForegroundColor Green
Write-Host "Files created:" -ForegroundColor Blue
Write-Host "  - Schema: $schemaPath" -ForegroundColor Gray
Write-Host "  - Tables: $tablesListPath" -ForegroundColor Gray
Write-Host "  - Data: $dataPath" -ForegroundColor Gray
Write-Host "  - Archive: $tarPath" -ForegroundColor Gray
