#!/usr/bin/env pwsh
param(
    [string]$Status = "",
    [ValidateSet("last_updated", "confidence", "title")]
    [string]$SortBy = "title",
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

function Get-FrontmatterValue {
    param(
        [string]$Content,
        [string]$Key
    )

    $match = [regex]::Match($Content, "(?m)^$Key\s*:\s*[`"']?(.+?)[`"']?\s*$")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim('"').Trim("'")
    }
    return ""
}

if ($Help) {
    Show-Usage "list-working-notes.ps1" "List working notes with status and review timing" @(
        ".\scripts\list-working-notes.ps1"
        ".\scripts\list-working-notes.ps1 -Status active"
        ".\scripts\list-working-notes.ps1 -SortBy last_updated"
    )
    exit 0
}

try {
    $config = Get-Config
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $workingDir = Join-Path $config.system.vault_root $config.folders.working
    $files = @(Get-ChildItem -Path $workingDir -Filter "*.md" -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        Write-Host "No working notes found" -ForegroundColor Yellow
        exit 0
    }

    $notes = @()
    foreach ($file in $files) {
        $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        $title = Get-FrontmatterValue -Content $content -Key "title"
        $noteStatus = Get-FrontmatterValue -Content $content -Key "status"
        $confidence = Get-FrontmatterValue -Content $content -Key "confidence"
        $lastUpdated = Get-FrontmatterValue -Content $content -Key "last_updated"
        $reviewTrigger = Get-FrontmatterValue -Content $content -Key "review_trigger"

        if ($Status -and $noteStatus -ne $Status) {
            continue
        }

        $today = (Get-Date).Date
        $reviewDisplay = "unknown"
        $color = "White"
        $daysUntilReview = 0
        $reviewDate = [datetime]::MinValue
        if (![string]::IsNullOrWhiteSpace($reviewTrigger) -and [datetime]::TryParseExact($reviewTrigger, "yyyy-MM-dd", $null, [System.Globalization.DateTimeStyles]::None, [ref]$reviewDate)) {
            $daysUntilReview = ($reviewDate - $today).Days
            if ($daysUntilReview -lt 0) {
                $reviewDisplay = "OVERDUE $([Math]::Abs($daysUntilReview)) days"
                $color = "Red"
            }
            else {
                $reviewDisplay = "$daysUntilReview days"
            }
        }

        $confidenceRank = 0
        switch ($confidence.ToLower()) {
            "high" { $confidenceRank = 3 }
            "medium" { $confidenceRank = 2 }
            "low" { $confidenceRank = 1 }
            default { $confidenceRank = 0 }
        }

        $sortDate = [datetime]::MinValue
        if (![datetime]::TryParse($lastUpdated, [ref]$sortDate)) {
            $sortDate = [datetime]::MinValue
        }

        $notes += [PSCustomObject]@{
            Title = if ($title) { $title } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
            Status = $noteStatus
            Confidence = $confidence
            LastUpdated = $lastUpdated
            ReviewDisplay = $reviewDisplay
            Color = $color
            SortDate = $sortDate
            ConfidenceRank = $confidenceRank
        }
    }

    if ($notes.Count -eq 0) {
        Write-Host "No working notes found" -ForegroundColor Yellow
        exit 0
    }

    switch ($SortBy) {
        "last_updated" { $notes = @($notes | Sort-Object -Property @{ Expression = 'SortDate'; Descending = $true }, @{ Expression = 'Title'; Descending = $false }) }
        "confidence" { $notes = @($notes | Sort-Object -Property @{ Expression = 'ConfidenceRank'; Descending = $true }, @{ Expression = 'Title'; Descending = $false }) }
        default { $notes = @($notes | Sort-Object Title) }
    }

    foreach ($note in $notes) {
        Write-Host ("{0} | {1} | {2} | {3} | {4}" -f $note.Title, $note.Status, $note.Confidence, $note.LastUpdated, $note.ReviewDisplay) -ForegroundColor $note.Color
    }
}
catch {
    Write-Log "List working notes failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ List working notes failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
