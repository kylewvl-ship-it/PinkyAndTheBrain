# Common PowerShell functions for PinkyAndTheBrain
# Shared utilities for all scripts

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile = "logs/script-errors.log"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure logs directory exists
    $logDir = Split-Path $LogFile -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $logEntry
    
    # Also write to console with color coding
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN" { Write-Host $logEntry -ForegroundColor Yellow }
        "INFO" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry }
    }
}

function Get-Config {
    param(
        [string]$ConfigPath = "config/pinky-config.yaml",
        [string]$Project = ""
    )

    $loaderPath = "$PSScriptRoot/config-loader.ps1"
    if (Test-Path $loaderPath) {
        if (-not (Get-Command 'Load-Config' -ErrorAction SilentlyContinue)) {
            . $loaderPath
        }
        return Load-Config -ConfigPath $ConfigPath -Project $Project
    }

    # Fallback if config-loader is missing
    Write-Log "config-loader.ps1 not found; using built-in defaults" "WARN"
    return @{
        system      = @{ vault_root = "./knowledge"; script_root = "./scripts"; template_root = "./templates" }
        folders     = @{ inbox = "inbox"; raw = "raw"; working = "working"; wiki = "wiki"; archive = "archive"; schemas = "schemas" }
        file_naming = @{ inbox_pattern = "YYYY-MM-DD-HHMMSS-{title}"; conversation_pattern = "YYYY-MM-DD-HHMMSS-conversation-{service}"; working_pattern = "{title}"; wiki_pattern = "{title}" }
        limits      = @{ max_content_size = 10485760 }
    }
}

function Get-TimestampedFilename {
    param(
        [string]$Title,
        [string]$Pattern = "YYYY-MM-DD-HHMMSS-{title}",
        [string]$Extension = ".md",
        [hashtable]$Placeholders = @{}
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $safeTitle = $Title -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '-+', '-'
    $safeTitle = $safeTitle.Trim('-').ToLower()
    
    $filename = $Pattern -replace 'YYYY-MM-DD-HHMMSS', $timestamp -replace '\{title\}', $safeTitle
    foreach ($key in $Placeholders.Keys) {
        $safeValue = ([string]$Placeholders[$key]) -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '-+', '-'
        $safeValue = $safeValue.Trim('-').ToLower()
        $filename = $filename -replace "\{$([regex]::Escape($key))\}", $safeValue
    }
    return $filename + $Extension
}

function Test-DirectoryStructure {
    param([hashtable]$Config)
    
    $vaultRoot = $Config.system.vault_root
    $requiredFolders = @(
        "$vaultRoot/$($Config.folders.inbox)",
        "$vaultRoot/$($Config.folders.raw)",
        "$vaultRoot/$($Config.folders.working)",
        "$vaultRoot/$($Config.folders.wiki)",
        "$vaultRoot/$($Config.folders.archive)",
        "$vaultRoot/$($Config.folders.schemas)"
    )
    
    $missing = @()
    foreach ($folder in $requiredFolders) {
        if (!(Test-Path $folder)) {
            $missing += $folder
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-Log "Missing required folders: $($missing -join ', ')" "ERROR"
        return $false
    }
    
    return $true
}

function Get-Template {
    param(
        [string]$TemplateName,
        [hashtable]$Variables = @{},
        [hashtable]$Config = $null
    )
    
    if ($null -eq $Config) { $Config = Get-Config }
    $templateRoot = if ($Config.system.template_root) { $Config.system.template_root } else { "templates" }
    $templatePath = Join-Path $templateRoot "$TemplateName.md"
    if (!(Test-Path $templatePath)) {
        Write-Log "Template not found: $templatePath" "ERROR"
        return $null
    }
    
    try {
        $template = Get-Content $templatePath -Raw
        
        # Replace variables using literal string replacement to avoid regex backreference issues
        foreach ($key in $Variables.Keys) {
            $value = $Variables[$key]
            if ($null -eq $value) { $value = "" }
            $template = $template.Replace("{{$key}}", [string]$value)
        }

        # Replace timestamp placeholders
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        $template = $template.Replace('{{timestamp}}', $timestamp)
        
        return $template
    }
    catch {
        Write-Log "Error processing template ${templatePath}: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Show-Usage {
    param([string]$ScriptName, [string]$Description, [array]$Examples)
    
    Write-Host "`n$ScriptName - $Description`n" -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Yellow
    foreach ($example in $Examples) {
        Write-Host "  $example" -ForegroundColor Gray
    }
    Write-Host ""
}

# Functions are available when dot-sourced
