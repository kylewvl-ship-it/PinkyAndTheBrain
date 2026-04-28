#!/usr/bin/env pwsh
# PinkyAndTheBrain Project Lister
# Lists all projects and their file counts across knowledge layers.

param(
    [string]$Project = "",
    [switch]$Counts,
    [switch]$Domain,
    [switch]$Help
)

if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/lib/frontmatter.ps1"

function Get-FrontmatterValuesLocal {
    param([string]$Frontmatter, [string]$Key)
    $value = Get-FrontmatterValue -Frontmatter $Frontmatter -Key $Key
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    $trimmed = $value.Trim()
    if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
        return @(($trimmed.Trim('[', ']') -split ',') |
            ForEach-Object { $_.Trim().Trim('"').Trim("'") } |
            Where-Object { $_ -ne '' })
    }
    return @($trimmed.Trim('"').Trim("'"))
}

if ($Help) {
    Show-Usage "list-projects.ps1" "List all projects and their file counts" @(
        ".\scripts\list-projects.ps1"
        ".\scripts\list-projects.ps1 -Project accounting"
        ".\scripts\list-projects.ps1 -Domain"
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

$fieldName = if ($Domain) { "domain" } else { "project" }
$headerName = if ($Domain) { "Domains" } else { "Projects" }

Write-Host "`nPinkyAndTheBrain $headerName" -ForegroundColor Cyan
Write-Host "Vault: $vaultRoot`n" -ForegroundColor Gray

# Collect values by scanning YAML front-matter.
$projectCounts = @{}
$untaggedCount = 0
$totalFiles = 0

foreach ($folder in $searchFolders) {
    $folderPath = "$vaultRoot/$folder"
    if (!(Test-Path $folderPath)) { continue }

    $mdFiles = Get-ChildItem $folderPath -Filter "*.md" -Recurse -ErrorAction SilentlyContinue
    foreach ($file in $mdFiles) {
        $totalFiles++

        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $frontmatterData = Get-FrontmatterData -Content $content
        $values = @()
        if ($null -ne $frontmatterData) {
            $values = @(Get-FrontmatterValuesLocal -Frontmatter $frontmatterData.Frontmatter -Key $fieldName)
        }

        if ($values.Count -eq 0) {
            $untaggedCount++
            continue
        }

        foreach ($value in $values) {
            if (!$projectCounts.ContainsKey($value)) { $projectCounts[$value] = 0 }
            $projectCounts[$value]++
        }
    }
}

if ($projectCounts.Count -eq 0 -and $untaggedCount -eq 0) {
    Write-Host "No markdown files found in knowledge folders." -ForegroundColor Yellow
    exit 0
}

if ($Project -and -not $Domain) {
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
    $sorted = $projectCounts.GetEnumerator() | Sort-Object -Property Key
    $maxLen = 10
    if ($sorted.Count -gt 0) {
        $maxLen = ($sorted | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum
    }

    foreach ($entry in $sorted) {
        $name = $entry.Key.PadRight($maxLen + 2)
        $count = "$($entry.Value) file(s)"
        Write-Host "  $name $count" -ForegroundColor White
    }
    if ($untaggedCount -gt 0) {
        Write-Host "  (untagged)".PadRight($maxLen + 4) "$untaggedCount file(s)" -ForegroundColor DarkGray
    }

    Write-Host ""
    $totalLabel = if ($Domain) { "domain(s)" } else { "project(s)" }
    Write-Host "Total: $($projectCounts.Count) $totalLabel, $totalFiles file(s)" -ForegroundColor Gray
}
