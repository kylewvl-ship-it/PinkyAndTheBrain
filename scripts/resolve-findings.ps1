#!/usr/bin/env pwsh
param(
    [string]$ReportFile = "",
    [int]$FindingIndex = 0,
    [ValidateSet("update-metadata", "accept-extracted", "reject-extracted", "fix-link", "merge-duplicate", "ignore-fingerprint", "rebuild-index", "archive", "defer")]
    [string]$Action = "",
    [string]$DeferNote = "",
    [switch]$Force,
    [switch]$WhatIf,
    [switch]$Help,
    [switch]$Batch,
    [string]$Field = "",
    [string]$Value = "",
    [switch]$BulkArchiveStale,
    [switch]$BatchExtendReview,
    [int]$Days = 30,
    [string]$Project = "",
    [string]$LinkTarget = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/lib/frontmatter.ps1"

function Show-ResolveFindingsHelp {
    Write-Host "resolve-findings.ps1 - Resolve health-check report findings"
    Write-Host "Usage:"
    Write-Host "  .\scripts\resolve-findings.ps1 -ReportFile knowledge/reviews/health-report-YYYY-MM-DD.md -FindingIndex 1 -Action update-metadata -Field confidence -Value medium -Force"
    Write-Host "  .\scripts\resolve-findings.ps1 -ReportFile knowledge/reviews/health-report-YYYY-MM-DD.md -FindingIndex 1 -Action defer -DeferNote 'waiting on source' -Force"
    Write-Host "  .\scripts\resolve-findings.ps1 -ReportFile knowledge/reviews/health-report-YYYY-MM-DD.md -BulkArchiveStale -Force"
}

function Get-RepoRootLocal {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (![string]::IsNullOrWhiteSpace($envRepoRoot)) { return [System.IO.Path]::GetFullPath($envRepoRoot) }
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Resolve-PathFromRoot {
    param([string]$Path, [string]$Root)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Test-PathWithinRoot {
    param([string]$CandidatePath, [string]$RootPath)
    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
    return $candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-VaultFindingPath {
    param([object]$Finding, [string]$VaultRoot)
    $filePath = Resolve-PathFromRoot -Path $Finding.File -Root $VaultRoot
    if (!(Test-PathWithinRoot -CandidatePath $filePath -RootPath $VaultRoot)) {
        Write-Host "WARNING: skipping finding outside vault root: $($Finding.File)" -ForegroundColor Yellow
        return $null
    }
    return $filePath
}

function Get-RelativePathLocal {
    param([string]$BasePath, [string]$TargetPath)
    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = New-Object System.Uri($baseFullPath)
    $targetUri = New-Object System.Uri($targetFullPath)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace('\', '/')
}

function Confirm-ResolveAction {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
    if ($Force) { return $true }
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        Write-Host "Resolution aborted: confirmation was not provided." -ForegroundColor Yellow
        exit 0
    }
    $answer = Read-Host "Apply this change? Y/N"
    if ($answer -ne 'Y' -and $answer -ne 'y') {
        Write-Host "Resolution aborted." -ForegroundColor Yellow
        exit 0
    }
    return $true
}

function Get-ReportFindings {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Report file not found: $Path" }
    $findings = @()
    $section = ""
    $current = $null
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^##\s+(.+)$') {
            $section = $matches[1]
            continue
        }
        if ($line -match '^- \*\*(High|Medium|Low)\*\*\s+(.+)$') {
            if ($null -ne $current) { $findings += [PSCustomObject]$current }
            $current = [ordered]@{
                Type = $section
                Severity = $matches[1]
                File = $matches[2].Trim()
                Rule = ""
                Issue = ""
                Suggestion = ""
            }
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^\s+- Rule:\s*(.*)$') { $current.Rule = $matches[1].Trim(); continue }
        if ($line -match '^\s+- Issue:\s*(.*)$') { $current.Issue = $matches[1].Trim(); continue }
        if ($line -match '^\s+- Suggested repair:\s*(.*)$') { $current.Suggestion = $matches[1].Trim(); continue }
    }
    if ($null -ne $current) { $findings += [PSCustomObject]$current }
    if ($findings.Count -eq 0) { throw "Report is malformed or has no findings: $Path" }
    return $findings
}

function Get-DeferPath {
    param([string]$RepoRoot)
    return (Join-Path $RepoRoot ".ai/health-deferred.json")
}

function Read-DeferRecords {
    param([string]$Path)
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    return @($json | ConvertFrom-Json)
}

function Add-DeferRecord {
    param([string]$RepoRoot, [object]$Finding, [string]$ActionName, [string]$Note)
    $path = Get-DeferPath -RepoRoot $RepoRoot
    $dir = Split-Path $path -Parent
    if (!(Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $records = @(Read-DeferRecords -Path $path)
    $now = (Get-Date).ToUniversalTime()
    $record = [ordered]@{
        file = [string]$Finding.File
        rule = [string]$Finding.Rule
        action = $ActionName
        deferred_at = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        deferred_until = if ($ActionName -eq "defer") { $now.AddDays(30).ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
        note = $Note
    }
    $records += [PSCustomObject]$record
    Set-Content -Path $path -Value ($records | ConvertTo-Json -Depth 8) -Encoding UTF8
    Write-Host "Recorded $ActionName for $($Finding.File) / $($Finding.Rule)"
}

function Get-SuggestedActionsForRule {
    param([string]$Rule)
    switch ($Rule) {
        { $_ -in @("require-metadata", "require-wiki-sources", "require-confidence") } { return "update-metadata, archive, defer" }
        "link-target-exists" { return "fix-link, mark-broken, defer" }
        { $_ -in @("stale-threshold", "review-trigger-overdue") } { return "update-metadata, archive, defer" }
        { $_ -in @("duplicate-title", "title-edit-distance") } { return "merge-duplicate, defer" }
        { $_ -in @("body-sha256-match", "body-prefix-length-match") } { return "ignore-fingerprint, merge-duplicate, defer" }
        "incoming-link-required" { return "archive, defer" }
        "index-drift" { return "rebuild-index, defer" }
        default { return "archive, defer" }
    }
}

function Get-MetadataFieldFromFinding {
    param([object]$Finding, [string]$Field)
    if (![string]::IsNullOrWhiteSpace($Field)) { return $Field }
    if ($Finding.Rule -match '^require-(.+)$') { return $matches[1] }
    if ($Finding.Issue -match 'Missing required field:\s*(\S+)') { return $matches[1] }
    throw "Metadata field is required for this finding. Supply -Field."
}

function Update-FindingMetadata {
    param([object]$Finding, [string]$VaultRoot)
    $fieldName = Get-MetadataFieldFromFinding -Finding $Finding -Field $Field
    $fieldValue = $Value
    if ([string]::IsNullOrWhiteSpace($fieldValue)) {
        if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') { throw "-Value is required in noninteractive mode." }
        $fieldValue = Read-Host "Value for $fieldName"
    }
    $filePath = Resolve-VaultFindingPath -Finding $Finding -VaultRoot $VaultRoot
    if ($null -eq $filePath) { return }
    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    $frontmatterData = Get-FrontmatterData -Content $content
    if ($null -eq $frontmatterData) { throw "File has no frontmatter: $($Finding.File)" }
    $before = [string]$frontmatterData.Frontmatter
    $after = Set-FrontmatterField -Frontmatter $before -Key $fieldName -Value $fieldValue
    Write-Host "Before:"
    Write-Host $before
    Write-Host "After:"
    Write-Host $after
    Confirm-ResolveAction "Plan: set $fieldName on $($Finding.File)." | Out-Null
    if (!$WhatIf) {
        Set-Content -Path $filePath -Value (Build-Document -Frontmatter $after -Body $frontmatterData.Body) -Encoding UTF8
    }
}

function Get-LevenshteinDistanceLocal {
    param([string]$Left, [string]$Right)
    if ($Left -eq $Right) { return 0 }
    if ([string]::IsNullOrEmpty($Left)) { return $Right.Length }
    if ([string]::IsNullOrEmpty($Right)) { return $Left.Length }
    $previous = New-Object int[] ($Right.Length + 1)
    $current = New-Object int[] ($Right.Length + 1)
    for ($j = 0; $j -le $Right.Length; $j++) { $previous[$j] = $j }
    for ($i = 1; $i -le $Left.Length; $i++) {
        $current[0] = $i
        for ($j = 1; $j -le $Right.Length; $j++) {
            $cost = if ($Left[$i - 1] -eq $Right[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min([Math]::Min($previous[$j] + 1, $current[$j - 1] + 1), $previous[$j - 1] + $cost)
        }
        $temp = $previous; $previous = $current; $current = $temp
    }
    return $previous[$Right.Length]
}

function Repair-BrokenLink {
    param([object]$Finding, [hashtable]$Config)
    if ($Finding.Issue -notmatch 'Broken link:\s*(.+)$') { throw "Finding does not include a broken link target." }
    $broken = $matches[1].Trim()
    $cleanBroken = ($broken -replace '#.*$', '').Trim()
    $vaultRoot = [string]$Config.system.vault_root
    $filePath = Resolve-VaultFindingPath -Finding $Finding -VaultRoot $vaultRoot
    if ($null -eq $filePath) { return }
    $content = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki)
    $candidates = @()
    foreach ($folder in $folders) {
        $folderPath = Join-Path $vaultRoot ([string]$folder)
        if (!(Test-Path -LiteralPath $folderPath)) { continue }
        foreach ($file in (Get-ChildItem -Path $folderPath -Filter "*.md" -File -Recurse)) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $candidates += [PSCustomObject]@{
                Stem = $stem
                RelativePath = Get-RelativePathLocal -BasePath $vaultRoot -TargetPath $file.FullName
                Distance = Get-LevenshteinDistanceLocal -Left $cleanBroken.ToLowerInvariant() -Right $stem.ToLowerInvariant()
            }
        }
    }
    $top = @($candidates | Sort-Object Distance, Stem | Select-Object -First 3)
    Write-Host "Candidates:"
    for ($i = 0; $i -lt $top.Count; $i++) { Write-Host ("{0}. {1}" -f ($i + 1), $top[$i].Stem) }
    $choice = ""
    if (![string]::IsNullOrWhiteSpace($LinkTarget)) {
        $target = $LinkTarget.Trim()
        $matched = @($candidates | Where-Object {
            $_.Stem -eq $target -or
            $_.RelativePath -eq $target -or
            ($_.RelativePath -replace '\.md$', '') -eq ($target -replace '\.md$', '')
        } | Sort-Object Distance, Stem | Select-Object -First 1)
        if ($matched.Count -eq 0) { throw "LinkTarget did not match any candidate: $LinkTarget" }
        $replacement = $matched[0].Stem
    }
    else {
        if ($Force) { throw "no candidate selected — provide -LinkTarget to proceed non-interactively" }
        $choice = Read-Host "Choose 1-$($top.Count) or mark-broken"
    }
    if ($choice -eq "mark-broken") {
        Add-DeferRecord -RepoRoot (Get-RepoRootLocal) -Finding $Finding -ActionName "mark-broken" -Note "marked broken link intentional"
        return
    }
    if ([string]::IsNullOrWhiteSpace($LinkTarget)) {
        $index = [int]$choice
        if ($index -lt 1 -or $index -gt $top.Count) { throw "Invalid link candidate selection." }
        $replacement = $top[$index - 1].Stem
    }
    Confirm-ResolveAction "Plan: replace link '$broken' with '$replacement' in $($Finding.File)." | Out-Null
    if (!$WhatIf) {
        $escaped = [regex]::Escape($broken)
        $updated = $content -replace "\[\[$escaped\]\]", "[[$replacement]]"
        $updated = $updated -replace "\]\($escaped\)", "]($replacement.md)"
        Set-Content -Path $filePath -Value $updated -Encoding UTF8
    }
}

function Invoke-ArchiveFinding {
    param([object]$Finding, [string]$VaultRoot)
    $filePath = Resolve-VaultFindingPath -Finding $Finding -VaultRoot $VaultRoot
    if ($null -eq $filePath) { return }
    Confirm-ResolveAction "Plan: archive $($Finding.File) with reason health-check-resolution." | Out-Null
    if (!$WhatIf) {
        & "$PSScriptRoot/archive-content.ps1" -File $filePath -Reason "health-check-resolution"
        if ($LASTEXITCODE -ne 0) { throw "archive-content.ps1 failed for $($Finding.File)" }
    }
}

function Invoke-BatchMetadata {
    param([array]$Findings, [string]$VaultRoot)
    if ([string]::IsNullOrWhiteSpace($Field) -or [string]::IsNullOrWhiteSpace($Value)) { throw "-Field and -Value are required for batch update-metadata." }
    $targets = @($Findings | Where-Object { $_.Rule -eq "require-$Field" -or $_.Issue -match "Missing required field:\s*$([regex]::Escape($Field))" })
    Confirm-ResolveAction "Plan: set $Field on $($targets.Count) files." | Out-Null
    foreach ($finding in $targets) {
        try { Update-FindingMetadata -Finding $finding -VaultRoot $VaultRoot }
        catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

function Invoke-BulkArchiveStale {
    param([array]$Findings, [string]$VaultRoot)
    $targets = @($Findings | Where-Object { $_.Type -eq "Stale Content" -and $_.Severity -eq "High" })
    Confirm-ResolveAction "Plan: archive $($targets.Count) high-severity stale files." | Out-Null
    foreach ($finding in $targets) {
        try {
            $filePath = Resolve-VaultFindingPath -Finding $finding -VaultRoot $VaultRoot
            if ($null -eq $filePath) { continue }
            if (!$WhatIf) {
                & "$PSScriptRoot/archive-content.ps1" -File $filePath -Reason "health-check-resolution"
                if ($LASTEXITCODE -ne 0) { throw "archive-content.ps1 failed for $($finding.File)" }
            }
        }
        catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

function Invoke-BatchExtendReview {
    param([array]$Findings, [string]$VaultRoot)
    if ([string]::IsNullOrWhiteSpace($Project)) { throw "-Project is required for -BatchExtendReview." }
    $reviewDate = (Get-Date).AddDays($Days).ToString("yyyy-MM-dd")
    $updated = 0
    foreach ($finding in @($Findings | Where-Object { $_.Type -eq "Stale Content" })) {
        $filePath = Resolve-VaultFindingPath -Finding $finding -VaultRoot $VaultRoot
        if ($null -eq $filePath) { continue }
        if (!(Test-Path -LiteralPath $filePath)) { continue }
        $data = Get-FrontmatterData -Content (Get-Content -LiteralPath $filePath -Raw -Encoding UTF8)
        if ($null -eq $data) { continue }
        if ((Get-FrontmatterValue -Frontmatter $data.Frontmatter -Key "project") -ne $Project) { continue }
        Confirm-ResolveAction "Plan: extend review_trigger for $($finding.File) to $reviewDate." | Out-Null
        if (!$WhatIf) { & "$PSScriptRoot/update-wiki-metadata.ps1" -File $filePath -ReviewTrigger $reviewDate }
        $updated++
    }
    Write-Host "Updated review_trigger for $updated files."
}

if ($Help) { Show-ResolveFindingsHelp; exit 0 }

try {
    $repoRoot = Get-RepoRootLocal
    $config = Get-Config -Project $Project
    $vaultRoot = [string]$config.system.vault_root
    if ($BulkArchiveStale -or $BatchExtendReview -or $Batch -or $FindingIndex -gt 0) {
        if ([string]::IsNullOrWhiteSpace($ReportFile)) { throw "-ReportFile is required." }
    }
    $reportPath = if (![string]::IsNullOrWhiteSpace($ReportFile)) { Resolve-PathFromRoot -Path $ReportFile -Root $repoRoot } else { "" }
    $findings = @(if (![string]::IsNullOrWhiteSpace($reportPath)) { Get-ReportFindings -Path $reportPath } else { @() })

    if ($BulkArchiveStale) { Invoke-BulkArchiveStale -Findings $findings -VaultRoot $vaultRoot; exit 0 }
    if ($BatchExtendReview) { Invoke-BatchExtendReview -Findings $findings -VaultRoot $vaultRoot; exit 0 }
    if ($Batch) {
        if ($Action -ne "update-metadata") { throw "-Batch currently supports -Action update-metadata only." }
        Invoke-BatchMetadata -Findings $findings -VaultRoot $vaultRoot
        exit 0
    }
    if ($FindingIndex -lt 1 -or $FindingIndex -gt $findings.Count) { throw "-FindingIndex must be between 1 and $($findings.Count)." }
    if ([string]::IsNullOrWhiteSpace($Action)) { throw "-Action is required." }

    $finding = $findings[$FindingIndex - 1]
    Write-Host "Finding #$FindingIndex"
    Write-Host "File: $($finding.File)"
    Write-Host "Severity: $($finding.Severity)"
    Write-Host "Rule: $($finding.Rule)"
    Write-Host "Issue: $($finding.Issue)"
    Write-Host "Suggested actions: $(Get-SuggestedActionsForRule -Rule $finding.Rule)"

    switch ($Action) {
        "update-metadata" { Update-FindingMetadata -Finding $finding -VaultRoot $vaultRoot }
        "fix-link" { Repair-BrokenLink -Finding $finding -Config $config }
        "archive" { Invoke-ArchiveFinding -Finding $finding -VaultRoot $vaultRoot }
        "rebuild-index" { Write-Host "index.md rebuild is a manual step - edit the folder index.md to reflect current content" }
        "defer" { Confirm-ResolveAction "Plan: defer $($finding.File) / $($finding.Rule) for 30 days."; if (!$WhatIf) { Add-DeferRecord -RepoRoot $repoRoot -Finding $finding -ActionName "defer" -Note $DeferNote } }
        default {
            Confirm-ResolveAction "Plan: record $Action for $($finding.File) / $($finding.Rule)." | Out-Null
            if (!$WhatIf) { Add-DeferRecord -RepoRoot $repoRoot -Finding $finding -ActionName $Action -Note "" }
            Write-Host "recorded - re-run health-check to see updated report"
        }
    }
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
