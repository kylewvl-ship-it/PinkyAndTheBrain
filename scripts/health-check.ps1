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

function Test-Metadata {
    param([hashtable]$Config)
    
    $findings = @()
    $vaultRoot = $Config.system.vault_root
    
    Write-Host "🔍 Checking metadata integrity..." -ForegroundColor Cyan
    
    # Check all knowledge files
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki, $Config.folders.archive)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (!(Test-Path $folderPath)) { continue }
        
        $files = Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        
        foreach ($file in $files) {
            try {
                $content = Get-Content $file.FullName -Raw
                $frontmatter = @{}
                
                # Check if frontmatter exists
                if ($content -notmatch '(?s)^---\s*\n(.*?)\n---') {
                    $findings += [PSCustomObject]@{
                        Type = "Missing Metadata"
                        Severity = "High"
                        File = $file.FullName.Replace($PWD.Path + "\", "")
                        Issue = "No frontmatter found"
                        Suggestion = "Add frontmatter with required fields"
                    }
                    continue
                }
                
                # Parse frontmatter
                $yamlContent = $matches[1]
                $yamlContent -split "`n" | ForEach-Object {
                    if ($_ -match '^(\w+):\s*(.*)$') {
                        $frontmatter[$matches[1]] = $matches[2].Trim('"')
                    }
                }
                
                # Check required fields based on folder
                $requiredFields = switch ($folder) {
                    $Config.folders.inbox { @("captured_date", "source_type", "review_status") }
                    $Config.folders.working { @("status", "confidence", "last_updated") }
                    $Config.folders.wiki { @("status", "confidence", "last_updated", "last_verified") }
                    default { @() }
                }
                
                foreach ($field in $requiredFields) {
                    if (!$frontmatter.ContainsKey($field) -or [string]::IsNullOrEmpty($frontmatter[$field])) {
                        $findings += [PSCustomObject]@{
                            Type = "Missing Metadata"
                            Severity = "Medium"
                            File = $file.FullName.Replace($PWD.Path + "\", "")
                            Issue = "Missing required field: $field"
                            Suggestion = "Add $field to frontmatter"
                        }
                    }
                }
                
                # Check content length
                $contentBody = $content -replace '(?s)^---.*?---\s*', ''
                if ($contentBody.Trim().Length -lt 50) {
                    $findings += [PSCustomObject]@{
                        Type = "Missing Metadata"
                        Severity = "Low"
                        File = $file.FullName.Replace($PWD.Path + "\", "")
                        Issue = "Content too short (< 50 characters)"
                        Suggestion = "Add more content or consider deletion"
                    }
                }
            }
            catch {
                $findings += [PSCustomObject]@{
                    Type = "Missing Metadata"
                    Severity = "High"
                    File = $file.FullName.Replace($PWD.Path + "\", "")
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
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki, $Config.folders.archive)
    
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
                        File = $file.FullName.Replace($PWD.Path + "\", "")
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
                        File = $file.FullName.Replace($PWD.Path + "\", "")
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
                                File = $file.FullName.Replace($PWD.Path + "\", "")
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
    
    Write-Host "🔄 Checking for duplicate content..." -ForegroundColor Cyan
    
    $allFiles = @()
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (Test-Path $folderPath) {
            $allFiles += Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        }
    }
    
    # Group by title and check for duplicates
    $titleGroups = $allFiles | Group-Object { 
        try {
            $content = Get-Content $_.FullName -Raw
            if ($content -match '(?s)^---\s*\n(.*?)\n---') {
                $yamlContent = $matches[1]
                if ($yamlContent -match 'title:\s*"?([^"]*)"?') {
                    return $matches[1].Trim()
                }
            }
            return [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        }
        catch {
            return [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        }
    }
    
    foreach ($group in $titleGroups) {
        if ($group.Count -gt 1) {
            $files = $group.Group | ForEach-Object { $_.FullName.Replace($PWD.Path + "\", "") }
            
            $findings += [PSCustomObject]@{
                Type = "Duplicates"
                Severity = "Medium"
                File = $files -join ", "
                Issue = "Duplicate title: '$($group.Name)'"
                Suggestion = "Review files and merge or rename duplicates"
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
    
    # Get all files and their links
    $allFiles = @()
    $allLinks = @()
    
    $folders = @($Config.folders.working, $Config.folders.wiki)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (!(Test-Path $folderPath)) { continue }
        
        $files = Get-ChildItem -Path $folderPath -Filter "*.md" -Recurse
        $allFiles += $files
        
        foreach ($file in $files) {
            try {
                $content = Get-Content $file.FullName -Raw
                
                # Find all internal links
                $links = @()
                $links += [regex]::Matches($content, '\[([^\]]+)\]\(([^)]+)\)') | ForEach-Object { $_.Groups[2].Value }
                $links += [regex]::Matches($content, '\[\[([^\]]+)\]\]') | ForEach-Object { $_.Groups[1].Value }
                
                foreach ($link in $links) {
                    if ($link -notmatch '^https?://') {
                        $allLinks += $link -replace '#.*$', '' # Remove anchors
                    }
                }
            }
            catch {
                Write-Log "Error processing $($file.FullName): $($_.Exception.Message)" "WARN"
            }
        }
    }
    
    # Find files with no incoming links
    foreach ($file in $allFiles) {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $relativePath = $file.FullName.Replace($vaultRoot + "\", "").Replace("\", "/")
        
        $hasIncomingLinks = $false
        foreach ($link in $allLinks) {
            if ($link -eq $fileName -or $link -eq $relativePath -or $link -eq ($relativePath -replace '\.md$', '')) {
                $hasIncomingLinks = $true
                break
            }
        }
        
        if (!$hasIncomingLinks) {
            $findings += [PSCustomObject]@{
                Type = "Orphans"
                Severity = "Low"
                File = $file.FullName.Replace($PWD.Path + "\", "")
                Issue = "No incoming links found"
                Suggestion = "Add links from other content or consider archiving"
            }
        }
    }
    
    return $findings
}

function Show-HealthReport {
    param([array]$Findings)
    
    if ($Findings.Count -eq 0) {
        Write-Host "✅ No health issues found! Knowledge base is healthy." -ForegroundColor Green
        return
    }
    
    # Group findings by type
    $groupedFindings = $Findings | Group-Object Type
    
    Write-Host "`n🏥 Health Check Report" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray
    Write-Host "Total Issues Found: $($Findings.Count)" -ForegroundColor Yellow
    
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
    foreach ($group in $groupedFindings) {
        Write-Host "📋 $($group.Name) ($($group.Count) issues)" -ForegroundColor Cyan
        Write-Host ("-" * 40) -ForegroundColor Gray
        
        foreach ($finding in $group.Group | Sort-Object Severity, File) {
            $severityColor = switch ($finding.Severity) {
                "High" { "Red" }
                "Medium" { "Yellow" }
                "Low" { "Gray" }
            }
            
            Write-Host "[$($finding.Severity)]" -NoNewline -ForegroundColor $severityColor
            Write-Host " $($finding.File)" -ForegroundColor White
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
        }
        "metadata" { $allFindings += Test-Metadata $config }
        "links" { $allFindings += Test-Links $config }
        "stale" { $allFindings += Test-StaleContent $config }
        "duplicates" { $allFindings += Test-Duplicates $config }
        "orphans" { $allFindings += Test-Orphans $config }
    }
    
    # Show report
    Show-HealthReport $allFindings
    
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
