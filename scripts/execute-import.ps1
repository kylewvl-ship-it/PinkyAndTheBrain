#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PreviewFile = "",
    [switch]$Resume,
    [switch]$DryRun,
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

function Show-ExecuteImportHelp {
    Write-Host "execute-import.ps1 - Execute a Story 5.3 vault import preview"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\scripts\execute-import.ps1 -PreviewFile .ai/import-previews/import-preview-20260428-120000.json"
    Write-Host "  .\scripts\execute-import.ps1 -PreviewFile .ai/import-previews/import-preview-20260428-120000.json -DryRun"
    Write-Host "  .\scripts\execute-import.ps1 -PreviewFile .ai/import-previews/import-preview-20260428-120000.json -Resume"
    Write-Host ""
    Write-Host "Notes:"
    Write-Host "  - Uses the preview JSON as the source of truth; it does not re-classify files."
    Write-Host "  - Copies files only into configured knowledge folders, .ai/import-logs/, and .ai/import-runs/."
    Write-Host "  - -DryRun creates run artifacts but does not write into knowledge folders."
    Write-Host "  - If a timestamp import id collides with existing run/log artifacts, a 4-character random suffix is appended."
}

function Resolve-AbsolutePath {
    param(
        [string]$Path,
        [string]$BasePath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

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

function Get-Sha256ForText {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function New-ExecutionFingerprint {
    param(
        [string]$PreviewContent,
        [string]$SourceVault,
        [hashtable]$Targets
    )

    $targetMap = [ordered]@{}
    foreach ($category in @('inbox', 'raw', 'working', 'wiki', 'archive')) {
        $targetMap[$category] = [System.IO.Path]::GetFullPath([string]$Targets[$category])
    }

    return [PSCustomObject]@{
        preview_sha256 = Get-Sha256ForText -Value $PreviewContent
        source_vault = [System.IO.Path]::GetFullPath($SourceVault)
        knowledge_folders = [PSCustomObject]$targetMap
    }
}

function Assert-ExecutionFingerprintMatches {
    param(
        [object]$Existing,
        [object]$Current
    )

    if ($null -eq $Existing) {
        throw "Resume run-state is missing execution fingerprint metadata."
    }

    if ([string]$Existing.preview_sha256 -ne [string]$Current.preview_sha256) {
        throw "Resume run-state mismatch: preview file content hash differs."
    }

    if ([string]$Existing.source_vault -ne [string]$Current.source_vault) {
        throw "Resume run-state mismatch: source_vault differs."
    }

    foreach ($category in @('inbox', 'raw', 'working', 'wiki', 'archive')) {
        $existingPath = [string]$Existing.knowledge_folders.$category
        $currentPath = [string]$Current.knowledge_folders.$category
        if ($existingPath -ne $currentPath) {
            throw "Resume run-state mismatch: knowledge folder '$category' differs."
        }
    }
}

function New-ImportArtifactPaths {
    param(
        [string]$RunRoot,
        [string]$LogRoot
    )

    $baseId = "import-{0}" -f ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $importId = $baseId
        if ($attempt -gt 0) {
            $suffix = -join ((1..4) | ForEach-Object { '{0:x}' -f (Get-Random -Minimum 0 -Maximum 16) })
            $importId = "{0}-{1}" -f $baseId, $suffix
        }

        $runStatePath = Join-Path $RunRoot ("{0}.json" -f $importId)
        $jsonLogPath = Join-Path $LogRoot ("import-{0}.json" -f $importId)
        $markdownLogPath = Join-Path $LogRoot ("import-{0}.md" -f $importId)
        if (!(Test-Path -LiteralPath $jsonLogPath) -and !(Test-Path -LiteralPath $markdownLogPath)) {
            $stream = $null
            try {
                $stream = [System.IO.File]::Open($runStatePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            }
            catch [System.IO.IOException] {
                continue
            }
            finally {
                if ($null -ne $stream) {
                    $stream.Dispose()
                }
            }

            return [PSCustomObject]@{
                ImportId = $importId
                RunStatePath = $runStatePath
                JsonLogPath = $jsonLogPath
                MarkdownLogPath = $markdownLogPath
            }
        }
    }

    throw "Unable to allocate a unique import id after repeated collision checks."
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

function Test-PreviewShape {
    param([object]$Preview)

    if ($null -eq $Preview) { return $false }

    $properties = @($Preview.PSObject.Properties.Name)
    if ($properties -notcontains 'source_vault' -or $properties -notcontains 'files') {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace([string]$Preview.source_vault)) {
        return $false
    }

    foreach ($entry in @($Preview.files)) {
        if ($null -eq $entry) { return $false }
        $entryProperties = @($entry.PSObject.Properties.Name)
        foreach ($required in @('source_path', 'relative_path', 'proposed_category')) {
            if ($entryProperties -notcontains $required) {
                return $false
            }
        }
    }

    return $true
}

function Get-PreviewMappingRules {
    param([object]$Preview)

    $properties = @($Preview.PSObject.Properties.Name)
    if ($properties -contains 'mapping_rules' -and $null -ne $Preview.mapping_rules) {
        return @($Preview.mapping_rules)
    }

    return @()
}

function Get-MatchingRule {
    param(
        [string]$RelativePath,
        [object[]]$MappingRules
    )

    $normalizedPath = $RelativePath.Replace('\', '/')
    $pathSegments = @($normalizedPath -split '/' | Where-Object { $_ -ne '' })
    foreach ($rule in @($MappingRules)) {
        $pattern = [string]$rule.pattern
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        $normalizedPattern = $pattern.Replace('\', '/').Trim('/')
        if ([string]::IsNullOrWhiteSpace($normalizedPattern)) {
            continue
        }

        foreach ($segment in $pathSegments) {
            if ($segment.Equals($normalizedPattern, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $rule
            }
        }
    }

    return $null
}

function ConvertTo-SafeSlug {
    param([string]$Value)

    $slug = ([string]$Value).ToLowerInvariant() -replace '\s+', '-' -replace '[^a-z0-9._-]', '' -replace '-+', '-'
    $slug = $slug.Trim('-', '.')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return 'imported'
    }

    return $slug
}

function Get-SafeDestinationFileName {
    param([string]$RelativePath)

    $leafName = [System.IO.Path]::GetFileName($RelativePath)
    $extension = [System.IO.Path]::GetExtension($leafName).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($extension)) {
        $extension = '.md'
    }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($leafName)
    $safeStem = ConvertTo-SafeSlug -Value $stem
    if ($safeStem -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$') {
        $safeStem = "_$safeStem"
    }

    return ("{0}{1}" -f $safeStem, $extension)
}

function Get-UniqueDestinationPath {
    param(
        [string]$TargetFolder,
        [string]$BaseFileName
    )

    $extension = [System.IO.Path]::GetExtension($BaseFileName)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($BaseFileName)
    $candidate = Join-Path $TargetFolder $BaseFileName
    $suffix = 0

    while (Test-Path -LiteralPath $candidate) {
        $suffix++
        $candidate = Join-Path $TargetFolder ("{0}-{1}{2}" -f $stem, $suffix, $extension)
    }

    return $candidate
}

function Get-CategoryDefaultStatus {
    param([string]$Category)

    switch ($Category) {
        'working' { return 'active' }
        'wiki' { return 'draft' }
        'archive' { return 'archived' }
        'inbox' { return 'draft' }
        'raw' { return 'draft' }
        default { return 'draft' }
    }
}

function Test-InvalidFrontmatter {
    param([string]$Content)

    $normalized = $Content -replace "`r`n", "`n"
    return ($normalized.TrimStart().StartsWith('---') -and $null -eq (Get-FrontmatterData -Content $Content))
}

function Merge-ImportedFrontmatter {
    param(
        [string]$Content,
        [string]$SourcePath,
        [string]$ImportDate,
        [string]$ImportId,
        [string]$Category,
        [string]$ProjectDefault
    )

    $warnings = @()
    if (Test-InvalidFrontmatter -Content $Content) {
        $warnings += 'invalid frontmatter detected; imported raw content preserved'
        return @{
            Content = $Content
            Warnings = $warnings
            InvalidFrontmatter = $true
        }
    }

    $frontmatterData = Get-FrontmatterData -Content $Content
    if ($null -eq $frontmatterData) {
        $frontmatter = ''
        $body = $Content
    }
    else {
        $frontmatter = [string]$frontmatterData.Frontmatter
        $body = [string]$frontmatterData.Body
    }

    $requiredFields = [ordered]@{
        imported_from = $SourcePath
        import_date = $ImportDate
        import_id = $ImportId
        confidence = 'medium'
        project = $ProjectDefault
        status = (Get-CategoryDefaultStatus -Category $Category)
    }

    foreach ($field in $requiredFields.Keys) {
        $existingPresent = Test-FrontmatterFieldPresent -Frontmatter $frontmatter -Key $field
        if ($existingPresent) {
            $existingValue = [string](Get-FrontmatterValue -Frontmatter $frontmatter -Key $field)
            if ($existingValue -ne $requiredFields[$field]) {
                $warnings += ('frontmatter conflict for {0}: kept existing value "{1}" instead of "{2}"' -f $field, $existingValue, $requiredFields[$field])
            }
            continue
        }

        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key $field -Value ([string]$requiredFields[$field])
    }

    return @{
        Content = (Build-Document -Frontmatter $frontmatter -Body $body)
        Warnings = $warnings
        InvalidFrontmatter = $false
    }
}

function Save-JsonArtifact {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 12
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-LatestResumeState {
    param(
        [string]$RunRoot,
        [string]$PreviewFile
    )

    if (!(Test-Path -LiteralPath $RunRoot)) {
        return $null
    }

    $stateFiles = @(Get-ChildItem -LiteralPath $RunRoot -Filter '*.json' -File | Sort-Object LastWriteTimeUtc -Descending)
    foreach ($file in $stateFiles) {
        try {
            $state = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $status = [string]$state.status
            if ([string]$state.preview_file -eq $PreviewFile -and $status -ne 'completed') {
                return $state
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-ProjectDefault {
    param(
        [string]$RelativePath,
        [object[]]$MappingRules
    )

    $matchingRule = Get-MatchingRule -RelativePath $RelativePath -MappingRules $MappingRules
    if ($null -ne $matchingRule) {
        return 'imported'
    }

    $normalized = $RelativePath.Replace('\', '/')
    $segments = @($normalized -split '/' | Where-Object { $_ -ne '' })
    if ($segments.Count -gt 1) {
        return (ConvertTo-SafeSlug -Value $segments[0])
    }

    return 'imported'
}

function New-FileRecord {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$Category,
        [string]$Action,
        [string[]]$Warnings,
        [string]$ErrorMessage
    )

    return [PSCustomObject]@{
        source_path = $SourcePath
        target_path = $TargetPath
        category = $Category
        action = $Action
        warnings = @($Warnings)
        error = $ErrorMessage
    }
}

function Get-MarkdownReport {
    param([object]$Log)

    $lines = @(
        "# Import Report",
        "",
        ('- Import ID: `{0}`' -f $Log.import_id),
        ('- Status: `{0}`' -f $Log.status),
        ('- Source Vault: `{0}`' -f $Log.source_vault),
        ('- Preview File: `{0}`' -f $Log.preview_file),
        ('- Started: `{0}`' -f $Log.started_at),
        ('- Finished: `{0}`' -f $Log.finished_at),
        "",
        "## Totals",
        "",
        ("- Copied: {0}" -f $Log.totals.copied),
        ("- Skipped: {0}" -f $Log.totals.skipped),
        ("- Renamed: {0}" -f $Log.totals.renamed),
        ("- Errors: {0}" -f $Log.totals.errors),
        ("- Warnings: {0}" -f $Log.totals.warnings),
        "",
        "## Renames",
        ""
    )

    $renamed = @($Log.files | Where-Object { $_.action -eq 'renamed' })
    if ($renamed.Count -eq 0) {
        $lines += "- None"
    }
    else {
        foreach ($entry in $renamed) {
            $lines += ('- `{0}` -> `{1}`' -f $entry.source_path, $entry.target_path)
        }
    }

    $lines += ""
    $lines += "## Warnings"
    $lines += ""
    $warnings = @($Log.files | Where-Object { @($_.warnings).Count -gt 0 })
    if ($warnings.Count -eq 0) {
        $lines += "- None"
    }
    else {
        foreach ($entry in $warnings) {
            foreach ($warning in @($entry.warnings)) {
                $lines += ('- `{0}`: {1}' -f $entry.source_path, $warning)
            }
        }
    }

    $lines += ""
    $lines += "## Errors"
    $lines += ""
    $errors = @($Log.files | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.error) })
    if ($errors.Count -eq 0) {
        $lines += "- None"
    }
    else {
        foreach ($entry in $errors) {
            $lines += ('- `{0}` -> `{1}`: {2}' -f $entry.source_path, $entry.target_path, $entry.error)
        }
    }

    $lines += ""
    $lines += "## By Category"
    $lines += ""
    foreach ($group in @($Log.files | Group-Object category | Sort-Object Name)) {
        $lines += ("- {0}: {1}" -f $group.Name, $group.Count)
    }

    $lines += ""
    $lines += "## Next Step"
    $lines += ""
    $lines += "- Story 5.5 rollback should use this import id and the JSON ledger for selective recovery."

    return ($lines -join "`r`n")
}

if ($Help) {
    Show-ExecuteImportHelp
    exit 0
}

$importId = $null
$runStatePath = $null
$jsonLogPath = $null
$markdownLogPath = $null
$runState = $null
$logRecords = @()
$startedAt = $null
$sourceVault = $null
$resolvedPreviewFile = $null

try {
    if ([string]::IsNullOrWhiteSpace($PreviewFile)) {
        Write-Host "PreviewFile is required. Use -PreviewFile <path>." -ForegroundColor Red
        exit 1
    }

    $repoRoot = Get-RepoRoot
    $resolvedPreviewFile = Resolve-AbsolutePath -Path $PreviewFile -BasePath (Get-Location).Path
    if (!(Test-Path -LiteralPath $resolvedPreviewFile -PathType Leaf)) {
        Write-Host "Preview file does not exist: $resolvedPreviewFile" -ForegroundColor Red
        exit 1
    }

    try {
        $previewContent = Get-Content -LiteralPath $resolvedPreviewFile -Raw -Encoding UTF8
        $preview = $previewContent | ConvertFrom-Json
    }
    catch {
        Write-Host ("Preview file is not valid JSON: {0}" -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }

    if (!(Test-PreviewShape -Preview $preview)) {
        Write-Host "Preview file is missing required Story 5.3 fields." -ForegroundColor Red
        exit 1
    }

    $sourceVault = [System.IO.Path]::GetFullPath([string]$preview.source_vault)
    if (!(Test-Path -LiteralPath $sourceVault -PathType Container)) {
        Write-Host "Preview references a source vault that does not exist: $sourceVault" -ForegroundColor Red
        exit 1
    }

    try {
        [void](Get-ChildItem -LiteralPath $sourceVault -ErrorAction Stop | Select-Object -First 1)
    }
    catch {
        Write-Host ("Source vault is unreadable: {0}" -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }

    $config = Get-Config
    $targets = Get-KnowledgeTargets -Config $config
    foreach ($category in $targets.Keys) {
        if (!(Test-Path -LiteralPath $targets[$category] -PathType Container)) {
            Write-Host ("Required knowledge folder is missing: {0}. Run .\scripts\setup-system.ps1 first." -f $targets[$category]) -ForegroundColor Red
            exit 2
        }
    }
    $executionFingerprint = New-ExecutionFingerprint -PreviewContent $previewContent -SourceVault $sourceVault -Targets $targets

    $runRoot = Join-Path $repoRoot '.ai/import-runs'
    $logRoot = Join-Path $repoRoot '.ai/import-logs'
    if (!(Test-Path -LiteralPath $runRoot)) {
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    }
    if (!(Test-Path -LiteralPath $logRoot)) {
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    }

    if ($Resume) {
        $existingState = Get-LatestResumeState -RunRoot $runRoot -PreviewFile $resolvedPreviewFile
        if ($null -eq $existingState) {
            Write-Host "No resumable import run was found for this preview file." -ForegroundColor Red
            exit 1
        }

        try {
            Assert-ExecutionFingerprintMatches -Existing $existingState.execution_fingerprint -Current $executionFingerprint
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            exit 1
        }

        $importId = [string]$existingState.import_id
        $runStatePath = Join-Path $runRoot ("{0}.json" -f $importId)
        $jsonLogPath = Join-Path $logRoot ("import-{0}.json" -f $importId)
        $markdownLogPath = Join-Path $logRoot ("import-{0}.md" -f $importId)
        $startedAt = [string]$existingState.started_at
        $runState = @{
            import_id = $importId
            preview_file = $resolvedPreviewFile
            started_at = $startedAt
            last_updated_at = [string]$existingState.last_updated_at
            status = 'in-progress'
            execution_fingerprint = $executionFingerprint
            processed = @($existingState.processed)
        }
    }
    else {
        $artifactPaths = New-ImportArtifactPaths -RunRoot $runRoot -LogRoot $logRoot
        $importId = $artifactPaths.ImportId
        $runStatePath = $artifactPaths.RunStatePath
        $jsonLogPath = $artifactPaths.JsonLogPath
        $markdownLogPath = $artifactPaths.MarkdownLogPath
        $startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $runState = @{
            import_id = $importId
            preview_file = $resolvedPreviewFile
            started_at = $startedAt
            last_updated_at = $startedAt
            status = 'in-progress'
            execution_fingerprint = $executionFingerprint
            processed = @()
        }
        Save-JsonArtifact -Path $runStatePath -Value $runState
    }

    Write-Host ("Import ID: {0}" -f $importId) -ForegroundColor Green
    Write-Host ("Run State: {0}" -f $runStatePath) -ForegroundColor Green
    Write-Host ("JSON Log: {0}" -f $jsonLogPath) -ForegroundColor Green
    Write-Host ("Markdown Report: {0}" -f $markdownLogPath) -ForegroundColor Green

    $processedBySource = @{}
    foreach ($record in @($runState.processed)) {
        if ([string]$record.action -eq 'error') {
            continue
        }

        $processedBySource[[string]$record.source_path] = $true
        $logRecords += New-FileRecord -SourcePath ([string]$record.source_path) -TargetPath ([string]$record.target_path) -Category ([string]$record.category) -Action ([string]$record.action) -Warnings @() -ErrorMessage $null
    }

    $previewRules = Get-PreviewMappingRules -Preview $preview
    $importDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $allowedCategories = @('inbox', 'raw', 'working', 'wiki', 'archive')

    foreach ($entry in @($preview.files)) {
        $sourcePath = [System.IO.Path]::GetFullPath([string]$entry.source_path)
        $relativePath = [string]$entry.relative_path
        $category = ([string]$entry.proposed_category).ToLowerInvariant()

        if ($processedBySource.ContainsKey($sourcePath)) {
            continue
        }

        if (!(Test-PathWithinRoot -RootPath $sourceVault -CandidatePath $sourcePath)) {
            $record = New-FileRecord -SourcePath $sourcePath -TargetPath "" -Category $category -Action 'error' -Warnings @() -ErrorMessage "Source path is outside the configured source_vault."
            $logRecords += $record
            $runState.last_updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            Save-JsonArtifact -Path $runStatePath -Value $runState
            continue
        }

        if ($category -notin $allowedCategories) {
            if ($category -in @('skip', 'unclassified')) {
                $record = New-FileRecord -SourcePath $sourcePath -TargetPath "" -Category $category -Action 'skipped' -Warnings @() -ErrorMessage $null
            }
            else {
                $record = New-FileRecord -SourcePath $sourcePath -TargetPath "" -Category $category -Action 'error' -Warnings @("Unrecognized proposed_category '$category'.") -ErrorMessage "Unrecognized proposed_category '$category'."
            }
            $logRecords += $record
            if ($record.action -ne 'error') {
                $runState.processed += [PSCustomObject]@{
                    source_path = $sourcePath
                    target_path = ""
                    category = $category
                    action = 'skipped'
                }
            }
            $runState.last_updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            Save-JsonArtifact -Path $runStatePath -Value $runState
            continue
        }

        $targetFolder = $targets[$category]
        $safeFileName = Get-SafeDestinationFileName -RelativePath $relativePath
        $targetPath = Get-UniqueDestinationPath -TargetFolder $targetFolder -BaseFileName $safeFileName
        if (!(Test-PathWithinRoot -RootPath $targetFolder -CandidatePath $targetPath)) {
            throw "Resolved target path escapes the configured $category folder: $targetPath"
        }

        $warnings = @()
        $action = if ([System.IO.Path]::GetFileName($targetPath) -ne $safeFileName) { 'renamed' } else { 'copied' }
        $errorMessage = $null

        try {
            if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Source file does not exist."
            }

            $sourceItem = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
            $projectDefault = Get-ProjectDefault -RelativePath $relativePath -MappingRules $previewRules

            if (!$DryRun) {
                $tempPath = "{0}.tmp-{1}" -f $targetPath, ([guid]::NewGuid().ToString('N'))
                try {
                    Copy-Item -LiteralPath $sourcePath -Destination $tempPath -Force -ErrorAction Stop
                    $tempItem = Get-Item -LiteralPath $tempPath -ErrorAction Stop
                    if ($tempItem.Length -ne $sourceItem.Length) {
                        throw "Temporary copy size does not match source file size."
                    }

                    $content = Get-Content -LiteralPath $tempPath -Raw -Encoding UTF8
                    $merged = Merge-ImportedFrontmatter -Content $content -SourcePath $sourcePath -ImportDate $importDate -ImportId $importId -Category $category -ProjectDefault $projectDefault
                    $warnings += @($merged.Warnings)
                    Set-Content -Path $tempPath -Value ([string]$merged.Content) -Encoding UTF8

                    $sourceAfter = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
                    if ($sourceAfter.Length -ne $sourceItem.Length) {
                        throw "Source file size changed during import."
                    }

                    Move-Item -LiteralPath $tempPath -Destination $targetPath -Force -ErrorAction Stop
                }
                catch {
                    if (Test-Path -LiteralPath $tempPath) {
                        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                    }
                    if (Test-Path -LiteralPath $targetPath) {
                        Remove-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue
                    }
                    throw
                }
            }
        }
        catch {
            $action = 'error'
            $errorMessage = $_.Exception.Message
        }

        $record = New-FileRecord -SourcePath $sourcePath -TargetPath $targetPath -Category $category -Action $action -Warnings $warnings -ErrorMessage $errorMessage
        $logRecords += $record
        if ($action -ne 'error') {
            $runState.processed += [PSCustomObject]@{
                source_path = $sourcePath
                target_path = $targetPath
                category = $category
                action = $action
            }
        }
        $runState.last_updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Save-JsonArtifact -Path $runStatePath -Value $runState
    }

    $totals = [ordered]@{
        copied = @($logRecords | Where-Object { $_.action -eq 'copied' }).Count
        skipped = @($logRecords | Where-Object { $_.action -eq 'skipped' }).Count
        renamed = @($logRecords | Where-Object { $_.action -eq 'renamed' }).Count
        errors = @($logRecords | Where-Object { $_.action -eq 'error' }).Count
        warnings = @($logRecords | ForEach-Object { @($_.warnings).Count } | Measure-Object -Sum).Sum
    }
    if ($null -eq $totals.warnings) {
        $totals.warnings = 0
    }

    $status = if ($totals.errors -gt 0) { 'completed-with-errors' } else { 'completed' }
    $finishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $log = [PSCustomObject]@{
        import_id = $importId
        preview_file = $resolvedPreviewFile
        source_vault = $sourceVault
        started_at = $startedAt
        finished_at = $finishedAt
        totals = [PSCustomObject]$totals
        files = @($logRecords)
        status = $status
    }

    Save-JsonArtifact -Path $jsonLogPath -Value $log
    Set-Content -Path $markdownLogPath -Value (Get-MarkdownReport -Log $log) -Encoding UTF8

    $runState.status = $status
    $runState.last_updated_at = $finishedAt
    Save-JsonArtifact -Path $runStatePath -Value $runState

    Write-Host ("Import ID: {0}" -f $importId) -ForegroundColor Green
    Write-Host ("Run State: {0}" -f $runStatePath) -ForegroundColor Green
    Write-Host ("JSON Log: {0}" -f $jsonLogPath) -ForegroundColor Green
    Write-Host ("Markdown Report: {0}" -f $markdownLogPath) -ForegroundColor Green
    exit 0
}
catch {
    if ($null -ne $importId -and -not [string]::IsNullOrWhiteSpace($jsonLogPath)) {
        $failedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $log = [PSCustomObject]@{
            import_id = $importId
            preview_file = $resolvedPreviewFile
            source_vault = $sourceVault
            started_at = $startedAt
            finished_at = $failedAt
            totals = [PSCustomObject]@{
                copied = @($logRecords | Where-Object { $_.action -eq 'copied' }).Count
                skipped = @($logRecords | Where-Object { $_.action -eq 'skipped' }).Count
                renamed = @($logRecords | Where-Object { $_.action -eq 'renamed' }).Count
                errors = (@($logRecords | Where-Object { $_.action -eq 'error' }).Count + 1)
                warnings = @($logRecords | ForEach-Object { @($_.warnings).Count } | Measure-Object -Sum).Sum
            }
            files = @($logRecords + (New-FileRecord -SourcePath '' -TargetPath '' -Category '' -Action 'error' -Warnings @() -ErrorMessage $_.Exception.Message))
            status = 'failed'
        }
        Save-JsonArtifact -Path $jsonLogPath -Value $log
        Set-Content -Path $markdownLogPath -Value (Get-MarkdownReport -Log $log) -Encoding UTF8
        if ($null -ne $runState) {
            $runState.status = 'failed'
            $runState.last_updated_at = $failedAt
            Save-JsonArtifact -Path $runStatePath -Value $runState
        }
    }

    Write-Host ("Unexpected import failure: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 2
}
