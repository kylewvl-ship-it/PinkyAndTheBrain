# Pester tests for working note scripts

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:CreateScript = Join-Path $script:Root "scripts/create-working-note.ps1"
$script:PromoteScript = Join-Path $script:Root "scripts/promote-to-working.ps1"
$script:ListScript = Join-Path $script:Root "scripts/list-working-notes.ps1"
$script:SummaryScript = Join-Path $script:Root "scripts/working-note-summary.ps1"
$script:TemplateRoot = Join-Path $script:Root "templates"

function Initialize-WorkingWorkspace {
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

function Invoke-WorkingScript {
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

function New-SourceItem {
    param(
        [string]$RelativePath,
        [string]$Title = "Source Item",
        [string]$Body = "Evidence body",
        [switch]$Corrupted
    )

    $path = Join-Path $script:WorkRoot $RelativePath
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ($Corrupted) {
        "Plain body without frontmatter`n$Body" | Set-Content -Path $path -Encoding UTF8
    }
    else {
@"
---
title: "$Title"
captured_date: "$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")"
source_type: "manual"
project: "general"
---

$Body
"@ | Set-Content -Path $path -Encoding UTF8
    }

    return $path
}

Describe "working note scripts - Story 1.3" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "creates a kebab-case working note filename" {
        Initialize-WorkingWorkspace
        $result = Invoke-WorkingScript -ScriptPath $script:CreateScript -Arguments @("-Title", "My Topic", "-Project", "research")

        $result.ExitCode | Should Be 0
        (Test-Path (Join-Path $script:VaultRoot "working\my-topic.md")) | Should Be $true
    }

    It "writes required frontmatter fields on create" {
        Initialize-WorkingWorkspace
        $result = Invoke-WorkingScript -ScriptPath $script:CreateScript -Arguments @("-Title", "Metadata Topic", "-Project", "research")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "working\metadata-topic.md") -Raw
        $content | Should Match 'status: "draft"'
        $content | Should Match 'confidence: "low"'
        $content | Should Match 'last_updated: ".+?"'
        $content | Should Match 'project: "research"'
    }

    It "sets review_trigger to today plus 30 days by default" {
        Initialize-WorkingWorkspace
        $result = Invoke-WorkingScript -ScriptPath $script:CreateScript -Arguments @("-Title", "Review Topic")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "working\review-topic.md") -Raw
        $expectedDate = (Get-Date).AddDays(30).ToString("yyyy-MM-dd")
        $content | Should Match "review_trigger: `"$expectedDate`""
    }

    It "prevents overwrite and suggests alternatives on duplicate title" {
        Initialize-WorkingWorkspace
        Invoke-WorkingScript -ScriptPath $script:CreateScript -Arguments @("-Title", "Duplicate Topic") | Out-Null
        $result = Invoke-WorkingScript -ScriptPath $script:CreateScript -Arguments @("-Title", "Duplicate Topic")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "duplicate-topic-2\.md"
        $result.Output | Should Match "duplicate-topic-3\.md"
    }

    It "promotes source body into Evidence and tracks source_list" {
        Initialize-WorkingWorkspace
        New-SourceItem -RelativePath "knowledge\inbox\source-item.md" -Body "Line one`nLine two" | Out-Null

        $result = Invoke-WorkingScript -ScriptPath $script:PromoteScript -Arguments @("-SourceFile", "knowledge\inbox\source-item.md", "-Title", "Working Topic")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "working\working-topic.md") -Raw
        $content | Should Match "## Evidence"
        $content | Should Match "Line one"
        $content | Should Match 'source_list: \["knowledge/inbox/source-item.md"\]'
    }

    It "updates promoted_to on the source file during promotion" {
        Initialize-WorkingWorkspace
        New-SourceItem -RelativePath "knowledge\raw\raw-item.md" -Body "Raw body" | Out-Null

        $result = Invoke-WorkingScript -ScriptPath $script:PromoteScript -Arguments @("-SourceFile", "knowledge\raw\raw-item.md", "-Title", "Promoted Topic")

        $result.ExitCode | Should Be 0
        $sourceContent = Get-Content (Join-Path $script:VaultRoot "raw\raw-item.md") -Raw
        $sourceContent | Should Match 'promoted_to: "knowledge/working/promoted-topic.md"'
    }

    It "creates a working note and logs when the source frontmatter is corrupted" {
        Initialize-WorkingWorkspace
        New-SourceItem -RelativePath "knowledge\inbox\broken-source.md" -Body "Broken source body" -Corrupted | Out-Null

        $result = Invoke-WorkingScript -ScriptPath $script:PromoteScript -Arguments @("-SourceFile", "knowledge\inbox\broken-source.md", "-Title", "Recovered Topic")

        $result.ExitCode | Should Be 0
        $content = Get-Content (Join-Path $script:VaultRoot "working\recovered-topic.md") -Raw
        $content | Should Match "# WARNING: Source frontmatter unreadable"
        $log = Get-Content (Join-Path $script:WorkRoot "logs\script-errors.log") -Raw
        $log | Should Match "Source frontmatter unreadable"
    }

    It "prints no working notes found when the folder is empty" {
        Initialize-WorkingWorkspace
        $result = Invoke-WorkingScript -ScriptPath $script:ListScript

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "No working notes found"
    }

    It "shows overdue working notes" {
        Initialize-WorkingWorkspace
@"
---
title: "Overdue"
status: "active"
confidence: "low"
last_updated: "2026-04-20T00:00:00.000Z"
review_trigger: "2026-04-01"
project: ""
domain: ""
source_list: []
promoted_to: ""
private: false
do_not_promote: false
---

# Overdue
"@ | Set-Content -Path (Join-Path $script:VaultRoot "working\overdue.md") -Encoding UTF8

        $result = Invoke-WorkingScript -ScriptPath $script:ListScript

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "OVERDUE"
    }

    It "filters working notes by status" {
        Initialize-WorkingWorkspace
@"
---
title: "Active Note"
status: "active"
confidence: "low"
last_updated: "2026-04-20T00:00:00.000Z"
review_trigger: "2099-04-01"
project: ""
domain: ""
source_list: []
promoted_to: ""
private: false
do_not_promote: false
---
"@ | Set-Content -Path (Join-Path $script:VaultRoot "working\active-note.md") -Encoding UTF8
@"
---
title: "Draft Note"
status: "draft"
confidence: "low"
last_updated: "2026-04-19T00:00:00.000Z"
review_trigger: "2099-04-01"
project: ""
domain: ""
source_list: []
promoted_to: ""
private: false
do_not_promote: false
---
"@ | Set-Content -Path (Join-Path $script:VaultRoot "working\draft-note.md") -Encoding UTF8

        $result = Invoke-WorkingScript -ScriptPath $script:ListScript -Arguments @("-Status", "active")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Active Note"
        $result.Output | Should Not Match "Draft Note"
    }

    It "sorts by last_updated with newest first" {
        Initialize-WorkingWorkspace
@"
---
title: "Older Note"
status: "active"
confidence: "low"
last_updated: "2026-04-19T00:00:00.000Z"
review_trigger: "2099-04-01"
project: ""
domain: ""
source_list: []
promoted_to: ""
private: false
do_not_promote: false
---
"@ | Set-Content -Path (Join-Path $script:VaultRoot "working\older.md") -Encoding UTF8
@"
---
title: "Newer Note"
status: "active"
confidence: "high"
last_updated: "2026-04-22T00:00:00.000Z"
review_trigger: "2099-04-01"
project: ""
domain: ""
source_list: []
promoted_to: ""
private: false
do_not_promote: false
---
"@ | Set-Content -Path (Join-Path $script:VaultRoot "working\newer.md") -Encoding UTF8

        $result = Invoke-WorkingScript -ScriptPath $script:ListScript -Arguments @("-SortBy", "last_updated")

        $result.ExitCode | Should Be 0
        $result.Output.IndexOf("Newer Note") -lt $result.Output.IndexOf("Older Note") | Should Be $true
    }

    It "prints no git history found when a working note has no history" {
        Initialize-WorkingWorkspace
@"
---
title: "No History"
status: "draft"
confidence: "low"
last_updated: "2026-04-22T00:00:00.000Z"
review_trigger: "2099-04-01"
project: ""
domain: ""
source_list: []
promoted_to: ""
private: false
do_not_promote: false
---
"@ | Set-Content -Path (Join-Path $script:VaultRoot "working\no-history.md") -Encoding UTF8

        $result = Invoke-WorkingScript -ScriptPath $script:SummaryScript -Arguments @("-File", "no-history.md")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "No git history found for this file"
    }
}
