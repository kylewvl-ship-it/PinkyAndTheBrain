$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:ResolveScript = Join-Path $script:Root "scripts/resolve-findings.ps1"
$script:HealthScript = Join-Path $script:Root "scripts/health-check.ps1"

function Initialize-ResolveWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas", "reviews")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function Invoke-ResolveScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ResolveScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-HealthScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:HealthScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-ResolveFile {
    param(
        [string]$RelativePath,
        [string]$Frontmatter = "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a",
        [string]$Body = "This body has enough content to satisfy the configured minimum content length for health checks and resolution tests.",
        [datetime]$LastWriteTime = (Get-Date),
        [switch]$NoFrontmatter
    )

    $path = Join-Path $script:VaultRoot $RelativePath
    $directory = Split-Path $path -Parent
    if (!(Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if ($NoFrontmatter) {
        Set-Content -Path $path -Value $Body -Encoding UTF8
    }
    else {
        Set-Content -Path $path -Value @"
---
$Frontmatter
---
$Body
"@ -Encoding UTF8
    }

    (Get-Item -LiteralPath $path).LastWriteTime = $LastWriteTime
    return $path
}

function New-ResolveReport {
    param([object[]]$Findings)

    $path = Join-Path $script:VaultRoot ("reviews/health-report-{0}.md" -f (Get-Date -Format "yyyy-MM-dd"))
    $lines = @(
        "---",
        "generated: $(Get-Date -Format "yyyy-MM-dd")",
        "check_type: all",
        "total_findings: $(@($Findings).Count)",
        "---",
        "",
        "# Health Check Report - $(Get-Date -Format "yyyy-MM-dd")"
    )

    foreach ($group in @($Findings | Group-Object Type)) {
        $lines += ""
        $lines += "## $($group.Name)"
        foreach ($finding in $group.Group) {
            $lines += ""
            $lines += "- **$($finding.Severity)** $($finding.File)"
            $lines += "  - Rule: $($finding.Rule)"
            $lines += "  - Issue: $($finding.Issue)"
            $lines += "  - Suggested repair: $($finding.Suggestion)"
        }
    }

    Set-Content -Path $path -Value $lines -Encoding UTF8
    return $path
}

function New-Finding {
    param(
        [string]$FindingType,
        [string]$Severity,
        [string]$File,
        [string]$Rule,
        [string]$Issue,
        [string]$Suggestion = "Review and repair this finding."
    )

    return [PSCustomObject]@{
        Type = $FindingType
        Severity = $Severity
        File = $File
        Rule = $Rule
        Issue = $Issue
        Suggestion = $Suggestion
    }
}

Describe "resolve-findings.ps1 - Story 6.2" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "fixes a broken wiki link using an explicit noninteractive link target" {
        Initialize-ResolveWorkspace
        New-ResolveFile -RelativePath "wiki/target-page.md" | Out-Null
        $source = New-ResolveFile -RelativePath "wiki/source.md" -Body "This note links to [[missing-page]] and contains enough supporting words for health checks."
        $report = New-ResolveReport -Findings @(
            New-Finding -FindingType "Broken Links" -Severity "High" -File "wiki/source.md" -Rule "broken-wiki-link" -Issue "Broken link: missing-page"
        )

        $result = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "fix-link", "-LinkTarget", "target-page", "-Force")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Candidates:"
        $result.Output | Should Match "target-page"
        (Get-Content $source -Raw) | Should Match "\[\[target-page\]\]"
        (Get-Content $source -Raw) | Should Not Match "\[\[missing-page\]\]"
    }

    It "does not auto-select a link candidate when -Force is used without -LinkTarget" {
        Initialize-ResolveWorkspace
        New-ResolveFile -RelativePath "wiki/target-page.md" | Out-Null
        $source = New-ResolveFile -RelativePath "wiki/source.md" -Body "This note links to [[missing-page]] and contains enough supporting words for health checks."
        $report = New-ResolveReport -Findings @(
            New-Finding -FindingType "Broken Links" -Severity "High" -File "wiki/source.md" -Rule "link-target-exists" -Issue "Broken link: missing-page"
        )

        $result = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "fix-link", "-Force")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "no candidate selected"
        (Get-Content $source -Raw) | Should Match "\[\[missing-page\]\]"
    }

    It "rejects report file paths that resolve outside the vault root" {
        Initialize-ResolveWorkspace
        $outside = Join-Path $script:WorkRoot "outside.md"
        Set-Content -Path $outside -Value @"
---
status: active
---
outside content
"@ -Encoding UTF8
        $report = New-ResolveReport -Findings @(
            New-Finding -FindingType "Missing Metadata" -Severity "High" -File "../outside.md" -Rule "require-confidence" -Issue "Missing required field: confidence"
        )

        $result = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "update-metadata", "-Field", "confidence", "-Value", "medium", "-Force")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "WARNING: skipping finding outside vault root"
        (Get-Content $outside -Raw) | Should Not Match "confidence:"
    }

    It "updates missing confidence metadata and prints the before and after frontmatter" {
        Initialize-ResolveWorkspace
        $file = New-ResolveFile -RelativePath "wiki/no-confidence.md" -Frontmatter "status: active`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a"
        $report = New-ResolveReport -Findings @(
            New-Finding -FindingType "Missing Metadata" -Severity "High" -File "wiki/no-confidence.md" -Rule "require-confidence" -Issue "Missing required field: confidence"
        )

        $result = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "update-metadata", "-Field", "confidence", "-Value", "medium", "-Force")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Before:"
        $result.Output | Should Match "After:"
        (Get-Content $file -Raw) | Should Match 'confidence: "?medium"?'
    }

    It "archives a finding by delegating to archive-content.ps1" {
        Initialize-ResolveWorkspace
        $file = New-ResolveFile -RelativePath "wiki/archive-me.md"
        $report = New-ResolveReport -Findings @(
            New-Finding -FindingType "Stale Content" -Severity "High" -File "wiki/archive-me.md" -Rule "stale-threshold" -Issue "File has not been updated in over 12 months"
        )

        $result = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "archive", "-Force")
        $archived = Get-ChildItem -Path (Join-Path $script:VaultRoot "archive") -Filter "archive-me.md" -File -Recurse | Select-Object -First 1

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Archived file:"
        Test-Path $file | Should Be $false
        $archived | Should Not Be $null
        (Get-Content $archived.FullName -Raw) | Should Match 'archive_reason: "?health-check-resolution"?'
    }

    It "defers a finding for 30 days and suppresses it from the next health check run" {
        Initialize-ResolveWorkspace
        New-ResolveFile -RelativePath "working/defer-me.md" -Body "plain text" -NoFrontmatter | Out-Null
        $report = New-ResolveReport -Findings @(
            New-Finding -FindingType "Missing Metadata" -Severity "High" -File "working/defer-me.md" -Rule "require-frontmatter" -Issue "No frontmatter found"
        )

        $resolve = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "defer", "-DeferNote", "waiting on review", "-Force")
        $records = @(Get-Content (Join-Path $script:WorkRoot ".ai/health-deferred.json") -Raw | ConvertFrom-Json)
        $until = [datetime]::Parse([string]$records[0].deferred_until)
        $days = ($until.ToUniversalTime() - (Get-Date).ToUniversalTime()).TotalDays
        $health = Invoke-HealthScript -Arguments @("-Type", "metadata")

        $resolve.ExitCode | Should Be 0
        $records[0].file | Should Be "working/defer-me.md"
        $records[0].rule | Should Be "require-frontmatter"
        $records[0].note | Should Be "waiting on review"
        $days | Should BeGreaterThan 29
        $days | Should BeLessThan 31
        $health.ExitCode | Should Be 0
        $health.Output | Should Match "Deferred Issues"
        $health.Output | Should Match "working/defer-me.md"
        $health.Output | Should Not Match "No frontmatter found"
    }

    It "allows expired deferred findings to reappear in health check output" {
        Initialize-ResolveWorkspace
        New-ResolveFile -RelativePath "working/expired.md" -Body "plain text" -NoFrontmatter | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:WorkRoot ".ai") -Force | Out-Null
        $record = @([PSCustomObject]@{
            file = "working/expired.md"
            rule = "require-frontmatter"
            action = "defer"
            deferred_at = (Get-Date).AddDays(-40).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            deferred_until = (Get-Date).AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            note = "expired"
        })
        Set-Content -Path (Join-Path $script:WorkRoot ".ai/health-deferred.json") -Value ($record | ConvertTo-Json -Depth 8) -Encoding UTF8

        $result = Invoke-HealthScript -Arguments @("-Type", "metadata")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "working/expired.md"
        $result.Output | Should Match "No frontmatter found"
    }

    It "batch-updates all findings missing the same metadata field" {
        Initialize-ResolveWorkspace
        $first = New-ResolveFile -RelativePath "wiki/batch-a.md" -Frontmatter "status: active`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a"
        $second = New-ResolveFile -RelativePath "working/batch-b.md" -Frontmatter "status: active`nlast_updated: 2026-04-01`nsources: source-a"
        $other = New-ResolveFile -RelativePath "wiki/batch-other.md" -Frontmatter "confidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a"
        $report = New-ResolveReport -Findings @(
            (New-Finding -FindingType "Missing Metadata" -Severity "High" -File "wiki/batch-a.md" -Rule "require-confidence" -Issue "Missing required field: confidence"),
            (New-Finding -FindingType "Missing Metadata" -Severity "High" -File "working/batch-b.md" -Rule "require-confidence" -Issue "Missing required field: confidence"),
            (New-Finding -FindingType "Missing Metadata" -Severity "High" -File "wiki/batch-other.md" -Rule "require-status" -Issue "Missing required field: status")
        )

        $result = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-Batch", "-Action", "update-metadata", "-Field", "confidence", "-Value", "medium", "-Force")

        $result.ExitCode | Should Be 0
        (Get-Content $first -Raw) | Should Match 'confidence: "?medium"?'
        (Get-Content $second -Raw) | Should Match 'confidence: "?medium"?'
        (Get-Content $other -Raw) | Should Not Match "status: active"
    }

    It "bulk-archives high-severity stale files and leaves medium-severity stale files untouched" {
        Initialize-ResolveWorkspace
        $high = New-ResolveFile -RelativePath "wiki/stale-high.md"
        $medium = New-ResolveFile -RelativePath "wiki/stale-medium.md"
        $report = New-ResolveReport -Findings @(
            (New-Finding -FindingType "Stale Content" -Severity "High" -File "wiki/stale-high.md" -Rule "stale-threshold" -Issue "File has not been updated in over 12 months"),
            (New-Finding -FindingType "Stale Content" -Severity "Medium" -File "wiki/stale-medium.md" -Rule "stale-threshold" -Issue "File has not been updated in over 6 months")
        )

        $result = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-BulkArchiveStale", "-Force")
        $archivedHigh = Get-ChildItem -Path (Join-Path $script:VaultRoot "archive") -Filter "stale-high.md" -File -Recurse | Select-Object -First 1

        $result.ExitCode | Should Be 0
        Test-Path $high | Should Be $false
        $archivedHigh | Should Not Be $null
        Test-Path $medium | Should Be $true
    }

    It "requires confirmation unless -Force is supplied in noninteractive mode" {
        Initialize-ResolveWorkspace
        $file = New-ResolveFile -RelativePath "wiki/confirm.md" -Frontmatter "status: active`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a"
        $report = New-ResolveReport -Findings @(
            New-Finding -FindingType "Missing Metadata" -Severity "High" -File "wiki/confirm.md" -Rule "require-confidence" -Issue "Missing required field: confidence"
        )

        $aborted = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "update-metadata", "-Field", "confidence", "-Value", "medium")
        $forced = Invoke-ResolveScript -Arguments @("-ReportFile", $report, "-FindingIndex", "1", "-Action", "update-metadata", "-Field", "confidence", "-Value", "medium", "-Force")

        $aborted.ExitCode | Should Be 0
        $aborted.Output | Should Match "Resolution aborted"
        $forced.ExitCode | Should Be 0
        (Get-Content $file -Raw) | Should Match 'confidence: "?medium"?'
    }

    It "prints deferred findings in the console and report file Deferred Issues section" {
        Initialize-ResolveWorkspace
        New-ResolveFile -RelativePath "working/deferred-section.md" -Body "plain text" -NoFrontmatter | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:WorkRoot ".ai") -Force | Out-Null
        $record = @([PSCustomObject]@{
            file = "working/deferred-section.md"
            rule = "require-frontmatter"
            action = "defer"
            deferred_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            deferred_until = (Get-Date).AddDays(30).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            note = "source pending"
        })
        Set-Content -Path (Join-Path $script:WorkRoot ".ai/health-deferred.json") -Value ($record | ConvertTo-Json -Depth 8) -Encoding UTF8

        $result = Invoke-HealthScript -Arguments @("-Type", "metadata")
        $reportPath = Join-Path $script:VaultRoot ("reviews/health-report-{0}.md" -f (Get-Date -Format "yyyy-MM-dd"))
        $report = Get-Content $reportPath -Raw

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Deferred Issues"
        $result.Output | Should Match "working/deferred-section.md"
        $result.Output | Should Match "source pending"
        $report | Should Match "## Deferred Issues"
        $report | Should Match "working/deferred-section.md"
        $report | Should Match "source pending"
    }
}
