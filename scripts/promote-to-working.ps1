#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceFile,
    [Parameter(Mandatory = $true)]
    [string]$Title,
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

function Get-KnowledgeRelativePath {
    param([string]$Path)

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).Replace('\', '/')
    $marker = "/knowledge/"
    $markerIndex = $resolvedPath.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($markerIndex -ge 0) {
        return $resolvedPath.Substring($markerIndex + 1)
    }

    return [System.IO.Path]::GetFileName($Path)
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

function Get-WorkingTemplateContent {
    param(
        [string]$TemplatePath,
        [string]$ResolvedTitle,
        [string]$IsoTimestamp,
        [string]$ReviewDate,
        [string]$EvidenceText,
        [string]$SourcePointer,
        [string]$SourceListValue
    )

    $template = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
    $template = $template.Replace('<title>', $ResolvedTitle)
    $template = $template.Replace('<timestamp>', $IsoTimestamp)
    $template = $template.Replace('<date>', $ReviewDate)
    $template = $template.Replace('status: "active"', 'status: "draft"')
    $template = $template.Replace('source_list: []', ('source_list: ["{0}"]' -f $SourceListValue))
    $template = $template.Replace('- Source or observation.', $EvidenceText)
    $template = $template.Replace('- raw/<file>', ('- {0}' -f $SourcePointer))
    return $template
}

function Update-SourcePromotedTo {
    param(
        [string]$Content,
        [string]$PromotedPath
    )

    $normalized = $Content -replace "`r`n", "`n"
    $lines = $normalized -split "`n"
    if ($lines.Count -lt 3 -or $lines[0] -ne "---") {
        return $Content
    }

    $closingIndex = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "---") {
            $closingIndex = $i
            break
        }
    }

    if ($closingIndex -lt 0) {
        return $Content
    }

    $frontmatterLines = @()
    $updated = $false
    for ($i = 1; $i -lt $closingIndex; $i++) {
        $line = $lines[$i]
        if ($line.TrimStart().StartsWith("promoted_to:")) {
            $frontmatterLines += ('promoted_to: "{0}"' -f $PromotedPath)
            $updated = $true
        }
        else {
            $frontmatterLines += $line
        }
    }

    if (!$updated) {
        $frontmatterLines += ('promoted_to: "{0}"' -f $PromotedPath)
    }

    $bodyLines = @()
    if ($closingIndex + 1 -lt $lines.Count) {
        $bodyLines = $lines[($closingIndex + 1)..($lines.Count - 1)]
    }

    return ("---`n{0}`n---`n{1}" -f ($frontmatterLines -join "`n"), ($bodyLines -join "`n"))
}

if ($Help) {
    Show-Usage "promote-to-working.ps1" "Create a working note from an inbox or raw source file" @(
        ".\scripts\promote-to-working.ps1 -SourceFile 'knowledge/inbox/my-item.md' -Title 'Working Topic'"
    )
    exit 0
}

try {
    $config = Get-Config
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $templatePath = Join-Path $config.system.template_root "working-note.md"
    if (!(Test-Path $templatePath)) {
        Write-Log "Working-note template not found: $templatePath" "ERROR"
        exit 2
    }

    $resolvedSourcePath = (Resolve-Path -LiteralPath $SourceFile -ErrorAction Stop).Path
    $sourceContent = Get-Content -Path $resolvedSourcePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($sourceContent)) {
        Write-Log "Source file unreadable or empty: $resolvedSourcePath" "ERROR"
        exit 1
    }

    $workingDir = Join-Path $config.system.vault_root $config.folders.working
    $reviewDays = 30
    if ($config.review_cadence -and $config.review_cadence.ContainsKey('working_days') -and $config.review_cadence.working_days -gt 0) {
        $reviewDays = $config.review_cadence.working_days
    }

    $fileName = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.working_pattern
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
    $targetPath = Join-Path $workingDir $fileName
    if (Test-Path $targetPath) {
        $suggestions = Get-AlternativeWorkingFileNames -WorkingDirectory $workingDir -BaseName $baseName
        Write-Host "Working note already exists: $fileName" -ForegroundColor Yellow
        Write-Host "Try one of these instead: $($suggestions -join ', ')" -ForegroundColor Yellow
        if (Test-WorkingInteractive) {
            $openExisting = Read-Host "Open existing note instead? (y/N)"
            if ($openExisting -match '^[yY]$') {
                Invoke-Item $targetPath
                exit 0
            }
        }
        exit 1
    }

    $corruptionWarning = $false
    $sourceBody = ""
    if ($sourceContent -match '(?s)^---\s*\r?\n(.*?)\r?\n---\s*\r?\n(.*)$') {
        $sourceBody = $matches[2].Trim()
    }
    else {
        Write-Log "Source frontmatter unreadable: $resolvedSourcePath" "WARN" "logs/script-errors.log"
        $sourceBody = $sourceContent.Trim()
        $corruptionWarning = $true
    }

    $evidenceText = $sourceBody
    if ($corruptionWarning) {
        $evidenceText = "# WARNING: Source frontmatter unreadable`n`n$sourceBody"
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
    $reviewDate = (Get-Date).AddDays($reviewDays).ToString("yyyy-MM-dd")
    $sourceRelativePath = Get-KnowledgeRelativePath -Path $resolvedSourcePath
    $targetRelativePath = "knowledge/working/$fileName"
    $content = Get-WorkingTemplateContent -TemplatePath $templatePath -ResolvedTitle $Title -IsoTimestamp $timestamp -ReviewDate $reviewDate -EvidenceText $evidenceText -SourcePointer $sourceRelativePath -SourceListValue $sourceRelativePath

    if ($WhatIf) {
        Write-Output "Would create file: $targetPath"
        exit 0
    }

    if (!(Test-Path $workingDir)) {
        New-Item -ItemType Directory -Path $workingDir -Force | Out-Null
    }

    Set-Content -Path $targetPath -Value $content -Encoding UTF8

    if (!$corruptionWarning) {
        $updatedSource = Update-SourcePromotedTo -Content $sourceContent -PromotedPath $targetRelativePath
        Set-Content -Path $resolvedSourcePath -Value $updatedSource -Encoding UTF8
    }

    Write-Host "Created working note: $targetPath" -ForegroundColor Green

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $filesToCommit = @()
        $targetRepoPath = Get-RelativeRepoPath -Path $targetPath -RepoRoot $repoRoot
        if ($targetRepoPath) { $filesToCommit += $targetRepoPath }
        $sourceRepoPath = Get-RelativeRepoPath -Path $resolvedSourcePath -RepoRoot $repoRoot
        if ($sourceRepoPath -and !$corruptionWarning) { $filesToCommit += $sourceRepoPath }
        if ($filesToCommit.Count -gt 0) {
            Invoke-GitCommit -Message ("Working note: promoted from {0}" -f [System.IO.Path]::GetFileName($resolvedSourcePath)) -Files $filesToCommit -RepoPath $repoRoot | Out-Null
        }
    }

    Write-Output $targetPath
}
catch {
    Write-Log "Promote to working failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Promote to working failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
