#!/usr/bin/env pwsh
# PinkyAndTheBrain Project Lister
# Lists all projects and their file counts across knowledge layers.

param(
    [string]$Project = "",
    [switch]$Counts,
    [switch]$Help
)

if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"

if ($Help) {
    Show-Usage "list-projects.ps1" "List all projects and their file counts" @(
        ".\scripts\list-projects.ps1"
        ".\scripts\list-projects.ps1 -Project accounting"
        ".\scripts\list-projects.ps1 -Counts"
    )
    exit 0
}

$config = Get-Config -Project $Project

$vaultRoot = $config.system.vault_root
$searchFolders = @(
    $config.folders.inbox,
    $config.folders.raw,
    $config.folders.working,
    $config.folders.wiki
)

Write-Host "`nPinkyAndTheBrain Projects" -ForegroundColor Cyan
Write-Host "Vault: $vaultRoot`n" -ForegroundColor Gray

# Collect projects by scanning YAML front-matter for 'project:' field
$projectCounts = @{}
$totalFiles = 0

foreach ($folder in $searchFolders) {
    $folderPath = "$vaultRoot/$folder"
    if (!(Test-Path $folderPath)) { continue }

    $mdFiles = Get-ChildItem $folderPath -Filter "*.md" -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $mdFiles) {
        $totalFiles++
        $proj = $null

        # Extract project from front-matter
        $lines = Get-Content $file.FullName -TotalCount 20 -ErrorAction SilentlyContinue
        $inFrontMatter = $false
        $lineIndex = 0
        foreach ($line in $lines) {
            if ($line -eq '---') {
                if (!$inFrontMatter) { $inFrontMatter = $true } else { break }
                $lineIndex++; continue
            }
            if ($inFrontMatter -and $line -match '^project:\s*(.+)$') {
                $proj = $Matches[1].Trim().Trim('"').Trim("'")
                if ([string]::IsNullOrWhiteSpace($proj)) { $proj = $null }
                break
            }
            if (!$inFrontMatter -and $lineIndex -gt 0) { break }
            $lineIndex++
        }

        if ($null -eq $proj) { continue }
        if (!$projectCounts.ContainsKey($proj)) { $projectCounts[$proj] = 0 }
        $projectCounts[$proj]++
    }
}

if ($projectCounts.Count -eq 0) {
    Write-Host "No markdown files found in knowledge folders." -ForegroundColor Yellow
    exit 0
}

# Filter by project if specified
if ($Project) {
    if ($projectCounts.ContainsKey($Project)) {
        Write-Host "Project: $Project" -ForegroundColor White
        Write-Host "  Files: $($projectCounts[$Project])" -ForegroundColor Gray
    }
    else {
        Write-Host "Project '$Project' not found." -ForegroundColor Yellow
        Write-Host "Known projects: $($projectCounts.Keys -join ', ')" -ForegroundColor Gray
        exit 1
    }
}
else {
    # List all projects
    $sorted = $projectCounts.GetEnumerator() | Sort-Object -Property Key
    $maxLen = ($sorted | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum

    foreach ($entry in $sorted) {
        $name = $entry.Key.PadRight($maxLen + 2)
        $count = "$($entry.Value) file(s)"
        Write-Host "  $name $count" -ForegroundColor White
    }

    Write-Host ""
    Write-Host "Total: $($projectCounts.Count) project(s), $totalFiles file(s)" -ForegroundColor Gray
}
