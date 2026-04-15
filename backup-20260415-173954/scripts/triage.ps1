param(
    [string]$File,
    [ValidateSet("raw", "working", "wiki", "archive", "delete", "inbox")]
    [string]$Disposition,
    [switch]$List
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$InboxDir = Join-Path $Root "knowledge/inbox"
$LogDir = Join-Path $Root "logs"

function Resolve-KnowledgePath {
    param([string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    $candidate = Join-Path $Root $PathValue
    if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    $inboxCandidate = Join-Path $InboxDir $PathValue
    if (Test-Path $inboxCandidate) { return (Resolve-Path $inboxCandidate).Path }
    return $candidate
}

try {
    if ($List) {
        Get-ChildItem -Path $InboxDir -Filter "*.md" -File | Sort-Object Name | ForEach-Object {
            Write-Host $_.FullName
        }
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($File) -or [string]::IsNullOrWhiteSpace($Disposition)) {
        throw "Provide -File and -Disposition, or use -List."
    }

    $source = Resolve-KnowledgePath $File
    if (-not (Test-Path $source)) { throw "File not found: $File" }

    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"

    if ($Disposition -eq "delete") {
        $targetDir = Join-Path $Root "knowledge/archive/deleted"
    }
    else {
        $targetDir = Join-Path $Root "knowledge/$Disposition"
    }
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    $target = Join-Path $targetDir (Split-Path -Leaf $source)
    if (Test-Path $target) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($target)
        $target = Join-Path $targetDir "$base-$((Get-Date).ToString('yyyyMMddHHmmss')).md"
    }

    Move-Item -LiteralPath $source -Destination $target
    Add-Content -Path (Join-Path $LogDir "triage.log") -Value "[$timestamp] $source -> $target ($Disposition)"
    Write-Host "Moved to $Disposition`: $target" -ForegroundColor Green
}
catch {
    Write-Error "Triage failed: $($_.Exception.Message)"
    exit 1
}

