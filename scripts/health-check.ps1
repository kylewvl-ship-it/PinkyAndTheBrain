#!/usr/bin/env pwsh
# PinkyAndTheBrain Health Check Script
# System validation and diagnostics for knowledge base

param(
    [ValidateSet("all", "metadata", "links", "stale", "duplicates", "orphans")]
    [string]$Type = "all",
    
    [switch]$Fix,
    [switch]$WhatIf,
    [switch]$Help
)

# Import common functions with validation
if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"

if (Test-Path "$PSScriptRoot/lib/git-operations.ps1") {
    . "$PSScriptRoot/lib/git-operations.ps1"
}

if ($Help) {
    Show-Usage "health-check.ps1" "Validate knowledge base health and integrity" @(
        ".\scripts\health-check.ps1"
        ".\scripts\health-check.ps1 -Type metadata"
        ".\scripts\health-check.ps1 -Type links -Fix"
        ".\scripts\health-check.ps1 -Type stale -WhatIf"
    )
    exit 0
}

function Get-HealthRelativePath {
    param([string]$Path, [string]$VaultRoot)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $resolvedVault = (Resolve-Path -LiteralPath $VaultRoot).Path
    if ($resolvedPath.StartsWith($resolvedVault, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Substring($resolvedVault.Length).TrimStart('\', '/') -replace '\\', '/'
    }
    return $resolvedPath -replace '\\', '/'
}

function Get-HealthFrontmatter {
    param([string]$Content)

    $frontmatter = @{}
    if ($Content -match '(?s)^---\s*\n(.*?)\n---') {
        $matches[1] -split "`n" | ForEach-Object {
            if ($_ -match '^(\w+):\s*(.*)$') {
                $frontmatter[$matches[1]] = $matches[2].Trim().Trim('"')
            }
        }
    }
    return $frontmatter
}

function Test-EmptyFrontmatterValue {
    param([hashtable]$Frontmatter, [string]$Key)

    if (!$Frontmatter.ContainsKey($Key)) { return $true }
    $value = [string]$Frontmatter[$Key]
    return [string]::IsNullOrWhiteSpace($value) -or $value.Trim() -eq "[]"
}

function Get-MarkdownBody {
    param([string]$Content)

    return ($Content -replace '(?s)^---.*?---\s*', '').Trim()
}

function Get-BodyHash {
    param([string]$Body)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Get-LevenshteinDistance {
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
            $current[$j] = [Math]::Min(
                [Math]::Min($previous[$j] + 1, $current[$j - 1] + 1),
                $previous[$j - 1] + $cost
            )
        }
        $temp = $previous
        $previous = $current
        $current = $temp
    }
    return $previous[$Right.Length]
}

function Test-Metadata {
    param([hashtable]$Config)
    
    $findings = @()
    $vaultRoot = $Config.system.vault_root
    $minContentLength = $Config.health_checks.min_content_length
    if ($null -eq $minContentLength -or $minContentLength -lt 0) { $minContentLength = 100 }
    
    Write-Host "🔍 Checking metadata integrity..." -ForegroundColor Cyan
    
    # Check all non-archived knowledge files
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (!(Test-Path $folderPath)) { continue }
        
        $files = Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        
        foreach ($file in $files) {
            try {
                $content = Get-Content $file.FullName -Raw
                
                # Check if frontmatter exists
                if ($content -notmatch '(?s)^---\s*\n(.*?)\n---') {
                    $findings += [PSCustomObject]@{
                        Type = "Missing Metadata"
                        Severity = "High"
                        File = Get-HealthRelativePath $file.FullName $vaultRoot
                        Rule = "require-frontmatter"
                        Issue = "No frontmatter found"
                        Suggestion = "Add frontmatter with required fields"
                    }
                    continue
                }
                
                $frontmatter = Get-HealthFrontmatter $content
                
                # Check required fields based on folder
                $requiredFields = switch ($folder) {
                    $Config.folders.inbox { @("captured_date", "source_type", "review_status") }
                    $Config.folders.working { @("status", "confidence", "last_updated") }
                    $Config.folders.wiki { @("status", "confidence", "last_updated", "last_verified") }
                    default { @() }
                }
                
                foreach ($field in $requiredFields) {
                    if (Test-EmptyFrontmatterValue $frontmatter $field) {
                        $findings += [PSCustomObject]@{
                            Type = "Missing Metadata"
                            Severity = "Medium"
                            File = Get-HealthRelativePath $file.FullName $vaultRoot
                            Rule = "require-$field"
                            Issue = "Missing required field: $field"
                            Suggestion = "Add $field to frontmatter"
                        }
                    }
                }

                if (($folder -eq $Config.folders.working -or $folder -eq $Config.folders.wiki) -and (Test-EmptyFrontmatterValue $frontmatter "sources")) {
                    $findings += [PSCustomObject]@{
                        Type = "Missing Metadata"
                        Severity = "Medium"
                        File = Get-HealthRelativePath $file.FullName $vaultRoot
                        Rule = "require-sources"
                        Issue = "Missing source references"
                        Suggestion = "Add sources to frontmatter"
                    }
                }
                
                # Check content length
                $contentBody = Get-MarkdownBody $content
                if ($contentBody.Length -lt $minContentLength) {
                    $findings += [PSCustomObject]@{
                        Type = "Missing Metadata"
                        Severity = "Low"
                        File = Get-HealthRelativePath $file.FullName $vaultRoot
                        Rule = "min-content-length"
                        Issue = "Content too short (< $minContentLength characters)"
                        Suggestion = "Add more content or consider deletion"
                    }
                }
            }
            catch {
                $findings += [PSCustomObject]@{
                    Type = "Missing Metadata"
                    Severity = "High"
                    File = Get-HealthRelativePath $file.FullName $vaultRoot
                    Rule = "parse-frontmatter"
                    Issue = "Failed to parse file: $($_.Exception.Message)"
                    Suggestion = "Check file format and encoding"
                }
            }
        }
    }
    
    return $findings
}

function Test-Links {
    param([hashtable]$Config)
    
    $findings = @()
    $vaultRoot = $Config.system.vault_root
    
    Write-Host "🔗 Checking internal links..." -ForegroundColor Cyan
    
    # Get all markdown files
    $allFiles = @()
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (Test-Path $folderPath) {
            $allFiles += Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        }
    }
    
    # Create lookup table of all files
    $fileMap = @{}
    foreach ($file in $allFiles) {
        $relativePath = $file.FullName.Replace($vaultRoot + "\", "").Replace("\", "/")
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $fileMap[$fileName] = $relativePath
        $fileMap[$relativePath] = $relativePath
    }
    
    # Check links in each file
    foreach ($file in $allFiles) {
        try {
            $content = Get-Content $file.FullName -Raw
            
            # Find markdown links [text](path) and wiki links [[path]]
            $links = @()
            $links += [regex]::Matches($content, '\[([^\]]+)\]\(([^)]+)\)') | ForEach-Object { $_.Groups[2].Value }
            $links += [regex]::Matches($content, '\[\[([^\]]+)\]\]') | ForEach-Object { $_.Groups[1].Value }
            
            foreach ($link in $links) {
                # Skip external links
                if ($link -match '^https?://') { continue }
                
                # Clean up link path
                $cleanLink = $link -replace '#.*$', '' # Remove anchors
                $cleanLink = $cleanLink.Trim()
                
                # Check if target exists
                $targetExists = $false
                
                # Try direct path match
                if ($fileMap.ContainsKey($cleanLink)) {
                    $targetExists = $true
                }
                # Try filename match
                elseif ($fileMap.ContainsKey([System.IO.Path]::GetFileNameWithoutExtension($cleanLink))) {
                    $targetExists = $true
                }
                # Try with .md extension
                elseif ($fileMap.ContainsKey($cleanLink + ".md")) {
                    $targetExists = $true
                }
                
                if (!$targetExists) {
                    $findings += [PSCustomObject]@{
                        Type = "Broken Links"
                        Severity = "Medium"
                        File = Get-HealthRelativePath $file.FullName $vaultRoot
                        Rule = "link-target-exists"
                        Issue = "Broken link: $link"
                        Suggestion = "Update link path or create missing file"
                    }
                }
            }
        }
        catch {
            Write-Log "Error checking links in $($file.FullName): $($_.Exception.Message)" "WARN"
        }
    }
    
    return $findings
}

function Test-StaleContent {
    param([hashtable]$Config)
    
    $findings = @()
    $vaultRoot = $Config.system.vault_root
    $staleThresholdMonths = $Config.health_checks.stale_threshold_months
    if (-not $staleThresholdMonths -or $staleThresholdMonths -le 0) { $staleThresholdMonths = 6 }
    
    Write-Host "📅 Checking for stale content..." -ForegroundColor Cyan
    
    $folders = @($Config.folders.working, $Config.folders.wiki)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (!(Test-Path $folderPath)) { continue }
        
        $files = Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        
        foreach ($file in $files) {
            try {
                $content = Get-Content $file.FullName -Raw
                $frontmatter = @{}
                
                # Parse frontmatter with error handling
                if ($content -match '(?s)^---\s*\n(.*?)\n---') {
                    try {
                        $yamlContent = $matches[1]
                        $yamlContent -split "`n" | ForEach-Object {
                            if ($_ -match '^(\w+):\s*(.*)$') {
                                $frontmatter[$matches[1]] = $matches[2].Trim('"')
                            }
                        }
                    }
                    catch {
                        Write-Log "Error parsing frontmatter in $($file.FullName): $($_.Exception.Message)" "WARN"
                        continue
                    }
                }
                
                # Check last_updated or last_verified dates
                $lastUpdated = $null
                if ($frontmatter.ContainsKey("last_updated")) {
                    try { $lastUpdated = [DateTime]::Parse($frontmatter.last_updated) } catch { }
                }
                if (!$lastUpdated -and $frontmatter.ContainsKey("last_verified")) {
                    try { $lastUpdated = [DateTime]::Parse($frontmatter.last_verified) } catch { }
                }
                if (!$lastUpdated) {
                    $lastUpdated = $file.LastWriteTime
                }
                
                $monthsOld = ((Get-Date) - $lastUpdated).Days / 30
                
                if ($monthsOld -gt $staleThresholdMonths) {
                    $severity = if ($monthsOld -gt 12) { "High" } elseif ($monthsOld -gt 9) { "Medium" } else { "Low" }
                    
                    $findings += [PSCustomObject]@{
                        Type = "Stale Content"
                        Severity = $severity
                        File = Get-HealthRelativePath $file.FullName $vaultRoot
                        Rule = "stale-threshold"
                        Issue = "Content is $([Math]::Round($monthsOld, 1)) months old"
                        Suggestion = "Review and update content or mark as archived"
                    }
                }
                
                # Check review_trigger dates
                if ($frontmatter.ContainsKey("review_trigger")) {
                    try {
                        $reviewDate = [DateTime]::Parse($frontmatter.review_trigger)
                        if ($reviewDate -lt (Get-Date)) {
                            $daysOverdue = ((Get-Date) - $reviewDate).Days
                            
                            $findings += [PSCustomObject]@{
                                Type = "Stale Content"
                                Severity = "Medium"
                                File = Get-HealthRelativePath $file.FullName $vaultRoot
                                Rule = "review-trigger-overdue"
                                Issue = "Review overdue by $daysOverdue days"
                                Suggestion = "Review content and update review_trigger date"
                            }
                        }
                    }
                    catch {
                        # Invalid date format
                    }
                }
            }
            catch {
                Write-Log "Error checking staleness of $($file.FullName): $($_.Exception.Message)" "WARN"
            }
        }
    }
    
    return $findings
}

function Test-Duplicates {
    param([hashtable]$Config)
    
    $findings = @()
    $vaultRoot = $Config.system.vault_root
    $similarityThreshold = $Config.health_checks.similarity_threshold
    if ($null -eq $similarityThreshold -or $similarityThreshold -le 0) { $similarityThreshold = 3 }
    
    Write-Host "🔄 Checking for duplicate content..." -ForegroundColor Cyan
    
    $allFiles = @()
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (Test-Path $folderPath) {
            $allFiles += Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        }
    }

    $fileData = @($allFiles | ForEach-Object {
        $content = ""
        try { $content = Get-Content $_.FullName -Raw } catch { }
        $frontmatter = Get-HealthFrontmatter $content
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $title = if ($frontmatter.ContainsKey("title") -and ![string]::IsNullOrWhiteSpace($frontmatter.title)) { [string]$frontmatter.title } else { $stem }
        $body = Get-MarkdownBody $content
        [PSCustomObject]@{
            File = $_
            RelativePath = Get-HealthRelativePath $_.FullName $vaultRoot
            Folder = $_.DirectoryName
            Stem = $stem
            Title = $title
            CompareName = $title.ToLowerInvariant()
            Body = $body
            BodyLength = $body.Length
            BodyHash = Get-BodyHash $body
        }
    })

    # Existing exact-title behavior, with subtype-compatible reporting.
    $titleGroups = $fileData | Group-Object Title
    foreach ($group in $titleGroups) {
        if ($group.Count -gt 1) {
            $files = $group.Group | ForEach-Object { $_.RelativePath }
            
            $findings += [PSCustomObject]@{
                Type = "Duplicates (title-similarity)"
                Severity = "Medium"
                File = $files -join ", "
                Rule = "duplicate-title"
                Issue = "Duplicate title: '$($group.Name)'"
                Suggestion = "Review files and merge or rename duplicates"
            }
        }
    }

    # Edit-distance candidates are limited to files in the same folder.
    foreach ($folderGroup in ($fileData | Group-Object Folder)) {
        $items = @($folderGroup.Group)
        for ($i = 0; $i -lt $items.Count; $i++) {
            for ($j = $i + 1; $j -lt $items.Count; $j++) {
                if ($items[$i].Stem.Length -gt 50 -and $items[$j].Stem.Length -gt 50) { continue }
                $distance = Get-LevenshteinDistance $items[$i].CompareName $items[$j].CompareName
                if ($distance -gt 0 -and $distance -lt $similarityThreshold) {
                    $findings += [PSCustomObject]@{
                        Type = "Duplicates (title-similarity)"
                        Severity = "Medium"
                        File = "$($items[$i].RelativePath), $($items[$j].RelativePath)"
                        Rule = "title-edit-distance"
                        Issue = "Similar titles or filenames: '$($items[$i].CompareName)' and '$($items[$j].CompareName)' (distance $distance)"
                        Suggestion = "Review files and merge or rename duplicates"
                    }
                }
            }
        }
    }

    $reportedPairs = @{}
    foreach ($hashGroup in ($fileData | Where-Object { $_.BodyLength -gt 0 } | Group-Object BodyHash)) {
        if ($hashGroup.Count -gt 1) {
            $items = @($hashGroup.Group)
            for ($i = 0; $i -lt $items.Count; $i++) {
                for ($j = $i + 1; $j -lt $items.Count; $j++) {
                    $key = @($items[$i].RelativePath, $items[$j].RelativePath) | Sort-Object
                    $pairKey = $key -join "|"
                    $reportedPairs[$pairKey] = $true
                    $findings += [PSCustomObject]@{
                        Type = "Duplicates (fingerprint-candidate)"
                        Severity = "Medium"
                        File = "$($items[$i].RelativePath), $($items[$j].RelativePath)"
                        Rule = "body-sha256-match"
                        Issue = "Identical content fingerprint"
                        Suggestion = "Review files and merge or archive duplicates"
                    }
                }
            }
        }
    }

    for ($i = 0; $i -lt $fileData.Count; $i++) {
        for ($j = $i + 1; $j -lt $fileData.Count; $j++) {
            if ($fileData[$i].BodyLength -eq 0 -or $fileData[$j].BodyLength -eq 0) { continue }
            $key = @($fileData[$i].RelativePath, $fileData[$j].RelativePath) | Sort-Object
            $pairKey = $key -join "|"
            if ($reportedPairs.ContainsKey($pairKey)) { continue }

            $maxLength = [Math]::Max($fileData[$i].BodyLength, $fileData[$j].BodyLength)
            $lengthDelta = [Math]::Abs($fileData[$i].BodyLength - $fileData[$j].BodyLength)
            $prefixA = if ($fileData[$i].BodyLength -lt 200) { $fileData[$i].Body } else { $fileData[$i].Body.Substring(0, 200) }
            $prefixB = if ($fileData[$j].BodyLength -lt 200) { $fileData[$j].Body } else { $fileData[$j].Body.Substring(0, 200) }
            if ($maxLength -gt 0 -and ($lengthDelta / $maxLength) -le 0.05 -and $prefixA -eq $prefixB) {
                $reportedPairs[$pairKey] = $true
                $findings += [PSCustomObject]@{
                    Type = "Duplicates (fingerprint-candidate)"
                    Severity = "Medium"
                    File = "$($fileData[$i].RelativePath), $($fileData[$j].RelativePath)"
                    Rule = "body-prefix-length-match"
                    Issue = "Near-identical content fingerprint"
                    Suggestion = "Review files and merge or archive duplicates"
                }
            }
        }
    }

    return $findings
}

function Test-ExtractionConfidenceGaps {
    param([hashtable]$Config)

    $findings = @()
    $vaultRoot = $Config.system.vault_root
    $folderPath = "$vaultRoot/$($Config.folders.wiki)"

    Write-Host "📚 Checking extraction confidence gaps..." -ForegroundColor Cyan

    if (!(Test-Path $folderPath)) { return $findings }

    foreach ($file in (Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse)) {
        try {
            $content = Get-Content $file.FullName -Raw
            $frontmatter = Get-HealthFrontmatter $content
            if (Test-EmptyFrontmatterValue $frontmatter "sources") {
                $findings += [PSCustomObject]@{
                    Type = "Extraction Confidence Gaps"
                    Severity = "Medium"
                    File = Get-HealthRelativePath $file.FullName $vaultRoot
                    Rule = "require-wiki-sources"
                    Issue = "Wiki file lacks source provenance"
                    Suggestion = "Add sources to frontmatter"
                }
            }
        }
        catch {
            Write-Log "Error checking extraction confidence in $($file.FullName): $($_.Exception.Message)" "WARN"
        }
    }

    return $findings
}

function Test-DerivedIndexDrift {
    param([hashtable]$Config)

    $findings = @()
    $vaultRoot = $Config.system.vault_root
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki)

    Write-Host "🧭 Checking derived index drift..." -ForegroundColor Cyan

    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (!(Test-Path $folderPath)) { continue }

        foreach ($directory in @(Get-Item -LiteralPath $folderPath) + @(Get-ChildItem -Path $folderPath -Directory -Recurse)) {
            $indexPath = Join-Path $directory.FullName "index.md"
            if (!(Test-Path -LiteralPath $indexPath)) { continue }

            $siblings = @(Get-ChildItem -Path $directory.FullName -Filter "*.md" -File | Where-Object { $_.Name -ne "index.md" })
            if ($siblings.Count -eq 0) { continue }

            $indexFile = Get-Item -LiteralPath $indexPath
            $indexTime = $indexFile.LastWriteTime
            try {
                $frontmatter = Get-HealthFrontmatter (Get-Content $indexPath -Raw)
                if ($frontmatter.ContainsKey("last_updated") -and ![string]::IsNullOrWhiteSpace($frontmatter.last_updated)) {
                    $indexTime = [DateTime]::Parse($frontmatter.last_updated)
                }
            }
            catch {
                $indexTime = $indexFile.LastWriteTime
            }

            $newestSibling = $siblings | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($indexTime -lt $newestSibling.LastWriteTime) {
                $findings += [PSCustomObject]@{
                    Type = "Derived Index Drift"
                    Severity = "Low"
                    File = Get-HealthRelativePath $indexPath $vaultRoot
                    Rule = "index-drift"
                    Issue = "Index is older than sibling file: $($newestSibling.Name)"
                    Suggestion = "Regenerate or update the folder index"
                }
            }
        }
    }
    
    return $findings
}

function Test-Orphans {
    param([hashtable]$Config)
    
    $findings = @()
    $vaultRoot = $Config.system.vault_root
    
    Write-Host "🏝️ Checking for orphaned files..." -ForegroundColor Cyan
    
    $candidateFiles = @()
    $sourceFiles = @()
    $targetMap = @{}
    $incomingTargets = @{}

    foreach ($folder in @($Config.folders.working, $Config.folders.wiki)) {
        $folderPath = "$vaultRoot/$folder"
        if (!(Test-Path $folderPath)) { continue }
        $candidateFiles += Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
    }

    foreach ($file in $candidateFiles) {
        $relativePath = Get-HealthRelativePath $file.FullName $vaultRoot
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        foreach ($key in @($relativePath, ($relativePath -replace '\.md$', ''), $stem)) {
            if (!$targetMap.ContainsKey($key)) { $targetMap[$key] = @() }
            $targetMap[$key] += $relativePath
        }
    }

    foreach ($folder in @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki)) {
        $folderPath = "$vaultRoot/$folder"
        if (Test-Path $folderPath) {
            $sourceFiles += Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        }
    }

    foreach ($file in $sourceFiles) {
            try {
                $content = Get-Content $file.FullName -Raw
                $sourceRelativePath = Get-HealthRelativePath $file.FullName $vaultRoot
                
                # Find all internal links
                $links = @()
                $links += [regex]::Matches($content, '\[([^\]]+)\]\(([^)]+)\)') | ForEach-Object { $_.Groups[2].Value }
                $links += [regex]::Matches($content, '\[\[([^\]]+)\]\]') | ForEach-Object { $_.Groups[1].Value }
                
                foreach ($link in $links) {
                    if ($link -match '^https?://') { continue }
                    $cleanLink = ($link -replace '#.*$', '').Trim()
                    $lookupKeys = @(
                        $cleanLink,
                        ([System.IO.Path]::GetFileNameWithoutExtension($cleanLink)),
                        ($cleanLink + ".md")
                    )
                    foreach ($key in $lookupKeys) {
                        if (!$targetMap.ContainsKey($key)) { continue }
                        foreach ($targetRelativePath in $targetMap[$key]) {
                            if ($targetRelativePath -ne $sourceRelativePath) {
                                $incomingTargets[$targetRelativePath] = $true
                            }
                        }
                    }
                }
            }
            catch {
                Write-Log "Error processing $($file.FullName): $($_.Exception.Message)" "WARN"
            }
    }
    
    # Find files with no incoming links
    foreach ($file in $candidateFiles) {
        $relativePath = Get-HealthRelativePath $file.FullName $vaultRoot

        if (!$incomingTargets.ContainsKey($relativePath)) {
            $findings += [PSCustomObject]@{
                Type = "Orphans"
                Severity = "Low"
                File = $relativePath
                Rule = "incoming-link-required"
                Issue = "No incoming links found"
                Suggestion = "Add links from other content or consider archiving"
            }
        }
    }
    
    return $findings
}

function Get-HealthTypeOrder {
    param([string]$Type)

    if ($Type -like "Duplicates*") { return 4 }
    switch ($Type) {
        "Missing Metadata" { 1 }
        "Broken Links" { 2 }
        "Stale Content" { 3 }
        "Orphans" { 5 }
        "Extraction Confidence Gaps" { 6 }
        "Derived Index Drift" { 7 }
        default { 99 }
    }
}

function Get-HealthDisplayType {
    param([string]$Type)

    if ($Type -like "Duplicates*") { return "Duplicates" }
    return $Type
}

function Get-HealthSeverityOrder {
    param([string]$Severity)

    switch ($Severity) {
        "High" { 1 }
        "Medium" { 2 }
        "Low" { 3 }
        default { 99 }
    }
}

function Get-OrderedHealthGroups {
    param([array]$Findings)

    return @($Findings | Group-Object { Get-HealthDisplayType $_.Type } | Sort-Object @{ Expression = { Get-HealthTypeOrder $_.Name } }, Name)
}

function Write-HealthReportFile {
    param([array]$Findings, [hashtable]$Config, [string]$CheckType)

    $vaultRoot = $Config.system.vault_root
    $date = Get-Date -Format 'yyyy-MM-dd'
    $reviewsFolder = if ($Config.folders.reviews) { $Config.folders.reviews } else { "reviews" }
    $reportDir = Join-Path $vaultRoot $reviewsFolder
    if (!(Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }

    $lines = @(
        "---",
        "generated: $date",
        "check_type: $CheckType",
        "total_findings: $($Findings.Count)",
        "---",
        "",
        "# Health Check Report - $date",
        "",
        "## Summary",
        "| Type | High | Medium | Low | Total |",
        "|------|------|--------|-----|-------|"
    )

    foreach ($group in (Get-OrderedHealthGroups $Findings)) {
        $high = @($group.Group | Where-Object { $_.Severity -eq "High" }).Count
        $medium = @($group.Group | Where-Object { $_.Severity -eq "Medium" }).Count
        $low = @($group.Group | Where-Object { $_.Severity -eq "Low" }).Count
        $lines += "| $($group.Name) | $high | $medium | $low | $($group.Count) |"
    }

    foreach ($group in (Get-OrderedHealthGroups $Findings)) {
        $lines += ""
        $lines += "## $($group.Name)"
        foreach ($finding in ($group.Group | Sort-Object @{ Expression = { Get-HealthSeverityOrder $_.Severity } }, File, Issue)) {
            $rule = if ($finding.PSObject.Properties.Name -contains "Rule") { $finding.Rule } else { "" }
            $lines += ""
            $lines += "- **$($finding.Severity)** $($finding.File)"
            if ((Get-HealthDisplayType $finding.Type) -ne $finding.Type) {
                $lines += "  - Subtype: $($finding.Type -replace '^Duplicates \((.*)\)$', '$1')"
            }
            $lines += "  - Rule: $rule"
            $lines += "  - Issue: $($finding.Issue)"
            $lines += "  - Suggested repair: $($finding.Suggestion)"
        }
    }

    if ($Findings.Count -eq 0) {
        $lines += "| None | 0 | 0 | 0 | 0 |"
        $lines += ""
        $lines += "No health issues found."
    }

    $reportPath = Join-Path $reportDir "health-report-$date.md"
    Set-Content -Path $reportPath -Value $lines -Encoding UTF8
    return $reportPath
}

function Show-HealthReport {
    param([array]$Findings, [hashtable]$Config, [string]$CheckType)

    $reportPath = Write-HealthReportFile $Findings $Config $CheckType

    Write-Host "`n🏥 Health Check Report" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray
    Write-Host "Total Issues Found: $($Findings.Count)" -ForegroundColor Yellow
    Write-Host "Report: $(Get-HealthRelativePath $reportPath $Config.system.vault_root)" -ForegroundColor Gray

    if ($Findings.Count -eq 0) {
        Write-Host "✅ No health issues found! Knowledge base is healthy." -ForegroundColor Green
        return
    }
    
    # Summary by severity
    $severityCounts = $Findings | Group-Object Severity
    foreach ($severity in $severityCounts) {
        $color = switch ($severity.Name) {
            "High" { "Red" }
            "Medium" { "Yellow" }
            "Low" { "Gray" }
        }
        Write-Host "$($severity.Name): $($severity.Count)" -ForegroundColor $color
    }
    
    Write-Host ""
    
    # Detailed findings by type
    foreach ($group in (Get-OrderedHealthGroups $Findings)) {
        Write-Host "📋 $($group.Name) ($($group.Count) issues)" -ForegroundColor Cyan
        Write-Host ("-" * 40) -ForegroundColor Gray
        
        foreach ($finding in $group.Group | Sort-Object @{ Expression = { Get-HealthSeverityOrder $_.Severity } }, File, Issue) {
            $severityColor = switch ($finding.Severity) {
                "High" { "Red" }
                "Medium" { "Yellow" }
                "Low" { "Gray" }
            }
            
            Write-Host "[$($finding.Severity)]" -NoNewline -ForegroundColor $severityColor
            Write-Host " $($finding.File)" -ForegroundColor White
            if ((Get-HealthDisplayType $finding.Type) -ne $finding.Type) {
                Write-Host "  Subtype: $($finding.Type -replace '^Duplicates \((.*)\)$', '$1')" -ForegroundColor DarkGray
            }
            if ($finding.PSObject.Properties.Name -contains "Rule") {
                Write-Host "  Rule: $($finding.Rule)" -ForegroundColor DarkGray
            }
            Write-Host "  Issue: $($finding.Issue)" -ForegroundColor Gray
            Write-Host "  Fix: $($finding.Suggestion)" -ForegroundColor DarkGray
            Write-Host ""
        }
    }
    
    Write-Host ("=" * 80) -ForegroundColor Gray
    Write-Host "💡 Use -Fix flag to automatically repair some issues" -ForegroundColor Yellow
}

try {
    # Load configuration
    $config = Get-Config
    
    # Validate directory structure
    if (!(Test-DirectoryStructure $config)) {
        Write-Log "Directory structure validation failed. Run setup-system.ps1 first." "ERROR"
        exit 2
    }
    
    Write-Host "🏥 Running PinkyAndTheBrain Health Check..." -ForegroundColor Cyan
    Write-Host "Check Type: $Type" -ForegroundColor Gray
    Write-Host ""
    
    $allFindings = @()
    
    # Run selected health checks
    switch ($Type) {
        "all" {
            $allFindings += Test-Metadata $config
            $allFindings += Test-Links $config
            $allFindings += Test-StaleContent $config
            $allFindings += Test-Duplicates $config
            $allFindings += Test-Orphans $config
            $allFindings += Test-ExtractionConfidenceGaps $config
            $allFindings += Test-DerivedIndexDrift $config
        }
        "metadata" { $allFindings += Test-Metadata $config }
        "links" { $allFindings += Test-Links $config }
        "stale" { $allFindings += Test-StaleContent $config }
        "duplicates" { $allFindings += Test-Duplicates $config }
        "orphans" { $allFindings += Test-Orphans $config }
    }
    
    # Show report
    Show-HealthReport $allFindings $config $Type
    
    # Log health check
    Write-Log "Health check completed: $Type - $($allFindings.Count) issues found" "INFO"

    if ($Fix -and -not $WhatIf -and (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue)) {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $candidateChanges = @(Get-GitUncommitted -RepoPath $repoRoot | ForEach-Object {
            if ($_ -match '^\s*\S+\s+(.+)$') { $matches[1].Trim('"') }
        } | Where-Object { $_ -match '^(knowledge|config)/' })
        if ($candidateChanges.Count -gt 0) {
            Invoke-GitCommit -Files $candidateChanges -Message "System maintenance: health check $Type fixes" -RepoPath $repoRoot | Out-Null
        }
    }
    
    if ($allFindings.Count -gt 0) {
        exit 1  # Issues found
    }
    else {
        exit 0  # All healthy
    }
}
catch {
    Write-Log "Health check failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Health check failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
