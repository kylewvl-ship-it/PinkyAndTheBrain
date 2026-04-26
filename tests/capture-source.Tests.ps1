# Pester tests for non-AI source capture

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:CaptureSourceScript = Join-Path $script:Root "scripts/capture-source.ps1"
$script:TemplateRoot = Join-Path $script:Root "templates"

function Initialize-SourceCaptureWorkspace {
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

function Invoke-CaptureSourceScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:CaptureSourceScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Get-CapturedFiles {
    return @(Get-ChildItem -Path (Join-Path $script:VaultRoot "inbox") -Filter "*.md" -File | Sort-Object LastWriteTimeUtc)
}

function Get-CapturedContent {
    $file = Get-CapturedFiles | Select-Object -Last 1
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

Describe "capture-source.ps1 - Story 4.2" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_GIT_REPO_ROOT = $null
    }

    It "creates a web source file in knowledge/inbox" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "web", "-Url", "https://example.com", "-Title", "Article Title", "-Notes", "My summary")

        $result.ExitCode | Should Be 0
        (Get-CapturedFiles).Count | Should Be 1
        $result.Output | Should Match '\.md'
    }

    It "writes web source frontmatter" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "web", "-Url", "https://example.com", "-Title", "Article Title", "-Notes", "My summary")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'source_type: "web"'
        $content | Should Match 'source_url: "https://example\.com"'
        $content | Should Match 'source_title: "Article Title"'
        $content | Should Match 'captured_date: "\d{4}-\d{2}-\d{2}"'
        $content | Should Match 'review_status: "pending"'
    }

    It "places user notes in the My Notes section" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "web", "-Url", "https://example.com", "-Notes", "Only user notes")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match '## My Notes'
        $content | Should Match 'Only user notes'
        $content | Should Not Match '## Source Context'
        $content | Should Not Match 'URL: https://example\.com'
    }

    It "supports URL-only web capture" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "web", "-Url", "https://example.com")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'source_url: "https://example\.com"'
        $content | Should Match 'source_title: "unknown"'
        $content | Should Match '## My Notes'
    }

    It "captures book metadata" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "book", "-Title", "The Book", "-Author", "A Writer", "-SourceDate", "2026-04-01", "-Notes", "Book notes")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'source_type: "book"'
        $content | Should Match 'title: "The Book"'
        $content | Should Match 'author: "A Writer"'
        $content | Should Match 'source_date: "2026-04-01"'
        $content | Should Match 'captured_date: "\d{4}-\d{2}-\d{2}"'
    }

    It "captures meeting participants instead of author" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "meeting", "-Title", "Planning", "-Author", "Reno, Team", "-SourceDate", "2026-04-02")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'source_type: "meeting"'
        $content | Should Match 'participants: "Reno, Team"'
        $content | Should Not Match 'author:'
    }

    It "uses the configured inbox filename pattern" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "article", "-Title", "Pattern Check")
        $file = Get-CapturedFiles | Select-Object -Last 1

        $result.ExitCode | Should Be 0
        $file.Name | Should Match '^\d{4}-\d{2}-\d{2}-\d{9}-pattern-check\.md$'
    }

    It "defaults missing string fields to unknown" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "book")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'title: "unknown"'
        $content | Should Match 'author: "unknown"'
        $content | Should Match 'source_date: "unknown"'
    }

    It "writes private true when requested" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "idea", "-Title", "Sensitive", "-Private")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'private: true'
    }

    It "does not add generated summary content" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "video", "-Title", "Talk", "-Notes", "User supplied only")
        $content = Get-CapturedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'User supplied only'
        $content | Should Not Match 'Summary'
        $content | Should Not Match 'Generated'
    }

    It "fails with exit code 2 when the inbox folder is missing" {
        Initialize-SourceCaptureWorkspace
        Remove-Item -Path (Join-Path $script:VaultRoot "inbox") -Recurse -Force

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "web", "-Url", "https://example.com")

        $result.ExitCode | Should Be 2
        $result.Output | Should Match 'setup-system\.ps1'
    }

    It "fails with exit code 1 for invalid source type" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "podcast")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'web,book,meeting,video,article,idea'
    }

    It "supports WhatIf without writing a file" {
        Initialize-SourceCaptureWorkspace

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "web", "-Url", "https://example.com", "-WhatIf")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Would capture web source to'
        (Get-CapturedFiles).Count | Should Be 0
    }

    It "creates a git commit after successful capture" {
        Initialize-SourceCaptureWorkspace
        Initialize-GitRepo

        $result = Invoke-CaptureSourceScript -Arguments @("-SourceType", "article", "-Title", "Git Commit", "-Notes", "commit me")

        $result.ExitCode | Should Be 0
        Push-Location $script:WorkRoot
        try {
            $gitLog = & git log --oneline -1
        }
        finally {
            Pop-Location
        }
        ($gitLog | Out-String) | Should Match 'inbox: capture article source'
    }

    It "writes review_status pending for all capture types" {
        foreach ($type in @("web", "book", "meeting", "video", "article", "idea")) {
            Initialize-SourceCaptureWorkspace
            $arguments = @("-SourceType", $type)
            if ($type -eq "web") {
                $arguments += @("-Url", "https://example.com")
            }

            $result = Invoke-CaptureSourceScript -Arguments $arguments
            $content = Get-CapturedContent

            $result.ExitCode | Should Be 0
            $content | Should Match 'review_status: "pending"'
        }
    }
}
