#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ImportId = "",
    [switch]$AllowOld,
    [ValidateSet('prompt', 'remove', 'keep', 'backup')]
    [string]$OnModified = 'prompt',
    [switch]$Force,
    [bool]$Confirm = $true,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
. "$PSScriptRoot\lib\frontmatter.ps1"

function Get-RepoRoot {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (![string]::IsNullOrWhiteSpace($envRepoRoot)) {
        return [System.IO.Path]::GetFullPath($envRepoRoot)
    }

    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Show-RollbackImportHelp {
    Write-Host "rollback-import.ps1 - Roll back files created by a vault import"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\scripts\rollback-import.ps1 -ImportId import-20260428-120000"
    Write-Host "  .\scripts\rollback-import.ps1 -ImportId import-20260428-120000 -AllowOld"
    Write-Host "  .\scripts\rollback-import.ps1 -ImportId import-20260428-120000 -OnModified backup -Force -Confirm:`$false"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -AllowOld       Permit rollback of imports older than 7 days."
    Write-Host "  -OnModified     prompt|remove|keep|backup. Default: prompt."
    Write-Host "  -Force          With -Confirm:`$false, skip the literal YES prompt."
}

function Resolve-AbsolutePath {
    param(
        [string]$Path,
        [string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Get-RelativePathLocal {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = New-Object System.Uri($baseFullPath)
    $targetUri = New-Object System.Uri($targetFullPath)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('\', '/')
}

function Test-PathWithinRoot {
    param(
        [string]$RootPath,
        [string]$CandidatePath
    )

    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
    return $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-KnowledgeTargets {
    param([hashtable]$Config)

    $vaultRoot = [System.IO.Path]::GetFullPath([string]$Config.system.vault_root)
    return [ordered]@{
        inbox = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.inbox)
        raw = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.raw)
        working = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.working)
        wiki = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.wiki)
        archive = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.archive)
    }
}

function Get-KnowledgeCategory {
    param(
        [string]$Path,
        [hashtable]$Targets
    )

    foreach ($category in $Targets.Keys) {
        if (Test-PathWithinRoot -RootPath ([string]$Targets[$category]) -CandidatePath $Path) {
            return [string]$category
        }
    }

    return ""
}

function Test-PathWithinAnyKnowledgeFolder {
    param(
        [string]$Path,
        [hashtable]$Targets
    )

    return -not [string]::IsNullOrWhiteSpace((Get-KnowledgeCategory -Path $Path -Targets $Targets))
}

function Save-JsonArtifact {
    param(
        [string]$Path,
        [object]$Value
    )

    Set-Content -Path $Path -Value ($Value | ConvertTo-Json -Depth 12) -Encoding UTF8
}

function Get-Sha256ForFile {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RecordedHash {
    param([object]$Entry)

    foreach ($name in @('content_hash', 'sha256', 'target_sha256', 'source_sha256', 'hash')) {
        if ($Entry.PSObject.Properties.Name -contains $name) {
            $value = [string]$Entry.$name
            if (![string]::IsNullOrWhiteSpace($value)) {
                return $value.ToLowerInvariant()
            }
        }
    }

    return ""
}

function Get-ImportDate {
    param([object]$ImportLog)

    foreach ($name in @('finished_at', 'started_at', 'import_date', 'generated_at')) {
        if ($ImportLog.PSObject.Properties.Name -contains $name) {
            $value = [string]$ImportLog.$name
            if (![string]::IsNullOrWhiteSpace($value)) {
                return [datetime]::Parse($value).ToUniversalTime()
            }
        }
    }

    throw "Import log is missing an import date."
}

function New-RollbackArtifactPaths {
    param(
        [string]$LogRoot
    )

    $baseId = "rollback-{0}" -f ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $rollbackId = $baseId
        if ($attempt -gt 0) {
            $suffix = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Minimum 0 -Maximum 16) })
            $rollbackId = "{0}-{1}" -f $baseId, $suffix
        }

        $jsonPath = Join-Path $LogRoot ("{0}.json" -f $rollbackId)
        $markdownPath = Join-Path $LogRoot ("{0}.md" -f $rollbackId)
        if (!(Test-Path -LiteralPath $jsonPath) -and !(Test-Path -LiteralPath $markdownPath)) {
            $stream = $null
            try {
                $stream = [System.IO.File]::Open($jsonPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            }
            catch [System.IO.IOException] {
                continue
            }
            finally {
                if ($null -ne $stream) { $stream.Dispose() }
            }

            return [PSCustomObject]@{
                RollbackId = $rollbackId
                JsonPath = $jsonPath
                MarkdownPath = $markdownPath
            }
        }
    }

    throw "Unable to allocate a unique rollback id after repeated collision checks."
}

function New-FileRecord {
    param(
        [object]$Entry,
        [string]$TargetPath,
        [string]$Action,
        [bool]$ModifiedSinceImport,
        [string]$Reason,
        [string]$ErrorMessage
    )

    return [PSCustomObject]@{
        source_path = [string]$Entry.source_path
        target_path = $TargetPath
        action = $Action
        modified_since_import = $ModifiedSinceImport
        reason = $Reason
        error = $ErrorMessage
    }
}

function Get-MarkdownReport {
    param([object]$Log)

    $lines = @(
        "# Import Rollback Report",
        "",
        ('- Rollback ID: `{0}`' -f $Log.rollback_id),
        ('- Import ID: `{0}`' -f $Log.import_id),
        ('- Status: `{0}`' -f $Log.status),
        ('- Started: `{0}`' -f $Log.started_at),
        ('- Finished: `{0}`' -f $Log.finished_at),
        "",
        "## Totals",
        "",
        ("- Removed: {0}" -f $Log.totals.removed),
        ("- Kept: {0}" -f $Log.totals.kept),
        ("- Backed up: {0}" -f $Log.totals.backed_up),
        ("- Skipped: {0}" -f $Log.totals.skipped),
        ("- Errors: {0}" -f $Log.totals.errors),
        "",
        "## Files",
        ""
    )

    foreach ($entry in @($Log.files)) {
        $suffix = if ([string]::IsNullOrWhiteSpace([string]$entry.error)) { "" } else { " - $($entry.error)" }
        $lines += ('- `{0}` -> `{1}`: {2}{3}' -f $entry.source_path, $entry.target_path, $entry.action, $suffix)
    }

    return ($lines -join "`r`n")
}

function Test-ModifiedSinceImport {
    param(
        [string]$Path,
        [object]$Entry,
        [string]$Frontmatter,
        [datetime]$ImportDate
    )

    $recordedHash = Get-RecordedHash -Entry $Entry
    if (![string]::IsNullOrWhiteSpace($recordedHash)) {
        return @{
            Modified = ((Get-Sha256ForFile -Path $Path) -ne $recordedHash)
            Reason = 'content hash differs from import log'
        }
    }

    $frontmatterDate = Get-FrontmatterValue -Frontmatter $Frontmatter -Key 'import_date'
    $comparisonDate = $ImportDate
    if (![string]::IsNullOrWhiteSpace($frontmatterDate)) {
        $comparisonDate = [datetime]::Parse($frontmatterDate).ToUniversalTime()
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return @{
        Modified = ($item.LastWriteTimeUtc -gt $comparisonDate)
        Reason = 'last write time is later than import date'
    }
}

function Get-ModifiedDecision {
    param(
        [string]$Path,
        [string]$OnModified
    )

    if ($OnModified -ne 'prompt') {
        return $OnModified
    }

    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return 'keep'
    }

    $answer = Read-Host "Modified since import: $Path. Type remove, keep, or backup-and-remove"
    switch ($answer) {
        'remove' { return 'remove' }
        'keep' { return 'keep' }
        'backup-and-remove' { return 'backup' }
        default { return 'keep' }
    }
}

function Backup-ImportedFile {
    param(
        [string]$Path,
        [string]$RepoRoot,
        [hashtable]$Targets,
        [string]$RollbackId,
        [string]$Frontmatter
    )

    $category = Get-KnowledgeCategory -Path $Path -Targets $Targets
    $relative = Get-RelativePathLocal -BasePath ([string]$Targets[$category]) -TargetPath $Path
    $backupRelative = Join-Path $category $relative
    $backupRoot = Join-Path $RepoRoot ".ai/rollback-backups/$RollbackId"
    $backupPath = Join-Path $backupRoot $backupRelative
    $backupDirectory = Split-Path $backupPath -Parent
    if (!(Test-Path -LiteralPath $backupDirectory)) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    }

    Copy-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
    Save-JsonArtifact -Path ("{0}.json" -f $backupPath) -Value ([PSCustomObject]@{
        original_path = $Path
        original_frontmatter = $Frontmatter
    })
}

if ($Help) {
    Show-RollbackImportHelp
    exit 0
}

try {
    if ([string]::IsNullOrWhiteSpace($ImportId)) {
        Write-Host "ImportId is required. Use -ImportId import-<yyyyMMdd-HHmmss>[-suffix]." -ForegroundColor Red
        exit 1
    }
    if ($ImportId -notmatch '^import-\d{8}-\d{6}(-[A-Za-z0-9]+)?$') {
        Write-Host "Invalid ImportId format: $ImportId" -ForegroundColor Red
        exit 1
    }

    $repoRoot = Get-RepoRoot
    $config = Get-Config
    $targets = Get-KnowledgeTargets -Config $config
    $logRoot = Join-Path $repoRoot '.ai/import-logs'
    $rollbackLogRoot = Join-Path $repoRoot '.ai/rollback-logs'
    if (!(Test-Path -LiteralPath $rollbackLogRoot)) {
        New-Item -ItemType Directory -Path $rollbackLogRoot -Force | Out-Null
    }

    $importLogPath = Join-Path $logRoot ("import-{0}.json" -f $ImportId)
    if (!(Test-Path -LiteralPath $importLogPath -PathType Leaf)) {
        Write-Host "Import log not found: $importLogPath" -ForegroundColor Red
        exit 1
    }

    try {
        $importLog = Get-Content -LiteralPath $importLogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Host ("Import log is malformed JSON: {0}" -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }

    if ($null -eq $importLog -or @($importLog.PSObject.Properties.Name) -notcontains 'import_id' -or @($importLog.PSObject.Properties.Name) -notcontains 'files') {
        Write-Host "Import log is malformed: missing import_id or files." -ForegroundColor Red
        exit 1
    }
    if ([string]$importLog.import_id -ne $ImportId) {
        Write-Host "Import log import_id does not match requested ImportId." -ForegroundColor Red
        exit 1
    }
    if (@($importLog.PSObject.Properties.Name) -contains 'rollback' -and $null -ne $importLog.rollback) {
        Write-Host ("Import {0} already rolled back at {1} by {2}." -f $ImportId, $importLog.rollback.rolled_back_at, $importLog.rollback.rollback_id) -ForegroundColor Yellow
        exit 0
    }

    $importDate = Get-ImportDate -ImportLog $importLog
    if (!$AllowOld -and $importDate -lt (Get-Date).ToUniversalTime().AddDays(-7)) {
        Write-Host ("Import {0} is older than 7 days. Re-run with -AllowOld to roll it back." -f $ImportId) -ForegroundColor Red
        exit 1
    }

    $candidateEntries = @($importLog.files | Where-Object { [string]$_.action -in @('copied', 'renamed') })
    foreach ($entry in $candidateEntries) {
        $targetPath = Resolve-AbsolutePath -Path ([string]$entry.target_path) -BasePath $repoRoot
        if (!(Test-PathWithinAnyKnowledgeFolder -Path $targetPath -Targets $targets)) {
            Write-Host ("Refusing rollback because target path is outside configured knowledge folders: {0}" -f $targetPath) -ForegroundColor Red
            exit 1
        }
    }

    $summary = [ordered]@{}
    foreach ($category in $targets.Keys) { $summary[$category] = 0 }
    $totalSize = 0L
    foreach ($entry in $candidateEntries) {
        $targetPath = Resolve-AbsolutePath -Path ([string]$entry.target_path) -BasePath $repoRoot
        $category = Get-KnowledgeCategory -Path $targetPath -Targets $targets
        if (![string]::IsNullOrWhiteSpace($category)) { $summary[$category]++ }
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            $totalSize += (Get-Item -LiteralPath $targetPath).Length
        }
    }

    Write-Host ("Rollback summary for {0}" -f $ImportId) -ForegroundColor Cyan
    Write-Host ("Import date: {0}" -f $importDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))
    Write-Host ("Total size: {0} bytes" -f $totalSize)
    foreach ($category in $summary.Keys) {
        Write-Host ("{0}: {1}" -f $category, $summary[$category])
    }
    Write-Host "Files to inspect/remove:"
    foreach ($entry in $candidateEntries) {
        Write-Host ("- {0}" -f (Resolve-AbsolutePath -Path ([string]$entry.target_path) -BasePath $repoRoot))
    }

    $confirmSkipped = ($Force -and !$Confirm)
    if (!$confirmSkipped) {
        if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
            Write-Host "Rollback aborted: literal YES confirmation was not provided." -ForegroundColor Yellow
            exit 0
        }

        $confirmation = Read-Host "Type YES to remove matching imported files"
        if ($confirmation -ne 'YES') {
            Write-Host "Rollback aborted: confirmation did not match YES." -ForegroundColor Yellow
            exit 0
        }
    }

    $artifactPaths = New-RollbackArtifactPaths -LogRoot $rollbackLogRoot
    $rollbackId = $artifactPaths.RollbackId
    $startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $records = @()

    foreach ($entry in $candidateEntries) {
        $targetPath = Resolve-AbsolutePath -Path ([string]$entry.target_path) -BasePath $repoRoot
        $modified = $false
        $reason = ""
        try {
            if (!(Test-Path -LiteralPath $targetPath -PathType Leaf)) {
                $records += New-FileRecord -Entry $entry -TargetPath $targetPath -Action 'skipped-not-found' -ModifiedSinceImport $false -Reason 'target file was not found' -ErrorMessage $null
                continue
            }

            $content = Get-Content -LiteralPath $targetPath -Raw -Encoding UTF8
            $frontmatterData = Get-FrontmatterData -Content $content
            $frontmatter = if ($null -ne $frontmatterData) { [string]$frontmatterData.Frontmatter } else { "" }
            $frontImportId = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'import_id'
            $frontImportedFrom = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'imported_from'
            if ($frontImportId -ne $ImportId -or $frontImportedFrom -ne [string]$entry.source_path) {
                $records += New-FileRecord -Entry $entry -TargetPath $targetPath -Action 'skipped-not-matching' -ModifiedSinceImport $false -Reason 'frontmatter provenance did not match import log' -ErrorMessage $null
                continue
            }

            $modifiedResult = Test-ModifiedSinceImport -Path $targetPath -Entry $entry -Frontmatter $frontmatter -ImportDate $importDate
            $modified = [bool]$modifiedResult.Modified
            $reason = if ($modified) { [string]$modifiedResult.Reason } else { "" }
            $decision = if ($modified) { Get-ModifiedDecision -Path $targetPath -OnModified $OnModified } else { 'remove' }

            switch ($decision) {
                'keep' {
                    $records += New-FileRecord -Entry $entry -TargetPath $targetPath -Action 'kept' -ModifiedSinceImport $modified -Reason $reason -ErrorMessage $null
                }
                'backup' {
                    Backup-ImportedFile -Path $targetPath -RepoRoot $repoRoot -Targets $targets -RollbackId $rollbackId -Frontmatter $frontmatter
                    Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
                    $records += New-FileRecord -Entry $entry -TargetPath $targetPath -Action 'backed-up' -ModifiedSinceImport $modified -Reason $reason -ErrorMessage $null
                }
                default {
                    Remove-Item -LiteralPath $targetPath -Force -ErrorAction Stop
                    $records += New-FileRecord -Entry $entry -TargetPath $targetPath -Action 'removed' -ModifiedSinceImport $modified -Reason $reason -ErrorMessage $null
                }
            }
        }
        catch {
            $records += New-FileRecord -Entry $entry -TargetPath $targetPath -Action 'error' -ModifiedSinceImport $modified -Reason $reason -ErrorMessage $_.Exception.Message
        }
    }

    $finishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $totals = [ordered]@{
        removed = @($records | Where-Object { $_.action -eq 'removed' }).Count
        kept = @($records | Where-Object { $_.action -eq 'kept' }).Count
        backed_up = @($records | Where-Object { $_.action -eq 'backed-up' }).Count
        errors = @($records | Where-Object { $_.action -eq 'error' }).Count
        skipped = @($records | Where-Object { $_.action -like 'skipped-*' }).Count
    }
    $status = if ($totals.errors -gt 0) { 'completed-with-errors' } else { 'completed' }
    $rollbackLog = [PSCustomObject]@{
        rollback_id = $rollbackId
        import_id = $ImportId
        started_at = $startedAt
        finished_at = $finishedAt
        totals = [PSCustomObject]$totals
        files = @($records)
        status = $status
    }

    Save-JsonArtifact -Path $artifactPaths.JsonPath -Value $rollbackLog
    Set-Content -Path $artifactPaths.MarkdownPath -Value (Get-MarkdownReport -Log $rollbackLog) -Encoding UTF8

    # Only seal the import log as rolled back when there were no per-file errors.
    # A completed-with-errors run leaves the rollback field absent so the user
    # can retry after resolving the failing files.
    if ($totals.errors -eq 0) {
        $importLog | Add-Member -NotePropertyName rollback -NotePropertyValue ([PSCustomObject]@{
            rollback_id = $rollbackId
            rolled_back_at = $finishedAt
        }) -Force
        Save-JsonArtifact -Path $importLogPath -Value $importLog
    }

    Write-Host ("Removed {0} files imported on {1}" -f ($totals.removed + $totals.backed_up), $importDate.ToString('yyyy-MM-dd')) -ForegroundColor Green
    Write-Host ("Rollback JSON: {0}" -f $artifactPaths.JsonPath) -ForegroundColor Green
    Write-Host ("Rollback Report: {0}" -f $artifactPaths.MarkdownPath) -ForegroundColor Green

    if ($totals.errors -gt 0) { exit 3 }
    exit 0
}
catch {
    Write-Host ("Unexpected rollback failure: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 2
}
