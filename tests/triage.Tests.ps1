# Pester tests for triage.ps1

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:Script = Join-Path $script:Root "scripts/triage.ps1"

function Initialize-TriageWorkspace {
    param(
        [string[]]$MissingFolders = @()
    )

    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null

    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        if ($MissingFolders -notcontains $folder) {
            New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
        }
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
    $env:PINKY_TRIAGE_SELECTION = $null
    $env:PINKY_CONFIRM_DELETE = $null
    $env:PINKY_ARCHIVE_REASON = $null
}

function New-InboxItem {
    param(
        [string]$FileName,
        [string]$Title,
        [string]$SourceType = "manual",
        [string]$Project = "general",
        [datetime]$CapturedDate = (Get-Date),
        [string]$Content = "Body"
    )

    $path = Join-Path $script:VaultRoot "inbox\$FileName"
    @"
---
title: "$Title"
captured_date: "$($CapturedDate.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))"
source_type: "$SourceType"
source_url: ""
source_title: ""
review_status: "pending"
disposition: "inbox"
project: "$Project"
private: false
do_not_promote: false
---

# $Title

$Content
"@ | Set-Content -Path $path -Encoding UTF8

    return $path
}

function Invoke-Triage {
    param(
        [string[]]$Arguments = @(),
        [string]$Selection = "q",
        [string]$ConfirmDelete = $null,
        [string]$ArchiveReason = $null
    )

    $env:PINKY_TRIAGE_SELECTION = $Selection
    $env:PINKY_CONFIRM_DELETE = $ConfirmDelete
    $env:PINKY_ARCHIVE_REASON = $ArchiveReason

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Script @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

Describe "triage.ps1 - Story 1.2 inbox triage" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_TRIAGE_SELECTION = $null
        $env:PINKY_CONFIRM_DELETE = $null
        $env:PINKY_ARCHIVE_REASON = $null
    }

    It "shows filename instead of frontmatter title" {
        Initialize-TriageWorkspace
        New-InboxItem -FileName "alpha-note.md" -Title "Frontmatter Title Only" -Content "Neutral preview text" | Out-Null

        $result = Invoke-Triage

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "1\. alpha-note\.md \[manual\]"
    }

    It "prints delete summary with filenames after successful deletion" {
        Initialize-TriageWorkspace
        New-InboxItem -FileName "delete-one.md" -Title "Delete One" | Out-Null
        New-InboxItem -FileName "delete-two.md" -Title "Delete Two" | Out-Null

        $result = Invoke-Triage -Selection "all D" -ConfirmDelete "y"

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Deleted 2 items: delete-one\.md, delete-two\.md"
        @(Get-ChildItem (Join-Path $script:VaultRoot "inbox") -Filter "*.md" -ErrorAction SilentlyContinue).Count | Should Be 0
    }

    It "continues deleting other items when one file is locked" {
        Initialize-TriageWorkspace
        $lockedPath = New-InboxItem -FileName "locked.md" -Title "Locked Item"
        New-InboxItem -FileName "free.md" -Title "Free Item" | Out-Null
        $lockStream = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)

        try {
            $result = Invoke-Triage -Selection "all D" -ConfirmDelete "y"
        }
        finally {
            $lockStream.Close()
            $lockStream.Dispose()
        }

        $result.ExitCode | Should Be 0
        (Test-Path (Join-Path $script:VaultRoot "inbox\locked.md")) | Should Be $true
        (Test-Path (Join-Path $script:VaultRoot "inbox\free.md")) | Should Be $false
        $result.Output | Should Match "Check file permissions or run as administrator"
    }

    It "writes a custom archive reason into archived frontmatter" {
        Initialize-TriageWorkspace
        New-InboxItem -FileName "archive-me.md" -Title "Archive Me" | Out-Null

        $result = Invoke-Triage -Selection "all A" -ArchiveReason "my-reason"

        $result.ExitCode | Should Be 0
        $archived = Get-Content (Join-Path $script:VaultRoot "archive\archive-me.md") -Raw
        $archived | Should Match "archive_reason: my-reason"
        $archived | Should Match 'disposition: "archived"'
    }

    It "supports all W to process all shown items" {
        Initialize-TriageWorkspace
        New-InboxItem -FileName "work-one.md" -Title "Work One" | Out-Null
        New-InboxItem -FileName "work-two.md" -Title "Work Two" | Out-Null

        $result = Invoke-Triage -Selection "all W"

        $result.ExitCode | Should Be 0
        @(Get-ChildItem (Join-Path $script:VaultRoot "working") -Filter "*.md").Count | Should Be 2
        @(Get-ChildItem (Join-Path $script:VaultRoot "inbox") -Filter "*.md" -ErrorAction SilentlyContinue).Count | Should Be 0
    }

    It "auto-creates the raw folder before moving items" {
        Initialize-TriageWorkspace -MissingFolders @("raw")
        New-InboxItem -FileName "raw-me.md" -Title "Raw Me" | Out-Null

        $result = Invoke-Triage -Selection "all R"

        $result.ExitCode | Should Be 0
        (Test-Path (Join-Path $script:VaultRoot "raw")) | Should Be $true
        (Test-Path (Join-Path $script:VaultRoot "raw\raw-me.md")) | Should Be $true
        $log = Get-Content (Join-Path $script:WorkRoot "logs/triage-actions.log") -Raw
        $log | Should Match "Created missing folder"
    }

    It "combines SourceType and OlderThan filters" {
        Initialize-TriageWorkspace
        New-InboxItem -FileName "match-web-old.md" -Title "Match" -SourceType "web" -CapturedDate (Get-Date).AddDays(-5) | Out-Null
        New-InboxItem -FileName "wrong-age.md" -Title "Wrong Age" -SourceType "web" -CapturedDate (Get-Date).AddDays(-1) | Out-Null
        New-InboxItem -FileName "wrong-type.md" -Title "Wrong Type" -SourceType "manual" -CapturedDate (Get-Date).AddDays(-5) | Out-Null

        $result = Invoke-Triage -Arguments @("-SourceType", "web", "-OlderThan", "3")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "match-web-old\.md"
        $result.Output | Should Not Match "wrong-age\.md"
        $result.Output | Should Not Match "wrong-type\.md"
    }
}
