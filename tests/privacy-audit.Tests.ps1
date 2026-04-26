# Pester tests for sensitive content controls

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:AuditScript = Join-Path $script:Root "scripts/privacy-audit.ps1"
$script:SearchScript = Join-Path $script:Root "scripts/search.ps1"
$script:HandoffScript = Join-Path $script:Root "scripts/generate-handoff.ps1"

function Initialize-PrivacyWorkspace {
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

function New-PrivacyDocument {
    param(
        [string]$RelativePath,
        [string]$Title,
        [string]$Body,
        [string[]]$ExtraFrontmatter = @()
    )

    $path = Join-Path $script:WorkRoot $RelativePath
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $frontmatterMap = [ordered]@{
        title = ('"{0}"' -f $Title)
        private = 'false'
        exclude_from_ai = 'false'
        redacted_sections = '[]'
    }

    foreach ($line in $ExtraFrontmatter) {
        if ($line -match '^([^:]+):\s*(.*)$') {
            $frontmatterMap[$matches[1].Trim()] = $matches[2].Trim()
        }
    }

    $lines = @('---')
    foreach ($key in $frontmatterMap.Keys) {
        $lines += ('{0}: {1}' -f $key, $frontmatterMap[$key])
    }
    $lines += '---'
    $lines += ''
    $lines += ($Body -split "`n")

    Set-Content -Path $path -Value ($lines -join "`r`n") -Encoding UTF8
    return $path
}

function Invoke-PrivacyAuditScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:AuditScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-PrivacySearchScript {
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

function Invoke-PrivacyHandoffScript {
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

function Get-LatestHandoffContent {
    $file = Get-ChildItem -Path $script:HandoffsRoot -Filter "handoff-*.md" | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $file) {
        return ""
    }

    return Get-Content -Path $file.FullName -Raw -Encoding UTF8
}

function Initialize-GitRepo {
    Push-Location $script:WorkRoot
    try {
        & git init | Out-Null
        & git config user.email "test@example.com" | Out-Null
        & git config user.name "Test User" | Out-Null
        Set-Content -Path (Join-Path $script:WorkRoot ".gitkeep") -Value "baseline" -Encoding UTF8
        & git add . | Out-Null
        & git commit -m "baseline" | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe "privacy-audit.ps1 - Story 5.1" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "finds private files in audit mode" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/private.md" -Title "Private" -Body "body" -ExtraFrontmatter @('private: true') | Out-Null

        $result = Invoke-PrivacyAuditScript

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'private.md'
    }

    It "finds exclude_from_ai files in audit mode" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/working/excluded.md" -Title "Excluded" -Body "body" -ExtraFrontmatter @('exclude_from_ai: true') | Out-Null

        $result = Invoke-PrivacyAuditScript

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'excluded.md'
    }

    It "finds files with redacted sections in audit mode" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/redacted.md" -Title "Redacted" -Body "body" -ExtraFrontmatter @('redacted_sections: ["Secret"]') | Out-Null

        $result = Invoke-PrivacyAuditScript

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'redacted.md'
    }

    It "filters only private files with -Private" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/private.md" -Title "Private" -Body "body" -ExtraFrontmatter @('private: true') | Out-Null
        New-PrivacyDocument -RelativePath "knowledge/wiki/excluded.md" -Title "Excluded" -Body "body" -ExtraFrontmatter @('exclude_from_ai: true') | Out-Null

        $result = Invoke-PrivacyAuditScript -Arguments @("-Private")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'private.md'
        $result.Output | Should Not Match 'excluded.md'
    }

    It "filters only exclude_from_ai files with -ExcludeFromAI" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/private.md" -Title "Private" -Body "body" -ExtraFrontmatter @('private: true') | Out-Null
        New-PrivacyDocument -RelativePath "knowledge/wiki/excluded.md" -Title "Excluded" -Body "body" -ExtraFrontmatter @('exclude_from_ai: true') | Out-Null

        $result = Invoke-PrivacyAuditScript -Arguments @("-ExcludeFromAI")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'excluded.md'
        $result.Output | Should Not Match 'private.md'
    }

    It "filters only redacted files with -Redacted" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/private.md" -Title "Private" -Body "body" -ExtraFrontmatter @('private: true') | Out-Null
        New-PrivacyDocument -RelativePath "knowledge/wiki/redacted.md" -Title "Redacted" -Body "body" -ExtraFrontmatter @('redacted_sections: ["Secret"]') | Out-Null

        $result = Invoke-PrivacyAuditScript -Arguments @("-Redacted")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'redacted.md'
        $result.Output | Should Not Match 'private.md'
    }

    It "prints no matches message when nothing qualifies" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/public.md" -Title "Public" -Body "body" | Out-Null

        $result = Invoke-PrivacyAuditScript

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'No files with sensitive content controls found\.'
    }

    It "sets private true and commits per file" {
        Initialize-PrivacyWorkspace
        Initialize-GitRepo
        $first = New-PrivacyDocument -RelativePath "knowledge/wiki/a.md" -Title "A" -Body "body"
        $second = New-PrivacyDocument -RelativePath "knowledge/working/b.md" -Title "B" -Body "body"

        $result = Invoke-PrivacyAuditScript -Arguments @("-SetPrivate", "true", "-Files", "$first,$second")

        $result.ExitCode | Should Be 0
        (Get-Content -Path $first -Raw -Encoding UTF8) | Should Match 'private: true'
        (Get-Content -Path $second -Raw -Encoding UTF8) | Should Match 'private: true'
        Push-Location $script:WorkRoot
        try {
            $log = & git log --oneline -2 | Out-String
        }
        finally {
            Pop-Location
        }
        $log | Should Match 'privacy: set private=true'
    }

    It "fails bulk update when files are missing" {
        Initialize-PrivacyWorkspace

        $result = Invoke-PrivacyAuditScript -Arguments @("-SetPrivate", "true")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'requires -Files'
    }

    It "fails bulk update for invalid path" {
        Initialize-PrivacyWorkspace

        $result = Invoke-PrivacyAuditScript -Arguments @("-SetPrivate", "true", "-Files", "missing.md")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'File not found'
    }

    It "fails bulk update for invalid value" {
        Initialize-PrivacyWorkspace
        $path = New-PrivacyDocument -RelativePath "knowledge/wiki/a.md" -Title "A" -Body "body"

        $result = Invoke-PrivacyAuditScript -Arguments @("-SetPrivate", "maybe", "-Files", $path)

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "must be 'true' or 'false'"
    }

    It "supports WhatIf for bulk update without writing" {
        Initialize-PrivacyWorkspace
        $path = New-PrivacyDocument -RelativePath "knowledge/wiki/a.md" -Title "A" -Body "body"
        $before = Get-Content -Path $path -Raw -Encoding UTF8

        $result = Invoke-PrivacyAuditScript -Arguments @("-SetPrivate", "true", "-Files", $path, "-WhatIf")
        $after = Get-Content -Path $path -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Would set private=true'
        $after | Should Be $before
    }

    It "excludes exclude_from_ai files from handoff output" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/excluded.md" -Title "topic" -Body "topic paragraph" -ExtraFrontmatter @('exclude_from_ai: true') | Out-Null

        $result = Invoke-PrivacyHandoffScript -Arguments @("-Topic", "topic")

        $result.ExitCode | Should Be 0
        (Get-LatestHandoffContent) | Should Not Match 'excluded.md'
    }

    It "redacts named sections in handoff output while keeping the heading" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/redacted.md" -Title "topic" -Body @"
topic paragraph.

## Salary Details
Actual sensitive content.

## Public Details
Visible content.
"@ -ExtraFrontmatter @('redacted_sections: ["Salary Details"]') | Out-Null

        $result = Invoke-PrivacyHandoffScript -Arguments @("-Topic", "topic")
        $content = Get-LatestHandoffContent

        $result.ExitCode | Should Be 0
        $content | Should Match '## Salary Details'
        $content | Should Match '\[REDACTED\]'
        $content | Should Not Match 'Actual sensitive content'
    }

    It "still excludes private files from handoff output" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/private.md" -Title "topic" -Body "topic paragraph" -ExtraFrontmatter @('private: true') | Out-Null

        $result = Invoke-PrivacyHandoffScript -Arguments @("-Topic", "topic")

        $result.ExitCode | Should Be 0
        (Get-LatestHandoffContent) | Should Not Match 'private.md'
    }

    It "shows private indicator and suppresses preview in search results" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/private.md" -Title "topic title" -Body "topic body line one`nline two" -ExtraFrontmatter @('private: true') | Out-Null

        $result = Invoke-PrivacySearchScript -Arguments @("-Query", "topic", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match '\[PRIVATE\]'
        $result.Output | Should Match 'preview suppressed for private file'
        $result.Output | Should Not Match 'topic body line one'
    }

    It "leaves non-private search previews intact" {
        Initialize-PrivacyWorkspace
        New-PrivacyDocument -RelativePath "knowledge/wiki/public.md" -Title "topic title" -Body "topic body line one`nline two" | Out-Null

        $result = Invoke-PrivacySearchScript -Arguments @("-Query", "topic", "-Wiki")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'topic body line one'
    }
}
