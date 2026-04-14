param(
    [Parameter(Mandatory=$true)]
    [string]$Query,
    [switch]$IncludeArchive,
    [int]$Context = 2
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$KnowledgeRoot = Join-Path $Root "knowledge"

try {
    $files = Get-ChildItem -Path $KnowledgeRoot -Recurse -Filter "*.md" -File
    if (-not $IncludeArchive) {
        $archivePath = (Join-Path $KnowledgeRoot "archive")
        $files = $files | Where-Object { -not $_.FullName.StartsWith($archivePath, [StringComparison]::OrdinalIgnoreCase) }
    }

    $matches = $files | Select-String -Pattern $Query -SimpleMatch -Context $Context
    if (-not $matches) {
        Write-Host "No matches found for '$Query'."
        Write-Host "Search miss checks: aliases, archived files (-IncludeArchive), raw/working layers, or alternate wording."
        exit 0
    }

    foreach ($match in $matches) {
        Write-Host ""
        Write-Host "$($match.Path):$($match.LineNumber)" -ForegroundColor Cyan
        if ($match.Context.PreContext) { $match.Context.PreContext | ForEach-Object { Write-Host "  $_" } }
        Write-Host "> $($match.Line)" -ForegroundColor Yellow
        if ($match.Context.PostContext) { $match.Context.PostContext | ForEach-Object { Write-Host "  $_" } }
    }
}
catch {
    Write-Error "Search failed: $($_.Exception.Message)"
    exit 1
}

