#!/usr/bin/env pwsh
# PinkyAndTheBrain Rollback Script
# Selective recovery of knowledge files using Git history

param(
    [int]$Hours = 0,
    [string]$File = "",
    [switch]$List,
    [switch]$WhatIf,
    [switch]$Help
)

if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"

if (!(Test-Path "$PSScriptRoot/lib/git-operations.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/git-operations.ps1"
    exit 2
}
. "$PSScriptRoot/lib/git-operations.ps1"

if ($Help) {
    Show-Usage "rollback.ps1" "Selective recovery of knowledge files from Git history" @(
        ".\scripts\rollback.ps1 -Hours 24 -List"
        ".\scripts\rollback.ps1 -Hours 24 -WhatIf"
        ".\scripts\rollback.ps1 -Hours 24"
        ".\scripts\rollback.ps1 -File 'knowledge/inbox/my-note.md' -WhatIf"
        ".\scripts\rollback.ps1 -File 'knowledge/inbox/my-note.md'"
    )
    exit 0
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Test-GitAvailable)) {
    Write-Host "⚠️  Git is not installed or not accessible." -ForegroundColor Yellow
    Write-Host "Install Git from https://git-scm.com to enable rollback functionality." -ForegroundColor Gray
    exit 1
}

if (-not (Test-GitRepository -Path $repoRoot)) {
    Write-Host "⚠️  No Git repository found at: $repoRoot" -ForegroundColor Yellow
    exit 1
}

if ($Hours -eq 0 -and -not $File) {
    Write-Host "❌ Specify -Hours <n> to list changes, or -File <path> to revert a specific file." -ForegroundColor Red
    Write-Host "Use -Help for usage examples." -ForegroundColor Gray
    exit 1
}

function Get-CommitsSince {
    param([int]$Hours, [string]$RepoPath)

    $since = (Get-Date).AddHours(-$Hours).ToString("yyyy-MM-dd HH:mm:ss")

    try {
        Push-Location $RepoPath
        $output = git log --since="$since" --format="%h|%ad|%s" --date=short 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }
        return $output | Where-Object { $_ -match '\S' }
    }
    catch {
        return @()
    }
    finally {
        Pop-Location
    }
}

function Get-FilesChangedSince {
    param([int]$Hours, [string]$RepoPath)

    $since = (Get-Date).AddHours(-$Hours).ToString("yyyy-MM-dd HH:mm:ss")

    try {
        Push-Location $RepoPath
        $output = git log --since="$since" --name-only --format="" 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }
        return $output | Where-Object { $_ -match '\S' } | Sort-Object | Get-Unique
    }
    catch {
        return @()
    }
    finally {
        Pop-Location
    }
}

function Get-BaselineCommitBefore {
    param([int]$Hours, [string]$RepoPath)

    $since = (Get-Date).AddHours(-$Hours).ToString("yyyy-MM-dd HH:mm:ss")

    try {
        Push-Location $RepoPath
        $baseline = git rev-list -1 --before="$since" HEAD 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($baseline)) { return "" }
        return [string]$baseline
    }
    catch {
        return ""
    }
    finally {
        Pop-Location
    }
}

function Get-PreviousFileCommit {
    param([string]$FilePath, [string]$RepoPath)

    try {
        Push-Location $RepoPath
        $history = @(git log --format="%H" -2 -- $FilePath 2>&1)
        if ($LASTEXITCODE -ne 0 -or $history.Count -lt 2) { return "" }
        return [string]$history[1]
    }
    catch {
        return ""
    }
    finally {
        Pop-Location
    }
}

function Invoke-FileRevert {
    param(
        [string]$FilePath,
        [string]$RepoPath,
        [string]$TargetRef = "HEAD",
        [switch]$WhatIf,
        [string]$LogFile = "logs/rollback-history.log"
    )

    try {
        Push-Location $RepoPath

        # Check if file has history
        $history = git log --format="%h" -1 -- $FilePath 2>&1
        if ([string]::IsNullOrWhiteSpace($history) -or $LASTEXITCODE -ne 0) {
            Write-Host "  ⚠️  No Git history found for: $FilePath" -ForegroundColor Yellow
            return $false
        }

        if ($WhatIf) {
            Write-Host "  Would revert: $FilePath to $TargetRef" -ForegroundColor Yellow
            return $true
        }

        git cat-file -e "${TargetRef}:$FilePath" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            git rm --ignore-unmatch -- $FilePath 2>&1 | Out-Null
        }
        else {
            git checkout $TargetRef -- $FilePath 2>&1 | Out-Null
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Reverted file: $FilePath" "INFO" $LogFile
            Write-Host "  ✅ Reverted: $FilePath to $TargetRef" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "  ❌ Failed to revert: $FilePath" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "  ❌ Error reverting $FilePath`: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        Pop-Location
    }
}

# Single file revert
if ($File) {
    $normalizedFile = $File -replace '\\', '/'
    Write-Host "`n🔄 File Rollback: $normalizedFile" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Gray

    $history = Get-GitFileHistory -FilePath $normalizedFile -RepoPath $repoRoot -Count 5
    if ($history.Count -gt 0) {
        Write-Host "`n  Recent history:" -ForegroundColor Gray
        foreach ($entry in $history) {
            $parts = $entry -split '\|', 3
            if ($parts.Count -eq 3) {
                Write-Host "    $($parts[1])  $($parts[2])" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    $targetRef = Get-PreviousFileCommit -FilePath $normalizedFile -RepoPath $repoRoot
    if ([string]::IsNullOrWhiteSpace($targetRef)) {
        Write-Host "  ⚠️  No previous revision found for: $normalizedFile" -ForegroundColor Yellow
        exit 1
    }

    $reverted = Invoke-FileRevert -FilePath $normalizedFile -RepoPath $repoRoot -TargetRef $targetRef -WhatIf:$WhatIf

    if ($reverted -and -not $WhatIf) {
        $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        $commitMsg = "Rollback: reverted $normalizedFile to $($targetRef.Substring(0, 12)) from $timestamp"
        Invoke-GitCommit -Files @($normalizedFile) -Message $commitMsg -RepoPath $repoRoot | Out-Null
        Write-Host "`n✅ Rollback committed." -ForegroundColor Green
    }
    exit 0
}

# Time-based rollback
$commits = Get-CommitsSince -Hours $Hours -RepoPath $repoRoot
$changedFiles = Get-FilesChangedSince -Hours $Hours -RepoPath $repoRoot
$baselineRef = Get-BaselineCommitBefore -Hours $Hours -RepoPath $repoRoot

Write-Host "`n🕐 Changes in the last $Hours hour(s):" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Gray

if ($commits.Count -eq 0) {
    Write-Host "  No commits found in the last $Hours hour(s)." -ForegroundColor Yellow
    exit 0
}

if ([string]::IsNullOrWhiteSpace($baselineRef)) {
    Write-Host "  ❌ Cannot find a baseline commit before the last $Hours hour(s)." -ForegroundColor Red
    exit 1
}

Write-Host "`n  Commits ($($commits.Count)):" -ForegroundColor Yellow
foreach ($commit in $commits) {
    $parts = $commit -split '\|', 3
    if ($parts.Count -eq 3) {
        Write-Host "    $($parts[1])  $($parts[2])" -ForegroundColor Gray
    }
}

Write-Host "`n  Files changed ($($changedFiles.Count)):" -ForegroundColor Yellow
foreach ($file in $changedFiles) {
    Write-Host "    $file" -ForegroundColor Gray
}

if ($List) {
    exit 0
}

# Perform revert
Write-Host "`n⚠️  This will revert all $($changedFiles.Count) file(s) to their state before the last $Hours hour(s)." -ForegroundColor Yellow

if (-not $WhatIf) {
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Rollback cancelled." -ForegroundColor Gray
        exit 0
    }
}

$revertedFiles = @()
$timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"

foreach ($file in $changedFiles) {
    $result = Invoke-FileRevert -FilePath $file -RepoPath $repoRoot -TargetRef $baselineRef -WhatIf:$WhatIf
    if ($result -and -not $WhatIf) {
        $revertedFiles += $file
    }
}

if (-not $WhatIf -and $revertedFiles.Count -gt 0) {
    $commitMsg = "Rollback: reverted $($revertedFiles.Count) file(s) from last ${Hours}h ($timestamp)"
    Invoke-GitCommit -Files $revertedFiles -Message $commitMsg -RepoPath $repoRoot | Out-Null
    Write-Log "Rollback completed: $($revertedFiles.Count) files, last ${Hours}h" "INFO" "logs/rollback-history.log"
    Write-Host "`n✅ Rollback complete. $($revertedFiles.Count) file(s) reverted and committed." -ForegroundColor Green
}
elseif ($WhatIf) {
    Write-Host "`n(WhatIf mode - no changes made)" -ForegroundColor Gray
}
