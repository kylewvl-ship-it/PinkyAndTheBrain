$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:RollbackScript = Join-Path $script:Root "scripts/rollback-import.ps1"
$script:PreviewScript = Join-Path $script:Root "scripts/import-preview.ps1"

# Compute once; keep "recent" within the 7-day recency gate for any test run date.
$script:NowUtc = (Get-Date).ToUniversalTime()
$script:RecentImportDate = $script:NowUtc.AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
$script:RecentImportId = "import-" + $script:NowUtc.AddHours(-1).ToString('yyyyMMdd-HHmmss')
$script:OldImportDate = $script:NowUtc.AddDays(-10).ToString('yyyy-MM-ddTHH:mm:ssZ')
$script:OldImportId = "import-" + $script:NowUtc.AddDays(-10).ToString('yyyyMMdd-HHmmss')

function Initialize-RollbackWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:SourceRoot = Join-Path $script:WorkRoot "source-vault"
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    $script:LogRoot = Join-Path $script:WorkRoot ".ai/import-logs"
    $script:RollbackLogRoot = Join-Path $script:WorkRoot ".ai/rollback-logs"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:SourceRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function Invoke-RollbackScript {
    param(
        [string[]]$Arguments = @(),
        [string]$InputText = $null
    )

    Push-Location $script:WorkRoot
    try {
        $argText = (($Arguments | ForEach-Object {
            $arg = [string]$_
            if ($arg -match '^-Confirm:') { return $arg }
            if ($arg -match '^-') { return $arg }
            return "'$($arg.Replace("'", "''"))'"
        }) -join ' ')
        $command = "& '$($script:RollbackScript.Replace("'", "''"))' $argText"
        if ($null -eq $InputText) {
            $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
        }
        else {
            $output = $InputText | & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
        }
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-PreviewScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:PreviewScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-ImportedFile {
    param(
        [string]$RelativePath,
        [string]$SourcePath,
        [string]$ImportId = $script:RecentImportId,
        [string]$ImportDate = $script:RecentImportDate,
        [string]$Body = "imported body",
        [switch]$NoFrontmatter
    )

    $targetPath = Join-Path $script:VaultRoot $RelativePath
    $directory = Split-Path $targetPath -Parent
    if (!(Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if ($NoFrontmatter) {
        Set-Content -Path $targetPath -Value $Body -Encoding UTF8
    }
    else {
        Set-Content -Path $targetPath -Value @"
---
imported_from: "$SourcePath"
import_date: "$ImportDate"
import_id: "$ImportId"
---
$Body
"@ -Encoding UTF8
    }

    (Get-Item -LiteralPath $targetPath).LastWriteTimeUtc = [datetime]::Parse($ImportDate).ToUniversalTime()
    return $targetPath
}

function New-SourceFile {
    param(
        [string]$RelativePath,
        [string]$Content = "source body"
    )

    $path = Join-Path $script:SourceRoot $RelativePath
    $directory = Split-Path $path -Parent
    if (!(Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

function New-ImportLog {
    param(
        [string]$ImportId = $script:RecentImportId,
        [string]$StartedAt = $script:RecentImportDate,
        [object[]]$Files
    )

    $path = Join-Path $script:LogRoot ("import-{0}.json" -f $ImportId)
    $log = [PSCustomObject]@{
        import_id = $ImportId
        started_at = $StartedAt
        finished_at = $StartedAt
        totals = [PSCustomObject]@{ copied = @($Files).Count; skipped = 0; renamed = 0; errors = 0; warnings = 0 }
        files = @($Files)
        status = "completed"
    }
    Set-Content -Path $path -Value ($log | ConvertTo-Json -Depth 8) -Encoding UTF8
    return $path
}

function New-LogEntry {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$Category = "wiki",
        [string]$Action = "copied",
        [string]$ContentHash = ""
    )

    $entry = [ordered]@{
        source_path = $SourcePath
        target_path = $TargetPath
        category = $Category
        action = $Action
        warnings = @()
        error = $null
    }
    if (![string]::IsNullOrWhiteSpace($ContentHash)) {
        $entry.content_hash = $ContentHash
    }
    return [PSCustomObject]$entry
}

function Get-LatestRollbackLog {
    if (!(Test-Path -LiteralPath $script:RollbackLogRoot)) { return $null }
    $file = Get-ChildItem -Path $script:RollbackLogRoot -Filter "rollback-*.json" -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if ($null -eq $file) { return $null }
    return Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe "rollback-import.ps1 - Story 5.5" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "rolls back matching imported files, prints a summary, and writes rollback logs" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "note.md"
        $target = New-ImportedFile -RelativePath "wiki\note.md" -SourcePath $source
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target)) | Out-Null

        $result = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force", "-Confirm:`$false")
        $log = Get-LatestRollbackLog

        $result.ExitCode | Should Be 0
        $result.Output | Should Match "Rollback summary"
        $result.Output | Should Match "Removed 1 files"
        Test-Path $target | Should Be $false
        $log.totals.removed | Should Be 1
        $log.files[0].action | Should Be "removed"
        Test-Path (Join-Path $script:RollbackLogRoot "$($log.rollback_id).md") | Should Be $true
    }

    It "never removes files without matching import_id provenance" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "manual.md"
        $target = New-ImportedFile -RelativePath "working\manual.md" -SourcePath $source -NoFrontmatter
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target -Category "working")) | Out-Null

        $result = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force", "-Confirm:`$false")
        $log = Get-LatestRollbackLog

        $result.ExitCode | Should Be 0
        Test-Path $target | Should Be $true
        $log.files[0].action | Should Be "skipped-not-matching"
    }

    It "rejects old imports unless -AllowOld is supplied" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "old.md"
        $target = New-ImportedFile -RelativePath "wiki\old.md" -SourcePath $source -ImportId $script:OldImportId -ImportDate $script:OldImportDate
        New-ImportLog -ImportId $script:OldImportId -StartedAt $script:OldImportDate -Files @((New-LogEntry -SourcePath $source -TargetPath $target)) | Out-Null

        $rejected = Invoke-RollbackScript -Arguments @("-ImportId", $script:OldImportId, "-Force", "-Confirm:`$false")
        $allowed = Invoke-RollbackScript -Arguments @("-ImportId", $script:OldImportId, "-AllowOld", "-OnModified", "remove", "-Force", "-Confirm:`$false")

        $rejected.ExitCode | Should Be 1
        $rejected.Output | Should Match "older than 7 days"
        Test-Path $target | Should Be $false
        $allowed.ExitCode | Should Be 0
    }

    It "enforces the confirmation gate and only skips it with -Force -Confirm:false together" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "confirm.md"
        $target = New-ImportedFile -RelativePath "wiki\confirm.md" -SourcePath $source
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target)) | Out-Null

        $aborted = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId)
        $aborted.ExitCode | Should Be 0
        Test-Path $target | Should Be $true  # no changes on abort

        $forceOnly = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force")
        $forceOnly.ExitCode | Should Be 0
        Test-Path $target | Should Be $true  # -Force alone must not delete

        $confirmed = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force", "-Confirm:`$false")
        $confirmed.ExitCode | Should Be 0
        Test-Path $target | Should Be $false
    }

    It "detects hash-modified files and honors -OnModified remove" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "hash.md"
        $target = New-ImportedFile -RelativePath "wiki\hash.md" -SourcePath $source
        $originalHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        Add-Content -Path $target -Value "changed" -Encoding UTF8
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target -ContentHash $originalHash)) | Out-Null

        $result = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-OnModified", "remove", "-Force", "-Confirm:`$false")
        $log = Get-LatestRollbackLog

        $result.ExitCode | Should Be 0
        Test-Path $target | Should Be $false
        $log.files[0].modified_since_import | Should Be $true
        $log.files[0].action | Should Be "removed"
    }

    It "detects timestamp-modified files and honors -OnModified keep" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "keep.md"
        $target = New-ImportedFile -RelativePath "wiki\keep.md" -SourcePath $source
        # Set LastWriteTime to after the recorded import date to trigger modification detection
        (Get-Item -LiteralPath $target).LastWriteTimeUtc = $script:NowUtc
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target)) | Out-Null

        $result = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-OnModified", "keep", "-Force", "-Confirm:`$false")
        $log = Get-LatestRollbackLog

        $result.ExitCode | Should Be 0
        Test-Path $target | Should Be $true
        $log.files[0].action | Should Be "kept"
        $log.files[0].modified_since_import | Should Be $true
    }

    It "backs up modified files with sidecar metadata when -OnModified backup is supplied" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "backup.md"
        $target = New-ImportedFile -RelativePath "raw\backup.md" -SourcePath $source
        # Set LastWriteTime to after the recorded import date to trigger modification detection
        (Get-Item -LiteralPath $target).LastWriteTimeUtc = $script:NowUtc
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target -Category "raw")) | Out-Null

        $result = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-OnModified", "backup", "-Force", "-Confirm:`$false")
        $log = Get-LatestRollbackLog
        $backupPath = Join-Path $script:WorkRoot ".ai/rollback-backups/$($log.rollback_id)/raw/backup.md"

        $result.ExitCode | Should Be 0
        Test-Path $target | Should Be $false
        Test-Path $backupPath | Should Be $true
        Test-Path "$backupPath.json" | Should Be $true
        $log.files[0].action | Should Be "backed-up"
    }

    It "is idempotent after the import log has a rollback field" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "again.md"
        $target = New-ImportedFile -RelativePath "wiki\again.md" -SourcePath $source
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target)) | Out-Null
        $first = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force", "-Confirm:`$false")
        $second = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force", "-Confirm:`$false")

        $first.ExitCode | Should Be 0
        $second.ExitCode | Should Be 0
        $second.Output | Should Match "already rolled back"
        @(Get-ChildItem -Path $script:RollbackLogRoot -Filter "rollback-*.json" -File).Count | Should Be 1
    }

    It "returns exit 1 for invalid id, missing log, malformed log, and invalid -OnModified" {
        Initialize-RollbackWorkspace
        $badId = Invoke-RollbackScript -Arguments @("-ImportId", "bad")
        $missing = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId)
        Set-Content -Path (Join-Path $script:LogRoot "import-$script:RecentImportId.json") -Value "{ not-json" -Encoding UTF8
        $malformed = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId)
        $invalidMode = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-OnModified", "delete")

        $badId.ExitCode | Should Be 1
        $missing.ExitCode | Should Be 1
        $malformed.ExitCode | Should Be 1
        $invalidMode.ExitCode | Should Be 1
    }

    It "refuses tampered logs whose target paths resolve outside knowledge folders" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "tampered.md"
        $outside = Join-Path $script:WorkRoot "outside.md"
        Set-Content -Path $outside -Value "outside" -Encoding UTF8
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $outside)) | Out-Null

        $result = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force", "-Confirm:`$false")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "outside configured knowledge folders"
        Test-Path $outside | Should Be $true
    }

    It "leaves rolled-back files absent so a retry preview starts from clean knowledge folders" {
        Initialize-RollbackWorkspace
        $source = New-SourceFile -RelativePath "Dup.md" -Content "duplicate words unique enough for overlap matching"
        $target = New-ImportedFile -RelativePath "wiki\dup.md" -SourcePath $source -Body "duplicate words unique enough for overlap matching"
        New-ImportLog -Files @((New-LogEntry -SourcePath $source -TargetPath $target)) | Out-Null

        $rollback = Invoke-RollbackScript -Arguments @("-ImportId", $script:RecentImportId, "-Force", "-Confirm:`$false")
        $preview = Invoke-PreviewScript -Arguments @("-SourceVault", $script:SourceRoot)

        $rollback.ExitCode | Should Be 0
        Test-Path $target | Should Be $false
        $preview.ExitCode | Should Be 0
    }
}
