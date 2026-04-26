# Pester tests for source type configuration management

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:ManageScript = Join-Path $script:Root "scripts/manage-source-types.ps1"
$script:CaptureScript = Join-Path $script:Root "scripts/capture-source.ps1"

function Initialize-SourceTypeWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    $script:TemplateRoot = Join-Path $script:WorkRoot "templates"
    $script:ConfigDir = Join-Path $script:WorkRoot "config"
    $script:ConfigPath = Join-Path $script:ConfigDir "pinky-config.yaml"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:VaultRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TemplateRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null

    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }

    foreach ($templateName in @("source-web.md", "source-book.md", "source-meeting.md", "source-video.md", "source-article.md", "source-idea.md")) {
        Copy-Item -Path (Join-Path $script:Root ("templates\" + $templateName)) -Destination (Join-Path $script:TemplateRoot $templateName) -Force
    }

    $env:PINKY_CONFIG_PATH = $script:ConfigPath
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot

    @"
project: PinkyAndTheBrain
version: 0.2.0
runtime: powershell

system:
  vault_root: "$($script:VaultRoot -replace '\\','/')"
  script_root: "./scripts"
  template_root: "$($script:TemplateRoot -replace '\\','/')"

folders:
  inbox: "inbox"
  raw: "raw"
  working: "working"
  wiki: "wiki"
  archive: "archive"
  schemas: "schemas"
  reviews: "reviews"
  handoffs: ".ai/handoffs"
  logs: "logs"

file_naming:
  inbox_pattern: "YYYY-MM-DD-HHMMSSfff-{title}"
  conversation_pattern: "YYYY-MM-DD-HHMMSS-conversation-{service}"
  working_pattern: "{title}"
  wiki_pattern: "{title}"

review_cadence:
  inbox_days: 7
  working_days: 30
  wiki_days: 90

health_checks:
  stale_threshold_months: 6
  min_content_length: 100
  similarity_threshold: 3

ai_handoff:
  max_context_tokens: 3000
  max_wiki_tokens_per_page: 500
  exclude_private: true

projects:
  default_project: "general"
  create_subfolders: true

search:
  max_results: 20
  include_archived: false
  case_sensitive: false

privacy:
  private_excluded_from_handoffs: true
  do_not_promote_blocks_wiki: true

source_types:
  web:
    template: "$($script:TemplateRoot -replace '\\','/')/source-web.md"
  book:
    template: "$($script:TemplateRoot -replace '\\','/')/source-book.md"
  meeting:
    template: "$($script:TemplateRoot -replace '\\','/')/source-meeting.md"
  video:
    template: "$($script:TemplateRoot -replace '\\','/')/source-video.md"
  article:
    template: "$($script:TemplateRoot -replace '\\','/')/source-article.md"
  idea:
    template: "$($script:TemplateRoot -replace '\\','/')/source-idea.md"

limits:
  max_content_size: 10485760
"@ | Set-Content -Path $script:ConfigPath -Encoding UTF8
}

function Invoke-ManageScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ManageScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-CaptureScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:CaptureScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Get-InboxFiles {
    return @(Get-ChildItem -Path (Join-Path $script:VaultRoot "inbox") -Filter "*.md" -File | Sort-Object LastWriteTimeUtc)
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

function Add-SourceTypeBlockToConfig {
    param(
        [string]$Name,
        [string[]]$Lines
    )

    $content = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8
    $entry = ($Lines -join "`r`n") + "`r`n"
    $updated = [regex]::Replace($content, '(?m)^limits:\s*$', $entry + "limits:")
    Set-Content -Path $script:ConfigPath -Value $updated -Encoding UTF8
}

Describe "manage-source-types.ps1 - Story 4.3" {
    AfterEach {
    $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_CONFIG_PATH = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_GIT_REPO_ROOT = $null
    }

    It "lists the 6 MVP types" {
        Initialize-SourceTypeWorkspace

        $result = Invoke-ManageScript -Arguments @("-List")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'web'
        $result.Output | Should Match 'book'
        $result.Output | Should Match 'meeting'
        $result.Output | Should Match 'video'
        $result.Output | Should Match 'article'
        $result.Output | Should Match 'idea'
    }

    It "shows template existence in list output" {
        Initialize-SourceTypeWorkspace

        $result = Invoke-ManageScript -Arguments @("-List")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'YES'
    }

    It "adds a new type to config" {
        Initialize-SourceTypeWorkspace

        $result = Invoke-ManageScript -Arguments @("-Add", "-TypeName", "podcast", "-TemplatePath", "templates/source-podcast.md")
        $content = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $content | Should Match 'podcast:'
        $content | Should Match 'template: "templates/source-podcast\.md"'
    }

    It "rejects invalid type names" {
        Initialize-SourceTypeWorkspace

        $result = Invoke-ManageScript -Arguments @("-Add", "-TypeName", "Podcast!", "-TemplatePath", "templates/source-podcast.md")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'Invalid TypeName'
    }

    It "rejects add without required arguments" {
        Initialize-SourceTypeWorkspace

        $result = Invoke-ManageScript -Arguments @("-Add", "-TypeName", "podcast")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'requires both -TypeName and -TemplatePath'
    }

    It "supports WhatIf without modifying config" {
        Initialize-SourceTypeWorkspace
        $before = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8

        $result = Invoke-ManageScript -Arguments @("-Add", "-TypeName", "podcast", "-TemplatePath", "templates/source-podcast.md", "-WhatIf")
        $after = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Would add source type'
        $after | Should Be $before
    }

    It "creates a git commit after successful add" {
        Initialize-SourceTypeWorkspace
        Initialize-GitRepo

        $result = Invoke-ManageScript -Arguments @("-Add", "-TypeName", "podcast", "-TemplatePath", "templates/source-podcast.md")

        $result.ExitCode | Should Be 0
        Push-Location $script:WorkRoot
        try {
            $gitLog = & git log --oneline -1
        }
        finally {
            Pop-Location
        }
        ($gitLog | Out-String) | Should Match "config: add source type 'podcast'"
    }

    It "treats missing template files as warnings in validate mode" {
        Initialize-SourceTypeWorkspace
        Add-SourceTypeBlockToConfig -Name "podcast" -Lines @(
            "  podcast:"
            "    template: ""templates/source-podcast.md"""
        )

        $result = Invoke-ManageScript -Arguments @("-Validate")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'WARNING'
    }

    It "fails validate mode when template key is missing" {
        Initialize-SourceTypeWorkspace
        Add-SourceTypeBlockToConfig -Name "podcast" -Lines @(
            "  podcast:"
            "    notes: ""missing template"""
        )

        $result = Invoke-ManageScript -Arguments @("-Validate")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "missing 'template' key"
    }

    It "passes validate mode when all templates exist" {
        Initialize-SourceTypeWorkspace

        $result = Invoke-ManageScript -Arguments @("-Validate")

        $result.ExitCode | Should Be 0
    }

    It "makes added custom types immediately usable in capture-source" {
        Initialize-SourceTypeWorkspace
        $env:PINKY_FORCE_NONINTERACTIVE = "1"
        Set-Content -Path (Join-Path $script:TemplateRoot "source-podcast.md") -Value @"
---
source_type: "podcast"
title: "{{title}}"
captured_date: "{{captured_date}}"
review_status: "pending"
private: false
---

# Podcast: {{title}}

## My Notes

{{my_notes}}
"@ -Encoding UTF8

        $addResult = Invoke-ManageScript -Arguments @("-Add", "-TypeName", "podcast", "-TemplatePath", (Join-Path $script:TemplateRoot "source-podcast.md"))
        $captureResult = Invoke-CaptureScript -Arguments @("-SourceType", "podcast", "-Title", "Episode Title", "-Notes", "My notes")
        $content = Get-Content -Path (Get-InboxFiles | Select-Object -Last 1).FullName -Raw -Encoding UTF8

        $addResult.ExitCode | Should Be 0
        $captureResult.ExitCode | Should Be 0
        $content | Should Match 'source_type: "podcast"'
    }

    It "rejects types not present in config" {
        Initialize-SourceTypeWorkspace
        $env:PINKY_FORCE_NONINTERACTIVE = "1"

        $result = Invoke-CaptureScript -Arguments @("-SourceType", "unknown", "-Title", "Bad", "-Notes", "Nope")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'Valid types:'
    }

    It "falls back to the 6 defaults when source_types is absent" {
        Initialize-SourceTypeWorkspace
        $env:PINKY_FORCE_NONINTERACTIVE = "1"
        $content = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8
        $updated = [regex]::Replace($content, '(?ms)\r?\nsource_types:\r?\n(?:  .*\r?\n(?:    .*\r?\n)*)', "`r`n")
        Set-Content -Path $script:ConfigPath -Value $updated -Encoding UTF8

        $result = Invoke-CaptureScript -Arguments @("-SourceType", "web", "-Url", "https://example.com", "-Title", "Fallback", "-Notes", "works")

        $result.ExitCode | Should Be 0
    }

    It "keeps the 6 existing types working as a regression guard" {
        Initialize-SourceTypeWorkspace
        $env:PINKY_FORCE_NONINTERACTIVE = "1"

        foreach ($type in @("web", "book", "meeting", "video", "article", "idea")) {
            $arguments = @("-SourceType", $type, "-Title", "Regression", "-Notes", "ok")
            if ($type -eq "web") {
                $arguments += @("-Url", "https://example.com")
            }
            $result = Invoke-CaptureScript -Arguments $arguments
            $result.ExitCode | Should Be 0
        }
    }
}
