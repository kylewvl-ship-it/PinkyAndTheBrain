# Pester tests for cross-layer knowledge search

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:SearchScript = Join-Path $script:Root "scripts/search.ps1"

function Initialize-SearchWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    $script:TasksRoot = Join-Path $script:WorkRoot ".ai/handoffs"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }
    New-Item -ItemType Directory -Path $script:TasksRoot -Force | Out-Null

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
    $env:PINKY_SEARCH_MAX_RESULTS = "20"
}

function Invoke-SearchScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:SearchScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-SearchDocument {
    param(
        [string]$RelativePath,
        [string]$Title,
        [string]$Body,
        [hashtable]$Metadata = @{}
    )

    $path = Join-Path $script:WorkRoot $RelativePath
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $frontmatterLines = @(
        '---'
        ('title: "{0}"' -f $Title)
    )

    foreach ($key in $Metadata.Keys) {
        $value = [string]$Metadata[$key]
        $frontmatterLines += ('{0}: "{1}"' -f $key, $value)
    }

    $frontmatterLines += '---'
    $frontmatterLines += ''
    $frontmatterLines += ($Body -split "`n")

    Set-Content -Path $path -Value ($frontmatterLines -join "`r`n") -Encoding UTF8
    return $path
}

Describe "search.ps1 - Story 3.1" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_SEARCH_MAX_RESULTS = $null
    }

    It "returns wiki working raw and task results by default while excluding archive" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/wiki-hit.md" -Title "shared topic wiki" -Body "shared topic first line`nsecond line" -Metadata @{ confidence = "high" } | Out-Null
        New-SearchDocument -RelativePath "knowledge/working/work-hit.md" -Title "working note" -Body "shared topic appears here`nsecond line" -Metadata @{ status = "active" } | Out-Null
        New-SearchDocument -RelativePath "knowledge/raw/raw-hit.md" -Title "raw note" -Body "shared topic captured`nsecond line" | Out-Null
        New-SearchDocument -RelativePath ".ai/handoffs/task-hit.md" -Title "task handoff" -Body "shared topic for task`nsecond line" | Out-Null
        New-SearchDocument -RelativePath "knowledge/archive/archive-hit.md" -Title "archive note" -Body "shared topic in archive`nsecond line" -Metadata @{ archived_date = "2026-04-23"; archive_reason = "stale" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "shared topic")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\[WIKI\]"
        $result.Output | Should Match "\[WORK\]"
        $result.Output | Should Match "\[RAW\]"
        $result.Output | Should Match "\[TASK\]"
        $result.Output | Should Not Match "\[ARCH\]"
    }

    It "returns archive results with archive metadata when Archive is requested" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/archive/archive-hit.md" -Title "shared archive" -Body "archive only term`nsecond line" -Metadata @{ archived_date = "2026-04-23"; archive_reason = "duplicate" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "archive only term", "-Archive")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\[ARCH\]"
        $result.Output | Should Match "Archived: 2026-04-23"
        $result.Output | Should Match "Reason: duplicate"
    }

    It "does not include archive results when only IncludeArchived is passed" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/archive/archive-hit.md" -Title "archive only" -Body "deprecated archive term`nsecond line" -Metadata @{ archived_date = "2026-04-23"; archive_reason = "duplicate" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "deprecated archive term", "-IncludeArchived")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Use -Archive to include archived content"
        $result.Output | Should Not Match "\[ARCH\]"
    }

    It "filters to wiki only when Wiki switch is used" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/wiki-only.md" -Title "query title" -Body "layer limited query" | Out-Null
        New-SearchDocument -RelativePath "knowledge/working/work-only.md" -Title "query title" -Body "layer limited query" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "layer limited query", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\[WIKI\]"
        $result.Output | Should Not Match "\[WORK\]"
    }

    It "ranks title matches ahead of content and metadata matches" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/title-match.md" -Title "ranking-query" -Body "first line`nsecond line" | Out-Null
        New-SearchDocument -RelativePath "knowledge/wiki/content-match.md" -Title "content title" -Body "ranking-query appears in content`nsecond line" | Out-Null
        New-SearchDocument -RelativePath "knowledge/wiki/partial-title.md" -Title "alpha ranking-query beta" -Body "first line`nsecond line" | Out-Null
        New-SearchDocument -RelativePath "knowledge/wiki/metadata-match.md" -Title "metadata title" -Body "first line`nsecond line" -Metadata @{ owner = "ranking-query" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "ranking-query", "-Wiki")

        $result.ExitCode | Should Be 0
        $titleIndex = $result.Output.IndexOf("title-match.md")
        $contentIndex = $result.Output.IndexOf("content-match.md")
        $partialTitleIndex = $result.Output.IndexOf("partial-title.md")
        $metadataIndex = $result.Output.IndexOf("metadata-match.md")
        ($titleIndex -ge 0) | Should Be $true
        ($contentIndex -gt $titleIndex) | Should Be $true
        ($partialTitleIndex -gt $contentIndex) | Should Be $true
        ($metadataIndex -gt $partialTitleIndex) | Should Be $true
    }

    It "caps results at the configured maximum" {
        Initialize-SearchWorkspace
        foreach ($i in 1..25) {
            New-SearchDocument -RelativePath ("knowledge/wiki/result-{0}.md" -f $i) -Title ("cap test {0}" -f $i) -Body "cap-query value`nsecond line" | Out-Null
        }

        $result = Invoke-SearchScript -Arguments @("-Query", "cap-query", "-Wiki")

        $result.ExitCode | Should Be 0
        ([regex]::Matches($result.Output, '(?m)^\d+\.\s+\[WIKI\]').Count) | Should Be 20
    }

    It "shows confidence for wiki results and archive reason for archive results" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/confident.md" -Title "metadata shared" -Body "metadata shared`nsecond line" -Metadata @{ confidence = "high" } | Out-Null
        New-SearchDocument -RelativePath "knowledge/archive/old.md" -Title "metadata shared archive" -Body "metadata shared archive`nsecond line" -Metadata @{ archived_date = "2026-04-23"; archive_reason = "stale" } | Out-Null

        $wikiResult = Invoke-SearchScript -Arguments @("-Query", "metadata shared", "-Wiki")
        $archiveResult = Invoke-SearchScript -Arguments @("-Query", "metadata shared archive", "-Archive")

        $wikiResult.ExitCode | Should Be 0
        $archiveResult.ExitCode | Should Be 0
        $wikiResult.Output | Should Match "Confidence: high"
        $archiveResult.Output | Should Match "Reason: stale"
    }

    It "marks broken links inline during open without modifying the source file" {
        Initialize-SearchWorkspace
        $path = New-SearchDocument -RelativePath "knowledge/wiki/broken-links.md" -Title "broken-query" -Body @"
broken-query first line
See [[missing-topic]] and [missing](knowledge/wiki/not-found.md)
"@

        $result = Invoke-SearchScript -Arguments @("-Query", "broken-query", "-Wiki", "-Open", "1")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\[BROKEN LINK: missing-topic\]"
        $result.Output | Should Match "\[BROKEN LINK: knowledge/wiki/not-found\.md\]"
        (Get-Content -Path $path -Raw) | Should Match "\[\[missing-topic\]\]"
    }

    It "filters Project by scalar value" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/work-budget.md" -Title "budget work" -Body "budget item" -Metadata @{ project = "work" } | Out-Null
        New-SearchDocument -RelativePath "knowledge/wiki/other-budget.md" -Title "budget other" -Body "budget item" -Metadata @{ project = "other" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "budget", "-Project", "work", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "work-budget.md"
        $result.Output | Should Not Match "other-budget.md"
    }

    It "filters Project by array value" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/array-budget.md" -Title "budget array" -Body "budget item" -Metadata @{ project = '["work","research"]' } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "budget", "-Project", "work", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "array-budget.md"
    }

    It "excludes untagged files from Project scoped results" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/no-project-budget.md" -Title "budget none" -Body "budget item" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "budget", "-Project", "work", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Not Match "no-project-budget.md"
    }

    It "includes shared files in Project scoped results" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/shared-budget.md" -Title "budget shared" -Body "budget item" -Metadata @{ shared = "true" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "budget", "-Project", "work", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "shared-budget.md"
    }

    It "filters Domain by scalar and array values" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/accounting.md" -Title "depreciation accounting" -Body "depreciation item" -Metadata @{ domain = "accounting" } | Out-Null
        New-SearchDocument -RelativePath "knowledge/wiki/tax.md" -Title "depreciation tax" -Body "depreciation item" -Metadata @{ domain = '["accounting","tax"]' } | Out-Null
        New-SearchDocument -RelativePath "knowledge/wiki/legal.md" -Title "depreciation legal" -Body "depreciation item" -Metadata @{ domain = "legal" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "depreciation", "-Domain", "accounting", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "accounting.md"
        $result.Output | Should Match "tax.md"
        $result.Output | Should Not Match "legal.md"
    }

    It "includes shared files in Domain scoped results" {
        Initialize-SearchWorkspace
        New-SearchDocument -RelativePath "knowledge/wiki/shared-domain.md" -Title "depreciation shared" -Body "depreciation item" -Metadata @{ domain = "legal"; shared = "true" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "depreciation", "-Domain", "accounting", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "shared-domain.md"
    }
}
