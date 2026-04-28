$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:ImportScript = Join-Path $script:Root "scripts/execute-import.ps1"

function Initialize-ExecuteImportWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:SourceRoot = Join-Path $script:WorkRoot "source-vault"
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    $script:PreviewRoot = Join-Path $script:WorkRoot ".ai/import-previews"
    $script:LogRoot = Join-Path $script:WorkRoot ".ai/import-logs"
    $script:RunRoot = Join-Path $script:WorkRoot ".ai/import-runs"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:SourceRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }
    foreach ($folder in @($script:PreviewRoot, $script:LogRoot, $script:RunRoot)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function Invoke-ExecuteImportScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ImportScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-SourceMarkdown {
    param(
        [string]$RelativePath,
        [string]$Content
    )

    $path = Join-Path $script:SourceRoot $RelativePath
    $directory = Split-Path $path -Parent
    if (!(Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

function New-PreviewFile {
    param(
        [object[]]$Files,
        [object[]]$MappingRules = @(),
        [string]$SourceVault = $script:SourceRoot
    )

    $path = Join-Path $script:PreviewRoot ("import-preview-{0}.json" -f ([guid]::NewGuid().ToString()))
    $preview = [PSCustomObject]@{
        generated_at = "2026-04-28T13:00:00Z"
        source_vault = $SourceVault
        summary = [PSCustomObject]@{
            total_files = @($Files).Count
            total_bytes = 0
            estimated_import_seconds = 1
        }
        category_counts = [PSCustomObject]@{}
        files = @($Files)
        duplicates = @()
        unclassified = @()
        errors = @()
        mapping_rules = @($MappingRules)
    }

    Set-Content -Path $path -Value ($preview | ConvertTo-Json -Depth 8) -Encoding UTF8
    return $path
}

function Get-TestFingerprint {
    param([string]$PreviewPath)

    $previewContent = Get-Content -LiteralPath $PreviewPath -Raw -Encoding UTF8
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($previewContent))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }

    return [PSCustomObject]@{
        preview_sha256 = $hash
        source_vault = [System.IO.Path]::GetFullPath($script:SourceRoot)
        knowledge_folders = [PSCustomObject]@{
            inbox = [System.IO.Path]::Combine($script:VaultRoot, "inbox")
            raw = [System.IO.Path]::Combine($script:VaultRoot, "raw")
            working = [System.IO.Path]::Combine($script:VaultRoot, "working")
            wiki = [System.IO.Path]::Combine($script:VaultRoot, "wiki")
            archive = [System.IO.Path]::Combine($script:VaultRoot, "archive")
        }
    }
}

function New-PreviewEntry {
    param(
        [string]$RelativePath,
        [string]$Category
    )

    $sourcePath = Join-Path $script:SourceRoot $RelativePath
    return [PSCustomObject]@{
        source_path = $sourcePath
        relative_path = $RelativePath.Replace('\', '/')
        title = [System.IO.Path]::GetFileNameWithoutExtension($RelativePath)
        proposed_category = $Category
        classification_reasons = @("test")
        size_bytes = 0
        link_count = 0
        word_count = 0
        project = @()
        domain = @()
        shared = ""
    }
}

function Get-LatestImportLog {
    $file = Get-ChildItem -Path $script:LogRoot -Filter "import-*.json" -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if ($null -eq $file) {
        return $null
    }

    return Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-LatestImportMarkdownPath {
    $file = Get-ChildItem -Path $script:LogRoot -Filter "import-*.md" -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if ($null -eq $file) {
        return ""
    }

    return $file.FullName
}

function Get-LatestRunState {
    $file = Get-ChildItem -Path $script:RunRoot -Filter "import-*.json" -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if ($null -eq $file) {
        return $null
    }

    return Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe "execute-import.ps1 - Story 5.4" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "fails with exit code 1 for an invalid preview file" {
        Initialize-ExecuteImportWorkspace

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", "missing.json")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "Preview file does not exist"
    }

    It "fails with exit code 1 for malformed preview JSON" {
        Initialize-ExecuteImportWorkspace
        $previewPath = Join-Path $script:PreviewRoot "malformed.json"
        Set-Content -Path $previewPath -Value "{ not-json" -Encoding UTF8

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "not valid JSON"
        (Get-ChildItem -Path $script:VaultRoot -Recurse -Filter "*.md" -File).Count | Should Be 0
    }

    It "fails with exit code 1 when the preview source vault is missing" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "note.md" -Content "body" | Out-Null
        $missingVault = Join-Path $script:WorkRoot "missing-vault"
        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "note.md" -Category "wiki")
        ) -SourceVault $missingVault

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "source vault that does not exist"
        (Get-ChildItem -Path $script:VaultRoot -Recurse -Filter "*.md" -File).Count | Should Be 0
    }

    It "copies supported categories, skips skip and unclassified entries, preserves source files, and creates log artifacts" {
        Initialize-ExecuteImportWorkspace
        $inboxSource = New-SourceMarkdown -RelativePath "Inbox Item.md" -Content "inbox body"
        $rawSource = New-SourceMarkdown -RelativePath "Daily/raw note.md" -Content "raw body"
        $workingSource = New-SourceMarkdown -RelativePath "Work/Working Note.md" -Content "working body"
        $wikiSource = New-SourceMarkdown -RelativePath "MOCs/Wiki Note.md" -Content "wiki body"
        $archiveSource = New-SourceMarkdown -RelativePath "Old/Archive Note.md" -Content "archive body"
        New-SourceMarkdown -RelativePath "skip.md" -Content "skip me" | Out-Null
        New-SourceMarkdown -RelativePath "unclassified.md" -Content "leave me" | Out-Null

        $hashesBefore = @{
            inbox = (Get-FileHash -Path $inboxSource).Hash
            raw = (Get-FileHash -Path $rawSource).Hash
            working = (Get-FileHash -Path $workingSource).Hash
            wiki = (Get-FileHash -Path $wikiSource).Hash
            archive = (Get-FileHash -Path $archiveSource).Hash
        }

        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "Inbox Item.md" -Category "inbox"),
            (New-PreviewEntry -RelativePath "Daily/raw note.md" -Category "raw"),
            (New-PreviewEntry -RelativePath "Work/Working Note.md" -Category "working"),
            (New-PreviewEntry -RelativePath "MOCs/Wiki Note.md" -Category "wiki"),
            (New-PreviewEntry -RelativePath "Old/Archive Note.md" -Category "archive"),
            (New-PreviewEntry -RelativePath "skip.md" -Category "skip"),
            (New-PreviewEntry -RelativePath "unclassified.md" -Category "unclassified")
        )

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $log = Get-LatestImportLog
        $markdownPath = Get-LatestImportMarkdownPath

        $result.ExitCode | Should Be 0
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "inbox") -Filter "*.md").Count | Should Be 1
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "raw") -Filter "*.md").Count | Should Be 1
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "working") -Filter "*.md").Count | Should Be 1
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "wiki") -Filter "*.md").Count | Should Be 1
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "archive") -Filter "*.md").Count | Should Be 1
        (Get-FileHash -Path $inboxSource).Hash | Should Be $hashesBefore.inbox
        (Get-FileHash -Path $rawSource).Hash | Should Be $hashesBefore.raw
        (Get-FileHash -Path $workingSource).Hash | Should Be $hashesBefore.working
        (Get-FileHash -Path $wikiSource).Hash | Should Be $hashesBefore.wiki
        (Get-FileHash -Path $archiveSource).Hash | Should Be $hashesBefore.archive
        $log.totals.copied | Should Be 5
        $log.totals.skipped | Should Be 2
        (Test-Path $markdownPath) | Should Be $true
        $result.Output | Should Match "Import ID:"
        $result.Output | Should Match "JSON Log:"
    }

    It "augments frontmatter, preserves conflicting existing values, and derives a project tag for unmapped folders" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "Work/alpha.md" -Content @'
---
title: "Alpha"
confidence: "high"
status: "custom"
project: "legacy"
---
Alpha body
'@ | Out-Null
        New-SourceMarkdown -RelativePath "Ideas/Beta Note.md" -Content "Beta body" | Out-Null

        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "Work/alpha.md" -Category "working"),
            (New-PreviewEntry -RelativePath "Ideas/Beta Note.md" -Category "wiki")
        ) -MappingRules @(
            [PSCustomObject]@{ pattern = "Work"; category = "working" }
        )

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $workingContent = Get-Content -Path (Join-Path $script:VaultRoot "working\alpha.md") -Raw -Encoding UTF8
        $wikiContent = Get-Content -Path (Join-Path $script:VaultRoot "wiki\beta-note.md") -Raw -Encoding UTF8
        $log = Get-LatestImportLog
        $alphaLog = @($log.files | Where-Object { $_.source_path -like "*alpha.md" })[0]

        $result.ExitCode | Should Be 0
        $workingContent | Should Match 'imported_from: ".+alpha\.md"'
        $workingContent | Should Match 'import_date: ".+?"'
        $workingContent | Should Match 'import_id: "import-\d{8}-\d{6}"'
        $workingContent | Should Match 'confidence: "high"'
        $workingContent | Should Match 'status: "custom"'
        $workingContent | Should Match 'project: "legacy"'
        $wikiContent | Should Match 'project: "ideas"'
        $wikiContent | Should Match 'status: "draft"'
        (@($alphaLog.warnings) -join " | ") | Should Match "confidence"
        (@($alphaLog.warnings) -join " | ") | Should Match "status"
        (@($alphaLog.warnings) -join " | ") | Should Match "project"
    }

    It "resolves filename collisions deterministically with numeric suffixes" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "One/Same Name.md" -Content "first" | Out-Null
        New-SourceMarkdown -RelativePath "Two/Same Name.md" -Content "second" | Out-Null
        New-SourceMarkdown -RelativePath "Three/Same Name.md" -Content "third" | Out-Null

        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "One/Same Name.md" -Category "wiki"),
            (New-PreviewEntry -RelativePath "Two/Same Name.md" -Category "wiki"),
            (New-PreviewEntry -RelativePath "Three/Same Name.md" -Category "wiki")
        )

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $files = @(Get-ChildItem -Path (Join-Path $script:VaultRoot "wiki") -Filter "*.md" -File | Sort-Object Name)
        $log = Get-LatestImportLog

        $result.ExitCode | Should Be 0
        @($files.Name) | Should Be @("same-name-1.md", "same-name-2.md", "same-name.md")
        $log.totals.renamed | Should Be 2
    }

    It "prefixes Windows reserved device stems during filename sanitization" {
        Initialize-ExecuteImportWorkspace
        $sourcePath = New-SourceMarkdown -RelativePath "safe-source.md" -Content "reserved"
        $entry = New-PreviewEntry -RelativePath "CON.md" -Category "wiki"
        $entry.source_path = $sourcePath

        $previewPath = New-PreviewFile -Files @(
            $entry
        )

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)

        $result.ExitCode | Should Be 0
        Test-Path (Join-Path $script:VaultRoot "wiki\_con.md") | Should Be $true
    }

    It "rejects source paths outside the preview source vault as per-file errors" {
        Initialize-ExecuteImportWorkspace
        $outsidePath = Join-Path $script:WorkRoot "outside.md"
        Set-Content -Path $outsidePath -Value "outside" -Encoding UTF8
        $entry = New-PreviewEntry -RelativePath "outside.md" -Category "wiki"
        $entry.source_path = $outsidePath
        $previewPath = New-PreviewFile -Files @($entry)

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $log = Get-LatestImportLog

        $result.ExitCode | Should Be 0
        $log.status | Should Be "completed-with-errors"
        $log.totals.errors | Should Be 1
        $log.files[0].error | Should Match "outside the configured source_vault"
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "wiki") -Filter "*.md" -File).Count | Should Be 0
    }

    It "records unknown proposed_category values as errors instead of clean skips" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "typo.md" -Content "body" | Out-Null

        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "typo.md" -Category "wki")
        )

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $log = Get-LatestImportLog

        $result.ExitCode | Should Be 0
        $log.status | Should Be "completed-with-errors"
        $log.files[0].action | Should Be "error"
        $log.files[0].error | Should Match "Unrecognized proposed_category 'wki'"
    }

    It "logs unreadable source files as per-file errors without leaving partial destinations" {
        Initialize-ExecuteImportWorkspace
        $sourcePath = New-SourceMarkdown -RelativePath "locked.md" -Content "locked"
        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "locked.md" -Category "wiki")
        )
        $stream = [System.IO.File]::Open($sourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        }
        finally {
            $stream.Dispose()
        }
        $log = Get-LatestImportLog
        $runState = Get-LatestRunState

        $result.ExitCode | Should Be 0
        $log.status | Should Be "completed-with-errors"
        $log.files[0].action | Should Be "error"
        $runState.status | Should Be "completed-with-errors"
        @($runState.processed).Count | Should Be 0
        Test-Path (Join-Path $script:VaultRoot "wiki\locked.md") | Should Be $false
    }

    It "retries previously errored entries on resume" {
        Initialize-ExecuteImportWorkspace
        $sourcePath = New-SourceMarkdown -RelativePath "retry.md" -Content "retry"
        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "retry.md" -Category "wiki")
        )
        $stream = [System.IO.File]::Open($sourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $first = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        }
        finally {
            $stream.Dispose()
        }

        $second = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath, "-Resume")
        $log = Get-LatestImportLog

        $first.ExitCode | Should Be 0
        $second.ExitCode | Should Be 0
        $log.status | Should Be "completed"
        $log.totals.copied | Should Be 1
        Test-Path (Join-Path $script:VaultRoot "wiki\retry.md") | Should Be $true
    }

    It "preserves invalid frontmatter content and records a warning" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "bad-frontmatter.md" -Content @'
---
title: "Broken
Bad body
'@ | Out-Null

        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "bad-frontmatter.md" -Category "wiki")
        )

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $content = Get-Content -Path (Join-Path $script:VaultRoot "wiki\bad-frontmatter.md") -Raw -Encoding UTF8
        $log = Get-LatestImportLog

        $result.ExitCode | Should Be 0
        $content | Should Match 'title: "Broken'
        $content | Should Match "Bad body"
        (@($log.files[0].warnings) -join " | ") | Should Match "invalid frontmatter"
    }

    It "adds an import_id suffix when timestamp artifacts already exist" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "collision.md" -Content "collision" | Out-Null
        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "collision.md" -Category "wiki")
        )
        $now = (Get-Date).ToUniversalTime()
        foreach ($stamp in @($now.ToString('yyyyMMdd-HHmmss'), $now.AddSeconds(1).ToString('yyyyMMdd-HHmmss'))) {
            $id = "import-$stamp"
            Set-Content -Path (Join-Path $script:RunRoot "$id.json") -Value "{}" -Encoding UTF8
            Set-Content -Path (Join-Path $script:LogRoot "import-$id.json") -Value "{}" -Encoding UTF8
            Set-Content -Path (Join-Path $script:LogRoot "import-$id.md") -Value "" -Encoding UTF8
        }

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $log = Get-LatestImportLog

        $result.ExitCode | Should Be 0
        $log.import_id | Should Match '^import-\d{8}-\d{6}-[a-f0-9]{4}$'
    }

    It "atomically reserves a suffixed run-state path when the base import id already exists" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "reserved-id.md" -Content "reserved" | Out-Null
        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "reserved-id.md" -Category "wiki")
        )
        $now = (Get-Date).ToUniversalTime()
        $baseIds = @()
        foreach ($offset in 0..3) {
            $baseIds += "import-$($now.AddSeconds($offset).ToString('yyyyMMdd-HHmmss'))"
        }
        foreach ($baseId in $baseIds) {
            Set-Content -Path (Join-Path $script:RunRoot "$baseId.json") -Value "{}" -Encoding UTF8
        }

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
        $log = Get-LatestImportLog
        $runStateFiles = @(Get-ChildItem -Path $script:RunRoot -Filter "import-*.json" -File)

        $result.ExitCode | Should Be 0
        $log.import_id | Should Match '^import-\d{8}-\d{6}-[a-f0-9]{4}$'
        foreach ($baseId in $baseIds) {
            Test-Path (Join-Path $script:RunRoot "$baseId.json") | Should Be $true
        }
        @($runStateFiles | Where-Object { $_.BaseName -eq $log.import_id }).Count | Should Be 1
        $baseIds -notcontains $log.import_id | Should Be $true
    }

    It "removes destinations for source-size changes and re-attempts them on resume" {
        Initialize-ExecuteImportWorkspace
        $largeContent = "stable line`r`n" * 800000
        $sourcePath = New-SourceMarkdown -RelativePath "changes-during-import.md" -Content $largeContent
        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "changes-during-import.md" -Category "wiki")
        )
        $targetPath = Join-Path $script:VaultRoot "wiki\changes-during-import.md"

        $mutation = Start-Job -ScriptBlock {
            param([string]$Path)
            foreach ($index in 1..200) {
                Add-Content -LiteralPath $Path -Value "changed $index" -Encoding UTF8
                Start-Sleep -Milliseconds 10
            }
        } -ArgumentList $sourcePath
        try {
            $first = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath)
            Wait-Job -Job $mutation | Out-Null
        }
        finally {
            Remove-Job -Job $mutation -Force -ErrorAction SilentlyContinue
        }

        $firstLog = Get-LatestImportLog
        $orphanAfterFirst = Test-Path $targetPath
        $second = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath, "-Resume")
        $secondLog = Get-LatestImportLog

        $first.ExitCode | Should Be 0
        $firstLog.status | Should Be "completed-with-errors"
        $firstLog.files[0].error | Should Match "size"
        $orphanAfterFirst | Should Be $false
        $second.ExitCode | Should Be 0
        $secondLog.status | Should Be "completed"
        $secondLog.totals.copied | Should Be 1
        Test-Path $targetPath | Should Be $true
    }

    It "resumes from an existing run-state and records per-file errors without aborting the run" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "Resume/one.md" -Content "one" | Out-Null
        New-SourceMarkdown -RelativePath "Resume/two.md" -Content "two" | Out-Null

        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "Resume/one.md" -Category "raw"),
            (New-PreviewEntry -RelativePath "Resume/two.md" -Category "raw"),
            (New-PreviewEntry -RelativePath "Resume/missing.md" -Category "raw")
        )

        Set-Content -Path (Join-Path $script:VaultRoot "raw\one.md") -Value "already imported" -Encoding UTF8
        $runStatePath = Join-Path $script:RunRoot "import-20260428-120000.json"
        $runState = [PSCustomObject]@{
            import_id = "import-20260428-120000"
            preview_file = $previewPath
            started_at = "2026-04-28T12:00:00Z"
            last_updated_at = "2026-04-28T12:00:30Z"
            status = "in-progress"
            execution_fingerprint = (Get-TestFingerprint -PreviewPath $previewPath)
            processed = @(
                [PSCustomObject]@{
                    source_path = (Join-Path $script:SourceRoot "Resume/one.md")
                    target_path = (Join-Path $script:VaultRoot "raw\one.md")
                    category = "raw"
                    action = "copied"
                }
            )
        }
        Set-Content -Path $runStatePath -Value ($runState | ConvertTo-Json -Depth 8) -Encoding UTF8

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath, "-Resume")
        $log = Get-LatestImportLog
        $missingRecord = @($log.files | Where-Object { $_.source_path -like "*missing.md" })[0]

        $result.ExitCode | Should Be 0
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "raw") -Filter "*.md" -File).Count | Should Be 2
        (Get-Content -Path (Join-Path $script:VaultRoot "raw\one.md") -Raw -Encoding UTF8) | Should Be "already imported`r`n"
        $log.status | Should Be "completed-with-errors"
        $log.totals.errors | Should Be 1
        $missingRecord.action | Should Be "error"
        $missingRecord.error | Should Match "Source file does not exist"
    }

    It "fails resume with exit code 1 when run-state preview hash is stale" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "Resume/stale.md" -Content "one" | Out-Null
        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "Resume/stale.md" -Category "raw")
        )
        $fingerprint = Get-TestFingerprint -PreviewPath $previewPath
        $fingerprint.preview_sha256 = "stale"
        $runState = [PSCustomObject]@{
            import_id = "import-20260428-130000"
            preview_file = $previewPath
            started_at = "2026-04-28T13:00:00Z"
            last_updated_at = "2026-04-28T13:00:30Z"
            status = "in-progress"
            execution_fingerprint = $fingerprint
            processed = @()
        }
        Set-Content -Path (Join-Path $script:RunRoot "import-20260428-130000.json") -Value ($runState | ConvertTo-Json -Depth 8) -Encoding UTF8

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath, "-Resume")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "preview file content hash differs"
    }

    It "supports dry run without writing into knowledge folders" {
        Initialize-ExecuteImportWorkspace
        New-SourceMarkdown -RelativePath "Dry/dry-run.md" -Content "dry body" | Out-Null

        $previewPath = New-PreviewFile -Files @(
            (New-PreviewEntry -RelativePath "Dry/dry-run.md" -Category "working")
        )

        $result = Invoke-ExecuteImportScript -Arguments @("-PreviewFile", $previewPath, "-DryRun")
        $log = Get-LatestImportLog

        $result.ExitCode | Should Be 0
        (Get-ChildItem -Path (Join-Path $script:VaultRoot "working") -Filter "*.md" -File).Count | Should Be 0
        (Get-ChildItem -Path $script:LogRoot -Filter "import-*.json" -File).Count | Should Be 1
        $log.totals.copied | Should Be 1
    }
}
