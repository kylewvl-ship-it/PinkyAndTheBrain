param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LogDir = Join-Path $Root "logs"
$LogPath = Join-Path $LogDir "setup.log"

function Write-Log {
    param([string]$Message)
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Add-Content -Path $LogPath -Value "[$(Get-Date -Format o)] $Message"
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Log "Created directory $Path"
    }
}

function Ensure-File {
    param(
        [string]$Path,
        [string]$Content
    )
    if ((Test-Path $Path) -and -not $Force) {
        Write-Log "Skipped existing file $Path"
        return
    }
    $parent = Split-Path -Parent $Path
    if ($parent) { Ensure-Directory $parent }
    Set-Content -Path $Path -Value $Content -Encoding UTF8
    Write-Log "Wrote file $Path"
}

try {
    Write-Log "Setup started"

    $requiredDirs = @(
        "knowledge/inbox", "knowledge/raw", "knowledge/working", "knowledge/wiki",
        "knowledge/schemas", "knowledge/archive", "knowledge/reviews",
        "scripts", "templates", ".ai/handoffs", ".ai/policies", "config", "logs", "backups", "quarantine"
    )

    foreach ($dir in $requiredDirs) {
        Ensure-Directory (Join-Path $Root $dir)
    }

    $indexFiles = @{
        "knowledge/inbox/index.md" = "# Inbox`n`nLow-friction capture area for new items awaiting triage.`n"
        "knowledge/raw/index.md" = "# Raw`n`nPreserved source material before interpretation.`n"
        "knowledge/working/index.md" = "# Working`n`nActive thinking, synthesis, contradictions, and open questions.`n"
        "knowledge/wiki/index.md" = "# Wiki`n`nDurable, sourced knowledge promoted after review.`n"
        "knowledge/archive/index.md" = "# Archive`n`nRetired or low-confidence material excluded from default retrieval.`n"
        "knowledge/reviews/index.md" = "# Reviews`n`nHealth reports and repair decisions.`n"
        "knowledge/schemas/index.md" = "# Schemas`n`nHuman-readable metadata contracts and templates.`n"
    }

    foreach ($path in $indexFiles.Keys) {
        Ensure-File -Path (Join-Path $Root $path) -Content $indexFiles[$path]
    }

    if (-not (Test-Path (Join-Path $Root "config/pinky-config.yaml"))) {
        Write-Warning "config/pinky-config.yaml is missing. Restore it from version control or create it before running automation."
    }

    Write-Host "PinkyAndTheBrain setup complete." -ForegroundColor Green
    Write-Log "Setup completed successfully"
    exit 0
}
catch {
    Write-Error "Setup failed: $($_.Exception.Message)"
    Write-Log "Setup failed: $($_.Exception.Message)"
    exit 1
}

