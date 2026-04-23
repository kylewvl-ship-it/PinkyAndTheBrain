# Pester tests for wiki metadata scripts

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:UpdateScript = Join-Path $script:Root "scripts/update-wiki-metadata.ps1"
$script:ListScript = Join-Path $script:Root "scripts/list-wiki-reviews.ps1"
$script:TemplateRoot = Join-Path $script:Root "templates"

function Initialize-WikiMetadataWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_TEMPLATE_ROOT = $script:TemplateRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
}

function Invoke-WikiMetadataScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-WikiPage {
    param(
        [string]$FileName = "my-topic.md",
        [string]$Title = "My Topic",
        [string]$Status = "draft",
        [string]$Owner = "Reno",
        [string]$Confidence = "medium",
        [string]$LastUpdated = "2026-04-23T00:00:00.000Z",
        [string]$LastVerified = "",
        [string]$ReviewTrigger = "2026-07-22",
        [string[]]$SourceList = @("knowledge/working/source-a.md"),
        [switch]$NoFrontmatter,
        [string[]]$OmitFields = @(),
        [string]$BodyText = "Structured explanation."
    )

    $path = Join-Path $script:VaultRoot ("wiki\" + $FileName)
    if ($NoFrontmatter) {
@"
# $Title

## Summary

$BodyText
"@ | Set-Content -Path $path -Encoding UTF8
        return $path
    }

    $lines = @("---")
    if ($OmitFields -notcontains "title") { $lines += ('title: "{0}"' -f $Title) }
    if ($OmitFields -notcontains "status") { $lines += ('status: "{0}"' -f $Status) }
    if ($OmitFields -notcontains "owner") { $lines += ('owner: "{0}"' -f $Owner) }
    if ($OmitFields -notcontains "confidence") { $lines += ('confidence: "{0}"' -f $Confidence) }
    if ($OmitFields -notcontains "last_updated") { $lines += ('last_updated: "{0}"' -f $LastUpdated) }
    if ($OmitFields -notcontains "last_verified") { $lines += ('last_verified: "{0}"' -f $LastVerified) }
    if ($OmitFields -notcontains "review_trigger") { $lines += ('review_trigger: "{0}"' -f $ReviewTrigger) }
    if ($OmitFields -notcontains "source_list") {
        if ($SourceList.Count -eq 0) {
            $lines += 'source_list: []'
        }
        else {
            $lines += ('source_list: ["{0}"]' -f ($SourceList -join '", "'))
        }
    }
    $lines += 'aliases: []'
    $lines += 'project: ""'
    $lines += 'domain: ""'
    $lines += 'private: false'
    $lines += 'do_not_promote: false'
    $lines += 'exclude_from_ai: false'
    $lines += '---'

    $body = @(
        "# $Title",
        "",
        "## Summary",
        "",
        "Short factual overview.",
        "",
        "## Why It Matters",
        "",
        "Why future-you should care.",
        "",
        "## Key Concepts",
        "",
        "- Concept.",
        "",
        "## Details",
        "",
        $BodyText,
        "",
        "## Relationships",
        "",
        "- [[linked-page]]",
        "",
        "## Contradictions / Caveats",
        "",
        "Known uncertainty.",
        "",
        "## Sources",
        "",
        "- Primary:"
    )

    (($lines + @("") + $body) -join "`r`n") | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Initialize-GitRepo {
    Push-Location $script:WorkRoot
    try {
        & git init | Out-Null
        & git config user.email "test@example.com" | Out-Null
        & git config user.name "Test User" | Out-Null
        & git add . | Out-Null
        & git commit -m "baseline" | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe "wiki metadata scripts - Story 2.2" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_GIT_REPO_ROOT = $null
    }

    It "validates when all required fields are present" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-Validate")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "All required metadata present"
    }

    It "reports missing required fields during validation" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -OmitFields @("confidence", "source_list") | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-Validate")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "confidence"
        $result.Output | Should Match "source_list"
    }

    It "updates status and confidence and preserves the body" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -BodyText "Original body text." | Out-Null
        $before = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-Status", "verified", "-Confidence", "high")

        $result.ExitCode | Should Be 0
        $after = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $after | Should Match 'status: "verified"'
        $after | Should Match 'confidence: "high"'
        $after | Should Match 'last_updated: ".+?"'
        $after | Should Match "Original body text\."
        $after.Substring($after.IndexOf("# My Topic")).TrimEnd("`r", "`n") | Should Be ($before.Substring($before.IndexOf("# My Topic")).TrimEnd("`r", "`n"))
    }

    It "marks a page as verified and resets the review trigger" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -LastVerified "" -ReviewTrigger "2026-01-01" | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-MarkVerified")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Match 'last_verified: ".+?"'
        $expectedDate = (Get-Date).AddDays(90).ToString("yyyy-MM-dd")
        $content | Should Match "review_trigger: `"$expectedDate`""
        $result.Output | Should Match "Marked verified\. Next review:"
    }

    It "extends review from the current review trigger" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -ReviewTrigger "2026-07-22" | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-ExtendReview", "30")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Match 'review_trigger: "2026-08-21"'
    }

    It "extends review from today with warning when review_trigger is unparseable" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -ReviewTrigger "not-a-date" | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-ExtendReview", "10")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "WARNING: Could not parse current review_trigger"
        $expectedDate = (Get-Date).AddDays(10).ToString("yyyy-MM-dd")
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Match "review_trigger: `"$expectedDate`""
    }

    It "adds a source and warns when a local path is missing" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -SourceList @("knowledge/working/source-a.md") | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-AddSource", "knowledge\working\missing.md")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "WARNING: Source not found:"
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Match 'source_list: \["knowledge/working/source-a\.md", "knowledge\\working\\missing\.md"\]'
    }

    It "accepts URL sources and avoids duplicating entries" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -SourceList @("https://example.com") | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-AddSource", "https://example.com")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "NOTE: URL source added"
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        ([regex]::Matches($content, [regex]::Escape("https://example.com")).Count) | Should Be 1
    }

    It "removes a source from the list" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -SourceList @("knowledge/working/source-a.md", "knowledge/working/source-b.md") | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-RemoveSource", "knowledge/working/source-a.md")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Not Match "source-a\.md"
        $content | Should Match "source-b\.md"
    }

    It "warns and makes no change when removing a missing source" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -SourceList @("knowledge/working/source-b.md") | Out-Null
        $before = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-RemoveSource", "knowledge/working/source-a.md")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "WARNING: Source not found in list"
        $after = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $after | Should Be $before
    }

    It "validates sources and exits 1 for broken local paths without modifying the file" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -SourceList @("knowledge/working/missing.md") | Out-Null
        $before = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-ValidateSources")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "WARNING: Source not found:"
        $after = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $after | Should Be $before
    }

    It "prints a notice when required fields remain missing after an update" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -OmitFields @("owner", "source_list") | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-Status", "draft")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "NOTICE: Page is missing required fields:"
    }

    It "supports WhatIf without writing files" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage | Out-Null
        $before = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-Status", "verified", "-WhatIf")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Would update wiki metadata"
        $after = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $after | Should Be $before
    }

    It "fails when the file is not found or is outside the wiki folder" {
        Initialize-WikiMetadataWorkspace
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot "working") -Force | Out-Null
        Set-Content -Path (Join-Path $script:VaultRoot "working\other.md") -Value "x" -Encoding UTF8

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\working\other.md", "-Validate")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "ERROR: File not found or not a wiki page"
    }

    It "fails on corrupted frontmatter" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -NoFrontmatter | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-Validate")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "ERROR: Cannot parse frontmatter"
    }

    It "lists overdue pages sorted by most overdue first" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -FileName "oldest.md" -Title "Oldest" -ReviewTrigger ((Get-Date).AddDays(-10).ToString("yyyy-MM-dd")) | Out-Null
        New-WikiPage -FileName "recent.md" -Title "Recent" -ReviewTrigger ((Get-Date).AddDays(-2).ToString("yyyy-MM-dd")) | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:ListScript

        $result.ExitCode | Should Be 0
        $result.Output.IndexOf("oldest.md") -lt $result.Output.IndexOf("recent.md") | Should Be $true
    }

    It "includes upcoming pages within DaysAhead" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -FileName "upcoming.md" -Title "Upcoming" -ReviewTrigger ((Get-Date).AddDays(5).ToString("yyyy-MM-dd")) | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:ListScript -Arguments @("-DaysAhead", "14")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "upcoming\.md"
    }

    It "lists pages with no trigger separately" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage -FileName "notrigger.md" -Title "No Trigger" -ReviewTrigger "" | Out-Null

        $result = Invoke-WikiMetadataScript -ScriptPath $script:ListScript -Arguments @("-All")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "\[NO TRIGGER SET\]"
        $result.Output | Should Match "notrigger\.md"
    }

    It "creates a git commit after a successful metadata write" {
        Initialize-WikiMetadataWorkspace
        New-WikiPage | Out-Null
        Initialize-GitRepo

        $result = Invoke-WikiMetadataScript -ScriptPath $script:UpdateScript -Arguments @("-File", "knowledge\wiki\my-topic.md", "-Status", "verified")

        $result.ExitCode | Should Be 0
        Push-Location $script:WorkRoot
        try {
            $gitLog = & git log --oneline -1
        }
        finally {
            Pop-Location
        }
        ($gitLog | Out-String) | Should Match "Wiki metadata: updated my-topic\.md"
    }
}
