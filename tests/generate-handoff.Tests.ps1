# Pester tests for AI handoff context generation

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:HandoffScript = Join-Path $script:Root "scripts/generate-handoff.ps1"

function Initialize-HandoffWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    $script:HandoffsRoot = Join-Path $script:WorkRoot ".ai/handoffs"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }
    New-Item -ItemType Directory -Path $script:HandoffsRoot -Force | Out-Null

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function Invoke-HandoffScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:HandoffScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-HandoffDocument {
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

function Get-LatestHandoffFile {
    return Get-ChildItem -Path $script:HandoffsRoot -Filter "handoff-*.md" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Get-HandoffContent {
    $file = Get-LatestHandoffFile
    if ($null -eq $file) {
        return ""
    }
    return Get-Content -Path $file.FullName -Raw -Encoding UTF8
}

function Invoke-TokenHelper {
    param([string]$Text)

    $content = Get-Content -Path $script:HandoffScript -Raw
    $match = [regex]::Match($content, '(?s)function Get-TokenEstimate \{.*?^\}', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $match.Success) {
        throw "Get-TokenEstimate function not found."
    }

    $safe = $Text.Replace("'", "''")
    $command = @"
$($match.Value)
`$result = Get-TokenEstimate -Text '$safe'
Write-Output `$result
"@

    return (& powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $command | Out-String).Trim()
}

Describe "generate-handoff.ps1 - Story 3.3" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "excludes private files" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/private.md" -Title "secret topic" -Body "topic paragraph" -Metadata @{ private = "true" } | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")

        $result.ExitCode | Should Be 0
        (Get-HandoffContent) | Should Not Match "private.md"
    }

    It "excludes files marked exclude_from_ai" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/excluded.md" -Title "topic" -Body "topic paragraph" -Metadata @{ exclude_from_ai = "true" } | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")

        $result.ExitCode | Should Be 0
        (Get-HandoffContent) | Should Not Match "excluded.md"
    }

    It "orders wiki before working before raw" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/wiki-topic.md" -Title "topic wiki" -Body "topic paragraph" | Out-Null
        New-HandoffDocument -RelativePath "knowledge/working/work-topic.md" -Title "topic working" -Body "topic paragraph" | Out-Null
        New-HandoffDocument -RelativePath "knowledge/raw/raw-topic.md" -Title "topic raw" -Body "topic paragraph" | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        ($content.IndexOf("## Wiki Knowledge") -lt $content.IndexOf("## Working Notes")) | Should Be $true
        ($content.IndexOf("## Working Notes") -lt $content.IndexOf("## Raw References")) | Should Be $true
    }

    It "includes full wiki body when under 500 tokens" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/short-topic.md" -Title "short topic" -Body "First paragraph.`n`nSecond paragraph." | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        $content | Should Match "Second paragraph\."
    }

    It "uses only the first paragraph for wiki pages at or above 500 tokens" {
        Initialize-HandoffWorkspace
        $longParagraph = ("A" * 2200)
        $body = "Topic introduction.`n`n$longParagraph"
        New-HandoffDocument -RelativePath "knowledge/wiki/long-topic.md" -Title "long topic" -Body $body | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        $content | Should Match "Topic introduction\."
        $content | Should Not Match ([regex]::Escape($longParagraph.Substring(0, 40)))
    }

    It "extracts working note interpretation lines" {
        Initialize-HandoffWorkspace
        $body = @"
Opening paragraph.

## Current Interpretation
line one
line two
line three
line four
"@
        New-HandoffDocument -RelativePath "knowledge/working/topic-note.md" -Title "topic note" -Body $body | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        $content | Should Match "## Current Interpretation"
        $content | Should Match "line three"
        $content | Should Not Match "line four"
    }

    It "keeps total tokens within the configured budget" {
        Initialize-HandoffWorkspace
        foreach ($i in 1..20) {
            $body = ("topic " + ("x" * 900))
            New-HandoffDocument -RelativePath ("knowledge/wiki/topic-{0}.md" -f $i) -Title ("topic {0}" -f $i) -Body $body | Out-Null
        }

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        $match = [regex]::Match($content, 'Total tokens used: (\d+) / 3000')
        $match.Success | Should Be $true
        ([int]$match.Groups[1].Value -le 3000) | Should Be $true
    }

    It "respects the project filter" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/work-topic.md" -Title "topic work" -Body "topic paragraph" -Metadata @{ project = "work" } | Out-Null
        New-HandoffDocument -RelativePath "knowledge/wiki/home-topic.md" -Title "topic home" -Body "topic paragraph" -Metadata @{ project = "home" } | Out-Null
        New-HandoffDocument -RelativePath "knowledge/wiki/no-project.md" -Title "topic none" -Body "topic paragraph" | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic", "-Project", "work")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        $content | Should Match "work-topic.md"
        $content | Should Not Match "home-topic.md"
        $content | Should Not Match "no-project.md"
    }

    It "flags conflicting info when confidence diverges" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/topic-one.md" -Title "topic one" -Body "topic paragraph" -Metadata @{ confidence = "high" } | Out-Null
        New-HandoffDocument -RelativePath "knowledge/wiki/topic-two.md" -Title "topic two" -Body "topic paragraph" -Metadata @{ confidence = "low" } | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        ([regex]::Matches($content, '\[CONFLICTING INFO\]').Count) | Should BeGreaterThan 1
    }

    It "flags conflicting info when status diverges" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/topic-one.md" -Title "topic one" -Body "topic paragraph" -Metadata @{ status = "draft" } | Out-Null
        New-HandoffDocument -RelativePath "knowledge/wiki/topic-two.md" -Title "topic two" -Body "topic paragraph" -Metadata @{ status = "verified" } | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        ([regex]::Matches($content, '\[CONFLICTING INFO\]').Count) | Should BeGreaterThan 1
    }

    It "writes the handoff file to the handoffs folder with the expected name pattern" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/topic-file.md" -Title "topic file" -Body "topic paragraph" | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic file")
        $file = Get-LatestHandoffFile

        $result.ExitCode | Should Be 0
        $file.Name | Should Match '^handoff-\d{4}-\d{2}-\d{2}-\d{6}-topic-file\.md$'
    }

    It "includes source file list entries with relative paths and token counts" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/topic-file.md" -Title "topic file" -Body "topic paragraph" | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        $content | Should Match "- knowledge/wiki/topic-file.md \[WIKI \| \d+ tokens\]"
    }

    It "does not modify knowledge source files" {
        Initialize-HandoffWorkspace
        $path = New-HandoffDocument -RelativePath "knowledge/wiki/topic-file.md" -Title "topic file" -Body "topic paragraph"
        $before = (Get-Item $path).LastWriteTimeUtc
        Start-Sleep -Milliseconds 1100

        $result = Invoke-HandoffScript -Arguments @("-Topic", "topic")
        $after = (Get-Item $path).LastWriteTimeUtc

        $result.ExitCode | Should Be 0
        $after | Should Be $before
    }

    It "returns the configured token estimate formula" {
        (Invoke-TokenHelper -Text "abcd") | Should Be "1"
        (Invoke-TokenHelper -Text "abcde") | Should Be "2"
        (Invoke-TokenHelper -Text ("a" * 9)) | Should Be "3"
    }

    It "returns exit code 0 when no candidates match" {
        Initialize-HandoffWorkspace
        New-HandoffDocument -RelativePath "knowledge/wiki/other.md" -Title "other" -Body "body" | Out-Null

        $result = Invoke-HandoffScript -Arguments @("-Topic", "missing")
        $content = Get-HandoffContent

        $result.ExitCode | Should Be 0
        $content | Should Match "Items included: 0"
    }

    It "returns exit code 1 when topic is empty" {
        Initialize-HandoffWorkspace

        $result = Invoke-HandoffScript -Arguments @("-Topic", "")

        $result.ExitCode | Should Be 1
    }
}
