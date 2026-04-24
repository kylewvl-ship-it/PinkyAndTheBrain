# Pester tests for AI conversation import

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:ImportScript = Join-Path $script:Root "scripts/import-conversation.ps1"
$script:TemplateRoot = Join-Path $script:Root "templates"

function Initialize-ImportWorkspace {
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

function Invoke-ImportScript {
    param(
        [string[]]$Arguments = @(),
        [string]$InputContent = ""
    )

    Push-Location $script:WorkRoot
    try {
        if ([string]::IsNullOrEmpty($InputContent)) {
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ImportScript @Arguments 2>&1
        }
        else {
            $output = $InputContent | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ImportScript @Arguments 2>&1
        }

        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-ConversationSource {
    param(
        [string]$FileName = "conversation.txt",
        [string]$Content
    )

    $path = Join-Path $script:WorkRoot $FileName
    $dir = Split-Path $path -Parent
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

function Get-ImportedFiles {
    return @(Get-ChildItem -Path (Join-Path $script:VaultRoot "raw") -Filter "*.md" -File | Sort-Object LastWriteTimeUtc)
}

function Get-ImportedContent {
    $file = Get-ImportedFiles | Select-Object -Last 1
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
        & git add . | Out-Null
        & git commit -m "baseline" | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe "import-conversation.ps1 - Story 4.1" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_TEMPLATE_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        $env:PINKY_GIT_REPO_ROOT = $null
    }

    It "imports a conversation file into knowledge/raw" {
        Initialize-ImportWorkspace
        $source = New-ConversationSource -Content "User: hello`nAssistant: hi"

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude")

        $result.ExitCode | Should Be 0
        (Get-ImportedFiles).Count | Should Be 1
    }

    It "uses the configured filename pattern and slugifies the service name" {
        Initialize-ImportWorkspace
        $source = New-ConversationSource -Content "User: hello"

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "Claude Desktop")
        $file = Get-ImportedFiles | Select-Object -Last 1

        $result.ExitCode | Should Be 0
        $file.Name | Should Match '^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-conversation-claude-desktop\.md$'
    }

    It "writes the required frontmatter fields" {
        Initialize-ImportWorkspace
        $source = New-ConversationSource -Content "User: hello"

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude", "-ConversationDate", "2026-04-20")
        $content = Get-ImportedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'conversation_date: "2026-04-20"'
        $content | Should Match 'ai_service: "claude"'
        $content | Should Match 'import_date: ".+?"'
        $content | Should Match 'import_method: "file"'
        $content | Should Match 'source_format: "text"'
        $content | Should Match 'review_status: "pending"'
    }

    It "leaves the source file unchanged after import" {
        Initialize-ImportWorkspace
        $sourceText = "User: hello`nAssistant: hi"
        $source = New-ConversationSource -Content $sourceText
        $before = Get-Content -Path $source -Raw -Encoding UTF8

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude")
        $after = Get-Content -Path $source -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $after | Should Be $before
    }

    It "detects markdown input" {
        Initialize-ImportWorkspace
        $source = New-ConversationSource -Content "---`ntitle: sample`n---`n`nConversation text"

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude")
        $content = Get-ImportedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'source_format: "markdown"'
    }

    It "detects json input and renders message turns" {
        Initialize-ImportWorkspace
        $json = '{"messages":[{"role":"user","content":"hello"},{"role":"assistant","content":"hi there"}]}'
        $source = New-ConversationSource -FileName "conversation.json" -Content $json

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "chatgpt")
        $content = Get-ImportedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'source_format: "json"'
        $content | Should Match '\*\*User:\*\*'
        $content | Should Match '\*\*Assistant:\*\*'
        $content | Should Match '---'
    }

    It "saves malformed json with import error notes instead of rejecting it" {
        Initialize-ImportWorkspace
        $source = New-ConversationSource -FileName "broken.json" -Content '{"messages": ['

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "chatgpt")
        $content = Get-ImportedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'import_errors: "true"'
        $content | Should Match '## Import Errors'
        $content | Should Match 'JSON parse error'
    }

    It "formats plain text role-prefixed turns and marks piped input as paste" {
        Initialize-ImportWorkspace
        $inputText = "Human: hello`nAssistant: hi"

        $result = Invoke-ImportScript -Arguments @("-Service", "claude") -InputContent $inputText
        $content = Get-ImportedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'import_method: "paste"'
        $content | Should Match '\*\*User:\*\*'
        $content | Should Match '\*\*Assistant:\*\*'
        $content | Should Match '---'
    }

    It "imports from the clipboard when no file or piped input is provided" {
        Initialize-ImportWorkspace
        $env:PINKY_FORCE_NONINTERACTIVE = $null
        Set-Clipboard -Value "User: clipboard hello`nAssistant: clipboard hi"

        $result = Invoke-ImportScript -Arguments @("-Service", "claude")
        $content = Get-ImportedContent

        $result.ExitCode | Should Be 0
        $content | Should Match 'import_method: "clipboard"'
        $content | Should Match 'clipboard hello'
    }

    It "preserves code blocks and urls in imported content" {
        Initialize-ImportWorkspace
        $body = @'
User: show me code
Assistant: use this
```powershell
Write-Host "hi"
```
https://example.com/docs
'@
        $source = New-ConversationSource -Content $body

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude")
        $content = Get-ImportedContent

        $result.ExitCode | Should Be 0
        $content | Should Match '```powershell'
        $content | Should Match 'https://example\.com/docs'
    }

    It "supports WhatIf without writing a file" {
        Initialize-ImportWorkspace
        $source = New-ConversationSource -Content "User: hello"

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude", "-WhatIf")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Would import conversation to'
        (Get-ImportedFiles).Count | Should Be 0
    }

    It "fails with exit code 2 when the raw folder is missing" {
        Initialize-ImportWorkspace
        Remove-Item -Path (Join-Path $script:VaultRoot "raw") -Recurse -Force
        $source = New-ConversationSource -Content "User: hello"

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude")

        $result.ExitCode | Should Be 2
        $result.Output | Should Match 'setup-system\.ps1'
    }

    It "fails with exit code 1 when the source file does not exist" {
        Initialize-ImportWorkspace

        $result = Invoke-ImportScript -Arguments @("-File", "missing.txt", "-Service", "claude")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'missing\.txt'
    }

    It "fails in non-interactive mode when no input source is provided" {
        Initialize-ImportWorkspace

        $result = Invoke-ImportScript -Arguments @("-Service", "claude")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'Provide -File or pipe content'
    }

    It "creates a git commit after a successful import" {
        Initialize-ImportWorkspace
        Initialize-GitRepo
        $source = New-ConversationSource -Content "User: hello"

        $result = Invoke-ImportScript -Arguments @("-File", $source, "-Service", "claude")

        $result.ExitCode | Should Be 0
        Push-Location $script:WorkRoot
        try {
            $gitLog = & git log --oneline -1
        }
        finally {
            Pop-Location
        }
        ($gitLog | Out-String) | Should Match 'raw: import conversation from claude'
    }
}
