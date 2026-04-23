#!/usr/bin/env pwsh
param(
    [int]$DaysAhead = 0,
    [switch]$All,
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

function Test-WikiInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }
    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Get-FrontmatterData {
    param([string]$Content)

    $normalized = $Content -replace "`r`n", "`n"
    if ($normalized -notmatch '(?s)^---\n(.*?)\n---\n?(.*)$') {
        return $null
    }
    return @{
        Frontmatter = $matches[1]
        Body = $matches[2]
    }
}

function Get-FrontmatterValue {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    $pattern = '(?m)^' + [regex]::Escape($Key) + '\s*:\s*["'']?(.*?)["'']?\s*$'
    $match = [regex]::Match($Frontmatter, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return ""
}

function Write-ReviewRow {
    param(
        [string]$Prefix,
        [hashtable]$Item
    )

    Write-Host ("{0}{1} | {2} | {3} | {4} | {5} | {6}" -f $Prefix, $Item.FileName, $Item.Title, $Item.Confidence, $Item.Status, $Item.ReviewTrigger, $Item.Display)
}

if ($Help) {
    Show-Usage "list-wiki-reviews.ps1" "List wiki pages due or upcoming for review" @(
        ".\scripts\list-wiki-reviews.ps1",
        ".\scripts\list-wiki-reviews.ps1 -DaysAhead 14",
        ".\scripts\list-wiki-reviews.ps1 -All"
    )
    exit 0
}

try {
    $config = Get-Config
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $wikiDir = Join-Path $config.system.vault_root $config.folders.wiki
    $today = (Get-Date).Date
    $overdue = @()
    $upcoming = @()
    $noTrigger = @()

    foreach ($wikiFile in (Get-ChildItem -Path $wikiDir -Filter *.md -File)) {
        $content = Get-Content -Path $wikiFile.FullName -Raw -Encoding UTF8
        $frontmatterData = Get-FrontmatterData -Content $content
        if ($null -eq $frontmatterData) {
            continue
        }

        $frontmatter = $frontmatterData.Frontmatter
        $title = Get-FrontmatterValue -Frontmatter $frontmatter -Key "title"
        if ([string]::IsNullOrWhiteSpace($title)) {
            $title = [System.IO.Path]::GetFileNameWithoutExtension($wikiFile.Name)
        }
        $confidence = Get-FrontmatterValue -Frontmatter $frontmatter -Key "confidence"
        $status = Get-FrontmatterValue -Frontmatter $frontmatter -Key "status"
        $reviewTrigger = Get-FrontmatterValue -Frontmatter $frontmatter -Key "review_trigger"

        $item = @{
            FileName = $wikiFile.Name
            Title = $title
            Confidence = $confidence
            Status = $status
            ReviewTrigger = $reviewTrigger
            Days = 0
            Display = ""
        }

        if ([string]::IsNullOrWhiteSpace($reviewTrigger)) {
            $item.Display = "[NO TRIGGER SET]"
            $noTrigger += $item
            continue
        }

        $reviewDate = [datetime]::MinValue
        if (-not [datetime]::TryParse($reviewTrigger, [ref]$reviewDate)) {
            $item.Display = "[NO TRIGGER SET]"
            $noTrigger += $item
            continue
        }

        $days = ($reviewDate.Date - $today).Days
        $item.Days = $days
        if ($days -le 0) {
            $item.Display = "{0} days overdue" -f [Math]::Abs($days)
            $overdue += $item
        }
        elseif ($All -or $days -le $DaysAhead) {
            $item.Display = "{0} days until due" -f $days
            $upcoming += $item
        }
    }

    $overdue = @($overdue | Sort-Object { [Math]::Abs($_.Days) } -Descending)
    $upcoming = @($upcoming | Sort-Object Days)
    $noTrigger = @($noTrigger | Sort-Object FileName)

    foreach ($item in $overdue) {
        Write-ReviewRow -Prefix "" -Item $item
    }
    foreach ($item in $upcoming) {
        Write-ReviewRow -Prefix "" -Item $item
    }
    if ($noTrigger.Count -gt 0) {
        Write-Host "[NO TRIGGER SET]"
        foreach ($item in $noTrigger) {
            Write-ReviewRow -Prefix "" -Item $item
        }
    }

    exit 0
}
catch {
    Write-Log "List wiki reviews failed: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
