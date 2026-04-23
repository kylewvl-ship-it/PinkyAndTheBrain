#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceFile,
    [switch]$WhatIf,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/lib/config-loader.ps1"
if (Test-Path "$PSScriptRoot/lib/git-operations.ps1") {
    . "$PSScriptRoot/lib/git-operations.ps1"
}

function Test-WikiInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }

    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Get-RelativeRepoPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if ($resolvedPath.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Replace($RepoRoot, '').TrimStart('/\').Replace('\', '/')
    }

    return ""
}

function Get-KnowledgeRelativePath {
    param([string]$Path)

    $resolvedPath = [System.IO.Path]::GetFullPath($Path).Replace('\', '/')
    $marker = "/knowledge/"
    $markerIndex = $resolvedPath.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($markerIndex -ge 0) {
        return $resolvedPath.Substring($markerIndex + 1)
    }

    return [System.IO.Path]::GetFileName($Path)
}

function Get-FrontmatterData {
    param([string]$Content)

    $normalized = $Content -replace "`r`n", "`n"
    if ($normalized -notmatch '(?s)^---\n(.*?)\n---\n?(.*)$') {
        return $null
    }

    return @{
        Frontmatter = $matches[1]
        Body = $matches[2]
    }
}

function Get-FrontmatterValue {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    $pattern = '(?m)^' + [regex]::Escape($Key) + '\s*:\s*["'']?(.+?)["'']?\s*$'
    $match = [regex]::Match($Frontmatter, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return ""
}

function Get-FrontmatterList {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    $match = [regex]::Match($Frontmatter, '(?m)^' + [regex]::Escape($Key) + '\s*:\s*(.+?)\s*$')
    if (!$match.Success) {
        return @()
    }

    $rawValue = $match.Groups[1].Value.Trim()
    if ($rawValue -eq '[]') {
        return @()
    }

    if ($rawValue.StartsWith('[') -and $rawValue.EndsWith(']')) {
        $inner = $rawValue.Substring(1, $rawValue.Length - 2).Trim()
        if ([string]::IsNullOrWhiteSpace($inner)) {
            return @()
        }

        $items = @()
        foreach ($part in ($inner -split ',')) {
            $clean = $part.Trim().Trim('"').Trim("'")
            if (![string]::IsNullOrWhiteSpace($clean)) {
                $items += $clean
            }
        }
        return $items
    }

    return @()
}

function Get-MarkdownSectionContent {
    param(
        [string]$Body,
        [string]$Heading
    )

    $normalized = $Body -replace "`r`n", "`n"
    $pattern = '(?ms)^## ' + [regex]::Escape($Heading) + '\n(.*?)(?=^## |\z)'
    $match = [regex]::Match($normalized, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return ""
}

function Set-MarkdownSectionContent {
    param(
        [string]$Document,
        [string]$Heading,
        [string]$Content
    )

    $normalized = $Document -replace "`r`n", "`n"
    $pattern = '(?ms)(^## ' + [regex]::Escape($Heading) + '\n)(.*?)(?=^## |\z)'
    $replacement = {
        param($match)
        return $match.Groups[1].Value + ($Content.Trim()) + "`n`n"
    }

    $updated = [regex]::Replace($normalized, $pattern, $replacement, 1)
    return $updated.TrimEnd() + "`n"
}

function Format-SourceList {
    param([string[]]$SourceList)

    if ($null -eq $SourceList -or $SourceList.Count -eq 0) {
        return "[]"
    }

    $quoted = @()
    foreach ($item in $SourceList) {
        $quoted += ('"{0}"' -f $item)
    }
    return "[{0}]" -f ($quoted -join ', ')
}

function Get-RepairTemplate {
    return @"
Repair template:
---
title: "Your Title Here"
status: "draft"
confidence: "low"
source_list: []
promoted_to: ""
---
"@
}

function Test-TrueString {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return ($Value.Trim().ToLower() -in @('true', '1', 'yes', 'on'))
}

function Get-NextAvailableWikiPath {
    param(
        [string]$WikiDirectory,
        [string]$BaseName
    )

    $candidate = Join-Path $WikiDirectory ($BaseName + ".md")
    if (!(Test-Path $candidate)) {
        return $candidate
    }

    $suffix = 2
    while ($true) {
        $candidate = Join-Path $WikiDirectory ("{0}-{1}.md" -f $BaseName, $suffix)
        if (!(Test-Path $candidate)) {
            return $candidate
        }
        $suffix++
    }
}

function Update-WorkingNotePromotion {
    param(
        [string]$Content,
        [string]$PromotedPath
    )

    $normalized = $Content -replace "`r`n", "`n"
    $lines = $normalized -split "`n"
    $closingIndex = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "---") {
            $closingIndex = $i
            break
        }
    }

    if ($closingIndex -lt 0) {
        return $Content
    }

    $frontmatterLines = @()
    $statusUpdated = $false
    $promotedUpdated = $false
    for ($i = 1; $i -lt $closingIndex; $i++) {
        $line = $lines[$i]
        if ($line.TrimStart().StartsWith("status:")) {
            $frontmatterLines += 'status: "promoted"'
            $statusUpdated = $true
        }
        elseif ($line.TrimStart().StartsWith("promoted_to:")) {
            $frontmatterLines += ('promoted_to: "{0}"' -f $PromotedPath)
            $promotedUpdated = $true
        }
        else {
            $frontmatterLines += $line
        }
    }

    if (!$statusUpdated) {
        $frontmatterLines += 'status: "promoted"'
    }
    if (!$promotedUpdated) {
        $frontmatterLines += ('promoted_to: "{0}"' -f $PromotedPath)
    }

    $bodyLines = @()
    if ($closingIndex + 1 -lt $lines.Count) {
        $bodyLines = $lines[($closingIndex + 1)..($lines.Count - 1)]
    }

    return ("---`n{0}`n---`n{1}" -f ($frontmatterLines -join "`n"), ($bodyLines -join "`n"))
}

function Write-RetryRecord {
    param(
        [string]$HandoffsDirectory,
        [string]$SourceRelativePath,
        [string]$IntendedTitle,
        [string]$IsoTimestamp
    )

    if (!(Test-Path $HandoffsDirectory)) {
        New-Item -ItemType Directory -Path $HandoffsDirectory -Force | Out-Null
    }

    $fileName = "promote-retry-{0}.md" -f (Get-Date -Format "yyyyMMddHHmmssfff")
    $retryPath = Join-Path $HandoffsDirectory $fileName
    $content = @"
---
type: promote-retry
created: $IsoTimestamp
source_file: $SourceRelativePath
intended_title: $IntendedTitle
---

# Promotion Retry Record

Promotion of working note failed due to inaccessible wiki folder.

- Source: $SourceRelativePath
- Intended wiki title: $IntendedTitle
- Attempted: $IsoTimestamp

Run `.\scripts\promote-to-wiki.ps1 -SourceFile "$SourceRelativePath"` again once the wiki folder is accessible.
"@

    Set-Content -Path $retryPath -Value $content -Encoding UTF8
}

if ($Help) {
    Show-Usage "promote-to-wiki.ps1" "Promote a working note into a wiki page" @(
        ".\scripts\promote-to-wiki.ps1 -SourceFile 'knowledge/working/my-topic.md'"
    )
    exit 0
}

try {
    $config = Get-Config
    $wikiDir = Join-Path $config.system.vault_root $config.folders.wiki
    $handoffsDir = $config.folders.handoffs
    $isoTimestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"

    if (!(Test-Path $wikiDir)) {
        Write-Host "ERROR: Wiki folder is inaccessible: $wikiDir. Check folder permissions and disk space." -ForegroundColor Red
        Write-RetryRecord -HandoffsDirectory $handoffsDir -SourceRelativePath $SourceFile -IntendedTitle "unknown" -IsoTimestamp $isoTimestamp
        exit 2
    }
    if (!(Test-DirectoryStructure $config)) { exit 2 }

    $resolvedSourcePath = (Resolve-Path -LiteralPath $SourceFile -ErrorAction Stop).Path
    $sourceContent = Get-Content -Path $resolvedSourcePath -Raw -Encoding UTF8
    $sourceData = Get-FrontmatterData -Content $sourceContent

    if ($null -eq $sourceData) {
        Write-Host "ERROR: Working note frontmatter is missing required fields: title, status, confidence" -ForegroundColor Red
        Write-Host (Get-RepairTemplate)
        exit 1
    }

    $frontmatter = $sourceData.Frontmatter
    $missingFields = @()
    foreach ($field in @("title", "status", "confidence")) {
        if ([string]::IsNullOrWhiteSpace((Get-FrontmatterValue -Frontmatter $frontmatter -Key $field))) {
            $missingFields += $field
        }
    }

    if ($missingFields.Count -gt 0) {
        Write-Host "ERROR: Working note frontmatter is missing required fields: $($missingFields -join ', ')" -ForegroundColor Red
        Write-Host (Get-RepairTemplate)
        exit 1
    }

    if ($config.privacy -and $config.privacy.do_not_promote_blocks_wiki -and (Test-TrueString (Get-FrontmatterValue -Frontmatter $frontmatter -Key "do_not_promote"))) {
        Write-Host "ERROR: Working note has do_not_promote: true and cannot be promoted to wiki." -ForegroundColor Red
        exit 1
    }

    $wikiTitle = Get-FrontmatterValue -Frontmatter $frontmatter -Key "title"
    $confidence = Get-FrontmatterValue -Frontmatter $frontmatter -Key "confidence"
    $sourceList = @(Get-FrontmatterList -Frontmatter $frontmatter -Key "source_list")
    $sourceRelativePath = Get-KnowledgeRelativePath -Path $resolvedSourcePath

    $templatePath = Join-Path $config.system.template_root "wiki-page.md"

    if (!(Test-Path $templatePath)) {
        Write-Log "Wiki template not found: $templatePath" "ERROR"
        exit 2
    }

    $wikiKebab = Get-TimestampedFilename -Title $wikiTitle -Pattern $config.file_naming.wiki_pattern
    $wikiBaseName = [System.IO.Path]::GetFileNameWithoutExtension($wikiKebab)

    $duplicatePaths = @()
    if (Test-Path $wikiDir) {
        foreach ($wikiFile in (Get-ChildItem -Path $wikiDir -Filter *.md -File)) {
            $existingContent = Get-Content -Path $wikiFile.FullName -Raw -Encoding UTF8
            $existingData = Get-FrontmatterData -Content $existingContent
            $existingTitle = ""
            if ($null -ne $existingData) {
                $existingTitle = Get-FrontmatterValue -Frontmatter $existingData.Frontmatter -Key "title"
            }

            $existingKebab = [System.IO.Path]::GetFileNameWithoutExtension($wikiFile.Name)
            if (($existingKebab -ieq $wikiBaseName) -or (![string]::IsNullOrWhiteSpace($existingTitle) -and $existingTitle -ieq $wikiTitle)) {
                $duplicatePaths += $wikiFile.FullName
            }
        }
    }

    if ($duplicatePaths.Count -gt 0) {
        Write-Host "Potential duplicate wiki pages found:" -ForegroundColor Yellow
        foreach ($path in $duplicatePaths) {
            Write-Host "- $path" -ForegroundColor Yellow
        }

        if (Test-WikiInteractive) {
            $choice = Read-Host "Choose action [U]pdate existing, [M]erge, [C]reate new page, [Q]uit"
            switch -Regex ($choice) {
                '^[uU]$' {
                    Write-Output $duplicatePaths[0]
                    Write-Host "Open the existing wiki page to update it manually"
                    exit 0
                }
                '^[mM]$' {
                    Write-Output $duplicatePaths[0]
                    Write-Output $resolvedSourcePath
                    Write-Host "Open both files to merge content manually"
                    exit 0
                }
                '^[qQ]$' {
                    Write-Host "Promotion cancelled — no files changed"
                    exit 0
                }
            }
        }
    }

    $saveDraftWithoutSources = $false
    if ($sourceList.Count -eq 0) {
        Write-Host "Working note has no sources in source_list. Add sources before promoting." -ForegroundColor Yellow
        $saveDraftWithoutSources = $true
        if (Test-WikiInteractive) {
            $draftChoice = Read-Host "Save as draft wiki page for now? (y/N)"
            if ($draftChoice -notmatch '^[yY]$') {
                Write-Host "Promotion deferred — add sources to the working note first"
                exit 0
            }
        }
    }

    $reviewDays = 90
    if ($config.review_cadence -and $config.review_cadence.ContainsKey('wiki_days') -and $config.review_cadence.wiki_days -gt 0) {
        $reviewDays = $config.review_cadence.wiki_days
    }

    $wikiPath = Get-NextAvailableWikiPath -WikiDirectory $wikiDir -BaseName $wikiBaseName
    $wikiFileName = [System.IO.Path]::GetFileName($wikiPath)
    $wikiRelativePath = "knowledge/wiki/$wikiFileName"

    if ($WhatIf) {
        Write-Output "Would create wiki page: $wikiPath"
        Write-Output "Would update working note: $resolvedSourcePath"
        exit 0
    }

    if (Test-WikiInteractive) {
        Write-Host "Wiki file: $wikiFileName"
        Write-Host "Source working note: $sourceRelativePath"
        Write-Host "Source count: $($sourceList.Count)"
        $approval = Read-Host "Promote to wiki? (y/N)"
        if ($approval -notmatch '^[yY]$') {
            Write-Host "Promotion cancelled — no files changed"
            exit 0
        }
    }

    if (!(Test-Path $wikiDir)) {
        Write-Host "ERROR: Wiki folder is inaccessible: $wikiDir. Check folder permissions and disk space." -ForegroundColor Red
        Write-RetryRecord -HandoffsDirectory $handoffsDir -SourceRelativePath $sourceRelativePath -IntendedTitle $wikiTitle -IsoTimestamp $isoTimestamp
        exit 2
    }

    $template = Get-Content -Path $templatePath -Raw -Encoding UTF8
    $template = $template.Replace('<title>', $wikiTitle)
    $template = $template.Replace('<timestamp>', $isoTimestamp)
    $template = $template.Replace('<date>', (Get-Date).AddDays($reviewDays).ToString("yyyy-MM-dd"))
    $template = $template.Replace('confidence: "low"', ('confidence: "{0}"' -f $confidence))
    $template = $template.Replace('source_list: []', ('source_list: {0}' -f (Format-SourceList -SourceList $sourceList)))

    $body = $sourceData.Body
    $summaryContent = Get-MarkdownSectionContent -Body $body -Heading "What I Think"
    $detailsContent = Get-MarkdownSectionContent -Body $body -Heading "Evidence"
    $relationshipsContent = Get-MarkdownSectionContent -Body $body -Heading "Connections"
    $contradictionsContent = Get-MarkdownSectionContent -Body $body -Heading "Tensions / Contradictions"
    $sourcesContent = Get-MarkdownSectionContent -Body $body -Heading "Source Pointers"

    $whyItMatters = "<!-- Promoted from working note — fill in why this matters -->"
    $keyConcepts = "<!-- Promoted from working note — fill in key concepts -->"
    if ([string]::IsNullOrWhiteSpace($contradictionsContent)) {
        $contradictionsContent = "<!-- No contradictions recorded -->"
    }
    if ([string]::IsNullOrWhiteSpace($sourcesContent)) {
        $sourcesContent = "- No source pointers recorded."
    }
    if ($saveDraftWithoutSources) {
        $sourcesContent = "<!-- REVIEW: No sources — add provenance before marking verified -->`n`n$sourcesContent"
    }
    if ([string]::IsNullOrWhiteSpace($relationshipsContent)) {
        $relationshipsContent = "- None recorded."
    }
    if ([string]::IsNullOrWhiteSpace($detailsContent)) {
        $detailsContent = "Structured explanation."
    }
    if ([string]::IsNullOrWhiteSpace($summaryContent)) {
        $summaryContent = "Short factual overview."
    }

    $wikiContent = Set-MarkdownSectionContent -Document $template -Heading "Summary" -Content $summaryContent
    $wikiContent = Set-MarkdownSectionContent -Document $wikiContent -Heading "Why It Matters" -Content $whyItMatters
    $wikiContent = Set-MarkdownSectionContent -Document $wikiContent -Heading "Key Concepts" -Content $keyConcepts
    $wikiContent = Set-MarkdownSectionContent -Document $wikiContent -Heading "Details" -Content $detailsContent
    $wikiContent = Set-MarkdownSectionContent -Document $wikiContent -Heading "Relationships" -Content $relationshipsContent
    $wikiContent = Set-MarkdownSectionContent -Document $wikiContent -Heading "Contradictions / Caveats" -Content $contradictionsContent
    $wikiContent = Set-MarkdownSectionContent -Document $wikiContent -Heading "Sources" -Content $sourcesContent

    try {
        Set-Content -Path $wikiPath -Value $wikiContent -Encoding UTF8
    }
    catch {
        Write-Host "ERROR: Wiki folder is inaccessible: $wikiDir. Check folder permissions and disk space." -ForegroundColor Red
        Write-RetryRecord -HandoffsDirectory $handoffsDir -SourceRelativePath $sourceRelativePath -IntendedTitle $wikiTitle -IsoTimestamp $isoTimestamp
        exit 2
    }

    $updatedWorkingNote = Update-WorkingNotePromotion -Content $sourceContent -PromotedPath $wikiRelativePath
    Set-Content -Path $resolvedSourcePath -Value $updatedWorkingNote -Encoding UTF8

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $wikiRepoPath = Get-RelativeRepoPath -Path $wikiPath -RepoRoot $repoRoot
        $sourceRepoPath = Get-RelativeRepoPath -Path $resolvedSourcePath -RepoRoot $repoRoot
        $filesToCommit = @()
        if ($wikiRepoPath) { $filesToCommit += $wikiRepoPath }
        if ($sourceRepoPath) { $filesToCommit += $sourceRepoPath }
        if ($filesToCommit.Count -gt 0) {
            Invoke-GitCommit -Message ("Wiki: promoted from {0}" -f [System.IO.Path]::GetFileName($resolvedSourcePath)) -Files $filesToCommit -RepoPath $repoRoot | Out-Null
        }
    }

    Write-Host "Created wiki page: $wikiPath" -ForegroundColor Green
    Write-Output $wikiPath
}
catch {
    Write-Log "Promote to wiki failed: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
