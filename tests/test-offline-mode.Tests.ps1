$script:Root       = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:OfflineScript = Join-Path $script:Root "scripts\test-offline-mode.ps1"

function Initialize-OfflineWorkspace {
    $script:WorkRoot    = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot   = Join-Path $script:WorkRoot "knowledge"
    $script:ScriptsDir  = Join-Path $script:WorkRoot "scripts"
    $script:TemplatesDir = Join-Path $script:WorkRoot "templates"
    $script:ConfigFile  = Join-Path $script:WorkRoot "config\pinky-config.yaml"
    $script:LibDir      = Join-Path $script:ScriptsDir "lib"

    foreach ($dir in @($script:VaultRoot, $script:ScriptsDir, $script:LibDir, $script:TemplatesDir,
                        (Split-Path $script:ConfigFile -Parent))) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT      = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT   = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"

    # Minimal common.ps1 stub so test-offline-mode.ps1 can dot-source it
    $commonStub = @'
function Get-Config { return @{ system = @{ vault_root = "./knowledge" }; folders = @{} } }
function Write-Log { param([string]$Message, [string]$Level = "INFO") }
function Show-Usage {
    param([string]$Script, [string]$Desc, [string[]]$Examples)
    Write-Host "Usage: $Script - $Desc"
}
'@
    Set-Content -Path (Join-Path $script:LibDir "common.ps1") -Value $commonStub -Encoding UTF8

    # Minimal config without absolute paths
    $configContent = @"
project: TestProject
system:
  vault_root: "./knowledge"
  script_root: "./scripts"
"@
    Set-Content -Path $script:ConfigFile -Value $configContent -Encoding UTF8

    # Copy the real test-offline-mode.ps1 but pointed at WorkRoot
    # We invoke it via powershell.exe with -File, so it resolves PSScriptRoot from WorkRoot\scripts
    Copy-Item -Path $script:OfflineScript -Destination (Join-Path $script:ScriptsDir "test-offline-mode.ps1")
}

function Invoke-OfflineScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $scriptPath = Join-Path $script:ScriptsDir "test-offline-mode.ps1"
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments 2>&1
        return @{
            Output   = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

Describe "test-offline-mode.Tests.ps1 - Story 6.3" {
    AfterEach {
        $env:PINKY_VAULT_ROOT              = $null
        $env:PINKY_GIT_REPO_ROOT           = $null
        $env:PINKY_FORCE_NONINTERACTIVE    = $null
    }

    # ------------------------------------------------------------------
    # 4.2 - obsidian-sync graceful degradation
    # ------------------------------------------------------------------
    It "obsidian-sync.ps1 contains Get-Command guard for obsidian-cli (Task 4.2)" {
        $syncScript = Join-Path $script:Root "scripts\obsidian-sync.ps1"
        $content = Get-Content -Path $syncScript -Raw
        $content | Should Match 'Get-Command\s+"obsidian-cli"'
    }

    # ------------------------------------------------------------------
    # 4.3 - invoke-codex-handoff graceful degradation
    # ------------------------------------------------------------------
    It "invoke-codex-handoff.ps1 exits 0 with warning when CodexCommand not on PATH (Task 4.3)" {
        $scriptPath = Join-Path $script:Root "scripts\invoke-codex-handoff.ps1"

        # Create a dummy prompt file
        $tmpDir  = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $promptFile = Join-Path $tmpDir "prompt.md"
        Set-Content -Path $promptFile -Value "test prompt" -Encoding UTF8
        $resultText = Join-Path $tmpDir "result.md"

        # Run with a CodexCommand that does not exist on PATH
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
            -PromptFile $promptFile -ResultText $resultText -CodexCommand "nonexistent-codex-tool-xyz.cmd" 2>&1
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        ($output | Out-String) | Should Match "not found on PATH|integration unavailable"
    }

    # ------------------------------------------------------------------
    # 4.4 - invoke-claude-handoff graceful degradation
    # ------------------------------------------------------------------
    It "invoke-claude-handoff.ps1 exits 0 with warning when ClaudeCommand not on PATH (Task 4.4)" {
        $scriptPath = Join-Path $script:Root "scripts\invoke-claude-handoff.ps1"

        $tmpDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
        $promptFile = Join-Path $tmpDir "prompt.md"
        Set-Content -Path $promptFile -Value "test prompt" -Encoding UTF8
        $resultJson = Join-Path $tmpDir "result.json"
        $resultText = Join-Path $tmpDir "result.md"

        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
            -PromptFile $promptFile -ResultJson $resultJson -ResultText $resultText `
            -ClaudeCommand "nonexistent-claude-tool-xyz.cmd" 2>&1
        $exitCode = $LASTEXITCODE

        $exitCode | Should Be 0
        ($output | Out-String) | Should Match "not found on PATH|integration unavailable"
    }

    # ------------------------------------------------------------------
    # 4.5 - network call detection: synthetic unconditional Invoke-WebRequest
    # ------------------------------------------------------------------
    It "reports unconditional Invoke-WebRequest as a network-call finding (Task 4.5)" {
        Initialize-OfflineWorkspace

        $badScript = @'
Set-StrictMode -Version Latest
Invoke-WebRequest -Uri "http://example.com" -OutFile "out.txt"
'@
        Set-Content -Path (Join-Path $script:ScriptsDir "bad-network.ps1") -Value $badScript -Encoding UTF8

        $result = Invoke-OfflineScript
        $result.ExitCode | Should Be 1
        $result.Output | Should Match "network-call"
        $result.Output | Should Match "bad-network.ps1"
    }

    # ------------------------------------------------------------------
    # 4.6 - clean repo passes with exit 0
    # ------------------------------------------------------------------
    It "clean repo with no findings exits 0 (Task 4.6)" {
        Initialize-OfflineWorkspace

        # Add a valid template
        $tmplContent = @"
---
type: test
---
# Test Template
"@
        Set-Content -Path (Join-Path $script:TemplatesDir "test.md") -Value $tmplContent -Encoding UTF8

        $result = Invoke-OfflineScript
        $result.ExitCode | Should Be 0
        $result.Output | Should Match "All checks passed"
    }

    # ------------------------------------------------------------------
    # 4.7 - PS 5.1 syntax: ?? operator flagged
    # ------------------------------------------------------------------
    It "reports null-coalescing ?? as a ps51-syntax finding (Task 4.7)" {
        Initialize-OfflineWorkspace

        $badScript = @'
Set-StrictMode -Version Latest
$x = $null
$y = $x ?? "default"
'@
        Set-Content -Path (Join-Path $script:ScriptsDir "bad-syntax.ps1") -Value $badScript -Encoding UTF8

        $result = Invoke-OfflineScript
        $result.ExitCode | Should Be 1
        $result.Output | Should Match "ps51-syntax"
        $result.Output | Should Match "bad-syntax.ps1"
    }

    # ------------------------------------------------------------------
    # 4.8 - Config portability: absolute vault_root flagged
    # ------------------------------------------------------------------
    It "reports absolute vault_root path as a config-portability finding (Task 4.8)" {
        Initialize-OfflineWorkspace

        $absoluteConfig = @"
project: TestProject
system:
  vault_root: "C:\Users\test\vault"
  script_root: "./scripts"
"@
        Set-Content -Path $script:ConfigFile -Value $absoluteConfig -Encoding UTF8

        $result = Invoke-OfflineScript
        $result.ExitCode | Should Be 1
        $result.Output | Should Match "config-portability"
        $result.Output | Should Match "vault_root"
    }
}
