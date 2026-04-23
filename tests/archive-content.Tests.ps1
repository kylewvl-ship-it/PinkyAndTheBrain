# Pester tests for archive content scripts

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:ArchiveScript = Join-Path $script:Root "scripts/archive-content.ps1"
$script:ListOrphansScript = Join-Path $script:Root "scripts/list-orphaned-refs.ps1"
$script:TemplateRoot = Join-Path $script:Root "templates"

function Initialize-ArchiveWorkspace {
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

function Invoke-ArchiveScript {
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

function New-ArchiveTarget {
    param(
        [string]$RelativePath = "knowledge/wiki/old-topic.md",
        [string]$Title = "Old Topic"
    )

    $path = Join-Path $script:WorkRoot $RelativePath
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

@"
---
title: "$Title"
status: "verified"
owner: "Reno"
confidence: "medium"
last_updated: "2026-04-23T00:00:00.000Z"
last_verified: ""
review_trigger: "2026-07-22"
source_list: ["knowledge/working/source-a.md"]
aliases: []
project: ""
domain: ""
private: false
do_not_promote: false
exclude_from_ai: false
---

# $Title

## Summary

Short factual overview.
"@ | Set-Content -Path $path -Encoding UTF8

    return $path
}

function New-ReferencingFile {
    param(
        [string]$RelativePath,
        [string]$Body
    )

    $path = Join-Path $script:WorkRoot $RelativePath
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

@"
---
title: "Ref"
status: "draft"
confidence: "low"
last_updated: "2026-04-23T00:00:00.000Z"
review_trigger: "2026-05-23"
project: ""
domain: ""
source_list: []
promoted_to: ""
private: false
do_not_promote: false
---

$Body
"@ | Set-Content -Path $path -Encoding UTF8

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

Describe "archive content scripts - Story 2.3" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_GIT_REPO_ROOT = $null
    }

    It "rejects an invalid archive reason" {
        Initialize-ArchiveWorkspace
        New-ArchiveTarget | Out-Null

        $result = Invoke-ArchiveScript -ScriptPath $script:ArchiveScript -Arguments @("-File", "knowledge/wiki/old-topic.md", "-Reason", "bad-reason")

        $result.ExitCode | Should Be 1
        (Test-Path (Join-Path $script:VaultRoot "wiki\old-topic.md")) | Should Be $true
        (Test-Path (Join-Path $script:VaultRoot "archive\old-topic.md")) | Should Be $false
    }

    It "moves a file to archive and writes archive metadata" {
        Initialize-ArchiveWorkspace
        New-ArchiveTarget | Out-Null

        $result = Invoke-ArchiveScript -ScriptPath $script:ArchiveScript -Arguments @("-File", "knowledge/wiki/old-topic.md", "-Reason", "stale")

        $result.ExitCode | Should Be 0
        (Test-Path (Join-Path $script:VaultRoot "wiki\old-topic.md")) | Should Be $false
        $archivedPath = Join-Path $script:VaultRoot "archive\old-topic.md"
        (Test-Path $archivedPath) | Should Be $true
        $content = Get-Content $archivedPath -Raw
        $content | Should Match 'status: "archived"'
        $content | Should Match 'archive_reason: "stale"'
        $content | Should Match 'archived_date: ".+?"'
        $content | Should Match 'replaced_by: ""'
    }

    It "discovers references and orphans them by default in non-interactive mode" {
        Initialize-ArchiveWorkspace
        New-ArchiveTarget | Out-Null
        New-ReferencingFile -RelativePath "knowledge/working/ref-note.md" -Body "Link: [[old-topic]]" | Out-Null
        New-ReferencingFile -RelativePath "knowledge/raw/ref-raw.md" -Body "Link: [topic](../wiki/old-topic.md)" | Out-Null

        $result = Invoke-ArchiveScript -ScriptPath $script:ArchiveScript -Arguments @("-File", "knowledge/wiki/old-topic.md", "-Reason", "duplicate")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Found references:"
        $orphanLog = Get-Content (Join-Path $script:VaultRoot "archive\orphaned-refs.md") -Raw
        $orphanLog | Should Match "ref-note\.md"
        $orphanLog | Should Match "ref-raw\.md"
    }

    It "updates references to the replacement path when requested" {
        Initialize-ArchiveWorkspace
        New-ArchiveTarget | Out-Null
        New-ReferencingFile -RelativePath "knowledge/working/ref-note.md" -Body "Link: [[old-topic]]" | Out-Null

        $result = Invoke-ArchiveScript -ScriptPath $script:ArchiveScript -Arguments @("-File", "knowledge/wiki/old-topic.md", "-Reason", "replaced", "-ReplacedBy", "knowledge/wiki/new-topic.md", "-UpdateReferences")

        $result.ExitCode | Should Be 0
        $updated = Get-Content (Join-Path $script:VaultRoot "working\ref-note.md") -Raw
        $updated | Should Match "knowledge/wiki/new-topic\.md"
        $archived = Get-Content (Join-Path $script:VaultRoot "archive\old-topic.md") -Raw
        $archived | Should Match 'replaced_by: "knowledge/wiki/new-topic.md"'
    }

    It "lists orphaned references and supports file filtering" {
        Initialize-ArchiveWorkspace
        $orphanPath = Join-Path $script:VaultRoot "archive\orphaned-refs.md"
@"
# Orphaned References Log

| Archived File | Referencing File | Linked As | Archived Date |
|---|---|---|---|
| wiki/old-topic.md | working/ref-note.md | `[[old-topic]]` | 2026-04-23 |
| wiki/other-topic.md | working/other-note.md | `[[other-topic]]` | 2026-04-23 |
"@ | Set-Content -Path $orphanPath -Encoding UTF8

        $result = Invoke-ArchiveScript -ScriptPath $script:ListOrphansScript -Arguments @("-File", "wiki/old-topic.md")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "old-topic\.md"
        $result.Output | Should Not Match "other-topic\.md"
    }

    It "creates a git commit after successful archival" {
        Initialize-ArchiveWorkspace
        New-ArchiveTarget | Out-Null
        Initialize-GitRepo

        $result = Invoke-ArchiveScript -ScriptPath $script:ArchiveScript -Arguments @("-File", "knowledge/wiki/old-topic.md", "-Reason", "stale")

        $result.ExitCode | Should Be 0
        Push-Location $script:WorkRoot
        try {
            $gitLog = & git log --oneline -1
        }
        finally {
            Pop-Location
        }
        ($gitLog | Out-String) | Should Match "Archive: old-topic\.md"
    }
}
