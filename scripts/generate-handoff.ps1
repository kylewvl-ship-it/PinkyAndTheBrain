#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Topic = "",
    [string]$Project = "",
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\frontmatter.ps1"

function Get-RepoRoot {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (![string]::IsNullOrWhiteSpace($envRepoRoot)) {
        return [System.IO.Path]::GetFullPath($envRepoRoot)
    }
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Remove-Frontmatter {
    param([string]$Content)

    if ($Content -match '(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$') {
        return $Matches[1].TrimStart()
    }
    return $Content
}

function Get-TokenEstimate {
    param([string]$Text)
    $effectiveText = if ($null -eq $Text) { '' } else { $Text }
    return [Math]::Ceiling($effectiveText.Length / 4)
}

function Test-ContainsText {
    param(
        [string]$Text,
        [string]$Needle
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Needle)) {
        return $false
    }

    return ($Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-FirstParagraph {
    param([string]$Body)

    $paragraph = @()
    $started = $false

    foreach ($line in ($Body -split "`r?`n")) {
        $trimmed = $line.Trim()
        if (!$started -and ($trimmed -eq '' -or $trimmed.StartsWith('#'))) {
            continue
        }
        if ($trimmed -eq '' -and $started) {
            break
        }
        if ($trimmed -ne '') {
            $started = $true
            $paragraph += $line
        }
    }

    return ($paragraph -join "`n").Trim()
}

function Get-SectionLines {
    param(
        [string]$Body,
        [string]$Heading
    )

    $results = @()
    $capture = $false

    foreach ($line in ($Body -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^##\s+') {
            if ($trimmed.Equals($Heading, [System.StringComparison]::OrdinalIgnoreCase)) {
                $capture = $true
                continue
            }
            if ($capture) {
                break
            }
        }

        if ($capture -and $trimmed -ne '' -and -not $trimmed.StartsWith('#')) {
            $results += $trimmed
            if ($results.Count -ge 3) {
                break
            }
        }
    }

    return @($results)
}

function Test-WorkingNoteTensions {
    param([string]$Body)

    $capture = $false
    foreach ($line in ($Body -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^##\s+') {
            if ($trimmed.Equals('## Tensions & Contradictions', [System.StringComparison]::OrdinalIgnoreCase)) {
                $capture = $true
                continue
            }
            if ($capture) {
                break
            }
        }

        if ($capture -and $trimmed -ne '' -and -not $trimmed.StartsWith('#')) {
            return $true
        }
    }

    return $false
}

function Get-FrontmatterValues {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    $value = Get-FrontmatterValue -Frontmatter $Frontmatter -Key $Key
    if ([string]::IsNullOrWhiteSpace($value)) {
        return @()
    }

    $trimmed = $value.Trim()
    if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
        return @(
            ($trimmed.Trim('[', ']') -split ',') |
                ForEach-Object { $_.Trim().Trim('"').Trim("'") } |
                Where-Object { $_ -ne '' }
        )
    }

    return @($trimmed.Trim('"').Trim("'"))
}

function Get-RedactedContent {
    param(
        [string]$Content,
        [string[]]$Sections
    )

    $updatedContent = $Content
    foreach ($sectionName in $Sections) {
        if ([string]::IsNullOrWhiteSpace($sectionName)) {
            continue
        }

        $pattern = "(?m)(^## $([regex]::Escape($sectionName))\s*$\r?\n)([\s\S]*?)(?=^## |\z)"
        $updatedContent = [regex]::Replace($updatedContent, $pattern, "`$1[REDACTED]`r`n`r`n")
    }

    return $updatedContent
}

function Get-HandoffCandidates {
    param(
        [string]$Topic,
        [string]$Project,
        [hashtable]$Config
    )

    $vaultRoot = [System.IO.Path]::GetFullPath([string]$Config.system.vault_root)
    $layerDefs = @(
        @{ Name = 'wiki'; Label = 'WIKI'; Path = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.wiki) }
        @{ Name = 'working'; Label = 'WORK'; Path = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.working) }
        @{ Name = 'raw'; Label = 'RAW'; Path = [System.IO.Path]::Combine($vaultRoot, [string]$Config.folders.raw) }
    )
    $repoRoot = Get-RepoRoot
    $candidates = @()
    $excludedPrivate = 0

    foreach ($layer in $layerDefs) {
        if (!(Test-Path $layer.Path)) {
            continue
        }

        $files = @(Get-ChildItem -Path $layer.Path -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($file in $files) {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            $frontmatterData = Get-FrontmatterData -Content $content
            $frontmatter = if ($null -ne $frontmatterData) { $frontmatterData.Frontmatter } else { '' }
            $body = Remove-Frontmatter -Content $content
            $firstParagraph = Get-FirstParagraph -Body $body
            $privateValues = @(Get-FrontmatterValues -Frontmatter $frontmatter -Key 'private')
            $excludeValues = @(Get-FrontmatterValues -Frontmatter $frontmatter -Key 'exclude_from_ai')
            $redactedSections = @(Get-FrontmatterValues -Frontmatter $frontmatter -Key 'redacted_sections')
            $projectValues = @(Get-FrontmatterValues -Frontmatter $frontmatter -Key 'project')

            $isPrivate = @($privateValues | Where-Object { $_.Equals('true', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            $excludeFromAi = @($excludeValues | Where-Object { $_.Equals('true', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
            if ($isPrivate -or $excludeFromAi) {
                $excludedPrivate++
                continue
            }

            if ($redactedSections.Count -gt 0) {
                $body = Get-RedactedContent -Content $body -Sections $redactedSections
            }

            if (-not [string]::IsNullOrWhiteSpace($Project)) {
                if ($projectValues.Count -eq 0) {
                    continue
                }

                $matchesProject = @($projectValues | Where-Object { $_.Equals($Project, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
                if (-not $matchesProject) {
                    continue
                }
            }

            $stem = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            if (-not (Test-ContainsText -Text $stem -Needle $Topic) -and -not (Test-ContainsText -Text $firstParagraph -Needle $Topic)) {
                continue
            }

            $titleValue = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'title'
            $statusValue = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'status'
            $confidenceValue = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'confidence'

            $candidates += [PSCustomObject]@{
                LayerName = $layer.Name
                LayerLabel = $layer.Label
                Path = $file.FullName
                RelativePath = Get-RelativeRepoPath -Path $file.FullName -RepoRoot $repoRoot
                FileName = $file.Name
                FileStem = $stem
                Title = if ($titleValue) { $titleValue } else { $stem }
                Frontmatter = $frontmatter
                Body = $body
                FirstParagraph = $firstParagraph
                Confidence = $confidenceValue
                Status = $statusValue
            }
        }
    }

    return @{
        Candidates = @($candidates)
        ExcludedPrivateCount = $excludedPrivate
    }
}

function Get-WikiContent {
    param(
        [pscustomobject]$Candidate,
        [int]$MaxWikiTokens
    )

    $body = $Candidate.Body.Trim()
    if ((Get-TokenEstimate -Text $body) -lt $MaxWikiTokens) {
        return $body
    }
    return (Get-FirstParagraph -Body $body)
}

function Get-WorkingNoteContent {
    param([pscustomobject]$Candidate)

    $sections = @()
    $firstParagraph = Get-FirstParagraph -Body $Candidate.Body
    if ($firstParagraph) {
        $sections += $firstParagraph
    }

    foreach ($heading in @('## Current Interpretation', '## Evidence', '## Key Points')) {
        $lines = @(Get-SectionLines -Body $Candidate.Body -Heading $heading)
        if ($lines.Count -gt 0) {
            $sections += $heading
            $sections += $lines
        }
    }

    return @{
        Content = ($sections -join "`n").Trim()
        HasTensions = (Test-WorkingNoteTensions -Body $Candidate.Body)
    }
}

function Get-RawContent {
    param([pscustomobject]$Candidate)

    $parts = @("# $($Candidate.FileStem)")
    $firstParagraph = Get-FirstParagraph -Body $Candidate.Body
    if ($firstParagraph) {
        $parts += ''
        $parts += $firstParagraph
    }

    return (($parts -join "`n").Trim())
}

function Test-ConflictingInfo {
    param(
        [object[]]$IncludedItems,
        [string]$Topic
    )

    $topicItems = @(
        $IncludedItems | Where-Object {
            (Test-ContainsText -Text $_.Title -Needle $Topic) -or (Test-ContainsText -Text $_.FirstHeading -Needle $Topic)
        }
    )

    if ($topicItems.Count -ge 2) {
        $confidenceValues = @($topicItems | ForEach-Object { $_.Confidence } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $statusValues = @($topicItems | ForEach-Object { $_.Status } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $needsReview = @($topicItems | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Status) -and $_.Status.Equals('needs_review', [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if ($confidenceValues.Count -gt 1 -or $statusValues.Count -gt 1 -or $needsReview) {
            foreach ($item in $topicItems) {
                if (-not $item.ConflictPrefix) {
                    $item.ConflictPrefix = '[CONFLICTING INFO]'
                }
            }
        }
    }

    foreach ($item in ($IncludedItems | Where-Object { $_.LayerName -eq 'working' -and $_.HasTensions })) {
        $item.ConflictPrefix = '[CONFLICTING INFO: see tensions section]'
    }
}

function Invoke-ContentAssembly {
    param(
        [object[]]$Candidates,
        [hashtable]$Config,
        [string]$Topic,
        [int]$ExcludedPrivateCount
    )

    $maxContextTokens = [int]$Config.ai_handoff.max_context_tokens
    $maxWikiTokens = [int]$Config.ai_handoff.max_wiki_tokens_per_page
    $includedItems = @()
    $excludedByBudget = 0
    $usedTokens = 0

    foreach ($candidate in $Candidates) {
        $contentBlock = ''
        $hasTensions = $false

        if ($candidate.LayerName -eq 'wiki') {
            $contentBlock = Get-WikiContent -Candidate $candidate -MaxWikiTokens $maxWikiTokens
        }
        elseif ($candidate.LayerName -eq 'working') {
            $working = Get-WorkingNoteContent -Candidate $candidate
            $contentBlock = $working.Content
            $hasTensions = $working.HasTensions
        }
        else {
            $contentBlock = Get-RawContent -Candidate $candidate
        }

        $itemTokens = [int](Get-TokenEstimate -Text $contentBlock)
        if (($usedTokens + $itemTokens) -gt $maxContextTokens) {
            $excludedByBudget++
            continue
        }

        $usedTokens += $itemTokens
        $firstHeading = ''
        foreach ($line in ($contentBlock -split "`r?`n")) {
            if ($line.Trim().StartsWith('#')) {
                $firstHeading = $line.Trim()
                break
            }
        }

        $includedItems += [PSCustomObject]@{
            LayerName = $candidate.LayerName
            LayerLabel = $candidate.LayerLabel
            RelativePath = $candidate.RelativePath
            Title = $candidate.Title
            FileStem = $candidate.FileStem
            ContentBlock = $contentBlock
            Tokens = $itemTokens
            Confidence = $candidate.Confidence
            Status = $candidate.Status
            HasTensions = $hasTensions
            FirstHeading = $firstHeading
            ConflictPrefix = ''
        }
    }

    Test-ConflictingInfo -IncludedItems $includedItems -Topic $Topic

    return @{
        IncludedItems = @($includedItems)
        TotalTokens = $usedTokens
        ExcludedByBudget = $excludedByBudget
        ExcludedPrivateCount = $ExcludedPrivateCount
    }
}

function Write-HandoffFile {
    param(
        [object[]]$IncludedItems,
        [string]$Topic,
        [string]$Project,
        [hashtable]$Config,
        [int]$TotalTokens,
        [int]$ExcludedByBudget,
        [int]$ExcludedPrivateCount
    )

    $repoRoot = Get-RepoRoot
    $handoffsDir = Join-Path $repoRoot ".ai\handoffs"
    New-Item -ItemType Directory -Path $handoffsDir -Force | Out-Null

    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $generatedLabel = Get-Date -Format "yyyy-MM-dd HH:mm"
    $slug = ($Topic.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 30) {
        $slug = $slug.Substring(0, 30).Trim('-')
    }
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'topic'
    }

    $outputPath = Join-Path $handoffsDir ("handoff-{0}-{1}.md" -f $timestamp, $slug)
    $maxContextTokens = [int]$Config.ai_handoff.max_context_tokens
    $lines = @(
        "# AI Handoff Context: $Topic"
        ''
        "**Generated:** $generatedLabel"
        "**Topic:** $Topic"
        "**Project scope:** $(if ([string]::IsNullOrWhiteSpace($Project)) { 'all' } else { $Project })"
        "**Token budget used:** $TotalTokens / $maxContextTokens"
    )

    foreach ($section in @(
        @{ Title = '## Wiki Knowledge'; Layer = 'wiki' }
        @{ Title = '## Working Notes'; Layer = 'working' }
        @{ Title = '## Raw References'; Layer = 'raw' }
    )) {
        $items = @($IncludedItems | Where-Object { $_.LayerName -eq $section.Layer })
        if ($items.Count -eq 0) {
            continue
        }

        $lines += ''
        $lines += $section.Title
        $lines += ''
        foreach ($item in $items) {
            $lines += "### $($item.RelativePath)"
            if ($item.ConflictPrefix) {
                $lines += $item.ConflictPrefix
            }
            $lines += $item.ContentBlock
            $lines += ''
        }
    }

    $lines += '## Source File List'
    $lines += ''
    foreach ($item in $IncludedItems) {
        $lines += "- $($item.RelativePath) [$($item.LayerLabel) | $($item.Tokens) tokens]"
    }
    if ($IncludedItems.Count -eq 0) {
        $lines += '- None'
    }

    $lines += ''
    $lines += '## Token Summary'
    $lines += ''
    $lines += "Total tokens used: $TotalTokens / $maxContextTokens"
    $lines += "Items included: $($IncludedItems.Count)"
    $lines += "Items excluded (budget): $ExcludedByBudget"
    $lines += "Items excluded (private): $ExcludedPrivateCount"

    Set-Content -Path $outputPath -Value ($lines -join "`r`n") -Encoding UTF8
    Write-Host "Handoff file: $outputPath" -ForegroundColor Green
    Write-Host "Token summary: $TotalTokens / $maxContextTokens | included: $($IncludedItems.Count) | excluded by budget: $ExcludedByBudget | excluded private: $ExcludedPrivateCount" -ForegroundColor Cyan

    return $outputPath
}

if ($Help) {
    Show-Usage "generate-handoff.ps1" "Generate a token-budgeted AI handoff context file" @(
        ".\scripts\generate-handoff.ps1 -Topic 'frontmatter validation'"
        ".\scripts\generate-handoff.ps1 -Topic 'capture workflow' -Project 'work'"
    )
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Topic)) {
    Show-Usage "generate-handoff.ps1" "Generate a token-budgeted AI handoff context file" @(
        ".\scripts\generate-handoff.ps1 -Topic 'frontmatter validation'"
        ".\scripts\generate-handoff.ps1 -Topic 'capture workflow' -Project 'work'"
    )
    exit 1
}

try {
    $config = Get-Config
    $discovery = Get-HandoffCandidates -Topic $Topic -Project $Project -Config $config
    $assembly = Invoke-ContentAssembly -Candidates $discovery.Candidates -Config $config -Topic $Topic -ExcludedPrivateCount $discovery.ExcludedPrivateCount
    $path = Write-HandoffFile -IncludedItems $assembly.IncludedItems -Topic $Topic -Project $Project -Config $config -TotalTokens $assembly.TotalTokens -ExcludedByBudget $assembly.ExcludedByBudget -ExcludedPrivateCount $assembly.ExcludedPrivateCount
    exit 0
}
catch {
    $lineNumber = if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 }
    Write-Log "Generate handoff failed at line ${lineNumber}: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: line ${lineNumber}: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
