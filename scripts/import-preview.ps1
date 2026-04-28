#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SourceVault = "",
    [string]$MappingRules = "",
    [string]$Profile = "",
    [string]$SaveProfile = "",
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

function Show-ImportPreviewHelp {
    Write-Host "import-preview.ps1 - Analyze an existing Obsidian vault without importing it"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\scripts\import-preview.ps1 -SourceVault C:\MyVault"
    Write-Host "  .\scripts\import-preview.ps1 -SourceVault C:\MyVault -MappingRules `"Daily Notes=raw;MOCs=wiki`""
    Write-Host "  .\scripts\import-preview.ps1 -SourceVault C:\MyVault -Profile .ai/import-previews/profile-work.json"
    Write-Host "  .\scripts\import-preview.ps1 -SourceVault C:\MyVault -Profile .ai/import-previews/profile-work.json -MappingRules `"Templates=skip`" -SaveProfile .ai/import-previews/profile-work.json"
    Write-Host ""
    Write-Host "Notes:"
    Write-Host "  - Mapping rule format: FolderName=category;Other Folder=category"
    Write-Host "  - Valid categories: inbox, raw, working, wiki, archive, skip"
    Write-Host "  - Explicit -MappingRules override matching entries loaded from -Profile"
    Write-Host "  - Preview artifacts are written under .ai/import-previews/"
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

function Get-FrontmatterValuesLocal {
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
        return @(($trimmed.Trim('[', ']') -split ',') |
            ForEach-Object { $_.Trim().Trim('"').Trim("'") } |
            Where-Object { $_ -ne '' })
    }

    return @($trimmed.Trim('"').Trim("'"))
}

function Get-CleanFilenameStem {
    param([string]$FileName)

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $stem = $stem -replace '^\d{4}-\d{2}-\d{2}-\d{6}-', ''
    $stem = $stem -replace '^\d{4}-\d{2}-\d{2}-', ''
    return $stem
}

function Get-LevenshteinDistance {
    param(
        [string]$A,
        [string]$B
    )

    $a = if ($null -eq $A) { '' } else { $A.ToLowerInvariant() }
    $b = if ($null -eq $B) { '' } else { $B.ToLowerInvariant() }
    $m = $a.Length
    $n = $b.Length
    $d = New-Object 'int[,]' ($m + 1), ($n + 1)

    for ($i = 0; $i -le $m; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $n; $j++) { $d[0, $j] = $j }

    for ($i = 1; $i -le $m; $i++) {
        for ($j = 1; $j -le $n; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $deleteCost = $d[($i - 1), $j] + 1
            $insertCost = $d[$i, ($j - 1)] + 1
            $replaceCost = $d[($i - 1), ($j - 1)] + $cost
            $d[$i, $j] = [Math]::Min([Math]::Min($deleteCost, $insertCost), $replaceCost)
        }
    }

    return $d[$m, $n]
}

function Get-LinkCount {
    param([string]$Content)

    $wikiLinks = [regex]::Matches($Content, '\[\[[^\]]+\]\]').Count
    $markdownLinks = [regex]::Matches($Content, '\[[^\]]+\]\([^)]+\)').Count
    return ($wikiLinks + $markdownLinks)
}

function Get-WordCount {
    param([string]$Content)

    $wordMatches = [regex]::Matches($Content, '\b[\p{L}\p{N}_-]+\b')
    return $wordMatches.Count
}

function Get-TokenSet {
    param([string]$Content)

    $tokens = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($match in [regex]::Matches($Content.ToLowerInvariant(), '\b[a-z0-9][a-z0-9_-]{2,}\b')) {
        [void]$tokens.Add($match.Value)
    }
    return $tokens
}

function Parse-MappingRulesString {
    param([string]$RuleText)

    $rules = @()
    if ([string]::IsNullOrWhiteSpace($RuleText)) {
        return $rules
    }

    foreach ($rawRule in ($RuleText -split ';')) {
        $trimmedRule = $rawRule.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedRule)) {
            continue
        }

        $parts = $trimmedRule -split '=', 2
        if ($parts.Count -ne 2) {
            throw "Invalid mapping rule '$trimmedRule'. Expected Folder=category."
        }

        $pattern = $parts[0].Trim()
        $category = $parts[1].Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw "Invalid mapping rule '$trimmedRule'. Folder name is empty."
        }
        if ($category -notin @('inbox', 'raw', 'working', 'wiki', 'archive', 'skip')) {
            throw "Invalid mapping rule '$trimmedRule'. Category '$category' is not supported."
        }

        $rules += [PSCustomObject]@{
            pattern = $pattern
            category = $category
        }
    }

    return $rules
}

function Get-ProfileRules {
    param([string]$ProfilePath)

    if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
        return @()
    }

    if (!(Test-Path $ProfilePath -PathType Leaf)) {
        throw "Profile file not found: $ProfilePath"
    }

    $profileData = Get-Content -Path $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rules = @()
    $hasMappingRules = $null -ne $profileData -and
        ($profileData.PSObject.Properties.Name -contains 'mapping_rules') -and
        $null -ne $profileData.mapping_rules
    if ($hasMappingRules) {
        foreach ($rule in @($profileData.mapping_rules)) {
            $pattern = [string]$rule.pattern
            $category = ([string]$rule.category).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                throw "Profile '$ProfilePath' contains a mapping rule with an empty pattern."
            }
            if ($category -notin @('inbox', 'raw', 'working', 'wiki', 'archive', 'skip')) {
                throw "Profile '$ProfilePath' contains mapping rule '$pattern' with unsupported category '$category'."
            }
            $rules += [PSCustomObject]@{
                pattern = $pattern
                category = $category
            }
        }
    }

    return $rules
}

function Merge-MappingRules {
    param(
        [object[]]$ProfileRules,
        [object[]]$ExplicitRules
    )

    $merged = [ordered]@{}
    foreach ($rule in @($ProfileRules)) {
        $merged[$rule.pattern.ToLowerInvariant()] = [PSCustomObject]@{
            pattern = $rule.pattern
            category = $rule.category
        }
    }
    foreach ($rule in @($ExplicitRules)) {
        $merged[$rule.pattern.ToLowerInvariant()] = [PSCustomObject]@{
            pattern = $rule.pattern
            category = $rule.category
        }
    }

    return @($merged.Values | Sort-Object { $_.pattern.Length } -Descending)
}

function Get-MatchingRule {
    param(
        [string]$RelativePath,
        [object[]]$MappingRules
    )

    $normalizedPath = $RelativePath.Replace('\', '/')
    $pathSegments = @($normalizedPath -split '/' | Where-Object { $_ -ne '' })
    foreach ($rule in @($MappingRules)) {
        $pattern = $rule.pattern.Replace('\', '/').Trim('/')
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        $patternSegments = @($pattern -split '/' | Where-Object { $_ -ne '' })
        if ($patternSegments.Count -eq 0) { continue }

        $patternMatched = $false
        for ($i = 0; $i -le ($pathSegments.Count - $patternSegments.Count); $i++) {
            $allEqual = $true
            for ($j = 0; $j -lt $patternSegments.Count; $j++) {
                if (-not [string]::Equals($pathSegments[$i + $j], $patternSegments[$j], [System.StringComparison]::OrdinalIgnoreCase)) {
                    $allEqual = $false
                    break
                }
            }
            if ($allEqual) { $patternMatched = $true; break }
        }
        if ($patternMatched) { return $rule }
    }

    return $null
}

function Get-ClassificationFromSignals {
    param(
        [string]$RelativePath,
        [string]$FileName,
        [string]$Title,
        [string]$Body,
        [string]$Frontmatter
    )

    $reasons = @()
    $normalizedPath = $RelativePath.Replace('\', '/').ToLowerInvariant()
    $normalizedName = $FileName.ToLowerInvariant()
    $normalizedTitle = $Title.ToLowerInvariant()
    $wordCount = Get-WordCount -Content $Body
    $linkCount = Get-LinkCount -Content $Body
    $linkDensity = if ($wordCount -gt 0) { [Math]::Round(($linkCount / [Math]::Max($wordCount, 1)), 3) } else { 0 }

    if ($normalizedPath -match '(^|/)(templates|\.obsidian|\.trash)(/|$)') {
        $reasons += "folder indicates template or Obsidian metadata"
        return @{ Category = 'skip'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($normalizedPath -match '(^|/)(archive|archives|old|deprecated)(/|$)') {
        $reasons += "folder indicates archived content"
        return @{ Category = 'archive'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($normalizedPath -match '(^|/)(daily|daily notes|journal|journals|log|logs|clippings|sources)(/|$)') {
        $reasons += "folder indicates raw captured material"
        return @{ Category = 'raw'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($normalizedPath -match '(^|/)(mocs?|maps? of content|indexes?)(/|$)' -or
        $normalizedName -match '\b(moc|index)\b' -or
        $normalizedTitle -match '\b(map of content|moc|index)\b') {
        $reasons += "path or title suggests map/index content"
        return @{ Category = 'wiki'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }

    if ($Frontmatter) {
        $statusRaw = Get-FrontmatterValue -Frontmatter $Frontmatter -Key 'status'
        $sourceTypeRaw = Get-FrontmatterValue -Frontmatter $Frontmatter -Key 'source_type'
        $reviewStatusRaw = Get-FrontmatterValue -Frontmatter $Frontmatter -Key 'review_status'
        $status = if ($null -eq $statusRaw) { '' } else { ([string]$statusRaw).ToLowerInvariant() }
        $sourceType = if ($null -eq $sourceTypeRaw) { '' } else { ([string]$sourceTypeRaw).ToLowerInvariant() }
        $reviewStatus = if ($null -eq $reviewStatusRaw) { '' } else { ([string]$reviewStatusRaw).ToLowerInvariant() }

        if ($sourceType -match '(capture|source|clip|reference)') {
            $reasons += "frontmatter source_type indicates captured source"
            return @{ Category = 'raw'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
        }
        if ($reviewStatus -eq 'published') {
            $reasons += "frontmatter review_status published"
            return @{ Category = 'wiki'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
        }
        if ($status -match '(active|draft|in-progress|wip)') {
            $reasons += "frontmatter status indicates active note"
            return @{ Category = 'working'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
        }
        if ($status -match '(archive|archived|deprecated)') {
            $reasons += "frontmatter status indicates archived note"
            return @{ Category = 'archive'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
        }
    }

    if ($wordCount -eq 0) {
        $reasons += "empty file has no content to classify"
        return @{ Category = 'unclassified'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($linkCount -ge 8 -or ($wordCount -gt 0 -and $linkDensity -ge 0.08)) {
        $reasons += "high link density suggests index or map note"
        return @{ Category = 'wiki'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($wordCount -le 12 -and $linkCount -eq 0) {
        $reasons += "very short note with weak signals is ambiguous"
        return @{ Category = 'unclassified'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($wordCount -le 80 -and $linkCount -le 1) {
        $reasons += "short standalone note defaults to inbox"
        return @{ Category = 'inbox'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($Body -match '(?im)^\s*(source|reference|quote|excerpt)\s*:') {
        $reasons += "content reads like captured source material"
        return @{ Category = 'raw'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }
    if ($wordCount -ge 180) {
        $reasons += "substantial developed note defaults to working"
        return @{ Category = 'working'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
    }

    $reasons += "signals were too weak for a confident recommendation"
    return @{ Category = 'unclassified'; Reasons = $reasons; WordCount = $wordCount; LinkCount = $linkCount; LinkDensity = $linkDensity }
}

function Get-DocumentTitle {
    param(
        [string]$Frontmatter,
        [string]$FilePath
    )

    if ($Frontmatter) {
        $frontmatterTitle = Get-FrontmatterValue -Frontmatter $Frontmatter -Key 'title'
        if (-not [string]::IsNullOrWhiteSpace($frontmatterTitle)) {
            return $frontmatterTitle.Trim()
        }
    }

    return [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
}

function Get-KnowledgeTargets {
    param([hashtable]$Config)

    $vaultRoot = [System.IO.Path]::GetFullPath([string]$Config.system.vault_root)
    $targets = @()
    foreach ($name in @('inbox', 'raw', 'working', 'wiki', 'archive')) {
        $targets += [PSCustomObject]@{
            category = $name
            path = [System.IO.Path]::GetFullPath((Join-Path $vaultRoot ([string]$Config.folders[$name])))
        }
    }

    return $targets
}

function Get-ExistingKnowledgeDocuments {
    param([hashtable]$Config)

    $documents = @()
    foreach ($target in (Get-KnowledgeTargets -Config $Config)) {
        if (!(Test-Path $target.path -PathType Container)) {
            continue
        }

        foreach ($file in @(Get-ChildItem -Path $target.path -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue)) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
                $frontmatterData = Get-FrontmatterData -Content $content
                $frontmatter = if ($null -ne $frontmatterData) { [string]$frontmatterData.Frontmatter } else { '' }
                $body = if ($null -ne $frontmatterData) { [string]$frontmatterData.Body } else { $content }
                $documents += [PSCustomObject]@{
                    path = $file.FullName
                    title = Get-DocumentTitle -Frontmatter $frontmatter -FilePath $file.FullName
                    stem = Get-CleanFilenameStem -FileName $file.Name
                    token_set = Get-TokenSet -Content $body
                }
            }
            catch {
            }
        }
    }

    return $documents
}

function Get-OverlapRatio {
    param(
        [System.Collections.Generic.HashSet[string]]$Left,
        [System.Collections.Generic.HashSet[string]]$Right
    )

    if ($Left.Count -eq 0 -or $Right.Count -eq 0) {
        return 0
    }

    $shared = 0
    foreach ($token in $Left) {
        if ($Right.Contains($token)) {
            $shared++
        }
    }

    if ($shared -eq 0) {
        return 0
    }

    return ($shared / [Math]::Min($Left.Count, $Right.Count))
}

function Get-DuplicateCandidates {
    param(
        [object[]]$SourceEntries,
        [object[]]$ExistingEntries
    )

    $duplicates = @()
    foreach ($sourceEntry in @($SourceEntries)) {
        foreach ($existingEntry in @($ExistingEntries)) {
            $reasons = @()

            $sourceTitle = if ($null -eq $sourceEntry.title) { '' } else { [string]$sourceEntry.title }
            $existingTitle = if ($null -eq $existingEntry.title) { '' } else { [string]$existingEntry.title }
            if ($sourceTitle -ne '' -and [string]::Equals($sourceTitle, $existingTitle, [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasons += 'exact title match'
            }

            $sourceStem = if ($null -eq $sourceEntry.clean_stem) { '' } else { [string]$sourceEntry.clean_stem }
            $existingStem = if ($null -eq $existingEntry.stem) { '' } else { [string]$existingEntry.stem }
            $distance = Get-LevenshteinDistance -A $sourceStem -B $existingStem
            if ($distance -lt 3 -and
                -not [string]::Equals($sourceStem, $existingStem, [System.StringComparison]::OrdinalIgnoreCase)) {
                $reasons += ('similar filename (distance {0})' -f $distance)
            }

            $overlapRatio = Get-OverlapRatio -Left $sourceEntry.token_set -Right $existingEntry.token_set
            if ($overlapRatio -ge 0.55 -and $sourceEntry.token_set.Count -ge 8 -and $existingEntry.token_set.Count -ge 8) {
                $reasons += ('content overlap estimate {0:p0}' -f $overlapRatio)
            }

            if ($reasons.Count -gt 0) {
                $duplicates += [PSCustomObject]@{
                    source_path = $sourceEntry.source_path
                    existing_path = $existingEntry.path
                    reasons = $reasons
                    resolution_options = @('skip', 'rename-with-suffix', 'merge-content', 'import-separate')
                }
            }
        }
    }

    return $duplicates
}

function New-PreviewMarkdown {
    param([pscustomobject]$Preview)

    $lines = @(
        '# Vault Import Preview'
        ''
        ('Generated: {0}' -f $Preview.generated_at)
        ('Source Vault: `{0}`' -f $Preview.source_vault)
        ''
        '## Summary'
        ''
        ('- Total files: {0}' -f $Preview.summary.total_files)
        ('- Total bytes: {0}' -f $Preview.summary.total_bytes)
        ('- Estimated import time: {0} seconds' -f $Preview.summary.estimated_import_seconds)
        ('- Estimate heuristic: 2 seconds base + 2 seconds per file + 1 second per duplicate candidate' )
        ''
        '## Proposed Category Counts'
        ''
    )

    foreach ($category in @('inbox', 'raw', 'working', 'wiki', 'archive', 'skip', 'unclassified')) {
        $lines += ('- {0}: {1}' -f $category, $Preview.category_counts.$category)
    }

    $lines += ''
    $lines += '## Mapping Rules'
    $lines += ''
    if (@($Preview.mapping_rules).Count -eq 0) {
        $lines += '- None'
    }
    else {
        foreach ($rule in @($Preview.mapping_rules)) {
            $lines += ('- `{0}` => `{1}`' -f $rule.pattern, $rule.category)
        }
    }

    $lines += ''
    $lines += '## Unclassified Files'
    $lines += ''
    if (@($Preview.unclassified).Count -eq 0) {
        $lines += '- None'
    }
    else {
        foreach ($entry in @($Preview.unclassified)) {
            $lines += ('- `{0}`: {1}' -f $entry.relative_path, ($entry.reasons -join '; '))
        }
    }

    $lines += ''
    $lines += '## Potential Duplicates'
    $lines += ''
    if (@($Preview.duplicates).Count -eq 0) {
        $lines += '- None'
    }
    else {
        foreach ($duplicate in @($Preview.duplicates)) {
            $lines += ('- `{0}` <> `{1}`' -f $duplicate.source_path, $duplicate.existing_path)
            $lines += ('  Reasons: {0}' -f ($duplicate.reasons -join '; '))
            $lines += ('  Options: {0}' -f ($duplicate.resolution_options -join ', '))
        }
    }

    $lines += ''
    $lines += '## Errors'
    $lines += ''
    if (@($Preview.errors).Count -eq 0) {
        $lines += '- None'
    }
    else {
        foreach ($errorEntry in @($Preview.errors)) {
            $lines += ('- `{0}`: {1}' -f $errorEntry.path, $errorEntry.message)
        }
    }

    $lines += ''
    $lines += '## Next Step'
    $lines += ''
    $lines += '- Story 5.4 can consume this preview to drive the actual import flow after review.'

    return ($lines -join "`r`n")
}

if ($Help) {
    Show-ImportPreviewHelp
    exit 0
}

try {
    if ([string]::IsNullOrWhiteSpace($SourceVault)) {
        Write-Host "Source vault is required. Use -SourceVault <path>." -ForegroundColor Red
        exit 1
    }

    $repoRoot = Get-RepoRoot
    $resolvedSourceVault = Resolve-AbsolutePath -Path $SourceVault -BasePath (Get-Location).Path
    if (!(Test-Path $resolvedSourceVault -PathType Container)) {
        Write-Host "Source vault does not exist or is not a directory: $resolvedSourceVault" -ForegroundColor Red
        exit 1
    }

    $config = Get-Config
    $sourceVaultWithSep = $resolvedSourceVault.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($target in (Get-KnowledgeTargets -Config $config)) {
        $targetWithSep = $target.path.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($sourceVaultWithSep.StartsWith($targetWithSep, [System.StringComparison]::OrdinalIgnoreCase) -or
            $targetWithSep.StartsWith($sourceVaultWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "Source vault overlaps configured knowledge folder '$($target.path)'. Choose a source vault outside the PinkyAndTheBrain knowledge tree." -ForegroundColor Red
            exit 1
        }
    }

    $previewRoot = Join-Path $repoRoot '.ai/import-previews'
    if (!(Test-Path $previewRoot)) {
        New-Item -ItemType Directory -Path $previewRoot -Force | Out-Null
    }

    $resolvedProfile = Resolve-AbsolutePath -Path $Profile -BasePath $repoRoot
    $resolvedSaveProfile = Resolve-AbsolutePath -Path $SaveProfile -BasePath $repoRoot
    try {
        $profileRules = Get-ProfileRules -ProfilePath $resolvedProfile
        $explicitRules = Parse-MappingRulesString -RuleText $MappingRules
    }
    catch {
        Write-Host ("Invalid mapping rules: {0}" -f $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    $effectiveRules = Merge-MappingRules -ProfileRules $profileRules -ExplicitRules $explicitRules

    $files = @(Get-ChildItem -Path $resolvedSourceVault -Filter '*.md' -Recurse -File -ErrorAction SilentlyContinue)
    $existingDocuments = Get-ExistingKnowledgeDocuments -Config $config
    $errors = @()
    $fileEntries = @()
    $unclassifiedEntries = @()
    $categoryCounts = [ordered]@{
        inbox = 0
        raw = 0
        working = 0
        wiki = 0
        archive = 0
        skip = 0
        unclassified = 0
    }
    $totalBytes = 0L

    foreach ($file in $files) {
        $relativePath = Get-RelativePathLocal -BasePath $resolvedSourceVault -TargetPath $file.FullName
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            $frontmatterData = Get-FrontmatterData -Content $content
            $frontmatter = if ($null -ne $frontmatterData) { [string]$frontmatterData.Frontmatter } else { '' }
            $body = if ($null -ne $frontmatterData) { [string]$frontmatterData.Body } else { $content }
            $title = Get-DocumentTitle -Frontmatter $frontmatter -FilePath $file.FullName
            $classification = Get-ClassificationFromSignals -RelativePath $relativePath -FileName $file.Name -Title $title -Body $body -Frontmatter $frontmatter
            $matchingRule = Get-MatchingRule -RelativePath $relativePath -MappingRules $effectiveRules
            $category = [string]$classification.Category
            $reasons = @($classification.Reasons)

            if ($null -ne $matchingRule) {
                $category = [string]$matchingRule.category
                $reasons = @('mapping rule override: {0}={1}' -f $matchingRule.pattern, $matchingRule.category) + $reasons
            }

            $entry = [PSCustomObject]@{
                source_path = $file.FullName
                relative_path = $relativePath
                title = $title
                proposed_category = $category
                classification_reasons = $reasons
                size_bytes = [int64]$file.Length
                link_count = [int]$classification.LinkCount
                word_count = [int]$classification.WordCount
                project = (Get-FrontmatterValuesLocal -Frontmatter $frontmatter -Key 'project')
                domain = (Get-FrontmatterValuesLocal -Frontmatter $frontmatter -Key 'domain')
                shared = (Get-FrontmatterValue -Frontmatter $frontmatter -Key 'shared')
                clean_stem = Get-CleanFilenameStem -FileName $file.Name
                token_set = Get-TokenSet -Content $body
            }

            $fileEntries += $entry
            $categoryCounts[$category]++
            $totalBytes += [int64]$file.Length

            if ($category -eq 'unclassified') {
                $unclassifiedEntries += [PSCustomObject]@{
                    source_path = $file.FullName
                    relative_path = $relativePath
                    reasons = $reasons
                }
            }
        }
        catch {
            $errors += [PSCustomObject]@{
                path = $file.FullName
                message = $_.Exception.Message
            }
            $categoryCounts['unclassified']++
            $unclassifiedEntries += [PSCustomObject]@{
                source_path = $file.FullName
                relative_path = $relativePath
                reasons = @('file could not be read', $_.Exception.Message)
            }
        }
    }

    $duplicates = Get-DuplicateCandidates -SourceEntries $fileEntries -ExistingEntries $existingDocuments
    $estimatedImportSeconds = (2 + (@($fileEntries).Count * 2) + @($duplicates).Count)
    $generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $jsonPath = Join-Path $previewRoot ("import-preview-{0}.json" -f $stamp)
    $markdownPath = Join-Path $previewRoot ("import-preview-{0}.md" -f $stamp)

    $preview = [PSCustomObject]@{
        generated_at = $generatedAt
        source_vault = $resolvedSourceVault
        summary = [PSCustomObject]@{
            total_files = @($fileEntries).Count
            total_bytes = $totalBytes
            estimated_import_seconds = $estimatedImportSeconds
        }
        category_counts = [PSCustomObject]$categoryCounts
        files = @($fileEntries | ForEach-Object {
            [PSCustomObject]@{
                source_path = $_.source_path
                relative_path = $_.relative_path
                title = $_.title
                proposed_category = $_.proposed_category
                classification_reasons = $_.classification_reasons
                size_bytes = $_.size_bytes
                link_count = $_.link_count
                word_count = $_.word_count
                project = $_.project
                domain = $_.domain
                shared = $_.shared
            }
        })
        duplicates = $duplicates
        unclassified = $unclassifiedEntries
        errors = $errors
        mapping_rules = @($effectiveRules)
        estimates = [PSCustomObject]@{
            total_bytes = $totalBytes
            estimated_import_seconds = $estimatedImportSeconds
        }
    }

    $json = $preview | ConvertTo-Json -Depth 8
    $markdown = New-PreviewMarkdown -Preview $preview

    if ($PSCmdlet.ShouldProcess($jsonPath, 'Write preview artifacts')) {
        Set-Content -Path $jsonPath -Value $json -Encoding UTF8
        Set-Content -Path $markdownPath -Value $markdown -Encoding UTF8
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedSaveProfile)) {
        $profilePayload = [PSCustomObject]@{
            source_vault = $resolvedSourceVault
            saved_at = $generatedAt
            mapping_rules = @($effectiveRules)
        } | ConvertTo-Json -Depth 5

        $profileDirectory = Split-Path $resolvedSaveProfile -Parent
        if ($profileDirectory -and !(Test-Path $profileDirectory)) {
            New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        }

        if ($PSCmdlet.ShouldProcess($resolvedSaveProfile, 'Write mapping profile')) {
            Set-Content -Path $resolvedSaveProfile -Value $profilePayload -Encoding UTF8
        }
    }

    Write-Host ("Preview JSON: {0}" -f $jsonPath) -ForegroundColor Green
    Write-Host ("Preview Report: {0}" -f $markdownPath) -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($resolvedSaveProfile)) {
        Write-Host ("Saved Profile: {0}" -f $resolvedSaveProfile) -ForegroundColor Green
    }

    exit 0
}
catch {
    Write-Host ("Import preview failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    if ($null -ne $_.InvocationInfo) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor Red
    }
    if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
    }
    exit 2
}
