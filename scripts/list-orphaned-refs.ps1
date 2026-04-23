#!/usr/bin/env pwsh
param(
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

if ($Help) {
    Show-Usage "list-orphaned-refs.ps1" "List orphaned archive references" @(
        ".\scripts\list-orphaned-refs.ps1",
        ".\scripts\list-orphaned-refs.ps1 -File 'wiki/old-topic.md'"
    )
    exit 0
}

try {
    $config = Get-Config
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $orphanPath = Join-Path (Join-Path $config.system.vault_root $config.folders.archive) "orphaned-refs.md"
    if (!(Test-Path $orphanPath)) {
        Write-Host "No orphaned references found"
        exit 0
    }

    $lines = Get-Content -Path $orphanPath -Encoding UTF8
    foreach ($line in $lines) {
        if ($line -match '^\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*`?(.*?)`?\s*\|\s*(.*?)\s*\|$') {
            $archivedFile = $matches[1].Trim()
            if (![string]::IsNullOrWhiteSpace($File) -and $archivedFile -ne $File) {
                continue
            }
            Write-Host $line
        }
    }
    exit 0
}
catch {
    Write-Log "List orphaned refs failed: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
