<#
.SYNOPSIS
Runs Claude Code headlessly from a repo-local handoff prompt.

.DESCRIPTION
Reads a prompt from _bmad-output/agent-handoff/codex-to-claude.md, runs
Claude Code in non-interactive JSON mode, and writes both raw JSON and the
final text result back under _bmad-output/agent-handoff/.

The default tool set allows file/search/edit tools only. Use -AllowBash only
when the handoff explicitly requires Claude to run commands.
#>

[CmdletBinding()]
param(
    [string]$PromptFile = "_bmad-output/agent-handoff/codex-to-claude.md",
    [string]$ResultJson = "_bmad-output/agent-handoff/claude-result.json",
    [string]$ResultText = "_bmad-output/agent-handoff/claude-result.md",
    [string]$ClaudeCommand = "claude.cmd",
    [string]$AllowedTools = "Read,Write,Edit,MultiEdit,Glob,Grep,LS",
    [switch]$AllowBash,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if (-not (Test-Path -LiteralPath $PromptFile)) {
    throw "Prompt file not found: $PromptFile"
}

$prompt = Get-Content -LiteralPath $PromptFile -Raw
if ([string]::IsNullOrWhiteSpace($prompt)) {
    throw "Prompt file is empty: $PromptFile"
}

$resultDir = Split-Path -Parent $ResultJson
if ($resultDir -and -not (Test-Path -LiteralPath $resultDir)) {
    New-Item -ItemType Directory -Path $resultDir | Out-Null
}

$tools = $AllowedTools
if ($AllowBash -and $tools -notmatch "(^|,)Bash($|,)") {
    $tools = "$tools,Bash"
}

$claudeArgs = @(
    "-p",
    "--output-format", "json",
    "--allowedTools", $tools,
    "--permission-mode", "acceptEdits"
)

if ($DryRun) {
    Write-Host "Repo: $repoRoot"
    Write-Host "Command: $ClaudeCommand $($claudeArgs -join ' ')"
    Write-Host "Prompt file: $PromptFile"
    Write-Host "Result JSON: $ResultJson"
    Write-Host "Result text: $ResultText"
    return
}

$output = $prompt | & $ClaudeCommand @claudeArgs 2>&1
$exitCode = $LASTEXITCODE
$raw = ($output | Out-String).Trim()

Set-Content -LiteralPath $ResultJson -Value $raw -Encoding UTF8

try {
    $parsed = $raw | ConvertFrom-Json
    if ($parsed.result) {
        Set-Content -LiteralPath $ResultText -Value $parsed.result -Encoding UTF8
    }
    else {
        Set-Content -LiteralPath $ResultText -Value $raw -Encoding UTF8
    }
}
catch {
    Set-Content -LiteralPath $ResultText -Value $raw -Encoding UTF8
}

if ($exitCode -ne 0) {
    throw "Claude exited with code $exitCode. See $ResultJson"
}

Write-Host "Claude handoff complete."
Write-Host "Raw result: $ResultJson"
Write-Host "Text result: $ResultText"
