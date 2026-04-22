#!/usr/bin/env pwsh
# PinkyAndTheBrain Configuration Validator
# Checks config/pinky-config.yaml for syntax and value errors.

param(
    [string]$ConfigPath = "config/pinky-config.yaml",
    [switch]$Fix,
    [switch]$Help
)

if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"

if (!(Test-Path "$PSScriptRoot/lib/config-loader.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/config-loader.ps1"
    exit 2
}
. "$PSScriptRoot/lib/config-loader.ps1"

if ($Help) {
    Show-Usage "validate-config.ps1" "Validate PinkyAndTheBrain configuration file" @(
        ".\scripts\validate-config.ps1"
        ".\scripts\validate-config.ps1 -ConfigPath config/pinky-config.yaml"
        ".\scripts\validate-config.ps1 -Fix"
    )
    exit 0
}

Write-Host "`nPinkyAndTheBrain Configuration Validator" -ForegroundColor Cyan
Write-Host "Validating: $ConfigPath`n" -ForegroundColor Gray

$allErrors = @()
$warnings = @()

# Check file exists
if (!(Test-Path $ConfigPath)) {
    Write-Host "✗ Config file not found: $ConfigPath" -ForegroundColor Red
    if ($Fix) {
        Initialize-Config -ConfigPath $ConfigPath
        Write-Host "✓ Created default config at: $ConfigPath" -ForegroundColor Green
        exit 0
    }
    Write-Host "  Run with -Fix to create a default configuration." -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Config file exists" -ForegroundColor Green

# Parse YAML
$parsed = $null
try {
    $parsed = Read-YamlConfig -Path $ConfigPath
    if ($null -eq $parsed -or $parsed.Count -eq 0) {
        $allErrors += "Config file is empty or could not be parsed"
    }
    else {
        Write-Host "✓ YAML syntax is valid" -ForegroundColor Green
    }
}
catch {
    $allErrors += "YAML parse error: $($_.Exception.Message)"
    Write-Host "✗ YAML syntax error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($parsed) {
    # Merge with defaults for full validation
    $config = Merge-Config -Defaults (Get-DefaultConfig) -Overrides $parsed

    # Check required sections
    $requiredSections = @('system', 'folders', 'file_naming', 'review_cadence', 'health_checks', 'ai_handoff', 'projects', 'search')
    foreach ($sec in $requiredSections) {
        if (!$config.ContainsKey($sec) -or $config[$sec] -isnot [hashtable]) {
            $allErrors += "Missing required section: $sec"
            Write-Host "✗ Missing section: $sec" -ForegroundColor Red
        }
        else {
            Write-Host "✓ Section present: $sec" -ForegroundColor Green
        }
    }

    # Validate values
    $valueErrors = Test-ConfigValues -Config $config
    foreach ($err in $valueErrors) {
        $allErrors += $err
        Write-Host "✗ $err" -ForegroundColor Red
    }
    if ($valueErrors.Count -eq 0) {
        Write-Host "✓ All values are within valid ranges" -ForegroundColor Green
    }

    # Validate paths (warn only — they may not exist yet)
    $pathErrors = Test-ConfigPaths -Config $config
    foreach ($err in $pathErrors) {
        $warnings += $err
        Write-Host "⚠ $err" -ForegroundColor Yellow
    }
    if ($pathErrors.Count -eq 0) {
        Write-Host "✓ All configured paths exist" -ForegroundColor Green
    }
}

# Summary
Write-Host ""
if ($allErrors.Count -eq 0) {
    Write-Host "✅ Configuration is valid" -ForegroundColor Green
    if ($warnings.Count -gt 0) {
        Write-Host "   ($($warnings.Count) warning(s) — paths may need to be created)" -ForegroundColor Yellow
    }
    exit 0
}
else {
    Write-Host "❌ Configuration has $($allErrors.Count) error(s)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Errors found:" -ForegroundColor Red
    foreach ($err in $allErrors) { Write-Host "  • $err" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Fix errors manually, or run with -Fix to reset to defaults." -ForegroundColor Yellow
    exit 1
}
