param(
    [switch]$Force,
    [switch]$SkipBackup,
    [string]$RootPath = $null
)

$ErrorActionPreference = "Stop"
$Root = if ($RootPath) { $RootPath } else { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$LogDir = Join-Path $Root "logs"
$LogPath = Join-Path $LogDir "setup.log"

function Write-Log {
    param([string]$Message)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -Path $LogPath -Value "[$(Get-Date -Format o)] $Message"
}

function Test-DiskSpace {
    param([string]$Path, [long]$RequiredBytes = 100MB)
    try {
        $drive = (Get-Item $Path).PSDrive
        $freeSpace = $drive.Free
        if ($freeSpace -lt $RequiredBytes) {
            throw "Insufficient disk space. Required: $([math]::Round($RequiredBytes/1MB, 2))MB, Available: $([math]::Round($freeSpace/1MB, 2))MB"
        }
        return $true
    }
    catch {
        Write-Log "Disk space check failed: $($_.Exception.Message)"
        throw
    }
}

function Test-WritePermissions {
    param([string]$Path)
    try {
        $testFile = Join-Path $Path "test-write-$(Get-Random).tmp"
        Set-Content -Path $testFile -Value "test" -ErrorAction Stop
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        Write-Log "Write permission test failed for $Path`: $($_.Exception.Message)"
        throw "Insufficient permissions to write to $Path. Try running as Administrator."
    }
}

function Backup-ExistingContent {
    param([string]$RootPath)
    
    if ($SkipBackup) {
        Write-Log "Skipping backup due to -SkipBackup flag"
        return $null
    }
    
    # Check if there's existing content that would be affected
    $existingItems = @()
    $foldersToCheck = @("knowledge", "scripts", "templates", "config", ".ai")
    
    foreach ($folder in $foldersToCheck) {
        $folderPath = Join-Path $RootPath $folder
        if (Test-Path $folderPath) {
            $items = Get-ChildItem $folderPath -Recurse -ErrorAction SilentlyContinue
            if ($items) {
                $existingItems += $items
            }
        }
    }
    
    if ($existingItems.Count -eq 0) {
        Write-Log "No existing content found, skipping backup"
        return $null
    }
    
    # Create backup directory with timestamp
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $RootPath "backup-$timestamp"
    
    Write-Host "Found existing content. Creating backup..." -ForegroundColor Yellow
    Write-Log "Creating backup directory: $backupDir"
    
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    # Copy existing folders to backup
    foreach ($folder in $foldersToCheck) {
        $sourcePath = Join-Path $RootPath $folder
        if (Test-Path $sourcePath) {
            $destPath = Join-Path $backupDir $folder
            Write-Log "Backing up $sourcePath to $destPath"
            try {
                Copy-Item $sourcePath $destPath -Recurse -Force -ErrorAction Stop
                Write-Log "Successfully backed up $folder"
            }
            catch {
                Write-Log "Failed to backup $folder`: $($_.Exception.Message)"
                Write-Host "Warning: Failed to backup $folder`: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        else {
            Write-Log "Folder $sourcePath does not exist, skipping backup"
        }
    }
    
    Write-Host "Backup created at: $backupDir" -ForegroundColor Green
    Write-Log "Backup completed successfully"
    
    # Ask for confirmation unless Force is specified
    if (-not $Force) {
        $response = Read-Host "Continue with setup? Existing files will be updated/overwritten. (y/N)"
        if ($response -notmatch '^[Yy]') {
            Write-Host "Setup cancelled by user" -ForegroundColor Yellow
            Write-Log "Setup cancelled by user after backup"
            exit 0
        }
    }
    
    return $backupDir
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Log "Created directory $Path"
    }
}

function Ensure-File {
    param(
        [string]$Path,
        [string]$Content
    )
    if ((Test-Path $Path) -and -not $Force) {
        Write-Log "Skipped existing file $Path"
        return
    }
    $parent = Split-Path -Parent $Path
    if ($parent) { Ensure-Directory $parent }
    Set-Content -Path $Path -Value $Content -Encoding UTF8
    Write-Log "Wrote file $Path"
}

try {
    Write-Log "Setup started"
    Write-Host "Starting PinkyAndTheBrain setup..." -ForegroundColor Cyan
    
    # Pre-flight checks
    Write-Host "Running pre-flight checks..." -ForegroundColor Yellow
    Test-DiskSpace -Path $Root -RequiredBytes 50MB
    Test-WritePermissions -Path $Root
    Write-Log "Pre-flight checks passed"
    
    # Create backup of existing content
    $backupPath = Backup-ExistingContent -RootPath $Root
    if ($backupPath) {
        Write-Log "Backup created at: $backupPath"
    }

    Write-Host "Creating folder structure..." -ForegroundColor Yellow
    $requiredDirs = @(
        "knowledge/inbox", "knowledge/raw", "knowledge/working", "knowledge/wiki",
        "knowledge/schemas", "knowledge/archive", "knowledge/reviews",
        "scripts", "templates", ".ai/handoffs", ".ai/policies", "config", "logs", "backups", "quarantine"
    )

    foreach ($dir in $requiredDirs) {
        Ensure-Directory (Join-Path $Root $dir)
    }
    Write-Log "Folder structure created"

    Write-Host "Creating index files..." -ForegroundColor Yellow
    $indexFiles = @{
        "knowledge/inbox/index.md" = "# Inbox`n`nLow-friction capture area for new items awaiting triage.`n"
        "knowledge/raw/index.md" = "# Raw`n`nPreserved source material before interpretation.`n"
        "knowledge/working/index.md" = "# Working`n`nActive thinking, synthesis, contradictions, and open questions.`n"
        "knowledge/wiki/index.md" = "# Wiki`n`nDurable, sourced knowledge promoted after review.`n"
        "knowledge/archive/index.md" = "# Archive`n`nRetired or low-confidence material excluded from default retrieval.`n"
        "knowledge/reviews/index.md" = "# Reviews`n`nHealth reports and repair decisions.`n"
        "knowledge/schemas/index.md" = "# Schemas`n`nHuman-readable metadata contracts and templates.`n"
    }

    foreach ($path in $indexFiles.Keys) {
        Ensure-File -Path (Join-Path $Root $path) -Content $indexFiles[$path]
    }
    Write-Log "Index files created"

    if (-not (Test-Path (Join-Path $Root "config/pinky-config.yaml"))) {
        Write-Warning "config/pinky-config.yaml is missing. Restore it from version control or create it before running automation."
    }

    Write-Host "PinkyAndTheBrain setup complete." -ForegroundColor Green
    Write-Log "Setup completed successfully"
    exit 0
}
catch {
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Log "Setup failed: $($_.Exception.Message)"
    
    # Cleanup on failure
    Write-Host "Cleaning up partial installation..." -ForegroundColor Yellow
    $foldersToCleanup = @("knowledge", "scripts", "templates", ".ai", "config")
    foreach ($folder in $foldersToCleanup) {
        $folderPath = Join-Path $Root $folder
        if (Test-Path $folderPath) {
            try {
                # Only remove if it was created by this script (check if it's empty or contains only our files)
                $items = Get-ChildItem $folderPath -Recurse -ErrorAction SilentlyContinue
                $ourFiles = $items | Where-Object { $_.Name -match '^(index\.md|pinky-config\.yaml)$' }
                if ($items.Count -eq $ourFiles.Count) {
                    Remove-Item $folderPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Cleaned up $folderPath"
                }
            }
            catch {
                Write-Log "Failed to cleanup $folderPath`: $($_.Exception.Message)"
            }
        }
    }
    
    Write-Host "Setup failed. Check logs at: $LogPath" -ForegroundColor Red
    exit 1
}

