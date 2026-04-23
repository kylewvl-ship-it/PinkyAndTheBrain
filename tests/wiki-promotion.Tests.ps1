# Pester tests for wiki promotion script

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:PromoteWikiScript = Join-Path $script:Root "scripts/promote-to-wiki.ps1"
$script:TemplateRoot = Join-Path $script:Root "templates"

function Initialize-WikiPromotionWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_TEMPLATE_ROOT = $script:TemplateRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function Invoke-WikiPromotionScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:PromoteWikiScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-WorkingNote {
    param(
        [string]$FileName = "my-topic.md",
        [string]$Title = "My Topic",
        [string]$Status = "draft",
        [string]$Confidence = "medium",
        [string[]]$SourceList = @("knowledge/raw/source-a.md"),
        [string]$WhatIThink = "Short summary.",
        [string]$Evidence = "Evidence line.",
        [string]$Connections = "- [[other-note]]",
        [string]$Contradictions = "Conflicting source says otherwise.",
        [string]$SourcePointers = "- knowledge/raw/source-a.md",
        [switch]$NoFrontmatter,
        [string[]]$OmitFields = @(),
        [bool]$DoNotPromote = $false
    )

    $path = Join-Path $script:VaultRoot ("working\" + $FileName)

    if ($NoFrontmatter) {
@"
# $Title

## What I Think

$WhatIThink
"@ | Set-Content -Path $path -Encoding UTF8
        return $path
    }

    $frontmatterLines = @("---")
    if ($OmitFields -notcontains "title") { $frontmatterLines += ('title: "{0}"' -f $Title) }
    if ($OmitFields -notcontains "status") { $frontmatterLines += ('status: "{0}"' -f $Status) }
    if ($OmitFields -notcontains "confidence") { $frontmatterLines += ('confidence: "{0}"' -f $Confidence) }
    $frontmatterLines += 'last_updated: "2026-04-23T00:00:00.000Z"'
    $frontmatterLines += 'review_trigger: "2026-05-23"'
    $frontmatterLines += 'project: ""'
    $frontmatterLines += 'domain: ""'
    if ($SourceList.Count -eq 0) {
        $frontmatterLines += 'source_list: []'
    }
    else {
        $frontmatterLines += ('source_list: ["{0}"]' -f ($SourceList -join '", "'))
    }
    $frontmatterLines += 'promoted_to: ""'
    $frontmatterLines += 'private: false'
    $frontmatterLines += ('do_not_promote: {0}' -f ($DoNotPromote.ToString().ToLower()))
    $frontmatterLines += '---'

    $body = @(
        "# $Title",
        "",
        "## Prompt / Trigger",
        "",
        "Created for testing.",
        "",
        "## What I Think",
        "",
        $WhatIThink,
        "",
        "## Evidence",
        "",
        $Evidence,
        "",
        "## Connections",
        "",
        $Connections,
        "",
        "## Tensions / Contradictions",
        "",
        $Contradictions,
        "",
        "## Open Questions",
        "",
        "- Question.",
        "",
        "## Next Moves",
        "",
        "- Action.",
        "",
        "## Source Pointers",
        "",
        $SourcePointers
    )

    (($frontmatterLines + @("") + $body) -join "`r`n") | Set-Content -Path $path -Encoding UTF8
    return $path
}

Describe "wiki promotion script - Story 2.1" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "creates a wiki page from a valid working note" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 0
        (Test-Path (Join-Path $script:VaultRoot "wiki\my-topic.md")) | Should Be $true
    }

    It "writes required wiki frontmatter fields" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote -Confidence "high" -SourceList @("knowledge/raw/source-a.md", "knowledge/raw/source-b.md") | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Match 'title: "My Topic"'
        $content | Should Match 'status: "draft"'
        $content | Should Match 'owner: "Reno"'
        $content | Should Match 'confidence: "high"'
        $content | Should Match 'last_updated: ".+?"'
        $content | Should Match 'review_trigger: ".+?"'
        $content | Should Match 'source_list: \["knowledge/raw/source-a\.md", "knowledge/raw/source-b\.md"\]'
    }

    It "sets wiki review_trigger to today plus 90 days by default" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $expectedDate = (Get-Date).AddDays(90).ToString("yyyy-MM-dd")
        $content | Should Match "review_trigger: `"$expectedDate`""
    }

    It "preserves contradictions in the wiki page" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote -Contradictions "Claim A conflicts with Claim B." | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Match "## Contradictions / Caveats"
        $content | Should Match "Claim A conflicts with Claim B\."
    }

    It "updates the working note status and promoted_to after promotion" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "working\my-topic.md") -Raw
        $content | Should Match 'status: "promoted"'
        $content | Should Match 'promoted_to: "knowledge/wiki/my-topic.md"'
    }

    It "warns on duplicates and creates a numbered wiki page in non-interactive mode" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote | Out-Null
@"
---
title: "My Topic"
status: "draft"
owner: "Reno"
confidence: "low"
last_updated: "2026-04-20T00:00:00.000Z"
last_verified: ""
review_trigger: "2026-07-20"
source_list: []
aliases: []
project: ""
domain: ""
private: false
do_not_promote: false
exclude_from_ai: false
---
"@ | Set-Content -Path (Join-Path $script:VaultRoot "wiki\my-topic.md") -Encoding UTF8

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Potential duplicate wiki pages found"
        (Test-Path (Join-Path $script:VaultRoot "wiki\my-topic-2.md")) | Should Be $true
    }

    It "saves a draft with review warning when source_list is empty" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote -SourceList @() -SourcePointers "- knowledge/working/unlinked.md" | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Working note has no sources in source_list"
        $content = Get-Content (Join-Path $script:VaultRoot "wiki\my-topic.md") -Raw
        $content | Should Match "<!-- REVIEW: No sources"
    }

    It "fails with repair guidance when frontmatter is corrupted" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote -NoFrontmatter | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "Working note frontmatter is missing required fields"
        $result.Output | Should Match "Repair template"
        (Test-Path (Join-Path $script:VaultRoot "wiki\my-topic.md")) | Should Be $false
    }

    It "identifies specific missing frontmatter fields" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote -OmitFields @("confidence") | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "confidence"
    }

    It "blocks promotion when do_not_promote is true" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote -DoNotPromote $true | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "do_not_promote"
        (Test-Path (Join-Path $script:VaultRoot "wiki\my-topic.md")) | Should Be $false
    }

    It "creates a retry record when the wiki folder is inaccessible" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote | Out-Null
        Remove-Item -LiteralPath (Join-Path $script:VaultRoot "wiki") -Recurse -Force

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md")

        $result.ExitCode | Should Be 2
        $result.Output | Should Match "Wiki folder is inaccessible"
        (Get-ChildItem (Join-Path $script:WorkRoot ".ai\handoffs") -Filter "promote-retry-*.md").Count | Should Be 1
    }

    It "does not write files in WhatIf mode" {
        Initialize-WikiPromotionWorkspace
        New-WorkingNote | Out-Null

        $result = Invoke-WikiPromotionScript -Arguments @("-SourceFile", "knowledge\working\my-topic.md", "-WhatIf")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Would create wiki page"
        (Test-Path (Join-Path $script:VaultRoot "wiki\my-topic.md")) | Should Be $false
    }
}
