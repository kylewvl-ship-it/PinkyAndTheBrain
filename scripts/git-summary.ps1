#!/usr/bin/env pwsh
# PinkyAndTheBrain Git Summary Script
# Shows repository activity grouped by operation type

param(
    [int]$Count = 20,
    [string]$File = "",
    [switch]$Uncommitted,
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
    Show-Usage "git-summary.ps1" "Repository activity summary and knowledge evolution history" @(
        ".\scripts\git-summary.ps1"
        ".\scripts\git-summary.ps1 -Count 50"
        ".\scripts\git-summary.ps1 -File 'knowledge/inbox/my-note.md'"
        ".\scripts\git-summary.ps1 -Uncommitted"
    )
    exit 0
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Test-GitAvailable)) {
    Write-Host "⚠️  Git is not installed or not accessible." -ForegroundColor Yellow
    Write-Host "Install Git from https://git-scm.com to enable version control features." -ForegroundColor Gray
    exit 1
}

if (-not (Test-GitRepository -Path $repoRoot)) {
    Write-Host "⚠️  No Git repository found at: $repoRoot" -ForegroundColor Yellow
    Write-Host "Run setup-system.ps1 to initialize version control." -ForegroundColor Gray
    exit 1
}

if ($Uncommitted) {
    $changes = Get-GitUncommitted -RepoPath $repoRoot
    Write-Host "`n📋 Uncommitted Changes:" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Gray
    if ($changes.Count -eq 0) {
        Write-Host "  ✅ No uncommitted changes" -ForegroundColor Green
    }
    else {
        foreach ($change in $changes) {
            Write-Host "  $change" -ForegroundColor Yellow
        }
        Write-Host "`n  Total: $($changes.Count) file(s)" -ForegroundColor Gray
    }
    exit 0
}

if ($File) {
    $history = Get-GitFileHistory -FilePath $File -RepoPath $repoRoot -Count $Count
    Write-Host "`n📄 History for: $File" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Gray
    if ($history.Count -eq 0) {
        Write-Host "  No history found for this file." -ForegroundColor Yellow
    }
    else {
        foreach ($entry in $history) {
            $parts = $entry -split '\|', 3
            if ($parts.Count -eq 3) {
                Write-Host "  $($parts[1])  " -NoNewline -ForegroundColor Gray
                Write-Host "$($parts[2])" -ForegroundColor White
            }
        }
    }
    exit 0
}

# Full summary grouped by operation type
$commits = Get-GitLog -RepoPath $repoRoot -Count $Count

Write-Host "`n📊 Knowledge Evolution Summary (last $Count commits)" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Gray

if ($commits.Count -eq 0) {
    Write-Host "  No commits found." -ForegroundColor Yellow
    exit 0
}

$groups = @{
    "Knowledge capture"   = @()
    "Knowledge triage"    = @()
    "Knowledge promotion" = @()
    "Knowledge archive"   = @()
    "Configuration"       = @()
    "System"              = @()
    "Rollback"            = @()
    "Other"               = @()
}

foreach ($entry in $commits) {
    $parts = $entry -split '\|', 3
    if ($parts.Count -ne 3) { continue }
    $msg = $parts[2]

    $bucket = switch -Regex ($msg) {
        '^Knowledge capture'   { "Knowledge capture" }
        '^Knowledge triage'    { "Knowledge triage" }
        '^Knowledge promotion' { "Knowledge promotion" }
        '^Knowledge archive'   { "Knowledge archive" }
        '^Configuration'       { "Configuration" }
        '^System'              { "System" }
        '^Rollback'            { "Rollback" }
        default                { "Other" }
    }
    $groups[$bucket] += [PSCustomObject]@{ Hash = $parts[0]; Date = $parts[1]; Message = $msg }
}

$order = "Knowledge capture", "Knowledge triage", "Knowledge promotion", "Knowledge archive", "Configuration", "System", "Rollback", "Other"

foreach ($key in $order) {
    $items = $groups[$key]
    if ($items.Count -eq 0) { continue }

    Write-Host "`n  $key ($($items.Count)):" -ForegroundColor Yellow
    foreach ($item in $items) {
        Write-Host "    $($item.Date)  $($item.Message)" -ForegroundColor Gray
    }
}

# Uncommitted changes summary
$uncommitted = Get-GitUncommitted -RepoPath $repoRoot
if ($uncommitted.Count -gt 0) {
    Write-Host "`n  ⚠️  Uncommitted changes: $($uncommitted.Count) file(s)" -ForegroundColor Yellow
    Write-Host "  Run with -Uncommitted to see details." -ForegroundColor Gray
}

Write-Host ""
