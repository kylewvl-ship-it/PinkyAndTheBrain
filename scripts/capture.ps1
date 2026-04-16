param(
    [Parameter(Mandatory=$true)]
    [string]$Title,

    [string]$Content = "",
    [ValidateSet("manual", "web", "conversation", "document", "idea", "meeting", "book", "video")]
    [string]$Type = "manual",
    [string]$SourceUrl = "",
    [string]$SourceTitle = "",
    [string]$Project = "",
    [switch]$Private,
    [string]$Service = "",
    [string]$File = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$InboxDir = Join-Path $Root "knowledge/inbox"
$RawDir = Join-Path $Root "knowledge/raw"
$TargetDir = if ($Type -eq "conversation") { $RawDir } else { $InboxDir }
$LogDir = Join-Path $Root "logs"

function Convert-ToSlug {
    param([string]$Value)
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return "capture" }
    return $slug
}

function Test-TemplateValid {
    param(
        [hashtable]$Fields,
        [string[]]$RequiredKeys
    )
    $missing = @()
    foreach ($key in $RequiredKeys) {
        if (-not $Fields.ContainsKey($key) -or $null -eq $Fields[$key]) {
            $missing += $key
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "Template validation failed. Missing required fields: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "Example frontmatter:" -ForegroundColor Yellow
        Write-Host "---"
        foreach ($key in $RequiredKeys) { Write-Host "${key}: <value>" }
        Write-Host "---"
        return $false
    }
    return $true
}

function Escape-YamlValue {
    param([string]$Value)
    return ($Value -replace '"', '\"')
}

try {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    if ([string]::IsNullOrWhiteSpace($Content)) {
        if (-not [string]::IsNullOrWhiteSpace($File) -and (Test-Path $File)) {
            $Content = Get-Content -Path $File -Raw
        } else {
            $piped = @($input)
            if ($piped.Count -gt 0) {
                $Content = ($piped -join [Environment]::NewLine)
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($Content)) {
        $Content = "Add captured content here."
    }

    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
    $datePart = Get-Date -Format "yyyyMMdd-HHmmss"
    $slug = Convert-ToSlug $Title
    $path = Join-Path $TargetDir "$datePart-$slug.md"
    $privateValue = if ($Private) { "true" } else { "false" }

    if ($Type -eq "conversation") {
        $body = @"
---
title: "$(Escape-YamlValue $Title)"
captured_date: "$timestamp"
source_type: "conversation"
ai_service: "$(Escape-YamlValue $Service)"
ai_derived: true
promotion_blocked: true
private: $privateValue
---

# $Title

$Content
"@
    } else {
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
    }

    Set-Content -Path $path -Value $body -Encoding UTF8
    Add-Content -Path (Join-Path $LogDir "capture.log") -Value "[$timestamp] captured $path"
    Write-Host "Captured: $path" -ForegroundColor Green
}
catch {
    Write-Error "Capture failed: $($_.Exception.Message)"
    exit 1
}

