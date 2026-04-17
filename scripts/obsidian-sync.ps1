#!/usr/bin/env pwsh
# PinkyAndTheBrain Obsidian Integration Script
# Utilities for Obsidian vault synchronization and compatibility

param(
    [ValidateSet("sync", "validate", "update-links", "create-index")]
    [string]$Action = "sync",
    
    [string]$VaultPath = "",
    [switch]$WhatIf,
    [switch]$Help
)

# Import common functions with validation
if (!(Test-Path "$PSScriptRoot/lib/common.ps1")) {
    Write-Error "Required dependency not found: $PSScriptRoot/lib/common.ps1"
    exit 2
}
. "$PSScriptRoot/lib/common.ps1"

if ($Help) {
    Show-Usage "obsidian-sync.ps1" "Obsidian vault integration utilities" @(
        ".\scripts\obsidian-sync.ps1 -Action sync"
        ".\scripts\obsidian-sync.ps1 -Action validate -VaultPath 'C:\MyVault'"
        ".\scripts\obsidian-sync.ps1 -Action update-links"
        ".\scripts\obsidian-sync.ps1 -Action create-index"
    )
    exit 0
}

function Sync-ObsidianVault {
    param([hashtable]$Config, [string]$VaultPath, [switch]$WhatIf)
    
    Write-Host "🔄 Syncing with Obsidian vault..." -ForegroundColor Cyan
    
    $vaultRoot = $Config.system.vault_root
    
    if ([string]::IsNullOrEmpty($VaultPath)) {
        # Try to detect Obsidian vault
        $possiblePaths = @(
            "$vaultRoot",
            "$env:USERPROFILE\Documents\Obsidian Vault",
            "$env:USERPROFILE\OneDrive\Documents\Obsidian Vault"
        )
        
        foreach ($path in $possiblePaths) {
            if (Test-Path "$path\.obsidian") {
                $VaultPath = $path
                break
            }
        }
        
        if ([string]::IsNullOrEmpty($VaultPath)) {
            Write-Host "❌ No Obsidian vault detected. Specify -VaultPath parameter." -ForegroundColor Red
            return $false
        }
    }
    
    Write-Host "📁 Vault Path: $VaultPath" -ForegroundColor Gray
    
    # Ensure .obsidian folder exists
    $obsidianFolder = "$VaultPath\.obsidian"
    if (!(Test-Path $obsidianFolder)) {
        if ($WhatIf) {
            Write-Host "Would create: $obsidianFolder" -ForegroundColor Yellow
        }
        else {
            New-Item -ItemType Directory -Path $obsidianFolder -Force | Out-Null
            Write-Host "✅ Created .obsidian folder" -ForegroundColor Green
        }
    }
    
    # Create basic Obsidian configuration
    $obsidianConfig = @{
        "theme" = "obsidian"
        "pluginEnabledStatus" = @{
            "file-explorer" = $true
            "global-search" = $true
            "switcher" = $true
            "graph" = $true
            "backlink" = $true
            "page-preview" = $true
            "note-composer" = $true
            "command-palette" = $true
            "markdown-importer" = $true
            "word-count" = $true
            "open-with-default-app" = $true
            "file-recovery" = $true
        }
    } | ConvertTo-Json -Depth 3
    
    $configPath = "$obsidianFolder\app.json"
    if ($WhatIf) {
        Write-Host "Would update: $configPath" -ForegroundColor Yellow
    }
    else {
        Set-Content -Path $configPath -Value $obsidianConfig -Encoding UTF8
        Write-Host "✅ Updated Obsidian configuration" -ForegroundColor Green
    }
    
    return $true
}

function Test-ObsidianCompatibility {
    param([hashtable]$Config, [string]$VaultPath)
    
    Write-Host "🔍 Validating Obsidian compatibility..." -ForegroundColor Cyan
    
    $issues = @()
    $vaultRoot = $Config.system.vault_root
    
    if ([string]::IsNullOrEmpty($VaultPath)) {
        $VaultPath = $vaultRoot
    }
    
    # Check for Obsidian-incompatible file names
    $allFiles = Get-ChildItem -Path $VaultPath -Filter "*.md" -Recurse
    
    foreach ($file in $allFiles) {
        # Check for invalid characters in filename
        $invalidChars = @(':', '*', '?', '"', '<', '>', '|')
        $hasInvalidChars = $false
        
        foreach ($char in $invalidChars) {
            if ($file.Name.Contains($char)) {
                $hasInvalidChars = $true
                break
            }
        }
        
        if ($hasInvalidChars) {
            $issues += [PSCustomObject]@{
                Type = "Invalid Filename"
                File = $file.FullName.Replace($VaultPath + "\", "")
                Issue = "Contains Obsidian-incompatible characters"
                Suggestion = "Rename file to remove: $($invalidChars -join ', ')"
            }
        }
        
        # Check for very long filenames (Obsidian limit ~255 chars)
        if ($file.Name.Length -gt 200) {
            $issues += [PSCustomObject]@{
                Type = "Long Filename"
                File = $file.FullName.Replace($VaultPath + "\", "")
                Issue = "Filename too long ($($file.Name.Length) characters)"
                Suggestion = "Shorten filename to under 200 characters"
            }
        }
    }
    
    # Check for proper frontmatter format
    foreach ($file in $allFiles) {
        try {
            $content = Get-Content $file.FullName -Raw
            
            if ($content -match '(?s)^---\s*\n(.*?)\n---') {
                $yamlContent = $matches[1]
                
                # Check for common YAML issues
                if ($yamlContent -match '^\s*[^:]+$') {
                    $issues += [PSCustomObject]@{
                        Type = "Invalid YAML"
                        File = $file.FullName.Replace($VaultPath + "\", "")
                        Issue = "Malformed frontmatter YAML"
                        Suggestion = "Fix YAML syntax in frontmatter"
                    }
                }
            }
        }
        catch {
            $issues += [PSCustomObject]@{
                Type = "File Error"
                File = $file.FullName.Replace($VaultPath + "\", "")
                Issue = "Cannot read file: $($_.Exception.Message)"
                Suggestion = "Check file encoding and permissions"
            }
        }
    }
    
    # Show results
    if ($issues.Count -eq 0) {
        Write-Host "✅ Vault is Obsidian-compatible!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ Found $($issues.Count) compatibility issues:" -ForegroundColor Yellow
        
        foreach ($issue in $issues) {
            Write-Host "[$($issue.Type)] $($issue.File)" -ForegroundColor Red
            Write-Host "  Issue: $($issue.Issue)" -ForegroundColor Gray
            Write-Host "  Fix: $($issue.Suggestion)" -ForegroundColor DarkGray
            Write-Host ""
        }
    }
    
    return $issues.Count -eq 0
}

function Update-ObsidianLinks {
    param([hashtable]$Config, [switch]$WhatIf)
    
    Write-Host "🔗 Updating links for Obsidian compatibility..." -ForegroundColor Cyan
    
    $vaultRoot = $Config.system.vault_root
    $updatedFiles = 0
    
    # Get all markdown files
    $allFiles = Get-ChildItem -Path $vaultRoot -Filter "*.md" -Recurse
    
    foreach ($file in $allFiles) {
        try {
            $content = Get-Content $file.FullName -Raw
            $originalContent = $content
            
            # Convert relative paths to Obsidian-style links
            # Convert [text](../folder/file.md) to [[file]]
            $content = $content -replace '\[([^\]]+)\]\(\.\.?/[^/]+/([^/)]+)\.md\)', '[[$2|$1]]'
            
            # Convert [text](file.md) to [[file|text]]
            $content = $content -replace '\[([^\]]+)\]\(([^/)]+)\.md\)', '[[$2|$1]]'
            
            # Convert simple markdown links to wiki links where appropriate
            $content = $content -replace '\[([^\]]+)\]\(([^/)]+)\)', '[[$2|$1]]'
            
            if ($content -ne $originalContent) {
                if ($WhatIf) {
                    Write-Host "Would update links in: $($file.Name)" -ForegroundColor Yellow
                }
                else {
                    Set-Content -Path $file.FullName -Value $content -Encoding UTF8
                    $updatedFiles++
                    Write-Host "✅ Updated links in: $($file.Name)" -ForegroundColor Green
                }
            }
        }
        catch {
            Write-Log "Error updating links in $($file.FullName): $($_.Exception.Message)" "WARN"
        }
    }
    
    if (!$WhatIf) {
        Write-Host "✅ Updated links in $updatedFiles files" -ForegroundColor Green
    }
}

function New-ObsidianIndex {
    param([hashtable]$Config, [switch]$WhatIf)
    
    Write-Host "📑 Creating Obsidian-compatible index files..." -ForegroundColor Cyan
    
    $vaultRoot = $Config.system.vault_root
    $folders = @($Config.folders.inbox, $Config.folders.raw, $Config.folders.working, $Config.folders.wiki, $Config.folders.archive)
    
    foreach ($folder in $folders) {
        $folderPath = "$vaultRoot/$folder"
        if (!(Test-Path $folderPath)) { continue }
        
        $indexPath = "$folderPath/index.md"
        $files = Get-ChildItem -Path $folderPath -Filter "*.md" | Where-Object { $_.Name -ne "index.md" }
        
        if ($files.Count -eq 0) { continue }
        
        # Create index content
        $indexContent = @"
# $($folder.ToUpper()) Index

This folder contains $($files.Count) files.

## Files

"@
        
        foreach ($file in $files | Sort-Object Name) {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $indexContent += "`n- [[$fileName]]"
        }
        
        $indexContent += @"


---
*Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')*
*Total files: $($files.Count)*
"@
        
        if ($WhatIf) {
            Write-Host "Would create/update: $indexPath" -ForegroundColor Yellow
        }
        else {
            Set-Content -Path $indexPath -Value $indexContent -Encoding UTF8
            Write-Host "✅ Created index for: $folder" -ForegroundColor Green
        }
    }
    
    # Create main vault index
    $mainIndexPath = "$vaultRoot/README.md"
    $mainIndexContent = @"
# PinkyAndTheBrain Knowledge Vault

Welcome to your personal knowledge management system.

## Folder Structure

- **[[inbox/index|Inbox]]** - New captures awaiting triage
- **[[raw/index|Raw]]** - Imported conversations and unprocessed content  
- **[[working/index|Working]]** - Notes in development
- **[[wiki/index|Wiki]]** - Verified knowledge base
- **[[archive/index|Archive]]** - Archived content

## Quick Actions

- Use capture scripts to add new content
- Run triage to organize inbox items
- Search across all layers for information
- Run health checks to maintain quality

---
*System: PinkyAndTheBrain v1.0*
*Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')*
"@
    
    if ($WhatIf) {
        Write-Host "Would create/update: $mainIndexPath" -ForegroundColor Yellow
    }
    else {
        Set-Content -Path $mainIndexPath -Value $mainIndexContent -Encoding UTF8
        Write-Host "✅ Created main vault index" -ForegroundColor Green
    }
}

try {
    # Load configuration
    $config = Get-Config
    
    # Validate directory structure
    if (!(Test-DirectoryStructure $config)) {
        Write-Log "Directory structure validation failed. Run setup-system.ps1 first." "ERROR"
        exit 2
    }
    
    Write-Host "🔧 Obsidian Integration Utilities" -ForegroundColor Cyan
    Write-Host "Action: $Action" -ForegroundColor Gray
    Write-Host ""
    
    $success = $true
    
    switch ($Action) {
        "sync" {
            $success = Sync-ObsidianVault -Config $config -VaultPath $VaultPath -WhatIf:$WhatIf
        }
        
        "validate" {
            $success = Test-ObsidianCompatibility -Config $config -VaultPath $VaultPath
        }
        
        "update-links" {
            Update-ObsidianLinks -Config $config -WhatIf:$WhatIf
        }
        
        "create-index" {
            New-ObsidianIndex -Config $config -WhatIf:$WhatIf
        }
    }
    
    if ($success) {
        Write-Host "`n✅ Obsidian integration completed successfully!" -ForegroundColor Green
        Write-Log "Obsidian sync completed: $Action" "INFO"
    }
    else {
        Write-Host "`n❌ Obsidian integration completed with issues." -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Log "Obsidian sync failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Obsidian sync failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}