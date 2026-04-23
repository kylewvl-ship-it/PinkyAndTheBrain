#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true)]
    [string]$File,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/lib/config-loader.ps1"
if (Test-Path "$PSScriptRoot/lib/git-operations.ps1") {
    . "$PSScriptRoot/lib/git-operations.ps1"
}

if ($Help) {
    Show-Usage "working-note-summary.ps1" "Show git history summary for a working note" @(
        ".\scripts\working-note-summary.ps1 -File 'my-topic.md'"
    )
    exit 0
}

try {
    $config = Get-Config
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $relFilePath = "knowledge/working/$File"
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    Push-Location $repoRoot
    try {
        $gitLog = git log --date=short --format="%ad %h %s" --follow -- $relFilePath 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($gitLog | Out-String))) {
            Write-Host "No git history found for this file" -ForegroundColor Yellow
            exit 0
        }

        $gitLog | ForEach-Object { Write-Host $_ }
    }
    finally {
        Pop-Location
    }
}
catch {
    Write-Log "Working note summary failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Working note summary failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
