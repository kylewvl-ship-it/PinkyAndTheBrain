param(
    [Parameter(Mandatory=$true)]
    [string]$Title,

    [string]$Content = "",
    [ValidateSet("manual", "web", "conversation", "document", "idea", "meeting", "book", "video")]
    [string]$Type = "manual",
    [string]$SourceUrl = "",
    [string]$SourceTitle = "",
    [string]$Project = "",
    [switch]$Private
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$InboxDir = Join-Path $Root "knowledge/inbox"
$LogDir = Join-Path $Root "logs"

function Convert-ToSlug {
    param([string]$Value)
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "capture" }
    return $slug
}

function Escape-YamlValue {
    param([string]$Value)
    return ($Value -replace '"', '\"')
}

try {
    New-Item -ItemType Directory -Path $InboxDir -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($Content)) {
        $piped = @($input)
        if ($piped.Count -gt 0) {
            $Content = ($piped -join [Environment]::NewLine)
        }
    }
    if ([string]::IsNullOrWhiteSpace($Content)) {
        $Content = "Add captured content here."
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    $datePart = Get-Date -Format "yyyyMMdd-HHmmss"
    $slug = Convert-ToSlug $Title
    $path = Join-Path $InboxDir "$datePart-$slug.md"
    $privateValue = if ($Private) { "true" } else { "false" }

    $body = @"
---
title: "$(Escape-YamlValue $Title)"
captured_date: "$timestamp"
source_type: "$Type"
source_url: "$(Escape-YamlValue $SourceUrl)"
source_title: "$(Escape-YamlValue $SourceTitle)"
review_status: "pending"
disposition: "inbox"
project: "$(Escape-YamlValue $Project)"
private: $privateValue
do_not_promote: false
---

# $Title

$Content

## Source Context

- Source type: $Type
- Source title: $SourceTitle
- Source URL: $SourceUrl

## Next Actions

- [ ] Review and assign disposition.
"@

    Set-Content -Path $path -Value $body -Encoding UTF8
    Add-Content -Path (Join-Path $LogDir "capture.log") -Value "[$timestamp] captured $path"
    Write-Host "Captured: $path" -ForegroundColor Green
}
catch {
    Write-Error "Capture failed: $($_.Exception.Message)"
    exit 1
}

