param(
    [switch]$WriteIndexes
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$KnowledgeRoot = Join-Path $Root "knowledge"
$LogDir = Join-Path $Root "logs"

function Get-Title {
    param([System.IO.FileInfo]$File)
    $heading = Get-Content -Path $File.FullName | Where-Object { $_ -match '^#\s+' } | Select-Object -First 1
    if ($heading) { return ($heading -replace '^#\s+', '').Trim() }
    return $File.BaseName
}

try {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"

    $layerDirs = "inbox", "raw", "working", "wiki", "archive", "reviews"
    foreach ($layer in $layerDirs) {
        $dir = Join-Path $KnowledgeRoot $layer
        if (-not (Test-Path $dir)) { continue }
        $notes = Get-ChildItem -Path $dir -Filter "*.md" -File | Where-Object { $_.Name -ne "index.md" } | Sort-Object Name
        Write-Host ""
        Write-Host "[$layer] $($notes.Count) notes" -ForegroundColor Cyan
        foreach ($note in $notes) {
            Write-Host "- $(Get-Title $note) ($($note.Name))"
        }

        if ($WriteIndexes) {
            $lines = @("# $($layer.Substring(0,1).ToUpperInvariant())$($layer.Substring(1)) Index", "", "Generated: $timestamp", "")
            foreach ($note in $notes) {
                $title = Get-Title $note
                $lines += "- [$title](./$($note.Name))"
            }
            Set-Content -Path (Join-Path $dir "index.md") -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
        }
    }

    Add-Content -Path (Join-Path $LogDir "obsidian-sync.log") -Value "[$timestamp] sync completed WriteIndexes=$WriteIndexes"
}
catch {
    Write-Error "Obsidian sync failed: $($_.Exception.Message)"
    exit 1
}

