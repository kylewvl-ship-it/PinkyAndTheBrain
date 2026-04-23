#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Query = "",
    [string]$Layers = "",
    [int]$MaxResults = 0,
    [string]$Project = "",
    [switch]$Wiki,
    [switch]$Working,
    [switch]$Raw,
    [switch]$Archive,
    [switch]$Tasks,
    [switch]$IncludeArchived,
    [switch]$CaseSensitive,
    [int]$Open = 0,
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
. "$PSScriptRoot/lib/frontmatter.ps1"

function Get-RepoRoot {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (![string]::IsNullOrWhiteSpace($envRepoRoot)) {
        return [System.IO.Path]::GetFullPath($envRepoRoot)
    }
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Test-ContainsValue {
    param(
        [string]$Text,
        [string]$Needle,
        [switch]$CaseSensitive
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Needle)) {
        return $false
    }

    $comparison = if ($CaseSensitive) {
        [System.StringComparison]::Ordinal
    }
    else {
        [System.StringComparison]::OrdinalIgnoreCase
    }

    return ($Text.IndexOf($Needle, $comparison) -ge 0)
}

function Get-QueryTokens {
    param([string]$Query)

    return @(
        ($Query -split '\s+') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' } |
            Select-Object -Unique
    )
}

function Get-LayerDefinitions {
    param([hashtable]$Config)

    $vaultRoot = [System.IO.Path]::GetFullPath([string]$Config.system.vault_root)
    $repoRoot = Get-RepoRoot
    $handoffFolder = if ($Config.folders.ContainsKey('handoffs')) { [string]$Config.folders.handoffs } else { ".ai/handoffs" }
    $tasksPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repoRoot, $handoffFolder))

    return [ordered]@{
        wiki = @{
            Name = 'wiki'
            Label = 'WIKI'
            Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.wiki))
        }
        working = @{
            Name = 'working'
            Label = 'WORK'
            Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.working))
        }
        raw = @{
            Name = 'raw'
            Label = 'RAW'
            Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.raw))
        }
        archive = @{
            Name = 'archive'
            Label = 'ARCH'
            Path = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.archive))
        }
        tasks = @{
            Name = 'tasks'
            Label = 'TASK'
            Path = $tasksPath
        }
    }
}

function Resolve-SelectedLayers {
    param(
        [hashtable]$Config,
        [string]$LayerSpec,
        [switch]$Wiki,
        [switch]$Working,
        [switch]$Raw,
        [switch]$Archive,
        [switch]$Tasks,
        [switch]$IncludeArchived
    )

    $definitions = Get-LayerDefinitions -Config $Config
    $explicit = @()

    if ($Wiki) { $explicit += 'wiki' }
    if ($Working) { $explicit += 'working' }
    if ($Raw) { $explicit += 'raw' }
    if ($Archive) { $explicit += 'archive' }
    if ($Tasks) { $explicit += 'tasks' }

    if ($IncludeArchived) {
        Write-Host "WARN: -IncludeArchived is deprecated; use -Archive to include archived content." -ForegroundColor Yellow
    }

    if (![string]::IsNullOrWhiteSpace($LayerSpec)) {
        foreach ($layerName in ($LayerSpec -split ',')) {
            $candidate = $layerName.Trim().ToLowerInvariant()
            if ($candidate -eq 'all') {
                $explicit = @('wiki', 'working', 'raw', 'tasks')
                if ($Archive) {
                    $explicit += 'archive'
                }
                break
            }
            if ($candidate -eq 'archive' -and -not $Archive) {
                continue
            }
            if ($definitions.Contains($candidate)) {
                $explicit += $candidate
            }
        }
    }

    if ($explicit.Count -eq 0) {
        $explicit = @('wiki', 'working', 'raw', 'tasks')
    }

    $orderedNames = @()
    foreach ($name in @('wiki', 'working', 'raw', 'archive', 'tasks')) {
        if ($explicit -contains $name) {
            $orderedNames += $name
        }
    }

    $selected = [ordered]@{}
    foreach ($name in ($orderedNames | Select-Object -Unique)) {
        $selected[$name] = $definitions[$name]
    }

    return $selected
}

function Get-PreviewLines {
    param([string]$Body)

    $lines = @(
        ($Body -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' } |
            Select-Object -First 2
    )

    if ($lines.Count -eq 0) {
        return @("(no preview available)")
    }

    return $lines
}

function Get-MatchScore {
    param(
        [string]$Title,
        [string]$Body,
        [hashtable]$FrontmatterValues,
        [string]$Query,
        [string[]]$Tokens,
        [switch]$CaseSensitive
    )

    $score = 0
    $sortRank = 0
    $matchType = ''
    $normalizedTitle = if ($Title) { $Title.Trim() } else { '' }
    $normalizedQuery = $Query.Trim()
    $comparison = if ($CaseSensitive) {
        [System.StringComparison]::Ordinal
    }
    else {
        [System.StringComparison]::OrdinalIgnoreCase
    }

    if ($normalizedTitle.Equals($normalizedQuery, $comparison)) {
        $score += 100
        $sortRank = 4
        $matchType = 'ExactTitle'
    }
    elseif (Test-ContainsValue -Text $normalizedTitle -Needle $normalizedQuery -CaseSensitive:$CaseSensitive) {
        $score += 35
        $sortRank = [Math]::Max($sortRank, 2)
        $matchType = 'PartialTitle'
    }

    if (Test-ContainsValue -Text $Body -Needle $normalizedQuery -CaseSensitive:$CaseSensitive) {
        $score += 50
        $sortRank = [Math]::Max($sortRank, 3)
        if ($matchType -eq '' -or $matchType -eq 'PartialTitle') {
            $matchType = 'ExactContent'
        }
    }
    else {
        $partialMatch = $false
        foreach ($token in $Tokens) {
            if ($token.Length -lt 3) {
                continue
            }
            if (Test-ContainsValue -Text $Body -Needle $token -CaseSensitive:$CaseSensitive) {
                $partialMatch = $true
                break
            }
        }

        if ($partialMatch) {
            $score += 35
            $sortRank = [Math]::Max($sortRank, 2)
            if ($matchType -eq '') {
                $matchType = 'PartialContent'
            }
        }
    }

    foreach ($key in $FrontmatterValues.Keys) {
        $value = [string]$FrontmatterValues[$key]
        if (Test-ContainsValue -Text $value -Needle $normalizedQuery -CaseSensitive:$CaseSensitive) {
            $score += 25
            $sortRank = [Math]::Max($sortRank, 1)
            if ($matchType -eq '') {
                $matchType = 'Metadata'
            }
        }
    }

    return @{
        Score = $score
        SortRank = $sortRank
        MatchType = $matchType
    }
}

function Search-Files {
    param(
        [hashtable]$Layers,
        [string]$Query,
        [string]$Project,
        [switch]$CaseSensitive,
        [int]$MaxResults
    )

    $results = @()
    $tokens = Get-QueryTokens -Query $Query
    $repoRoot = Get-RepoRoot

    foreach ($layerName in $Layers.Keys) {
        $layer = $Layers[$layerName]
        if (!(Test-Path $layer.Path)) {
            Write-Log "Layer path not found: $($layer.Path)" "WARN"
            continue
        }

        foreach ($file in (Get-ChildItem -Path $layer.Path -Filter "*.md" -Recurse -File)) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
                $frontmatterData = Get-FrontmatterData -Content $content
                $frontmatter = if ($null -ne $frontmatterData) { $frontmatterData.Frontmatter } else { '' }
                $body = if ($null -ne $frontmatterData) { $frontmatterData.Body } else { $content }

                $frontmatterValues = @{
                    title = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'title'
                    confidence = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'confidence'
                    status = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'status'
                    archived_date = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'archived_date'
                    archive_reason = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'archive_reason'
                    owner = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'owner'
                    project = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'project'
                }

                if ($Project -and $frontmatterValues.project -ne $Project) {
                    continue
                }

                $title = if ($frontmatterValues.title) { $frontmatterValues.title } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
                $scoring = Get-MatchScore -Title $title -Body $body -FrontmatterValues $frontmatterValues -Query $Query -Tokens $tokens -CaseSensitive:$CaseSensitive
                if ($scoring.Score -le 0) {
                    continue
                }

                $results += [PSCustomObject]@{
                    LayerName = $layer.Name
                    Layer = $layer.Label
                    FileName = $file.Name
                    FullPath = $file.FullName
                    RepoRelativePath = (Get-RelativeRepoPath -Path $file.FullName -RepoRoot $repoRoot)
                    Title = $title
                    LastModified = $file.LastWriteTime
                    PreviewLines = @(Get-PreviewLines -Body $body)
                    MatchType = $scoring.MatchType
                    SortRank = $scoring.SortRank
                    RelevanceScore = $scoring.Score
                    Frontmatter = $frontmatter
                    ContentBody = $body
                    Confidence = $frontmatterValues.confidence
                    Status = $frontmatterValues.status
                    ArchivedDate = $frontmatterValues.archived_date
                    ArchiveReason = $frontmatterValues.archive_reason
                    Owner = $frontmatterValues.owner
                }
            }
            catch {
                Write-Log "Error processing file $($file.FullName): $($_.Exception.Message)" "WARN"
            }
        }
    }

    return @(
        $results |
            Sort-Object @{ Expression = 'SortRank'; Descending = $true }, @{ Expression = 'RelevanceScore'; Descending = $true }, @{ Expression = 'Title'; Descending = $false } |
            Select-Object -First $MaxResults
    )
}

function Get-LayerColor {
    param([string]$Layer)

    if ($Layer -eq 'WIKI') { return 'Green' }
    if ($Layer -eq 'WORK') { return 'Yellow' }
    if ($Layer -eq 'RAW') { return 'Blue' }
    if ($Layer -eq 'ARCH') { return 'DarkGray' }
    if ($Layer -eq 'TASK') { return 'Cyan' }
    return 'White'
}

function Show-LayerSpecificMetadata {
    param([pscustomobject]$Result)

    if ($Result.Layer -eq 'WIKI' -and $Result.Confidence) {
        $color = 'Gray'
        if ($Result.Confidence -eq 'high') { $color = 'Green' }
        elseif ($Result.Confidence -eq 'medium') { $color = 'Yellow' }
        elseif ($Result.Confidence -eq 'low') { $color = 'Red' }
        Write-Host "   Confidence: $($Result.Confidence)" -ForegroundColor $color
    }
    elseif ($Result.Layer -eq 'ARCH') {
        $archiveBits = @()
        if ($Result.ArchivedDate) { $archiveBits += "Archived: $($Result.ArchivedDate)" }
        if ($Result.ArchiveReason) { $archiveBits += "Reason: $($Result.ArchiveReason)" }
        if ($archiveBits.Count -gt 0) {
            Write-Host ("   " + ($archiveBits -join ' | ')) -ForegroundColor DarkGray
        }
    }
    elseif ($Result.Layer -eq 'WORK' -and $Result.Status) {
        Write-Host "   Status: $($Result.Status)" -ForegroundColor Yellow
    }
}

function Show-SearchResults {
    param(
        [array]$Results,
        [string]$Query,
        [int]$MaxResults
    )

    if ($Results.Count -eq 0) {
        Write-Host "No results found for '$Query'." -ForegroundColor Yellow
        Write-Host "Try broader keywords or include archive with -Archive." -ForegroundColor Gray
        return
    }

    Write-Host "Search results for '$Query' ($($Results.Count) found)" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray

    for ($i = 0; $i -lt $Results.Count; $i++) {
        $result = $Results[$i]
        Write-Host "$($i + 1). " -NoNewline -ForegroundColor White
        Write-Host "[$($result.Layer)]" -NoNewline -ForegroundColor (Get-LayerColor -Layer $result.Layer)
        Write-Host " $($result.Title)" -ForegroundColor White
        Write-Host "   File: $($result.FileName) | Last modified: $($result.LastModified.ToString('yyyy-MM-dd HH:mm')) | Match: $($result.MatchType)" -ForegroundColor Gray
        Show-LayerSpecificMetadata -Result $result
        foreach ($line in $result.PreviewLines) {
            Write-Host "   $line" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    Write-Host ("=" * 80) -ForegroundColor Gray
    if ($Results.Count -eq $MaxResults) {
        Write-Host "Showing up to $MaxResults results." -ForegroundColor Yellow
    }
}

function Test-WikiTargetExists {
    param(
        [string]$Stem,
        [string]$KnowledgeRoot
    )

    if ([string]::IsNullOrWhiteSpace($Stem) -or !(Test-Path $KnowledgeRoot)) {
        return $false
    }

    return ($null -ne (Get-ChildItem -Path $KnowledgeRoot -Filter ($Stem + '.md') -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Test-MarkdownTargetExists {
    param(
        [string]$RelativeTarget,
        [string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($RelativeTarget)) {
        return $false
    }
    if ($RelativeTarget -match '^(https?:|mailto:|#)') {
        return $true
    }

    $candidate = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($RepoRoot, $RelativeTarget))
    return (Test-Path $candidate)
}

function Replace-BrokenLinks {
    param(
        [string]$Line,
        [string]$KnowledgeRoot,
        [string]$RepoRoot
    )

    $updated = [regex]::Replace(
        $Line,
        '\[\[([^\]|]+)(\|[^\]]+)?\]\]',
        {
            param($match)
            $stem = $match.Groups[1].Value.Trim()
            if (Test-WikiTargetExists -Stem $stem -KnowledgeRoot $KnowledgeRoot) {
                return $match.Value
            }
            return "[BROKEN LINK: $stem]"
        },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    return [regex]::Replace(
        $updated,
        '\[([^\]]+)\]\(([^)]+)\)',
        {
            param($match)
            $target = $match.Groups[2].Value.Trim()
            if (Test-MarkdownTargetExists -RelativeTarget $target -RepoRoot $RepoRoot) {
                return $match.Value
            }
            return "[BROKEN LINK: $target]"
        },
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
}

function Show-HighlightedLine {
    param(
        [string]$Line,
        [string]$Query,
        [switch]$CaseSensitive
    )

    if (Test-ContainsValue -Text $Line -Needle $Query -CaseSensitive:$CaseSensitive) {
        Write-Host $Line -ForegroundColor Yellow
    }
    else {
        Write-Host $Line
    }
}

function Show-SourceMetadataBlock {
    param(
        [pscustomobject]$Result,
        [hashtable]$Config
    )

    $fields = @()
    if ($Result.Confidence) { $fields += "Confidence: $($Result.Confidence)" }
    if ($Result.Status) { $fields += "Status: $($Result.Status)" }
    if ($Result.Owner) { $fields += "Owner: $($Result.Owner)" }
    if ($Result.ArchivedDate) { $fields += "Archived: $($Result.ArchivedDate)" }
    if ($Result.ArchiveReason) { $fields += "Reason: $($Result.ArchiveReason)" }
    $sourceList = Get-FrontmatterValue -Frontmatter $Result.Frontmatter -Key 'source_list'
    if ($sourceList) { $fields += "Sources: $sourceList" }

    Write-Host ('━' * 58) -ForegroundColor Gray
    Write-Host "[$($Result.Layer)] $($Result.RepoRelativePath)" -ForegroundColor (Get-LayerColor -Layer $Result.Layer)
    Write-Host "Last modified: $($Result.LastModified.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
    if ($fields.Count -gt 0) {
        Write-Host ($fields -join ' | ') -ForegroundColor Gray
    }
    Write-Host ('━' * 58) -ForegroundColor Gray
}

function Show-FileContent {
    param(
        [pscustomobject]$Result,
        [string]$Query,
        [hashtable]$Config,
        [switch]$CaseSensitive
    )

    $repoRoot = Get-RepoRoot
    $knowledgeRoot = [System.IO.Path]::GetFullPath([string]$Config.system.vault_root)
    $content = Get-Content -Path $Result.FullPath -Raw -Encoding UTF8
    $frontmatterData = Get-FrontmatterData -Content $content
    $body = if ($null -ne $frontmatterData) { $frontmatterData.Body } else { $content }

    Show-SourceMetadataBlock -Result $Result -Config $Config

    foreach ($line in ($body -split "`r?`n")) {
        $displayLine = Replace-BrokenLinks -Line $line -KnowledgeRoot $knowledgeRoot -RepoRoot $repoRoot
        Show-HighlightedLine -Line $displayLine -Query $Query -CaseSensitive:$CaseSensitive
    }
}

if ($Help) {
    Show-Usage "search.ps1" "Search across knowledge layers and open a result in the terminal" @(
        ".\scripts\search.ps1 -Query 'PowerShell'"
        ".\scripts\search.ps1 -Query 'metadata' -Wiki -Working"
        ".\scripts\search.ps1 -Query 'old topic' -Archive"
        ".\scripts\search.ps1 -Query 'frontmatter' -Open 2"
    )
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Query)) {
    Write-Host "ERROR: -Query is required." -ForegroundColor Red
    exit 1
}

if ($Open -lt 0) {
    Write-Host "ERROR: -Open must be zero or a positive result number." -ForegroundColor Red
    exit 1
}

try {
    $config = Get-Config -Project $Project
    if (!$PSBoundParameters.ContainsKey('MaxResults') -or $MaxResults -le 0) {
        $MaxResults = [int]$config.search.max_results
    }

    if (!$PSBoundParameters.ContainsKey('CaseSensitive')) {
        $CaseSensitive = [bool]$config.search.case_sensitive
    }

    if (!(Test-DirectoryStructure $config)) {
        Write-Log "Directory structure validation failed. Run setup-system.ps1 first." "ERROR"
        exit 2
    }

    $selectedLayers = Resolve-SelectedLayers -Config $config -LayerSpec $Layers -Wiki:$Wiki -Working:$Working -Raw:$Raw -Archive:$Archive -Tasks:$Tasks -IncludeArchived:$IncludeArchived
    if ($selectedLayers.Count -eq 0) {
        Write-Host "ERROR: No valid layers selected. Use -Wiki, -Working, -Raw, -Archive, or -Tasks." -ForegroundColor Red
        exit 1
    }

    Write-Host "Searching layers: $($selectedLayers.Keys -join ', ')" -ForegroundColor Cyan
    $results = @(Search-Files -Layers $selectedLayers -Query $Query -Project $Project -CaseSensitive:$CaseSensitive -MaxResults $MaxResults)
    Show-SearchResults -Results $results -Query $Query -MaxResults $MaxResults

    if ($Open -gt 0) {
        if ($Open -gt $results.Count) {
            Write-Host "ERROR: Result index $Open is out of range." -ForegroundColor Red
            exit 1
        }

        Write-Host ""
        Show-FileContent -Result $results[$Open - 1] -Query $Query -Config $config -CaseSensitive:$CaseSensitive
    }

    Write-Log "Search performed: '$Query' in layers [$($selectedLayers.Keys -join ',')] - $($results.Count) results" "INFO"
    exit 0
}
catch {
    Write-Log "Search failed: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
