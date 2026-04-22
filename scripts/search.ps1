#!/usr/bin/env pwsh
# PinkyAndTheBrain Knowledge Search Script
# Cross-layer knowledge search with relevance ranking

param(
    [Parameter(Mandatory=$true)]
    [string]$Query,
    
    [string]$Layers = "all",
    [int]$MaxResults = 0,
    [string]$Project = "",
    [switch]$IncludeArchived,
    [switch]$CaseSensitive,
    [switch]$Help
)

# Import common functions with validation
if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"

if ($Help) {
    Show-Usage "search.ps1" "Search across all knowledge layers" @(
        ".\scripts\search.ps1 -Query 'search term'"
        ".\scripts\search.ps1 -Query 'PowerShell' -Layers 'wiki,working'"
        ".\scripts\search.ps1 -Query 'project' -MaxResults 10"
        ".\scripts\search.ps1 -Query 'project' -Project general"
        ".\scripts\search.ps1 -Query 'archived content' -IncludeArchived"
    )
    exit 0
}

function Get-LayerFolders {
    param(
        [hashtable]$Config,
        [string]$LayerSpec,
        [switch]$IncludeArchived
    )
    
    $vaultRoot = $Config.system.vault_root
    $allLayers = @{
        "inbox" = @{ Path = "$vaultRoot/$($Config.folders.inbox)"; Label = "INBOX" }
        "raw" = @{ Path = "$vaultRoot/$($Config.folders.raw)"; Label = "RAW" }
        "working" = @{ Path = "$vaultRoot/$($Config.folders.working)"; Label = "WORK" }
        "wiki" = @{ Path = "$vaultRoot/$($Config.folders.wiki)"; Label = "WIKI" }
        "archive" = @{ Path = "$vaultRoot/$($Config.folders.archive)"; Label = "ARCH" }
    }
    
    if ($LayerSpec -eq "all") {
        $selectedLayers = $allLayers.Clone()
        if (!$IncludeArchived) {
            $selectedLayers.Remove("archive")
        }
    }
    else {
        $selectedLayers = @{}
        $LayerSpec -split ',' | ForEach-Object {
            $layer = $_.Trim().ToLower()
            if ($allLayers.ContainsKey($layer)) {
                $selectedLayers[$layer] = $allLayers[$layer]
            }
        }
    }
    
    return $selectedLayers
}

function Search-Files {
    param(
        [hashtable]$Layers,
        [string]$Query,
        [string]$Project = "",
        [switch]$CaseSensitive,
        [int]$MaxResults
    )
    
    $results = @()
    $searchOptions = if ($CaseSensitive) { @{} } else { @{ "CaseSensitive" = $false } }
    
    foreach ($layerName in $Layers.Keys) {
        $layer = $Layers[$layerName]
        $layerPath = $layer.Path
        $layerLabel = $layer.Label
        
        if (!(Test-Path $layerPath)) {
            Write-Log "Layer path not found: $layerPath" "WARN"
            continue
        }
        
        $files = Get-ChildItem -Path $layerPath -Filter "*.md" -Recurse
        
        foreach ($file in $files) {
            try {
                $content = Get-Content $file.FullName -Raw
                $frontmatter = @{}
                $contentBody = $content
                
                # Parse frontmatter
                if ($content -match '(?s)^---\s*\n(.*?)\n---') {
                    $yamlContent = $matches[1]
                    $contentBody = $content -replace '(?s)^---.*?---\s*', ''
                    
                    $yamlContent -split "`n" | ForEach-Object {
                        if ($_ -match '^(\w+):\s*(.*)$') {
                            $frontmatter[$matches[1]] = $matches[2].Trim('"')
                        }
                    }
                }
                
                if ($Project -and $frontmatter.project -ne $Project) {
                    continue
                }

                # Calculate relevance score
                $relevanceScore = 0
                $matchType = ""
                
                # Title match (highest priority)
                $title = if ($frontmatter.title) { $frontmatter.title } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
                if (($CaseSensitive -and $title -clike "*$Query*") -or (!$CaseSensitive -and $title -like "*$Query*")) {
                    $relevanceScore += 100
                    $matchType = "Title"
                }
                
                # Exact content match
                if (($CaseSensitive -and $contentBody -clike "*$Query*") -or (!$CaseSensitive -and $contentBody -like "*$Query*")) {
                    $relevanceScore += 50
                    if ($matchType -eq "") { $matchType = "Content" }
                }
                
                # Metadata match
                foreach ($key in $frontmatter.Keys) {
                    $metadataValue = [string]$frontmatter[$key]
                    if (($CaseSensitive -and $metadataValue -clike "*$Query*") -or (!$CaseSensitive -and $metadataValue -like "*$Query*")) {
                        $relevanceScore += 25
                        if ($matchType -eq "") { $matchType = "Metadata" }
                    }
                }
                
                # Skip if no matches
                if ($relevanceScore -eq 0) {
                    continue
                }
                
                # Get preview (first 2 lines of content)
                $lines = $contentBody -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 2
                $preview = ($lines -join " ").Substring(0, [Math]::Min(150, ($lines -join " ").Length))
                if (($lines -join " ").Length -gt 150) {
                    $preview += "..."
                }
                
                # Get confidence level if available
                $confidence = if ($frontmatter.confidence) { $frontmatter.confidence } else { "" }
                
                $results += [PSCustomObject]@{
                    Layer = $layerLabel
                    FileName = $file.Name
                    FullPath = $file.FullName
                    Title = $title
                    LastModified = $file.LastWriteTime
                    Preview = $preview
                    MatchType = $matchType
                    RelevanceScore = $relevanceScore
                    Confidence = $confidence
                    Private = ($frontmatter.private -eq "true")
                }
            }
            catch {
                Write-Log "Error processing file $($file.FullName): $($_.Exception.Message)" "WARN"
            }
        }
    }
    
    # Sort by relevance score (descending) and limit results
    return $results | Sort-Object RelevanceScore -Descending | Select-Object -First $MaxResults
}

function Show-SearchResults {
    param([array]$Results, [string]$Query)
    
    if ($Results.Count -eq 0) {
        Write-Host "🔍 No results found for: '$Query'" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Suggestions:" -ForegroundColor Cyan
        Write-Host "• Try different keywords or partial matches" -ForegroundColor Gray
        Write-Host "• Use -IncludeArchived to search archived content" -ForegroundColor Gray
        Write-Host "• Check spelling and try broader terms" -ForegroundColor Gray
        return
    }
    
    Write-Host "🔍 Search Results for: '$Query' ($($Results.Count) found)" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray
    
    for ($i = 0; $i -lt $Results.Count; $i++) {
        $result = $Results[$i]
        
        # Format result header
        Write-Host "$($i + 1). " -NoNewline -ForegroundColor White
        Write-Host "[$($result.Layer)]" -NoNewline -ForegroundColor $(
            if ($result.Layer -eq "WIKI") { "Green" }
            elseif ($result.Layer -eq "WORK") { "Yellow" }
            elseif ($result.Layer -eq "RAW") { "Blue" }
            elseif ($result.Layer -eq "INBOX") { "Cyan" }
            elseif ($result.Layer -eq "ARCH") { "Gray" }
            else { "White" }
        )
        
        Write-Host " $($result.Title)" -NoNewline -ForegroundColor White
        
        if ($result.Confidence) {
            $confidenceColor = if ($result.Confidence -eq "high") { "Green" }
                              elseif ($result.Confidence -eq "medium") { "Yellow" }
                              elseif ($result.Confidence -eq "low") { "Red" }
                              else { "Gray" }
            Write-Host " [$($result.Confidence)]" -NoNewline -ForegroundColor $confidenceColor
        }
        
        # Show private indicator
        if ($result.Private) {
            Write-Host " [PRIVATE]" -NoNewline -ForegroundColor Red
        }
        
        Write-Host ""
        
        # Show file info
        Write-Host "   📁 $($result.FileName)" -NoNewline -ForegroundColor Gray
        Write-Host " | 📅 $($result.LastModified.ToString('yyyy-MM-dd HH:mm'))" -NoNewline -ForegroundColor Gray
        Write-Host " | 🎯 $($result.MatchType)" -ForegroundColor Gray
        
        # Show preview
        Write-Host "   $($result.Preview)" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    Write-Host ("=" * 80) -ForegroundColor Gray
    
    if ($Results.Count -eq $MaxResults) {
        Write-Host "💡 Showing first $MaxResults results. Use -MaxResults to see more." -ForegroundColor Yellow
    }
}

try {
    # Load configuration
    $config = Get-Config -Project $Project
    if (!$PSBoundParameters.ContainsKey('MaxResults') -or $MaxResults -le 0) { $MaxResults = $config.search.max_results }
    $includeArchivedEffective = if ($PSBoundParameters.ContainsKey('IncludeArchived')) { $IncludeArchived.IsPresent } else { [bool]$config.search.include_archived }
    $caseSensitiveEffective = if ($PSBoundParameters.ContainsKey('CaseSensitive')) { $CaseSensitive.IsPresent } else { [bool]$config.search.case_sensitive }
    
    # Validate directory structure
    if (!(Test-DirectoryStructure $config)) {
        Write-Log "Directory structure validation failed. Run setup-system.ps1 first." "ERROR"
        exit 2
    }
    
    # Get layer folders to search
    $layersToSearch = Get-LayerFolders -Config $config -LayerSpec $Layers -IncludeArchived:$includeArchivedEffective
    
    if ($layersToSearch.Count -eq 0) {
        Write-Host "❌ No valid layers specified. Available layers: inbox, raw, working, wiki, archive" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "🔍 Searching layers: $($layersToSearch.Keys -join ', ')" -ForegroundColor Cyan
    
    # Perform search
    $results = Search-Files -Layers $layersToSearch -Query $Query -Project $Project -CaseSensitive:$caseSensitiveEffective -MaxResults $MaxResults
    
    # Display results
    Show-SearchResults -Results $results -Query $Query
    
    # Log search activity
    Write-Log "Search performed: '$Query' in layers [$($layersToSearch.Keys -join ',')] - $($results.Count) results" "INFO"
}
catch {
    Write-Log "Search failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Search failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
