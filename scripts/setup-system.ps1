param(
    [switch]$Force,
    [switch]$SkipBackup,
    [string]$RootPath = $null,
    [switch]$Rollback,
    [string]$BackupPath = $null
)

$ErrorActionPreference = "Stop"
$Root = if ($RootPath) { $RootPath } else { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$LogDir = [System.IO.Path]::Combine($Root, "logs")
$LogPath = [System.IO.Path]::Combine($LogDir, "setup.log")
$ConfigPath = [System.IO.Path]::Combine($Root, "config", "pinky-config.yaml")
$Config = $null

function Write-Log {
    param([string]$Message)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -Path $LogPath -Value "[$(Get-Date -Format o)] $Message"
}

function Test-DiskSpace {
    param([string]$Path, [long]$RequiredBytes = 100MB)
    try {
        $rootPath = [System.IO.Path]::GetPathRoot((Resolve-Path $Path -ErrorAction Stop).Path)
        $drive = New-Object System.IO.DriveInfo($rootPath)
        $freeSpace = $drive.AvailableFreeSpace
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
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $shortUser = $env:USERNAME
        $writeRights = [System.Security.AccessControl.FileSystemRights]::Write -bor
            [System.Security.AccessControl.FileSystemRights]::Modify -bor
            [System.Security.AccessControl.FileSystemRights]::FullControl -bor
            [System.Security.AccessControl.FileSystemRights]::WriteData

        $denyRule = Get-Acl $Path | Select-Object -ExpandProperty Access | Where-Object {
            $_.AccessControlType -eq "Deny" -and
            ($_.IdentityReference.Value -eq $currentUser -or $_.IdentityReference.Value -like "*\$shortUser") -and
            (($_.FileSystemRights -band $writeRights) -ne 0)
        } | Select-Object -First 1

        if ($denyRule) {
            throw "Insufficient permissions to write to $Path. Try running as Administrator."
        }

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
    Write-Host "  To rollback: .\scripts\setup-system.ps1 -Rollback -BackupPath `"$backupDir`"" -ForegroundColor DarkGray
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

function Restore-FromBackup {
    param([string]$RootPath, [string]$BackupDir)

    if (-not (Test-Path $BackupDir)) {
        throw "Backup directory not found: $BackupDir"
    }

    $folders = Get-ChildItem -Path $BackupDir -Directory -ErrorAction SilentlyContinue
    if (-not $folders -or $folders.Count -eq 0) {
        throw "Backup directory is empty — nothing to restore: $BackupDir"
    }

    Write-Host "Restoring from backup: $BackupDir" -ForegroundColor Yellow
    Write-Log "Rollback started from: $BackupDir"

    foreach ($folder in $folders) {
        $dest = Join-Path $RootPath $folder.Name
        if (Test-Path $dest) {
            # Rename before copy so data is recoverable if copy fails
            $tempName = "$dest.rollback-tmp"
            Rename-Item $dest $tempName -Force -ErrorAction Stop
            try {
                Copy-Item $folder.FullName $dest -Recurse -Force -ErrorAction Stop
                Remove-Item $tempName -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                # Restore the renamed original on copy failure
                if (Test-Path $tempName) {
                    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
                    Rename-Item $tempName $dest -Force -ErrorAction SilentlyContinue
                }
                throw
            }
        }
        else {
            Copy-Item $folder.FullName $dest -Recurse -Force -ErrorAction Stop
        }
        Write-Log "Restored $($folder.Name)"
    }

    Write-Host "Rollback complete. Files restored from backup." -ForegroundColor Green
    Write-Log "Rollback completed successfully"
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

function Resolve-ConfiguredPath {
    param([string]$RootPath, [string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    $relative = $Path.TrimStart('.', '/', '\')
    return Join-Path $RootPath $relative
}

# Handle rollback mode
if ($Rollback) {
    if (-not $BackupPath) {
        Write-Host "Error: -BackupPath is required when using -Rollback" -ForegroundColor Red
        exit 1
    }
    $resolvedBackup = if ([System.IO.Path]::IsPathRooted($BackupPath)) { $BackupPath } else { Join-Path $Root $BackupPath }
    try {
        Restore-FromBackup -RootPath $Root -BackupDir $resolvedBackup
        exit 0
    }
    catch {
        Write-Host "Rollback failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Rollback failed: $($_.Exception.Message)"
        exit 1
    }
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

    if (Test-Path "$PSScriptRoot/lib/config-loader.ps1") {
        . "$PSScriptRoot/lib/config-loader.ps1"
        $Config = Load-Config -ConfigPath $ConfigPath
    }
    else {
        $Config = @{
            system = @{ vault_root = "./knowledge"; script_root = "./scripts"; template_root = "./templates" }
            folders = @{ inbox = "inbox"; raw = "raw"; working = "working"; wiki = "wiki"; archive = "archive"; schemas = "schemas"; reviews = "reviews" }
        }
    }

    Write-Host "Creating folder structure..." -ForegroundColor Yellow
    $vaultRoot = Resolve-ConfiguredPath -RootPath $Root -Path $Config.system.vault_root
    $scriptRoot = Resolve-ConfiguredPath -RootPath $Root -Path $Config.system.script_root
    $templateRoot = Resolve-ConfiguredPath -RootPath $Root -Path $Config.system.template_root

    $requiredDirs = @(
        (Join-Path $vaultRoot $Config.folders.inbox),
        (Join-Path $vaultRoot $Config.folders.raw),
        (Join-Path $vaultRoot $Config.folders.working),
        (Join-Path $vaultRoot $Config.folders.wiki),
        (Join-Path $vaultRoot $Config.folders.schemas),
        (Join-Path $vaultRoot $Config.folders.archive),
        (Join-Path $vaultRoot $Config.folders.reviews),
        $scriptRoot, $templateRoot, ".ai/handoffs", ".ai/policies", "config", "logs", "backups", "quarantine"
    )

    foreach ($dir in $requiredDirs) {
        $targetDir = if ([System.IO.Path]::IsPathRooted($dir)) { $dir } else { Join-Path $Root $dir }
        Ensure-Directory $targetDir
    }
    Write-Log "Folder structure created"

    Write-Host "Creating index files..." -ForegroundColor Yellow
    $indexFiles = @{
        (Join-Path (Join-Path $vaultRoot $Config.folders.inbox) "index.md") = "# Inbox`n`nLow-friction capture area for new items awaiting triage.`n"
        (Join-Path (Join-Path $vaultRoot $Config.folders.raw) "index.md") = "# Raw`n`nPreserved source material before interpretation.`n"
        (Join-Path (Join-Path $vaultRoot $Config.folders.working) "index.md") = "# Working`n`nActive thinking, synthesis, contradictions, and open questions.`n"
        (Join-Path (Join-Path $vaultRoot $Config.folders.wiki) "index.md") = "# Wiki`n`nDurable, sourced knowledge promoted after review.`n"
        (Join-Path (Join-Path $vaultRoot $Config.folders.archive) "index.md") = "# Archive`n`nRetired or low-confidence material excluded from default retrieval.`n"
        (Join-Path (Join-Path $vaultRoot $Config.folders.reviews) "index.md") = "# Reviews`n`nHealth reports and repair decisions.`n"
        (Join-Path (Join-Path $vaultRoot $Config.folders.schemas) "index.md") = "# Schemas`n`nHuman-readable metadata contracts and templates.`n"
    }

    foreach ($path in $indexFiles.Keys) {
        Ensure-File -Path $path -Content $indexFiles[$path]
    }
    Write-Log "Index files created"

    Write-Host "PinkyAndTheBrain setup complete." -ForegroundColor Green
    Write-Log "Setup completed successfully"
    exit 0
}
catch {
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    try { Write-Log "Setup failed: $($_.Exception.Message)" } catch {}

    # Cleanup on failure
    Write-Host "Cleaning up partial installation..." -ForegroundColor Yellow
    $foldersToCleanup = @("knowledge", "scripts", "templates", ".ai", "config")
    foreach ($folder in $foldersToCleanup) {
        $folderPath = [System.IO.Path]::Combine($Root, $folder)
        if (Test-Path $folderPath) {
            try {
                # Only remove if it was created by this script (check if it's empty or contains only our files)
                $items = Get-ChildItem $folderPath -Recurse -ErrorAction SilentlyContinue
                $ourFiles = $items | Where-Object { $_.Name -match '^(index\.md|pinky-config\.yaml)$' }
                if ($items.Count -eq $ourFiles.Count) {
                    Remove-Item $folderPath -Recurse -Force -ErrorAction SilentlyContinue
                    try { Write-Log "Cleaned up $folderPath" } catch {}
                }
            }
            catch {
                try { Write-Log "Failed to cleanup $folderPath`: $($_.Exception.Message)" } catch {}
            }
        }
    }

    Write-Host "Setup failed. Check logs at: $LogPath" -ForegroundColor Red
    exit 1
}
