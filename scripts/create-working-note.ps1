#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [string]$Project = "",
    [switch]$WhatIf,
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

function Test-WorkingInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }

    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Get-WorkingTemplateContent {
    param(
        [string]$TemplatePath,
        [string]$ResolvedTitle,
        [string]$ResolvedProject,
        [string]$IsoTimestamp,
        [string]$ReviewDate
    )

    $template = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    $template = $template.Replace('<title>', $ResolvedTitle)
    $template = $template.Replace('<timestamp>', $IsoTimestamp)
    $template = $template.Replace('<date>', $ReviewDate)
    $template = $template.Replace('status: "active"', 'status: "draft"')
    $template = $template.Replace('project: ""', ('project: "{0}"' -f $ResolvedProject))
    return $template
}

function Get-RelativeRepoPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if ($resolvedPath.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Replace($RepoRoot, '').TrimStart('/\').Replace('\', '/')
    }

    return ""
}

function Get-AlternativeWorkingFileNames {
    param(
        [string]$WorkingDirectory,
        [string]$BaseName
    )

    $suggestions = @()
    $suffix = 2
    while ($suggestions.Count -lt 2) {
        $candidate = "{0}-{1}.md" -f $BaseName, $suffix
        if (!(Test-Path (Join-Path $WorkingDirectory $candidate))) {
            $suggestions += $candidate
        }
        $suffix++
    }

    return $suggestions
}

function Test-RequiredMetadata {
    param([string]$Content)

    $requiredFields = @("status", "confidence", "last_updated")
    $missing = @()
    foreach ($field in $requiredFields) {
        if ($Content -notmatch "(?m)^$field\s*:") {
            $missing += $field
        }
    }
    return $missing
}

if ($Help) {
    Show-Usage "create-working-note.ps1" "Create a new working note from the working-note template" @(
        ".\scripts\create-working-note.ps1 -Title 'My Topic'"
        ".\scripts\create-working-note.ps1 -Title 'My Topic' -Project research"
    )
    exit 0
}

try {
    $config = Get-Config -Project $Project
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $workingDir = Join-Path $config.system.vault_root $config.folders.working
    $templatePath = Join-Path $config.system.template_root "working-note.md"
    if (!(Test-Path $templatePath)) {
        Write-Log "Working-note template not found: $templatePath" "ERROR"
        exit 2
    }

    $reviewDays = 30
    if ($config.review_cadence -and $config.review_cadence.ContainsKey('working_days') -and $config.review_cadence.working_days -gt 0) {
        $reviewDays = $config.review_cadence.working_days
    }

    $fileName = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.working_pattern
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $filePath = Join-Path $workingDir $fileName

    if (Test-Path $filePath) {
        $suggestions = Get-AlternativeWorkingFileNames -WorkingDirectory $workingDir -BaseName $baseName
        Write-Host "Working note already exists: $fileName" -ForegroundColor Yellow
        Write-Host "Try one of these instead: $($suggestions -join ', ')" -ForegroundColor Yellow

        if (Test-WorkingInteractive) {
            $openExisting = Read-Host "Open existing note instead? (y/N)"
            if ($openExisting -match '^[yY]$') {
                Invoke-Item $filePath
                exit 0
            }
        }
        exit 1
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $reviewDate = (Get-Date).AddDays($reviewDays).ToString("yyyy-MM-dd")
    $projectValue = if ([string]::IsNullOrWhiteSpace($Project)) { "" } else { $Project }
    $content = Get-WorkingTemplateContent -TemplatePath $templatePath -ResolvedTitle $Title -ResolvedProject $projectValue -IsoTimestamp $timestamp -ReviewDate $reviewDate

    $missingFields = @(Test-RequiredMetadata -Content $content)
    if ($missingFields.Count -gt 0) {
        Write-Host "Missing required metadata fields: $($missingFields -join ', ')" -ForegroundColor Red
        exit 1
    }

    if ($content -match '(?m)^status:\s*"?(.*?)"?\s*$') {
        $statusValue = $Matches[1]
        if (@("draft", "active", "promoted", "archived") -notcontains $statusValue) {
            [Console]::Error.WriteLine("WARNING: Invalid status value '$statusValue'")
        }
    }

    if ($WhatIf) {
        Write-Output "Would create file: $filePath"
        exit 0
    }

    if (!(Test-Path $workingDir)) {
        New-Item -ItemType Directory -Path $workingDir -Force | Out-Null
    }

    Set-Content -Path $filePath -Value $content -Encoding UTF8
    Write-Host "Created working note: $filePath" -ForegroundColor Green

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $relPath = Get-RelativeRepoPath -Path $filePath -RepoRoot $repoRoot
        if ($relPath) {
            Invoke-GitCommit -Message "Working note: created $fileName" -Files @($relPath) -RepoPath $repoRoot | Out-Null
        }
    }

    Write-Output $filePath
}
catch {
    Write-Log "Create working note failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Create working note failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
