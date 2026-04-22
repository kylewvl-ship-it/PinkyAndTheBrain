#!/usr/bin/env pwsh
# PinkyAndTheBrain Git Hooks Integration
# Called by other scripts after knowledge operations to commit changes automatically

param(
    [ValidateSet("capture", "triage", "promotion", "archive", "config", "maintenance", "setup")]
    [string]$Operation,
    [string[]]$Files = @(),
    [string]$Detail = "",
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
    Show-Usage "git-hooks.ps1" "Commit knowledge operations to Git automatically" @(
        ".\scripts\git-hooks.ps1 -Operation capture -Files 'knowledge/inbox/note.md' -Detail 'note from web'"
        ".\scripts\git-hooks.ps1 -Operation triage -Detail 'moved 3 items from inbox'"
        ".\scripts\git-hooks.ps1 -Operation config -Detail 'git_enabled changed to true'"
    )
    exit 0
}

if (-not $Operation) {
    Write-Host "❌ -Operation is required. Use -Help for usage." -ForegroundColor Red
    exit 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$messageTemplate = switch ($Operation) {
    "capture"     { "Knowledge capture: $Detail" }
    "triage"      { "Knowledge triage: $Detail" }
    "promotion"   { "Knowledge promotion: $Detail" }
    "archive"     { "Knowledge archive: $Detail" }
    "config"      { "Configuration update: $Detail" }
    "maintenance" { "System maintenance: $Detail" }
    "setup"       { "System maintenance: $Detail" }
    default       { "System maintenance: $Detail" }
}

$result = Invoke-GitCommit -Files $Files -Message $messageTemplate -RepoPath $repoRoot
if ($result) {
    Write-Log "Auto-committed: $messageTemplate" "INFO" "logs/git-operations.log"
}
