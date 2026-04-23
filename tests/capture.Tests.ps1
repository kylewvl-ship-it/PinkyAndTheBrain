# Pester tests for capture.ps1

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:Script = Join-Path $script:Root "scripts/capture.ps1"
$script:Templates = Join-Path $script:Root "templates"

function Initialize-CaptureWorkspace {
    param(
        [switch]$WithoutInbox,
        [int]$MaxContentSize = 0
    )

    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null

    foreach ($folder in @("raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }
    if (!$WithoutInbox) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot "inbox") -Force | Out-Null
    }

    if ($MaxContentSize -gt 0) {
        New-Item -ItemType Directory -Path (Join-Path $script:WorkRoot "config") -Force | Out-Null
        @"
limits:
  max_content_size: $MaxContentSize
"@ | Set-Content -Path (Join-Path $script:WorkRoot "config/pinky-config.yaml") -Encoding UTF8
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_TEMPLATE_ROOT = $script:Templates
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function Invoke-Capture {
    param([string[]]$Arguments)

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

function Get-InboxFiles {
    $inbox = Join-Path $script:VaultRoot "inbox"
    return @(Get-ChildItem $inbox -Filter "*.md" -ErrorAction SilentlyContinue)
}

Describe "Get-TimestampedFilename" {
    It "uses millisecond-precision inbox filenames" {
        . (Join-Path $script:Root "scripts/lib/common.ps1")
        $name = Get-TimestampedFilename -Title "My Note" -Pattern "YYYY-MM-DD-HHMMSSfff-{title}"
        $name | Should Match '^\d{4}-\d{2}-\d{2}-\d{9}-my-note\.md$'
    }
}

Describe "capture.ps1 - Story 1.1 quick capture" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "creates unique inbox files for rapid manual captures" {
        Initialize-CaptureWorkspace
        $first = Invoke-Capture -Arguments @("-Type", "manual", "-Title", "Rapid Note", "-Content", "first")
        $second = Invoke-Capture -Arguments @("-Type", "manual", "-Title", "Rapid Note", "-Content", "second")

        $first.ExitCode | Should Be 0
        $second.ExitCode | Should Be 0
        $files = Get-InboxFiles
        $files.Count | Should Be 2
        ($files[0].Name -ne $files[1].Name) | Should Be $true
    }

    It "returns code 2 and setup guidance when inbox is missing" {
        Initialize-CaptureWorkspace -WithoutInbox
        $result = Invoke-Capture -Arguments @("-Type", "manual", "-Title", "Missing Inbox", "-Content", "content")

        $result.ExitCode | Should Be 2
        $result.Output | Should Match "setup-system.ps1"
    }

    It "writes web source metadata and source context" {
        Initialize-CaptureWorkspace
        $result = Invoke-Capture -Arguments @("-Type", "web", "-Title", "Article", "-Url", "https://example.com", "-Content", "My notes")

        $result.ExitCode | Should Be 0
        $file = (Get-InboxFiles)[0].FullName
        $content = Get-Content $file -Raw
        $content | Should Match 'source_url: "https://example.com"'
        $content | Should Match 'source_title: "Article"'
        $content | Should Match 'source_type: "web"'
        $content | Should Match "## Source Context"
        $content | Should Match "https://example.com"
    }

    It "captures piped stdin instead of the Content parameter" {
        Initialize-CaptureWorkspace
        Push-Location $script:WorkRoot
        try {
            $output = "piped body" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Script -Type manual -Title "Piped Note" -Content "ignored body" 2>&1
            $LASTEXITCODE | Should Be 0
        }
        finally {
            Pop-Location
        }

        $file = (Get-InboxFiles)[0].FullName
        $content = Get-Content $file -Raw
        $content | Should Match "piped body"
        $content | Should Not Match "ignored body"
    }

    It "logs and exits code 1 for oversized content in non-interactive mode" {
        Initialize-CaptureWorkspace -MaxContentSize 200
        $result = Invoke-Capture -Arguments @("-Type", "manual", "-Title", "Oversized", "-Content", ("x" * 500))

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "exceeds limit"
        $log = Get-Content (Join-Path $script:WorkRoot "logs/script-errors.log") -Raw
        $log | Should Match "Oversized capture attempt"
    }

    It "uses exclusive sidecar locks for capture writes" {
        $scriptText = Get-Content $script:Script -Raw
        $scriptText | Should Match "FileMode]::CreateNew"
        $scriptText | Should Match "FileShare]::None"
        $scriptText | Should Match "Remove-Item.*lockPath"
    }
}
