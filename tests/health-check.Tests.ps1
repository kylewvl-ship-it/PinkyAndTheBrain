$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:HealthScript = Join-Path $script:Root "scripts/health-check.ps1"

function Initialize-HealthWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
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

function New-HealthFile {
    param(
        [string]$RelativePath,
        [string]$Frontmatter = "",
        [string]$Body = "This body has enough content to satisfy the configured minimum content length for health checks.",
        [datetime]$LastWriteTime = (Get-Date)
    )

    $path = Join-Path $script:VaultRoot $RelativePath
    $directory = Split-Path $path -Parent
    if (!(Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if ([string]::IsNullOrEmpty($Frontmatter)) {
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

Describe "health-check.ps1 - Story 6.1" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "reports missing frontmatter, missing wiki confidence, and body shorter than configured minimum" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "working/no-frontmatter.md" -Body "plain text" | Out-Null
        New-HealthFile -RelativePath "wiki/no-confidence.md" -Frontmatter "status: active`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" | Out-Null
        New-HealthFile -RelativePath "working/short.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nsources: source-a" -Body "short" | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "metadata")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "No frontmatter found"
        $result.Output | Should Match "Missing required field: confidence"
        $result.Output | Should Match "Content too short \(< 100 characters\)"
    }

    It "reports wiki source provenance gaps" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "wiki/no-sources.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01" | Out-Null

        $result = Invoke-HealthScript

        $result.Output | Should Match "Extraction Confidence Gaps"
        $result.Output | Should Match "require-wiki-sources"
    }

    It "reports broken wiki and markdown links but ignores external links" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "wiki/links.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "See [[missing-page]], [missing](missing.md), and [external](https://example.com)." | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "links")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "Broken link: missing-page"
        $result.Output | Should Match "Broken link: missing.md"
        $result.Output | Should Not Match "https://example.com"
    }

    It "reports orphan files but not files with incoming links" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "wiki/referenced.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" | Out-Null
        New-HealthFile -RelativePath "inbox/linker.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "This note links to [[referenced]] with enough words to avoid short content." | Out-Null
        New-HealthFile -RelativePath "wiki/orphan.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "orphans")

        $result.Output | Should Match "wiki/orphan.md"
        $result.Output | Should Not Match "wiki/referenced.md"
    }

    It "does not count self-links as orphan incoming links" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "wiki/self-linked.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "This note links to [[self-linked]] but no other knowledge file links here." | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "orphans")

        $result.Output | Should Match "wiki/self-linked.md"
    }

    It "reports stale content and overdue review triggers" {
        Initialize-HealthWorkspace
        $oldDate = (Get-Date).AddMonths(-7).ToString("yyyy-MM-dd")
        $pastReview = (Get-Date).AddDays(-2).ToString("yyyy-MM-dd")
        New-HealthFile -RelativePath "working/old.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: $oldDate`nsources: source-a" | Out-Null
        New-HealthFile -RelativePath "wiki/review.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nreview_trigger: $pastReview`nsources: source-a" | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "stale")

        $result.Output | Should Match "stale-threshold"
        $result.Output | Should Match "review-trigger-overdue"
    }

    It "reports title-similarity duplicates using configured edit distance" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "wiki/alpha.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "alpha unique content that is deliberately long enough and not duplicated" | Out-Null
        New-HealthFile -RelativePath "wiki/alphi.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "alphi unique content that is deliberately long enough and not duplicated" | Out-Null
        New-HealthFile -RelativePath "wiki/bravo.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "bravo unique content that is deliberately long enough and not duplicated" | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "duplicates")

        $result.Output | Should Match "Duplicates"
        $result.Output | Should Match "Subtype: title-similarity"
        $result.Output | Should Match "alpha"
        $result.Output | Should Match "alphi"
        $result.Output | Should Not Match "bravo.md"
    }

    It "uses frontmatter title for duplicate edit-distance comparison before filename stem" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "wiki/2026-01-01-alpha-concept.md" -Frontmatter "title: Alpha Concept`nstatus: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "alpha concept unique body long enough to avoid fingerprint duplicate behavior" | Out-Null
        New-HealthFile -RelativePath "wiki/unrelated-file-name.md" -Frontmatter "title: Alpha Conxept`nstatus: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body "alpha conxept different body long enough to avoid fingerprint duplicate behavior" | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "duplicates")

        $result.Output | Should Match "title-edit-distance"
        $result.Output | Should Match "alpha concept"
        $result.Output | Should Match "alpha conxept"
    }

    It "reports duplicate fingerprint candidates" {
        Initialize-HealthWorkspace
        $body = "Shared duplicate body with enough content to avoid empty hash handling and trigger identical fingerprint detection."
        New-HealthFile -RelativePath "wiki/copy-a.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -Body $body | Out-Null
        New-HealthFile -RelativePath "working/copy-b.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nsources: source-a" -Body $body | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "duplicates")

        $result.Output | Should Match "Duplicates"
        $result.Output | Should Match "Subtype: fingerprint-candidate"
        $result.Output | Should Match "body-sha256-match"
    }

    It "reports derived index drift" {
        Initialize-HealthWorkspace
        $old = (Get-Date).AddDays(-2)
        $new = (Get-Date)
        New-HealthFile -RelativePath "wiki/index.md" -Frontmatter "last_updated: $($old.ToString("yyyy-MM-dd"))" -Body "Index body with sufficient length for the file." -LastWriteTime $old | Out-Null
        New-HealthFile -RelativePath "wiki/newer.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2026-04-01`nlast_verified: 2026-04-01`nsources: source-a" -LastWriteTime $new | Out-Null

        $result = Invoke-HealthScript

        $result.Output | Should Match "Derived Index Drift"
        $result.Output | Should Match "index-drift"
    }

    It "writes a dated report file after every run" {
        Initialize-HealthWorkspace

        $result = Invoke-HealthScript -Arguments @("-Type", "metadata")
        $reportPath = Join-Path $script:VaultRoot ("reviews/health-report-{0}.md" -f (Get-Date -Format "yyyy-MM-dd"))

        $result.ExitCode | Should Be 0
        Test-Path $reportPath | Should Be $true
        (Get-Content $reportPath -Raw) | Should Match "total_findings: 0"
    }

    It "excludes archive files from all checks by default" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "archive/bad.md" -Body "[[missing]]" | Out-Null

        $result = Invoke-HealthScript

        $result.ExitCode | Should Be 0
        $result.Output | Should Not Match "archive/bad.md"
    }

    It "runs only metadata checks when -Type metadata is selected" {
        Initialize-HealthWorkspace
        New-HealthFile -RelativePath "wiki/mixed.md" -Frontmatter "status: active`nconfidence: medium`nlast_updated: 2020-01-01`nlast_verified: 2020-01-01`nsources: source-a" -Body "Contains [[missing-link]] and old dates but metadata has required fields and enough content for this focused check." | Out-Null

        $result = Invoke-HealthScript -Arguments @("-Type", "metadata")

        $result.Output | Should Not Match "Broken Links"
        $result.Output | Should Not Match "Stale Content"
    }
}
