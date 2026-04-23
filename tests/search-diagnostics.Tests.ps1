# Pester tests for search diagnostics

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:SearchScript = Join-Path $script:Root "scripts/search.ps1"

function Initialize-DiagnosticsWorkspace {
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

function New-DiagnosticsDocument {
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
        $frontmatterLines += ('{0}: "{1}"' -f $key, [string]$Metadata[$key])
    }

    $frontmatterLines += '---'
    $frontmatterLines += ''
    $frontmatterLines += ($Body -split "`n")

    Set-Content -Path $path -Value ($frontmatterLines -join "`r`n") -Encoding UTF8
    return $path
}

function Invoke-LevenshteinFunction {
    param(
        [string]$A,
        [string]$B
    )

    $content = Get-Content -Path $script:SearchScript -Raw
    $match = [regex]::Match($content, '(?s)function Get-LevenshteinDistance \{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $match.Success) {
        throw "Get-LevenshteinDistance function not found."
    }

    $command = @"
$($match.Value)
`$result = Get-LevenshteinDistance -A '$A' -B '$B'
Write-Output `$result
"@

    return (& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $command | Out-String).Trim()
}

Describe "search diagnostics - Story 3.2" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_SEARCH_MAX_RESULTS = $null
    }

    It "shows the diagnostic section when Diagnose is used" {
        Initialize-DiagnosticsWorkspace
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/topic.md" -Title "other" -Body "body" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "missing", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "--- Search Diagnostics for ""missing"" ---"
    }

    It "reports file counts per layer" {
        Initialize-DiagnosticsWorkspace
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/wiki-a.md" -Title "a" -Body "body" | Out-Null
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/wiki-b.md" -Title "b" -Body "body" | Out-Null
        New-DiagnosticsDocument -RelativePath "knowledge/working/work-a.md" -Title "c" -Body "body" | Out-Null
        New-DiagnosticsDocument -RelativePath ".ai/handoffs/task-a.md" -Title "d" -Body "body" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "missing", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\[WIKI\]\s+2 files"
        $result.Output | Should Match "\[WORK\]\s+1 files"
        $result.Output | Should Match "\[TASK\]\s+1 files"
        $result.Output | Should Match "\[ARCH\]\s+0 files"
    }

    It "finds case-insensitive partial filename matches that normal search misses" {
        Initialize-DiagnosticsWorkspace
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/2026-04-23-120000-Missing-Topic.md" -Title "totally unrelated" -Body "body" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "missing", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "No results found for 'missing'\."
        $result.Output | Should Match "knowledge/wiki/2026-04-23-120000-Missing-Topic.md"
    }

    It "reports case-insensitive content matches when the normal result set is too small" {
        Initialize-DiagnosticsWorkspace
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/body-only.md" -Title "other" -Body "Needle appears only in body content" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "needle", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Case-Insensitive Content Matches:"
        $result.Output | Should Match "knowledge/wiki/body-only.md"
    }

    It "computes known Levenshtein distances" {
        (Invoke-LevenshteinFunction -A "cat" -B "cat") | Should Be "0"
        (Invoke-LevenshteinFunction -A "cat" -B "bat") | Should Be "1"
        (Invoke-LevenshteinFunction -A "kitten" -B "sitting") | Should Be "3"
    }

    It "shows similar filename suggestions only when edit distance is less than three" {
        Initialize-DiagnosticsWorkspace
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/bat.md" -Title "other" -Body "body" | Out-Null
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/doge.md" -Title "other" -Body "body" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "cat", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "bat\.md \(distance: 1\)"
        $result.Output | Should Not Match "doge\.md"
        $result.Output | Should Match "\\scripts\\search\.ps1 -Query ""bat"" -Wiki"
    }

    It "reports frontmatter metadata field matches" {
        Initialize-DiagnosticsWorkspace
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/metadata.md" -Title "other" -Body "body" -Metadata @{ owner = "Reno Search" } | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "Search", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "metadata\.md \(field: owner\)"
    }

    It "counts corrupted frontmatter files without failing" {
        Initialize-DiagnosticsWorkspace
        $brokenPath = Join-Path $script:WorkRoot "knowledge/raw/broken.md"
        "not frontmatter" | Set-Content -Path $brokenPath -Encoding UTF8

        $result = Invoke-SearchScript -Arguments @("-Query", "broken", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\[RAW\].*corrupted frontmatter: 1"
        $result.Output | Should Match "unreadable: knowledge/raw/broken.md"
    }

    It "always includes the archive suggestion" {
        Initialize-DiagnosticsWorkspace
        New-DiagnosticsDocument -RelativePath "knowledge/wiki/topic.md" -Title "topic" -Body "body" | Out-Null

        $result = Invoke-SearchScript -Arguments @("-Query", "topic", "-Diagnose")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\\scripts\\search\.ps1 -Query ""topic"" -Archive"
    }

    It "does not modify knowledge file timestamps during diagnostics" {
        Initialize-DiagnosticsWorkspace
        $path = New-DiagnosticsDocument -RelativePath "knowledge/wiki/stable.md" -Title "stable" -Body "body"
        $before = (Get-Item $path).LastWriteTimeUtc
        Start-Sleep -Milliseconds 1100

        $result = Invoke-SearchScript -Arguments @("-Query", "stable", "-Diagnose")
        $after = (Get-Item $path).LastWriteTimeUtc

        $result.ExitCode | Should Be 0
        $after | Should Be $before
    }
}
