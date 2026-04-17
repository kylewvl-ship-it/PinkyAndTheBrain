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
    param([string]$ConfigPath = "config/pinky-config.yaml")
    
    if (!(Test-Path $ConfigPath)) {
        Write-Log "Configuration file not found: $ConfigPath" "WARN"
        return @{
            system = @{
                vault_root = "./knowledge"
                script_root = "./scripts"
                template_root = "./templates"
            }
            folders = @{
                inbox = "inbox"
                raw = "raw"
                working = "working"
                wiki = "wiki"
                archive = "archive"
                schemas = "schemas"
            }
            file_naming = @{
                inbox_pattern = "YYYY-MM-DD-HHMMSS-{title}"
                conversation_pattern = "YYYY-MM-DD-HHMMSS-conversation-{service}"
                working_pattern = "{title}"
                wiki_pattern = "{title}"
            }
        }
    }
    
    # Simple YAML parsing for basic config
    $config = @{
        system = @{
            vault_root = "./knowledge"
            script_root = "./scripts"
            template_root = "./templates"
        }
        folders = @{
            inbox = "inbox"
            raw = "raw"
            working = "working"
            wiki = "wiki"
            archive = "archive"
            schemas = "schemas"
        }
        file_naming = @{
            inbox_pattern = "YYYY-MM-DD-HHMMSS-{title}"
            conversation_pattern = "YYYY-MM-DD-HHMMSS-conversation-{service}"
            working_pattern = "{title}"
            wiki_pattern = "{title}"
        }
    }
    
    $currentSection = $null
    
    Get-Content $ConfigPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^(\w+):$') {
            $currentSection = $matches[1]
        }
        elseif ($line -match '^\s+(\w+):\s*(.*)$' -and $currentSection -eq "paths") {
            $key = $matches[1]
            $value = $matches[2].Trim()
            
            # Map the config paths to our expected structure
            switch ($key) {
                "knowledge_root" { $config.system.vault_root = "./$value" }
                "inbox" { $config.folders.inbox = $value -replace '^knowledge/', '' }
                "raw" { $config.folders.raw = $value -replace '^knowledge/', '' }
                "working" { $config.folders.working = $value -replace '^knowledge/', '' }
                "wiki" { $config.folders.wiki = $value -replace '^knowledge/', '' }
                "archive" { $config.folders.archive = $value -replace '^knowledge/', '' }
                "schemas" { $config.folders.schemas = $value -replace '^knowledge/', '' }
            }
        }
    }
    
    return $config
}

function Get-TimestampedFilename {
    param(
        [string]$Title,
        [string]$Pattern = "YYYY-MM-DD-HHMMSS-{title}",
        [string]$Extension = ".md"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $safeTitle = $Title -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '-+', '-'
    $safeTitle = $safeTitle.Trim('-').ToLower()
    
    $filename = $Pattern -replace 'YYYY-MM-DD-HHMMSS', $timestamp -replace '\{title\}', $safeTitle
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
        [hashtable]$Variables = @{}
    )
    
    $templatePath = "templates/$TemplateName.md"
    if (!(Test-Path $templatePath)) {
        Write-Log "Template not found: $templatePath" "ERROR"
        return $null
    }
    
    try {
        $template = Get-Content $templatePath -Raw
        
        # Replace variables in template with validation
        foreach ($key in $Variables.Keys) {
            $value = $Variables[$key]
            if ($value -eq $null) { $value = "" }
            # Escape special regex characters in the key for safe replacement
            $escapedKey = [regex]::Escape($key)
            $template = $template -replace "\{\{$escapedKey\}\}", $value
        }
        
        # Replace timestamp placeholders
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        $template = $template -replace '\{\{timestamp\}\}', $timestamp
        
        return $template
    }
    catch {
        Write-Log "Error processing template $templatePath: $($_.Exception.Message)" "ERROR"
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