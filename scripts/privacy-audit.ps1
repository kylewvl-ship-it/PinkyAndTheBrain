#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Private,
    [switch]$ExcludeFromAI,
    [switch]$Redacted,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files,
    [string]$SetPrivate = "",
    [string]$SetExcludeFromAI = "",
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
. "$PSScriptRoot\lib\frontmatter.ps1"
if (Test-Path "$PSScriptRoot\lib\git-operations.ps1") {
    . "$PSScriptRoot\lib\git-operations.ps1"
}

function Get-RepoRoot {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($envRepoRoot)) {
        return [System.IO.Path]::GetFullPath($envRepoRoot)
    }

    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-BooleanSettingString {
    param([string]$Value)

    if ($Value -eq 'true' -or $Value -eq 'false') {
        return $Value
    }

    return ""
}

function Get-ArrayFieldValues {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    $value = Get-FrontmatterValue -Frontmatter $Frontmatter -Key $Key
    if ([string]::IsNullOrWhiteSpace($value)) {
        return @()
    }

    $trimmed = $value.Trim()
    if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
        return @(
            ($trimmed.Trim('[', ']') -split ',') |
                ForEach-Object { $_.Trim().Trim('"').Trim("'") } |
                Where-Object { $_ -ne '' }
        )
    }

    return @($trimmed.Trim('"').Trim("'"))
}

function Get-LayerLabelFromPath {
    param(
        [string]$FullPath,
        [hashtable]$Config
    )

    $vaultRoot = [System.IO.Path]::GetFullPath([string]$Config.system.vault_root)
    $folderMap = @(
        @{ Folder = [System.IO.Path]::GetFullPath((Join-Path $vaultRoot $Config.folders.wiki)); Label = "[WIKI]" }
        @{ Folder = [System.IO.Path]::GetFullPath((Join-Path $vaultRoot $Config.folders.working)); Label = "[WORK]" }
        @{ Folder = [System.IO.Path]::GetFullPath((Join-Path $vaultRoot $Config.folders.raw)); Label = "[RAW]" }
        @{ Folder = [System.IO.Path]::GetFullPath((Join-Path $vaultRoot $Config.folders.inbox)); Label = "[INBOX]" }
        @{ Folder = [System.IO.Path]::GetFullPath((Join-Path $vaultRoot $Config.folders.archive)); Label = "[ARCH]" }
    )

    foreach ($item in $folderMap) {
        if ($FullPath.StartsWith($item.Folder, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $item.Label
        }
    }

    return "[FILE]"
}

function Get-UpdatedFrontmatter {
    param(
        [string]$Frontmatter,
        [string]$FieldName,
        [string]$FieldValue
    )

    $lines = $Frontmatter -split "`r?`n"
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^' + [regex]::Escape($FieldName) + '\s*:')) {
            $lines[$i] = ('{0}: {1}' -f $FieldName, $FieldValue)
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        $insertIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^private\s*:') {
                $insertIndex = $i + 1
                break
            }
        }

        if ($insertIndex -ge 0) {
            $before = @()
            if ($insertIndex -gt 0) {
                $before = $lines[0..($insertIndex - 1)]
            }
            $after = @()
            if ($insertIndex -lt $lines.Count) {
                $after = $lines[$insertIndex..($lines.Count - 1)]
            }
            $lines = @($before + ('{0}: {1}' -f $FieldName, $FieldValue) + $after)
        }
        else {
            $lines += ('{0}: {1}' -f $FieldName, $FieldValue)
        }
    }

    return ($lines -join "`n")
}

function Expand-FileArguments {
    param([string[]]$InputFiles)

    $expanded = @()
    foreach ($item in $InputFiles) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        foreach ($part in ($item -split ',')) {
            $trimmed = $part.Trim().Trim('"')
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $expanded += $trimmed
            }
        }
    }

    return @($expanded)
}

if ($Help) {
    Show-Usage "privacy-audit.ps1" "Audit and update sensitive content controls" @(
        ".\scripts\privacy-audit.ps1"
        ".\scripts\privacy-audit.ps1 -Private"
        ".\scripts\privacy-audit.ps1 -SetPrivate true -Files 'knowledge/wiki/a.md','knowledge/working/b.md'"
    )
    exit 0
}

try {
    $config = Get-Config
    $setMode = -not [string]::IsNullOrWhiteSpace($SetPrivate) -or -not [string]::IsNullOrWhiteSpace($SetExcludeFromAI)

    if ($setMode) {
        $fieldName = ""
        $fieldValue = ""
        if (-not [string]::IsNullOrWhiteSpace($SetPrivate)) {
            $fieldName = "private"
            $fieldValue = Get-BooleanSettingString -Value $SetPrivate
        }
        else {
            $fieldName = "exclude_from_ai"
            $fieldValue = Get-BooleanSettingString -Value $SetExcludeFromAI
        }

        if ([string]::IsNullOrWhiteSpace($fieldValue)) {
            Write-Log "Privacy update value must be 'true' or 'false'." "ERROR"
            exit 1
        }
        $targetFiles = @(Expand-FileArguments -InputFiles $Files)
        if ($targetFiles.Count -eq 0) {
            Write-Log "Bulk update requires -Files." "ERROR"
            exit 1
        }

        $repoRoot = Get-RepoRoot
        $updatedCount = 0
        foreach ($filePath in $targetFiles) {
            $resolvedPath = $filePath
            if (-not (Test-Path $resolvedPath)) {
                $candidate = Join-Path $repoRoot $filePath
                if (Test-Path $candidate) {
                    $resolvedPath = $candidate
                }
            }

            if (-not (Test-Path $resolvedPath)) {
                Write-Log "File not found: $filePath" "ERROR"
                exit 1
            }

            if ($WhatIfPreference) {
                Write-Output ("Would set {0}={1} in {2}" -f $fieldName, $fieldValue, $resolvedPath)
                continue
            }

            $content = Get-Content -Path $resolvedPath -Raw -Encoding UTF8
            $frontmatterData = Get-FrontmatterData -Content $content
            if ($null -eq $frontmatterData) {
                Write-Log "File does not contain frontmatter: $resolvedPath" "ERROR"
                exit 1
            }

            $updatedFrontmatter = Get-UpdatedFrontmatter -Frontmatter $frontmatterData.Frontmatter -FieldName $fieldName -FieldValue $fieldValue
            $updatedDocument = Build-Document -Frontmatter $updatedFrontmatter -Body $frontmatterData.Body
            Set-Content -Path $resolvedPath -Value $updatedDocument -Encoding UTF8
            $updatedCount++

            if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
                $relPath = Get-RelativeRepoPath -Path $resolvedPath -RepoRoot $repoRoot
                Invoke-GitCommit -Message ("privacy: set {0}={1} in {2}" -f $fieldName, $fieldValue, $relPath) -Files @($relPath) -RepoPath $repoRoot | Out-Null
            }
        }

        if (-not $WhatIfPreference) {
            Write-Output ("Updated {0} file(s)." -f $updatedCount)
        }
        exit 0
    }

    $vaultRoot = [System.IO.Path]::GetFullPath([string]$config.system.vault_root)
    $rows = @()
    foreach ($file in (Get-ChildItem -Path $vaultRoot -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue)) {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $frontmatterData = Get-FrontmatterData -Content $content
        if ($null -eq $frontmatterData) {
            continue
        }

        $frontmatter = $frontmatterData.Frontmatter
        $isPrivate = ((Get-FrontmatterValue -Frontmatter $frontmatter -Key 'private') -eq 'true')
        $isExcludedFromAi = ((Get-FrontmatterValue -Frontmatter $frontmatter -Key 'exclude_from_ai') -eq 'true')
        $redactedSections = @(Get-ArrayFieldValues -Frontmatter $frontmatter -Key 'redacted_sections')
        $hasRedactions = $redactedSections.Count -gt 0

        if (-not ($isPrivate -or $isExcludedFromAi -or $hasRedactions)) {
            continue
        }
        if ($Private -and -not $isPrivate) {
            continue
        }
        if ($ExcludeFromAI -and -not $isExcludedFromAi) {
            continue
        }
        if ($Redacted -and -not $hasRedactions) {
            continue
        }

        $rows += [pscustomobject]@{
            File = Get-RelativeRepoPath -Path $file.FullName -RepoRoot (Get-RepoRoot)
            Layer = Get-LayerLabelFromPath -FullPath $file.FullName -Config $config
            Private = $isPrivate.ToString().ToLowerInvariant()
            ExcludeFromAI = $isExcludedFromAi.ToString().ToLowerInvariant()
            RedactedSections = $redactedSections.Count
        }
    }

    if ($rows.Count -eq 0) {
        Write-Output "No files with sensitive content controls found."
        exit 0
    }

    Write-Output ($rows | Format-Table -AutoSize | Out-String -Width 4096)
    exit 0
}
catch {
    $lineNumber = if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 }
    Write-Log "Privacy audit failed at line ${lineNumber}: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: line ${lineNumber}: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
