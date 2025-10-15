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
.PARAMETER SchemaOnlyTables
    Array of tables to export schema only (no data), like mysqldump --schema-only-tables
.PARAMETER DataRowLimit
    Maximum rows per table for data export (default: unlimited)
.EXAMPLE
    .\export-database.ps1 -SqlInstance "localhost,1499" -Database "MyApp" -OutputPath "./exports"
.EXAMPLE
    .\export-database.ps1 -SqlInstance "prod.server.com" -Database "MyApp" -Username "dbuser" -Password "mypass" -DataRowLimit 10000
.EXAMPLE
    .\export-database.ps1 -SqlInstance "localhost,1499" -Database "MyApp" -SchemaOnlyTables "AuditLog","TempData","SessionLog"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SqlInstance,

    [Parameter(Mandatory=$true)]
    [string]$Database,

    [string]$Username,
    [string]$Password,
    [string]$OutputPath = "./db-export",
    [string]$TarFileName = "db-dump.tar.gz",
    [string[]]$SchemaOnlyTables = @(),
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
                if ($ForegroundColor) {
                    Write-Host "${timestamp}${prefix} $Message" -ForegroundColor $ForegroundColor
                } else {
                    Write-Host "${timestamp}${prefix} $Message"
                }
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

# Helper function for database export
function Export-Database {
    param(
        [string]$SqlInstance,
        [string]$Database,
        [string]$Username,
        [string]$Password,
        [string]$OutputPath,
        [string]$TarFileName,
        [string[]]$SchemaOnlyTables,
        [int]$DataRowLimit,
        [switch]$TrustServerCertificate
    )

    # Create output directories
    $schemaPath = Join-Path $OutputPath "schema.sql"
    $tablesListPath = Join-Path $OutputPath "tables.txt"
    $dataPath = Join-Path $OutputPath "data"

    Write-LogDebug "Creating output directories..."
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
        Write-LogDebug "Using SQL Server authentication"
        Write-LogDebug "Username: $Username"
    } else {
        Write-LogDebug "Using Windows authentication"
    }

    if ($TrustServerCertificate) {
        $connectParams.TrustServerCertificate = $true
        Write-LogWarning "Trusting server certificate (bypassing SSL validation)"
        Write-LogDebug "TrustServerCertificate parameter added to connection"
    }

    # Test connection and get server instance
    Write-LogDebug "Testing database connection..."
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
        throw "Database connection failed"
    }

    # Build connection parameters for other dbatools commands
    $connectionParams = @{
        SqlInstance = $server
        Database = $Database
    }

    # Export schema
    try {
        #Write-LogSuccess "Connected to database..."
        Export-DatabaseSchema -ConnectionParams $connectionParams -SchemaPath $schemaPath
    } catch {
        Write-LogError "Schema export failed: $_"
        throw "Schema export failed"
    }

    # Export table list
    try {
        Export-TableList -ConnectionParams $connectionParams -TablesListPath $tablesListPath
    } catch {
        Write-LogError "Table list export failed: $_"
        throw "Table list export failed"
    }

    # Export data using bash script
    try {
        # Call without assignment to avoid capturing output, then check exit code
        Export-TableData -SqlInstance $SqlInstance -Database $Database -Username $Username -Password $Password -DataPath $dataPath -TablesListPath $tablesListPath -SchemaOnlyTables $SchemaOnlyTables -DataRowLimit $DataRowLimit -TrustServerCertificate $TrustServerCertificate
        $dataExportSuccess = $?
        if (-not $dataExportSuccess) {
            throw "Data export failed"
        }
    } catch {
        Write-LogError "Data export failed: $_"
        throw "Data export failed"
    }

    # Create archive
    try {
        Create-DatabaseArchive -OutputPath $OutputPath -TarFileName $TarFileName
    } catch {
        Write-LogError "Archive creation failed: $_"
        throw "Archive creation failed"
    }

    # Success - no explicit return needed
}

function Export-DatabaseSchema {
    param(
        [hashtable]$ConnectionParams,
        [string]$SchemaPath
    )

    Write-LogSection "EXPORTING SCHEMA"

    # Configure scripting options for schema export
    $scriptingOptions = New-DbaScriptingOption
    $scriptingOptions.ScriptSchema = $true
    $scriptingOptions.ScriptData = $false
    $scriptingOptions.Indexes = $true          # Include indexes (clustered and non-clustered)
    $scriptingOptions.DriForeignKeys = $false # Export foreign keys separately
    $scriptingOptions.DriAllConstraints = $false # Export constraints separately
    $scriptingOptions.DriPrimaryKey = $true    # Keep primary keys with tables
    $scriptingOptions.DriChecks = $false       # Export check constraints separately
    $scriptingOptions.Triggers = $false        # Export triggers separately
    $scriptingOptions.IncludeDatabaseContext = $false
    $scriptingOptions.IncludeHeaders = $true
    $scriptingOptions.ScriptBatchTerminator = $true
    $scriptingOptions.AnsiFile = $true

    Write-LogDebug "Exporting database schema..."
    Write-LogDebug "Schema export configured with indexes, constraints, and triggers"

    # Determine output method based on log level
    $currentLogLevel = Get-LogLevel
    $isTraceLevel = (Get-LogLevelValue $currentLogLevel) -ge 5

    # Helper functions for database object retrieval with consistent parameters
    function Get-DbaTables {
        param([hashtable]$ConnectionParams)
        Get-DbaDbTable @ConnectionParams  # Already excludes system tables by default
    }

    function Get-DbaViews {
        param([hashtable]$ConnectionParams)
        Get-DbaDbView @ConnectionParams -ExcludeSystemView
    }

    function Get-DbaStoredProcedures {
        param([hashtable]$ConnectionParams)
        Get-DbaDbStoredProcedure @ConnectionParams -ExcludeSystemSp
    }

    function Get-DbaUserDefinedFunctions {
        param([hashtable]$ConnectionParams)
        Get-DbaDbUdf @ConnectionParams -ExcludeSystemUdf
    }

    # SQL processing function to add IF NOT EXISTS checks
    function Add-IfNotExistsToSql {
        param([string]$FilePath)

        $content = Get-Content $FilePath -Raw
        $lines = $content -split "`n"
        $processedLines = @()

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            # Check if this line starts a CREATE TABLE statement
            # Pattern matches: CREATE TABLE [schema].[table] or CREATE TABLE [table] (defaults to dbo)
            if ($line -match '^CREATE TABLE\s+(?:\[?(\w+)\]?\.)?\[?(\w+)\]?') {
                $schemaName = if ($matches[1]) { $matches[1] } else { "dbo" }
                $tableName = $matches[2]

                Write-LogDebug "Found CREATE TABLE for [$schemaName].[$tableName]"

                # Add IF NOT EXISTS check before CREATE TABLE
                $ifNotExistsCheck = @(
                    "IF NOT EXISTS (",
                    "    SELECT * FROM INFORMATION_SCHEMA.TABLES",
                    "    WHERE TABLE_SCHEMA = '$schemaName'",
                    "    AND TABLE_TYPE = 'BASE TABLE'",
                    "    AND TABLE_NAME = '$tableName'",
                    ")"
                )

                $processedLines += $ifNotExistsCheck
                $processedLines += $line
            }
            else {
                $processedLines += $line
            }
        }

        return $processedLines -join "`n"
    }

    # Define export configurations - each component gets its own file
    # Order: tables -> constraints -> procedures -> views -> functions
    $exportConfigs = @(
        @{
            Name = "tables"
            Description = "Exporting tables..."
            Command = "Get-DbaTables"
            UseScriptingOptions = $true
            FileName = "schema-tables.sql"
        },
        @{
            Name = "constraints"
            Description = "Exporting foreign keys and constraints..."
            Command = "Get-DbaTables"
            UseScriptingOptions = $true
            FileName = "schema-constraints--unfiltered.sql"
            OptionsKey = "constraints"
            FilterToFile = "schema-constraints.sql"  # Filtered version
        },
        @{
            Name = "stored procedures"
            Description = "Exporting stored procedures..."
            Command = "Get-DbaStoredProcedures"
            UseScriptingOptions = $false
            FileName = "schema-procedures.sql"
        },
        @{
            Name = "user defined functions"
            Description = "Exporting user defined functions..."
            Command = "Get-DbaUserDefinedFunctions"
            UseScriptingOptions = $false
            FileName = "schema-functions.sql"
        },
        @{
            Name = "views"
            Description = "Exporting views..."
            Command = "Get-DbaViews"
            UseScriptingOptions = $true
            FileName = "schema-views.sql"
            OptionsKey = "views"
        }

    )

    # Create scripting options for different object types
    $scriptingOptionsSets = @{
        "default" = $scriptingOptions
        "constraints" = (& {
            $options = New-DbaScriptingOption
            $options.ScriptSchema = $true
            $options.ScriptData = $false
            $options.Indexes = $false
            $options.DriForeignKeys = $true
            $options.DriAllConstraints = $false
            $options.DriPrimaryKey = $false
            $options.DriChecks = $true
            $options.Triggers = $true
            $options.IncludeDatabaseContext = $false
            $options.IncludeHeaders = $true
            $options.ScriptBatchTerminator = $true
            $options.AnsiFile = $true
            return $options
        })
        "views" = (& {
            $options = New-DbaScriptingOption
            $options.ScriptSchema = $true
            $options.IncludeHeaders = $true
            $options.ScriptBatchTerminator = $true
            $options.AnsiFile = $true
            return $options
        })
    }

    if ($isTraceLevel) {
        Write-LogTrace "Using direct file output (verbose console output enabled)"
    } else {
        Write-LogDebug "Using PassThru method (suppressing verbose console output)"
    }

    # Process each export configuration
    foreach ($config in $exportConfigs) {
        Write-LogDebug $config.Description

        $componentFilePath = Join-Path (Split-Path $SchemaPath -Parent) $config.FileName

        if ($isTraceLevel) {
            # At trace level - direct file output with verbose console
            $exportParams = @{
                FilePath = $componentFilePath
                NoPrefix = $true
            }

            if ($config.UseScriptingOptions) {
                $optionsKey = if ($config.OptionsKey) { $config.OptionsKey } else { "default" }
                $exportParams.ScriptingOptionsObject = $scriptingOptionsSets[$optionsKey]
            }

            & $config.Command -ConnectionParams $ConnectionParams | Export-DbaScript @exportParams

        } else {
            # Below trace level - PassThru method to suppress verbose output
            $exportParams = @{
                NoPrefix = $true
                PassThru = $true
            }

            if ($config.UseScriptingOptions) {
                $optionsKey = if ($config.OptionsKey) { $config.OptionsKey } else { "default" }
                $exportParams.ScriptingOptionsObject = $scriptingOptionsSets[$optionsKey]
            }

            $scriptContent = & $config.Command -ConnectionParams $ConnectionParams | Export-DbaScript @exportParams

            $scriptContent | Out-File -FilePath $componentFilePath -Encoding UTF8
        }

        Write-LogSuccess "$($config.Name) exported to: $($config.FileName)"

        # Handle SQL processing for constraints
        if ($config.FilterToFile) {
            Write-LogDebug "Processing SQL with IF NOT EXISTS checks..."
            $unfilteredPath = $componentFilePath
            $filteredPath = Join-Path (Split-Path $SchemaPath -Parent) $config.FilterToFile

            try {
                $processedSql = Add-IfNotExistsToSql -FilePath $unfilteredPath
                $processedSql | Out-File -FilePath $filteredPath -Encoding UTF8
                Write-LogSuccess "Processed SQL exported to: $($config.FilterToFile)"
            } catch {
                Write-LogWarning "Failed to process SQL: $_"
                # Copy unfiltered as fallback
                Copy-Item $unfilteredPath $filteredPath
                Write-LogInfo "Copied unfiltered SQL as fallback"
            }
        }
    }

    # Create schemas.txt file with ordered list of schema files
    Write-LogDebug "Creating schemas.txt file with import order..."
    $schemasListPath = Join-Path (Split-Path $SchemaPath -Parent) "schemas.txt"
    $schemaFiles = @()

    foreach ($config in $exportConfigs) {
        # Use filtered file if it exists, otherwise use the main file
        if ($config.FilterToFile) {
            $fileName = $config.FilterToFile
        } else {
            $fileName = $config.FileName
        }

        $componentFilePath = Join-Path (Split-Path $SchemaPath -Parent) $fileName
        if (Test-Path $componentFilePath) {
            $schemaFiles += $fileName
            Write-LogDebug "Added to schema import order: $fileName"
        }
    }

    $schemaFiles | Out-File -FilePath $schemasListPath -Encoding UTF8
    Write-LogSuccess "Schema import order exported to: $schemasListPath"
    Write-LogInfo "Schema files will be imported in this order:" -Color "Blue"
    $schemaFiles | ForEach-Object { Write-LogInfo "  - $_" -Color "Gray" }
}

function Export-TableList {
    param(
        [hashtable]$ConnectionParams,
        [string]$TablesListPath
    )

    Write-LogSection "EXPORTING TABLE LIST"

    # Helper function for table list export (matching schema export)
    function Get-DbaTablesForList {
        param([hashtable]$ConnectionParams)
        Get-DbaDbTable @ConnectionParams  # Already excludes system tables by default
    }

    # Get all tables and export list
    $tables = Get-DbaTablesForList -ConnectionParams $ConnectionParams
    $tableList = $tables | ForEach-Object {
        "$($_.Parent.Name).$($_.Schema).$($_.Name)"
    }

    $tableList | Out-File -FilePath $TablesListPath -Encoding UTF8
    Write-LogSuccess "Table list exported to: $TablesListPath"
    Write-LogInfo "Found $($tables.Count) tables" -Color "Blue"
    Write-LogDebug "Table list format: Database.Schema.Table"
}

function Export-TableData {
    param(
        [string]$SqlInstance,
        [string]$Database,
        [string]$Username,
        [string]$Password,
        [string]$DataPath,
        [string]$TablesListPath,
        [string[]]$SchemaOnlyTables,
        [int]$DataRowLimit,
        [switch]$TrustServerCertificate
    )

    Write-LogSection "CALLING EXPORT DATA SCRIPT"

    # Prepare parameters for bash script
    $bashScriptPath = Join-Path $PSScriptRoot "export-data.sh"
    Write-LogDebug "Bash script path: $bashScriptPath"

    if (-not (Test-Path $bashScriptPath)) {
        Write-LogError "export-data.sh not found at: $bashScriptPath"
        return $false
    }

    # Convert relative paths to absolute paths for bash script
    $absoluteDataPath = Resolve-Path $DataPath | Select-Object -ExpandProperty Path
    $absoluteTablesPath = Resolve-Path $TablesListPath | Select-Object -ExpandProperty Path

    # Build parameters for the bash script using proper arguments
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

    if ($SchemaOnlyTables -and $SchemaOnlyTables.Count -gt 0) {
        $bashArgs += "--schema-only-tables", ($SchemaOnlyTables -join ",")
    }

    Write-LogDebug "Calling export-data.sh with arguments..."
    Write-LogTrace "Script: $bashScriptPath"
    Write-LogDebug "Final arguments with absolute paths: $($bashArgs -join ' ')"

    # Execute the bash script with direct output (no capturing)
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
            throw "Data export failed with exit code: $exitCode"
        }
    } else {
        Write-LogError "bash command not found. Please ensure bash is installed and in PATH."
        throw "bash command not found"
    }
}

function Create-DatabaseArchive {
    param(
        [string]$OutputPath,
        [string]$TarFileName
    )

    Write-LogSection "CREATING ARCHIVE"

    # Create tar.gz archive - handle both relative and absolute TarFileName
    if ([System.IO.Path]::IsPathRooted($TarFileName)) {
        # TarFileName is already a full path
        $tarPath = $TarFileName
    } else {
        # TarFileName is just a filename - create it relative to current working directory
        $tarPath = Join-Path (Get-Location).Path $TarFileName
    }

    try {
        # Change to output directory for relative paths in tar
        Push-Location $OutputPath

        # Create tar.gz file
        Write-LogDebug "Archive path: $tarPath"
        if (Get-Command tar -ErrorAction SilentlyContinue) {
            Write-LogDebug "Creating tar.gz archive using system tar..."
            Write-LogTrace "Archive contents: schemas.txt, tables.txt, data/, schema-*.sql"
            & tar -czf $tarPath schemas.txt tables.txt data/ schema-*.sql

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
            $archiveItems = @("schemas.txt", "tables.txt", "data") + (Get-ChildItem -Path "schema-*.sql" | Select-Object -ExpandProperty Name)
            Compress-Archive -Path $archiveItems -DestinationPath $zipPath -Force
            Write-LogSuccess "ZIP archive created: $zipPath"
        }
    } finally {
        Pop-Location
    }
}

# Import required modules
try {
    Import-Module dbatools -ErrorAction Stop
    Write-LogSuccess "dbatools module loaded"
} catch {
    Write-LogError "dbatools module not found. Install with: Install-Module dbatools -Scope CurrentUser"
    exit 1
}

# Execute the main export process
try {
    Export-Database -SqlInstance $SqlInstance -Database $Database -Username $Username -Password $Password -OutputPath $OutputPath -TarFileName $TarFileName -SchemaOnlyTables $SchemaOnlyTables -DataRowLimit $DataRowLimit -TrustServerCertificate:$TrustServerCertificate

    Write-LogSection "EXPORT COMPLETE"
    Write-LogSuccess "Database export completed successfully!"

    $schemasListPath = Join-Path $OutputPath "schemas.txt"
    $tablesListPath = Join-Path $OutputPath "tables.txt"
    $dataPath = Join-Path $OutputPath "data"
    $tarPath = if ([System.IO.Path]::IsPathRooted($TarFileName)) { $TarFileName } else { Join-Path (Get-Location).Path $TarFileName }

    Write-LogInfo "Files created:" -Color "Blue"
    Write-LogInfo "  - Schema files: $dataPath/schema-*.sql" -Color "Gray"
    Write-LogInfo "  - Schema import order: $schemasListPath" -Color "Gray"
    Write-LogInfo "  - Tables: $tablesListPath" -Color "Gray"
    Write-LogInfo "  - Data: $dataPath" -Color "Gray"
    Write-LogInfo "  - Archive: $tarPath" -Color "Gray"
    Write-LogDebug "Export process finished with all components"

    exit 0
} catch {
    Write-LogError "Database export failed: $_"
    exit 1
}
