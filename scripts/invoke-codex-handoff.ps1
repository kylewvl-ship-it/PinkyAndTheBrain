<#
.SYNOPSIS
Runs Codex CLI non-interactively from a repo-local handoff prompt.

.DESCRIPTION
Reads a prompt from _bmad-output/agent-handoff/claude-to-codex.md and runs
Codex CLI in either exec or review mode. Writes the final assistant message
and raw CLI output back under _bmad-output/agent-handoff/.

This is intended as a file-based bridge where Claude orchestrates and Codex
performs repo-grounded implementation or review work.
#>

[CmdletBinding()]
param(
    [string]$PromptFile = "_bmad-output/agent-handoff/claude-to-codex.md",
    [string]$ResultText = "_bmad-output/agent-handoff/codex-result.md",
    [string]$ResultRaw = "_bmad-output/agent-handoff/codex-result.log",
    [string]$CodexCommand = "codex.cmd",
    [switch]$Review,
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

$resultDir = Split-Path -Parent $ResultText
if ($resultDir -and -not (Test-Path -LiteralPath $resultDir)) {
    New-Item -ItemType Directory -Path $resultDir | Out-Null
}

if ($Review) {
    $codexArgs = @(
        "review",
        "--uncommitted",
        "-"
    )
}
else {
    $codexArgs = @(
        "exec",
        "--full-auto",
        "--output-last-message", $ResultText,
        "-"
    )
}

if ($DryRun) {
    Write-Host "Repo: $repoRoot"
    Write-Host "Command: $CodexCommand $($codexArgs -join ' ')"
    Write-Host "Prompt file: $PromptFile"
    Write-Host "Result text: $ResultText"
    Write-Host "Raw log: $ResultRaw"
    return
}

$output = $prompt | & $CodexCommand @codexArgs 2>&1
$exitCode = $LASTEXITCODE
$raw = ($output | Out-String).Trim()

Set-Content -LiteralPath $ResultRaw -Value $raw -Encoding UTF8

if ($Review) {
    Set-Content -LiteralPath $ResultText -Value $raw -Encoding UTF8
}
elseif (-not (Test-Path -LiteralPath $ResultText)) {
    Set-Content -LiteralPath $ResultText -Value $raw -Encoding UTF8
}

if ($exitCode -ne 0) {
    throw "Codex exited with code $exitCode. See $ResultRaw"
}

Write-Host "Codex handoff complete."
Write-Host "Text result: $ResultText"
Write-Host "Raw log: $ResultRaw"
