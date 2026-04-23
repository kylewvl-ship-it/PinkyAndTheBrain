#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true)]
    [string]$File,
    [string]$Status,
    [string]$Confidence,
    [string]$Owner,
    [string]$ReviewTrigger,
    [switch]$MarkVerified,
    [int]$ExtendReview,
    [string[]]$AddSource,
    [string[]]$RemoveSource,
    [switch]$ValidateSources,
    [switch]$Validate,
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

function Test-WikiInteractive {
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

function Get-RequiredMetadataIssues {
    param([string]$Frontmatter)

    $requiredFields = @("status", "owner", "confidence", "last_updated", "last_verified", "review_trigger", "source_list")
    $issues = @()
    foreach ($field in $requiredFields) {
        if ($field -eq "source_list") {
            if (!(Test-FrontmatterFieldPresent -Frontmatter $Frontmatter -Key $field)) {
                $issues += $field
            }
        }
        elseif ($field -eq "last_verified" -or $field -eq "review_trigger") {
            if (!(Test-FrontmatterFieldPresent -Frontmatter $Frontmatter -Key $field)) {
                $issues += $field
            }
        }
        else {
            $value = Get-FrontmatterValue -Frontmatter $Frontmatter -Key $field
            if ([string]::IsNullOrWhiteSpace($value)) {
                $issues += $field
            }
        }
    }
    return $issues
}

function Test-SourceAccessibility {
    param(
        [string]$Source,
        [hashtable]$Config,
        [switch]$EmitNotes
    )

    if ($Source -match '^https?://') {
        if ($EmitNotes) {
            Write-Host "NOTE: URL source added — verify it is still accessible: $Source"
        }
        return $true
    }

    $looksLikePath = ($Source -match '[\\/]' -or $Source -match '\.[A-Za-z0-9]+$')
    if (!$looksLikePath) {
        return $true
    }

    if (Test-Path $Source) {
        return $true
    }

    $vaultPath = Join-Path $Config.system.vault_root $Source
    if (Test-Path $vaultPath) {
        return $true
    }

    Write-Host "WARNING: Source not found: $Source" -ForegroundColor Yellow
    return $false
}

if ($Help) {
    Show-Usage "update-wiki-metadata.ps1" "Validate and update metadata on an existing wiki page" @(
        ".\scripts\update-wiki-metadata.ps1 -File 'knowledge/wiki/my-topic.md' -Validate",
        ".\scripts\update-wiki-metadata.ps1 -File 'knowledge/wiki/my-topic.md' -Status verified -Confidence high",
        ".\scripts\update-wiki-metadata.ps1 -File 'knowledge/wiki/my-topic.md' -MarkVerified"
    )
    exit 0
}

try {
    $config = Get-Config
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $wikiDir = [System.IO.Path]::GetFullPath((Join-Path $config.system.vault_root $config.folders.wiki))
    $resolvedFile = $null
    try {
        $resolvedFile = (Resolve-Path -LiteralPath $File -ErrorAction Stop).Path
    }
    catch {
        Write-Host "ERROR: File not found or not a wiki page: $File" -ForegroundColor Red
        exit 1
    }

    $resolvedFull = [System.IO.Path]::GetFullPath($resolvedFile)
    if (!$resolvedFull.StartsWith($wikiDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "ERROR: File not found or not a wiki page: $File" -ForegroundColor Red
        exit 1
    }

    $content = Get-Content -Path $resolvedFile -Raw -Encoding UTF8
    $frontmatterData = Get-FrontmatterData -Content $content
    if ($null -eq $frontmatterData) {
        Write-Host "ERROR: Cannot parse frontmatter in $resolvedFile. File may be corrupted." -ForegroundColor Red
        exit 1
    }

    $frontmatter = $frontmatterData.Frontmatter
    $body = $frontmatterData.Body
    $sourceList = @(Get-SourceList -Frontmatter $frontmatter)

    if ($Validate) {
        $issues = @(Get-RequiredMetadataIssues -Frontmatter $frontmatter)
        if ($issues.Count -eq 0) {
            Write-Host "All required metadata present" -ForegroundColor Green
            exit 0
        }
        Write-Host "Missing or empty required metadata fields: $($issues -join ', ')" -ForegroundColor Red
        exit 1
    }

    if ($ValidateSources) {
        $broken = 0
        foreach ($source in $sourceList) {
            if (!(Test-SourceAccessibility -Source $source -Config $config -EmitNotes)) {
                $broken++
            }
        }
        if ($broken -gt 0) {
            exit 1
        }
        exit 0
    }

    $changes = @()
    $writeRequired = $false
    $now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"

    if ($Status) {
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "status" -Value $Status
        $changes += "status"
        $writeRequired = $true
    }
    if ($Confidence) {
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "confidence" -Value $Confidence
        $changes += "confidence"
        $writeRequired = $true
    }
    if ($Owner) {
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "owner" -Value $Owner
        $changes += "owner"
        $writeRequired = $true
    }
    if ($ReviewTrigger) {
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "review_trigger" -Value $ReviewTrigger
        $changes += "review_trigger"
        $writeRequired = $true
    }

    $reviewDays = 90
    if ($config.review_cadence -and $config.review_cadence.ContainsKey('wiki_days') -and $config.review_cadence.wiki_days -gt 0) {
        $reviewDays = $config.review_cadence.wiki_days
    }

    if ($MarkVerified) {
        $verifiedAt = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
        $newTrigger = (Get-Date).AddDays($reviewDays).ToString("yyyy-MM-dd")
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "last_verified" -Value $verifiedAt
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "review_trigger" -Value $newTrigger
        $changes += "last_verified"
        $changes += "review_trigger"
        $writeRequired = $true
    }

    if ($ExtendReview -gt 0) {
        $currentTrigger = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'review_trigger'
        $baseDate = [datetime]::MinValue
        if (-not [datetime]::TryParse($currentTrigger, [ref]$baseDate)) {
            Write-Host "WARNING: Could not parse current review_trigger '$currentTrigger'. Extending from today." -ForegroundColor Yellow
            $baseDate = Get-Date
        }
        $newTrigger = $baseDate.AddDays($ExtendReview).ToString("yyyy-MM-dd")
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "review_trigger" -Value $newTrigger
        $changes += "review_trigger"
        $writeRequired = $true
    }

    if ($AddSource) {
        foreach ($source in $AddSource) {
            Test-SourceAccessibility -Source $source -Config $config -EmitNotes | Out-Null
            if ($sourceList -notcontains $source) {
                $sourceList += $source
                $writeRequired = $true
            }
        }
        $frontmatter = Set-SourceList -Frontmatter $frontmatter -Sources $sourceList
        $changes += "source_list"
    }

    if ($RemoveSource) {
        $removedAny = $false
        foreach ($source in $RemoveSource) {
            if ($sourceList -contains $source) {
                $sourceList = @($sourceList | Where-Object { $_ -ne $source })
                $removedAny = $true
            }
            else {
                Write-Host "WARNING: Source not found in list: $source" -ForegroundColor Yellow
            }
        }
        if ($removedAny) {
            $frontmatter = Set-SourceList -Frontmatter $frontmatter -Sources $sourceList
            $changes += "source_list"
            $writeRequired = $true
        }
    }

    if (!$writeRequired) {
        Write-Host "No metadata changes requested" -ForegroundColor Yellow
        exit 0
    }

    $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key "last_updated" -Value $now

    if ($WhatIf) {
        $changeSummary = (@($changes | Select-Object -Unique) -join ', ')
        Write-Output "Would update wiki metadata: $resolvedFile"
        Write-Output "Would change fields: $changeSummary"
        exit 0
    }

    $updatedContent = Build-Document -Frontmatter $frontmatter -Body $body
    Set-Content -Path $resolvedFile -Value $updatedContent -Encoding UTF8

    $distinctChanges = @($changes | Select-Object -Unique)
    if ($MarkVerified) {
        $nextReview = Get-FrontmatterValue -Frontmatter $frontmatter -Key "review_trigger"
        Write-Host "Marked verified. Next review: $nextReview" -ForegroundColor Green
    }
    elseif ($ExtendReview -gt 0) {
        $nextReview = Get-FrontmatterValue -Frontmatter $frontmatter -Key "review_trigger"
        Write-Host "Review extended to: $nextReview" -ForegroundColor Green
    }
    else {
        Write-Host "Updated metadata fields: $($distinctChanges -join ', ')" -ForegroundColor Green
    }

    $issuesAfterUpdate = @(Get-RequiredMetadataIssues -Frontmatter $frontmatter)
    if ($issuesAfterUpdate.Count -gt 0) {
        Write-Host "NOTICE: Page is missing required fields: $($issuesAfterUpdate -join ', '). Run with -Validate to see full report." -ForegroundColor Yellow
    }

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $repoRoot = Get-RepoRoot
        $relPath = Get-RelativeRepoPath -Path $resolvedFile -RepoRoot $repoRoot
        if ($relPath) {
            Invoke-GitCommit -Message ("Wiki metadata: updated $([System.IO.Path]::GetFileName($resolvedFile))") -Files @($relPath) -RepoPath $repoRoot | Out-Null
        }
    }

    exit 0
}
catch {
    Write-Log "Update wiki metadata failed: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
