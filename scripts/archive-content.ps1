#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true)]
    [string]$File,
    [Parameter(Mandatory = $true)]
    [string]$Reason,
    [string]$ReplacedBy = "",
    [switch]$UpdateReferences,
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
. "$PSScriptRoot/lib/frontmatter.ps1"

function Test-ArchiveInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }
    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Get-RepoRoot {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (![string]::IsNullOrWhiteSpace($envRepoRoot)) {
        return [System.IO.Path]::GetFullPath($envRepoRoot)
    }
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-AllowedArchiveReasons {
    return @("stale", "replaced", "low-confidence", "no-longer-relevant", "duplicate")
}

function Ensure-ArchiveMetadata {
    param(
        [string]$Frontmatter,
        [string]$ArchiveReason,
        [string]$Replacement
    )

    $requiredDefaults = @{
        status = "archived"
        owner = "Reno"
        confidence = "low"
        last_updated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
        last_verified = ""
        review_trigger = ""
    }

    foreach ($key in $requiredDefaults.Keys) {
        if (!(Test-FrontmatterFieldPresent -Frontmatter $Frontmatter -Key $key)) {
            $Frontmatter = Set-FrontmatterField -Frontmatter $Frontmatter -Key $key -Value $requiredDefaults[$key]
        }
    }

    if (!(Test-FrontmatterFieldPresent -Frontmatter $Frontmatter -Key "source_list")) {
        $Frontmatter = Set-SourceList -Frontmatter $Frontmatter -Sources @()
    }

    $Frontmatter = Set-FrontmatterField -Frontmatter $Frontmatter -Key "status" -Value "archived"
    $Frontmatter = Set-FrontmatterField -Frontmatter $Frontmatter -Key "archived_date" -Value (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    $Frontmatter = Set-FrontmatterField -Frontmatter $Frontmatter -Key "archive_reason" -Value $ArchiveReason
    $Frontmatter = Set-FrontmatterField -Frontmatter $Frontmatter -Key "replaced_by" -Value $Replacement
    $Frontmatter = Set-FrontmatterField -Frontmatter $Frontmatter -Key "last_updated" -Value (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
    return $Frontmatter
}

function Get-ArchiveDestinationPath {
    param(
        [string]$SourcePath,
        [hashtable]$Config
    )

    $archiveDir = [System.IO.Path]::Combine([string]$Config.system.vault_root, [string]$Config.folders.archive)
    $fileName = [System.IO.Path]::GetFileName($SourcePath)
    $candidate = [System.IO.Path]::Combine($archiveDir, $fileName)
    if (!(Test-Path $candidate)) {
        return $candidate
    }

    $parent = Split-Path (Split-Path $SourcePath -Parent) -Leaf
    $candidate = [System.IO.Path]::Combine($archiveDir, ("{0}-{1}" -f $parent, $fileName))
    return $candidate
}

function Get-ArchiveRelativePath {
    param(
        [string]$SourceRelative,
        [string]$DestinationPath,
        [hashtable]$Config
    )

    $archiveDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([string]$Config.system.vault_root, [string]$Config.folders.archive))
    $destinationFull = [System.IO.Path]::GetFullPath($DestinationPath)
    if ($destinationFull.StartsWith($archiveDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "knowledge/archive/" + [System.IO.Path]::GetFileName($destinationFull)
    }
    return $SourceRelative
}

function Find-ReferencingFiles {
    param(
        [string]$Stem,
        [string]$FileName,
        [string]$TargetRelativePath,
        [hashtable]$Config,
        [string]$SourceFullPath
    )

    $results = @()
    $scanDirs = @(
        [System.IO.Path]::Combine([string]$Config.system.vault_root, [string]$Config.folders.wiki),
        [System.IO.Path]::Combine([string]$Config.system.vault_root, [string]$Config.folders.working),
        [System.IO.Path]::Combine([string]$Config.system.vault_root, [string]$Config.folders.raw)
    )

    foreach ($dir in $scanDirs) {
        if (!(Test-Path $dir)) { continue }
        foreach ($candidate in (Get-ChildItem -Path $dir -Filter *.md -File)) {
            if ([System.IO.Path]::GetFullPath($candidate.FullName) -eq [System.IO.Path]::GetFullPath($SourceFullPath)) {
                continue
            }
            $content = Get-Content -Path $candidate.FullName -Raw -Encoding UTF8
            $match = [regex]::Match($content, '\[\[' + [regex]::Escape($Stem) + '(\|[^\]]+)?\]\]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if (!$match.Success) {
                $match = [regex]::Match($content, '\[[^\]]+\]\(([^)]*' + [regex]::Escape($FileName) + ')\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            }
            if ($match.Success) {
                $repoRoot = Get-RepoRoot
                $relative = Get-RelativeRepoPath -Path $candidate.FullName -RepoRoot $repoRoot
                $results += @{
                    Path = $candidate.FullName
                    RelativePath = $relative
                    LinkedAs = $match.Value
                }
            }
        }
    }

    return $results
}

function Ensure-OrphanLog {
    param([hashtable]$Config)

    $orphanPath = [System.IO.Path]::Combine([string]$Config.system.vault_root, [string]$Config.folders.archive, "orphaned-refs.md")
    if (!(Test-Path $orphanPath)) {
@"
# Orphaned References Log

| Archived File | Referencing File | Linked As | Archived Date |
|---|---|---|---|
"@ | Set-Content -Path $orphanPath -Encoding UTF8
    }
    return $orphanPath
}

function Append-OrphanRecord {
    param(
        [string]$OrphanPath,
        [string]$ArchivedRelative,
        [hashtable]$Reference
    )

    $archivedDisplay = $ArchivedRelative.Replace('knowledge/', '')
    $refDisplay = $Reference.RelativePath.Replace('knowledge/', '')
    $row = '| {0} | {1} | `{2}` | {3} |' -f $archivedDisplay, $refDisplay, $Reference.LinkedAs, (Get-Date -Format "yyyy-MM-dd")
    Add-Content -Path $OrphanPath -Value $row -Encoding UTF8
}

function Update-ReferenceContent {
    param(
        [string]$Path,
        [string]$Stem,
        [string]$FileName,
        [string]$Replacement
    )

    $content = Get-Content -Path $Path -Raw -Encoding UTF8
    if (![string]::IsNullOrWhiteSpace($Replacement)) {
        $content = [regex]::Replace($content, '\[\[' + [regex]::Escape($Stem) + '(\|[^\]]+)?\]\]', '[' + $Replacement + '](' + $Replacement + ')', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $content = [regex]::Replace($content, '(\[[^\]]+\]\()([^)]*' + [regex]::Escape($FileName) + ')(\))', '$1' + $Replacement + '$3', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    else {
        $content = [regex]::Replace($content, '\[\[' + [regex]::Escape($Stem) + '(\|[^\]]+)?\]\]', '$0 [ARCHIVED]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $content = [regex]::Replace($content, '(\[[^\]]+\]\([^)]*' + [regex]::Escape($FileName) + '\))', '$1 [ARCHIVED]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    Set-Content -Path $Path -Value $content -Encoding UTF8
}

if ($Help) {
    Show-Usage "archive-content.ps1" "Archive wiki or working content with archive metadata" @(
        ".\scripts\archive-content.ps1 -File 'knowledge/wiki/old-topic.md' -Reason stale",
        ".\scripts\archive-content.ps1 -File 'knowledge/wiki/old-topic.md' -Reason replaced -ReplacedBy 'knowledge/wiki/new-topic.md' -UpdateReferences"
    )
    exit 0
}

try {
    $config = Get-Config
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    if ((Get-AllowedArchiveReasons) -notcontains $Reason) {
        Write-Host "ERROR: Invalid archive reason: $Reason" -ForegroundColor Red
        exit 1
    }

    $resolvedFile = $null
    try {
        $resolvedFile = (Resolve-Path -LiteralPath $File -ErrorAction Stop).Path
    }
    catch {
        Write-Host "ERROR: File not found or not archivable: $File" -ForegroundColor Red
        exit 1
    }

    $wikiDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([string]$config.system.vault_root, [string]$config.folders.wiki))
    $workingDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([string]$config.system.vault_root, [string]$config.folders.working))
    $resolvedFull = [System.IO.Path]::GetFullPath($resolvedFile)
    if (!$resolvedFull.StartsWith($wikiDir, [System.StringComparison]::OrdinalIgnoreCase) -and !$resolvedFull.StartsWith($workingDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "ERROR: File not found or not archivable: $File" -ForegroundColor Red
        exit 1
    }

    $repoRoot = Get-RepoRoot
    $sourceRelative = Get-RelativeRepoPath -Path $resolvedFile -RepoRoot $repoRoot
    $sourceContent = Get-Content -Path $resolvedFile -Raw -Encoding UTF8
    $frontmatterData = Get-FrontmatterData -Content $sourceContent
    if ($null -eq $frontmatterData) {
        Write-Host "ERROR: Cannot parse frontmatter in $resolvedFile. File may be corrupted." -ForegroundColor Red
        exit 1
    }

    $fileName = [System.IO.Path]::GetFileName($resolvedFile)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($resolvedFile)
    $references = @(Find-ReferencingFiles -Stem $stem -FileName $fileName -TargetRelativePath $sourceRelative -Config $config -SourceFullPath $resolvedFile)

    if ($references.Count -gt 0) {
        Write-Host "Found references:" -ForegroundColor Yellow
        foreach ($reference in $references) {
            Write-Host "- $($reference.RelativePath) => $($reference.LinkedAs)" -ForegroundColor Yellow
        }
    }

    $destinationPath = Get-ArchiveDestinationPath -SourcePath $resolvedFile -Config $config
    $archivedRelative = Get-ArchiveRelativePath -SourceRelative $sourceRelative -DestinationPath $destinationPath -Config $config

    if ($WhatIf) {
        Write-Output "Would archive file: $resolvedFile"
        Write-Output "Would move to: $destinationPath"
        exit 0
    }

    $orphanPath = Ensure-OrphanLog -Config $config
    $updatedReferencePaths = @()
    foreach ($reference in $references) {
        $shouldUpdate = $UpdateReferences
        if (!$UpdateReferences -and (Test-ArchiveInteractive)) {
            $choice = Read-Host "Reference $($reference.RelativePath): [U]pdate, [O]rphan, [S]kip"
            $shouldUpdate = ($choice -match '^[uU]$')
            if ($choice -match '^[sS]$') {
                continue
            }
        }

        if ($shouldUpdate) {
            Update-ReferenceContent -Path $reference.Path -Stem $stem -FileName $fileName -Replacement $ReplacedBy
            $updatedReferencePaths += $reference.Path
        }
        else {
            Append-OrphanRecord -OrphanPath $orphanPath -ArchivedRelative $archivedRelative -Reference $reference
        }
    }

    $frontmatter = Ensure-ArchiveMetadata -Frontmatter $frontmatterData.Frontmatter -ArchiveReason $Reason -Replacement $ReplacedBy
    $updatedContent = Build-Document -Frontmatter $frontmatter -Body $frontmatterData.Body
    Set-Content -Path $resolvedFile -Value $updatedContent -Encoding UTF8

    Move-Item -LiteralPath $resolvedFile -Destination $destinationPath -Force

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $filesToCommit = @()
        $destinationRel = Get-RelativeRepoPath -Path $destinationPath -RepoRoot $repoRoot
        if ($destinationRel) { $filesToCommit += $destinationRel }
        $orphanRel = Get-RelativeRepoPath -Path $orphanPath -RepoRoot $repoRoot
        if ($references.Count -gt 0 -and $orphanRel) { $filesToCommit += $orphanRel }
        foreach ($referencePath in $updatedReferencePaths) {
            $refRel = Get-RelativeRepoPath -Path $referencePath -RepoRoot $repoRoot
            if ($refRel) { $filesToCommit += $refRel }
        }
        $filesToCommit = @($filesToCommit | Select-Object -Unique)
        if ($filesToCommit.Count -gt 0) {
            Invoke-GitCommit -Message ("Archive: {0}" -f $fileName) -Files $filesToCommit -RepoPath $repoRoot | Out-Null
        }
    }

    Write-Host "Archived file: $destinationPath" -ForegroundColor Green
    exit 0
}
catch {
    Write-Log "Archive content failed: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
