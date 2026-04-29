[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"

if ($Help) {
    Show-Usage "test-offline-mode.ps1" "Verify offline/hook-free operation of all scripts" @(
        ".\scripts\test-offline-mode.ps1"
        ".\scripts\test-offline-mode.ps1 -Verbose"
        ".\scripts\test-offline-mode.ps1 -Fix"
    )
    exit 0
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptsDir = Join-Path $repoRoot "scripts"
$templatesDir = Join-Path $repoRoot "templates"
$configFile = Join-Path $repoRoot "config\pinky-config.yaml"

$findings = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-Finding {
    param([string]$Check, [string]$File, [string]$Detail)
    $script:findings.Add([PSCustomObject]@{
        Check  = $Check
        File   = $File
        Detail = $Detail
    })
    Write-Host "  [FINDING] ${File}: ${Detail}" -ForegroundColor Yellow
}

function Write-CheckHeader {
    param([string]$Name)
    Write-Host "`nCheck: $Name" -ForegroundColor Cyan
}

# ------------------------------------------------------------------
# Check 1: External tool dependency - integration scripts must guard
#          calls to optional CLIs with Get-Command checks
# ------------------------------------------------------------------
Write-CheckHeader "1 - External tool dependency"

$integrationChecks = @(
    @{ File = "invoke-claude-handoff.ps1"; CallPattern = '\$ClaudeCommand'; ToolName = 'claude' }
    @{ File = "invoke-codex-handoff.ps1";  CallPattern = '\$CodexCommand';  ToolName = 'codex'  }
    @{ File = "obsidian-sync.ps1";         CallPattern = '"obsidian-cli"';  ToolName = 'obsidian-cli' }
)

foreach ($entry in $integrationChecks) {
    $scriptPath = Join-Path $scriptsDir $entry.File
    if (-not (Test-Path $scriptPath)) {
        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Host "  SKIP (not found): $($entry.File)" -ForegroundColor Gray
        }
        continue
    }
    $content = Get-Content -Path $scriptPath -Raw
    $refsCallPattern = $content -match $entry.CallPattern
    if (-not $refsCallPattern) {
        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Host "  OK (no hard dependency): $($entry.File)" -ForegroundColor Green
        }
        continue
    }
    $hasGuard = $content -match 'Get-Command\s+\S+\s+-ErrorAction\s+SilentlyContinue'
    if (-not $hasGuard) {
        Add-Finding "external-tool-dependency" $entry.File "references '$($entry.ToolName)' without a Get-Command availability check"
    }
    elseif ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Host "  OK (guarded): $($entry.File)" -ForegroundColor Green
    }
}

# ------------------------------------------------------------------
# Check 2: Network call detection - flag unconditional network calls
# ------------------------------------------------------------------
Write-CheckHeader "2 - Network calls"

$networkPatterns = @(
    'Invoke-WebRequest',
    'Invoke-RestMethod',
    '\bcurl\b',
    '\bwget\b',
    '\[System\.Net\.WebClient\]',
    '\[System\.Net\.Http'
)

$psFiles = @(Get-ChildItem -Path $scriptsDir -Filter "*.ps1" -Recurse -File |
    Where-Object { $_.Name -ne "test-offline-mode.ps1" })

foreach ($file in $psFiles) {
    $lines = @(Get-Content -Path $file.FullName)
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*#') { continue }
        $hasNetCall = $false
        foreach ($pat in $networkPatterns) {
            if ($trimmed -match $pat) { $hasNetCall = $true; break }
        }
        if (-not $hasNetCall) { continue }
        $isGuarded = ($trimmed -match '-ErrorAction\s+SilentlyContinue') -or ($trimmed -match 'try\s*\{')
        if (-not $isGuarded) {
            Add-Finding "network-call" "$($file.Name):$lineNum" "unconditional network call: $trimmed"
        }
        elseif ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Host "  OK (guarded): $($file.Name):$lineNum" -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------------
# Check 3: PS 5.1 syntax
# ------------------------------------------------------------------
Write-CheckHeader "3 - PS 5.1 syntax"

$ps6Checks = @(
    @{ Pattern = '(?<![!<>=?])\?\?(?![>])'; Label = 'null-coalescing operator (PS6+ only)' }
    @{ Pattern = '\?\.';                     Label = 'null-conditional operator (PS6+ only)' }
    @{ Pattern = 'ForEach-Object\s+-Parallel'; Label = 'ForEach-Object -Parallel (PS6+ only)' }
    @{ Pattern = 'Get-Content\s+.*-AsByteStream'; Label = '-AsByteStream on Get-Content (PS6+ only)' }
    @{ Pattern = '(?<![|])\|\|(?![|])';      Label = 'pipeline chain OR operator (PS6+ only)' }
    @{ Pattern = '(?<![&])\&\&(?![&])';      Label = 'pipeline chain AND operator (PS6+ only)' }
)

foreach ($file in $psFiles) {
    $lines = @(Get-Content -Path $file.FullName)
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        $trimmed = $line.Trim()
        if ($trimmed -match '^\s*#') { continue }
        foreach ($chk in $ps6Checks) {
            if ($trimmed -match $chk.Pattern) {
                Add-Finding "ps51-syntax" "$($file.Name):$lineNum" "$($chk.Label): $trimmed"
            }
        }
    }
}

# ------------------------------------------------------------------
# Check 4: Template completeness
# ------------------------------------------------------------------
Write-CheckHeader "4 - Template completeness"

if (Test-Path $templatesDir) {
    $templates = @(Get-ChildItem -Path $templatesDir -Filter "*.md" -File)
    foreach ($tmpl in $templates) {
        $content = Get-Content -Path $tmpl.FullName -Raw
        if (-not ($content -match '(?s)^---\r?\n.*?\r?\n---')) {
            Add-Finding "template-completeness" $tmpl.Name "missing or malformed YAML frontmatter"
        }
        elseif ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Host "  OK: $($tmpl.Name)" -ForegroundColor Green
        }
    }
}
else {
    Add-Finding "template-completeness" "templates/" "templates directory not found at: $templatesDir"
}

# ------------------------------------------------------------------
# Check 5: Config portability - no absolute paths in path-like keys
# ------------------------------------------------------------------
Write-CheckHeader "5 - Config portability"

if (Test-Path $configFile) {
    $configLines = @(Get-Content -Path $configFile)
    $pathKeys = @('vault_root', 'script_root', 'template_root', 'handoffs', 'logs')
    $lineNum = 0
    foreach ($configLine in $configLines) {
        $lineNum++
        $trimmedLine = $configLine.Trim()
        if ($trimmedLine -match '^\s*#') { continue }
        foreach ($key in $pathKeys) {
            if ($trimmedLine -match "^\s*${key}\s*:" -and $trimmedLine -match '[A-Za-z]:\\') {
                Add-Finding "config-portability" "config/pinky-config.yaml:$lineNum" "absolute path in key '${key}': $trimmedLine"
            }
        }
    }
    if ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Host "  Config file checked for absolute paths." -ForegroundColor Green
    }
}
else {
    Add-Finding "config-portability" "config/pinky-config.yaml" "config file not found at: $configFile"
}

# ------------------------------------------------------------------
# Check 6 (Fix pass): Normalize absolute vault_root to relative
# ------------------------------------------------------------------
if ($Fix) {
    Write-CheckHeader "6 - Fix: normalizing absolute vault_root in config"
    if (Test-Path $configFile) {
        $configContent = Get-Content -Path $configFile -Raw
        $normalised = $configContent -replace '(?m)(^\s*vault_root\s*:\s*)[A-Za-z]:\\[^\r\n]*', '$1"./knowledge"'
        if ($normalised -ne $configContent) {
            Set-Content -Path $configFile -Value $normalised -Encoding UTF8
            Write-Host "  Fixed: vault_root normalised to relative path." -ForegroundColor Green
        }
        else {
            Write-Host "  No fix needed: vault_root already uses relative path." -ForegroundColor Green
        }
    }
    else {
        Write-Warning "Config file not found; nothing to fix."
    }
}

# ------------------------------------------------------------------
# Final report
# ------------------------------------------------------------------
Write-Host "`n--- Offline Mode Check Results ---" -ForegroundColor Cyan

if ($findings.Count -eq 0) {
    Write-Host "All checks passed. System is offline-ready." -ForegroundColor Green
    exit 0
}

$byCheck = $findings | Group-Object Check
foreach ($group in $byCheck) {
    Write-Host "`n[$($group.Name)] - $($group.Count) finding(s):" -ForegroundColor Red
    foreach ($f in $group.Group) {
        Write-Host "  $($f.File): $($f.Detail)" -ForegroundColor Yellow
    }
}
Write-Host "`nTotal findings: $($findings.Count)" -ForegroundColor Red
exit 1
