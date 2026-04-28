#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SetProject = "",
    [string]$SetDomain = "",
    [string]$Folder = "",
    [string]$Pattern = "*.md",
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

function Resolve-FolderPath {
    param(
        [string]$InputPath,
        [string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        return ""
    }

    if ([System.IO.Path]::IsPathRooted($InputPath)) {
        return [System.IO.Path]::GetFullPath($InputPath)
    }

    $candidate = Join-Path $RepoRoot $InputPath
    if (Test-Path $candidate) {
        return [System.IO.Path]::GetFullPath($candidate)
    }

    return $InputPath
}

function Test-PathInsideRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    return ($resolvedPath.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedPath.StartsWith($resolvedRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))
}

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

function Test-FrontmatterValuePresent {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    return (@(Get-FrontmatterValuesLocal -Frontmatter $Frontmatter -Key $Key).Count -gt 0)
}

function Set-DocumentFrontmatterField {
    param(
        [string]$Content,
        [string]$Key,
        [string]$Value
    )

    $frontmatterData = Get-FrontmatterData -Content $Content
    $frontmatter = ""
    $body = $Content
    if ($null -ne $frontmatterData) {
        $frontmatter = $frontmatterData.Frontmatter
        $body = $frontmatterData.Body
    }

    $updatedFrontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key $Key -Value $Value
    return Build-Document -Frontmatter $updatedFrontmatter -Body $body
}

if ($Help) {
    Show-Usage "manage-project-tags.ps1" "Bulk-assign project or domain tags to untagged markdown files" @(
        ".\scripts\manage-project-tags.ps1 -SetProject work -Folder knowledge/inbox/work-notes"
        ".\scripts\manage-project-tags.ps1 -SetDomain accounting -Folder knowledge/wiki"
        ".\scripts\manage-project-tags.ps1 -SetProject work -SetDomain accounting -Folder knowledge/inbox -WhatIf"
    )
    exit 0
}

try {
    $config = Get-Config
    $repoRoot = Get-RepoRoot

    if ([string]::IsNullOrWhiteSpace($SetProject) -and [string]::IsNullOrWhiteSpace($SetDomain)) {
        Write-Log "At least one of -SetProject or -SetDomain is required." "ERROR"
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($Folder)) {
        Write-Log "-Folder is required." "ERROR"
        exit 1
    }

    $folderPath = Resolve-FolderPath -InputPath $Folder -RepoRoot $repoRoot
    if (-not (Test-Path $folderPath -PathType Container)) {
        Write-Log "Folder not found: $Folder" "ERROR"
        exit 1
    }

    $vaultRoot = [System.IO.Path]::GetFullPath([string]$config.system.vault_root)
    if (-not (Test-PathInsideRoot -Path $folderPath -Root $repoRoot) -and -not (Test-PathInsideRoot -Path $folderPath -Root $vaultRoot)) {
        Write-Log "Folder must be inside the repository or configured vault: $Folder" "ERROR"
        exit 1
    }

    $files = @(Get-ChildItem -Path $folderPath -Filter $Pattern -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $taggedCount = 0
    $skippedCount = 0

    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $frontmatterData = Get-FrontmatterData -Content $content
        if ($null -eq $frontmatterData -and $content -match '^\s*---') {
            Write-Log "File has malformed frontmatter: $($file.FullName)" "ERROR"
            exit 1
        }

        $frontmatter = ""
        if ($null -ne $frontmatterData) {
            $frontmatter = $frontmatterData.Frontmatter
        }

        $updates = @()
        $alreadyTagged = $false
        if (-not [string]::IsNullOrWhiteSpace($SetProject)) {
            if (Test-FrontmatterValuePresent -Frontmatter $frontmatter -Key "project") {
                $alreadyTagged = $true
            }
            else {
                $updates += @{ Key = "project"; Value = $SetProject }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($SetDomain)) {
            if (Test-FrontmatterValuePresent -Frontmatter $frontmatter -Key "domain") {
                $alreadyTagged = $true
            }
            else {
                $updates += @{ Key = "domain"; Value = $SetDomain }
            }
        }

        if ($updates.Count -eq 0) {
            if ($alreadyTagged) {
                $skippedCount++
            }
            continue
        }

        $relPath = Get-RelativeRepoPath -Path $file.FullName -RepoRoot $repoRoot
        if ($WhatIfPreference) {
            foreach ($update in $updates) {
                Write-Output ("Would set {0}={1} in {2}" -f $update.Key, $update.Value, $file.FullName)
            }
            $taggedCount++
            continue
        }

        $updatedContent = $content
        foreach ($update in $updates) {
            $updatedContent = Set-DocumentFrontmatterField -Content $updatedContent -Key $update.Key -Value $update.Value
        }

        if (-not $PSCmdlet.ShouldProcess($file.FullName, "Set project/domain tag")) {
            continue
        }

        Set-Content -Path $file.FullName -Value $updatedContent -Encoding UTF8
        $taggedCount++

        if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
            $messageParts = @()
            foreach ($update in $updates) {
                $messageParts += ("{0}={1}" -f $update.Key, $update.Value)
            }
            Invoke-GitCommit -Message ("project-tags: set {0} in {1}" -f ($messageParts -join ", "), $relPath) -Files @($relPath) -RepoPath $repoRoot | Out-Null
        }
    }

    Write-Output ("Tagged {0} file(s). Skipped {1} file(s) (already tagged)." -f $taggedCount, $skippedCount)
    exit 0
}
catch {
    $lineNumber = if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 }
    Write-Log "Project tag management failed at line ${lineNumber}: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: line ${lineNumber}: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
