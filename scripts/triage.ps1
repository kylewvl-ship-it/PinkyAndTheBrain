#!/usr/bin/env pwsh
# PinkyAndTheBrain Inbox Triage Script
# Interactive triage of inbox items with disposition assignment

param(
    [string]$SourceType = "",
    [string]$Project = "",
    [int]$OlderThan = 0,
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
    Show-Usage "triage.ps1" "Interactive triage of inbox items" @(
        ".\scripts\triage.ps1"
        ".\scripts\triage.ps1 -SourceType web"
        ".\scripts\triage.ps1 -Project general"
        ".\scripts\triage.ps1 -OlderThan 7"
        ".\scripts\triage.ps1 -SourceType conversation -OlderThan 3"
    )
    exit 0
}

function Get-InboxItems {
    param(
        [string]$InboxPath,
        [string]$FilterSourceType = "",
        [string]$FilterProject = "",
        [int]$FilterOlderThan = 0
    )
    
    $items = @()
    $files = Get-ChildItem -Path $InboxPath -Filter "*.md" | Sort-Object LastWriteTime
    
    foreach ($file in $files) {
        try {
            $content = Get-Content $file.FullName -Raw
            $frontmatter = @{}
            
            # Parse frontmatter
            if ($content -match '(?s)^---\s*\n(.*?)\n---') {
                $yamlContent = $matches[1]
                $yamlContent -split "`n" | ForEach-Object {
                    if ($_ -match '^(\w+):\s*(.*)$') {
                        $frontmatter[$matches[1]] = $matches[2].Trim('"')
                    }
                }
            }
            
            # Apply filters
            if ($FilterSourceType -and $frontmatter.source_type -ne $FilterSourceType) {
                continue
            }

            if ($FilterProject -and $frontmatter.project -ne $FilterProject) {
                continue
            }
            
            if ($FilterOlderThan -gt 0) {
                $fileAge = (Get-Date) - $file.LastWriteTime
                if ($fileAge.Days -lt $FilterOlderThan) {
                    continue
                }
            }
            
            # Get content preview (first 100 characters after frontmatter)
            $contentBody = $content -replace '(?s)^---.*?---\s*', ''
            $preview = $contentBody.Substring(0, [Math]::Min(100, $contentBody.Length)).Trim()
            if ($contentBody.Length -gt 100) {
                $preview += "..."
            }
            
            $items += [PSCustomObject]@{
                Index = $items.Count + 1
                FileName = $file.Name
                FullPath = $file.FullName
                CaptureDate = $frontmatter.captured_date
                SourceType = $frontmatter.source_type
                Title = if ($frontmatter.title) { $frontmatter.title } else { "Untitled" }
                Preview = $preview
                Frontmatter = $frontmatter
            }
        }
        catch {
            Write-Log "Error processing file $($file.FullName): $($_.Exception.Message)" "WARN"
        }
    }
    
    return $items
}

function Show-InboxItems {
    param([array]$Items)
    
    if ($Items.Count -eq 0) {
        Write-Host "📭 No inbox items found matching criteria." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n📋 Inbox Items ($($Items.Count) total):" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Gray
    
    foreach ($item in $Items) {
        Write-Host "$($item.Index). " -NoNewline -ForegroundColor White
        Write-Host "$($item.Title)" -NoNewline -ForegroundColor Green
        Write-Host " [$($item.SourceType)]" -NoNewline -ForegroundColor Yellow
        Write-Host " ($($item.CaptureDate))" -ForegroundColor Gray
        Write-Host "   $($item.Preview)" -ForegroundColor Gray
        Write-Host ""
    }
    
    Write-Host ("=" * 80) -ForegroundColor Gray
}

function Get-UserSelection {
    param([int]$MaxIndex)
    
    Write-Host "`nDisposition Options:" -ForegroundColor Cyan
    Write-Host "[D]elete - Permanently remove items" -ForegroundColor Red
    Write-Host "[A]rchive - Move to archive folder" -ForegroundColor Yellow
    Write-Host "[R]aw - Move to raw folder" -ForegroundColor Blue
    Write-Host "[W]orking - Move to working folder" -ForegroundColor Green
    Write-Host "Wiki-[C]andidate - Mark for wiki promotion" -ForegroundColor Magenta
    Write-Host "[Q]uit - Exit without changes" -ForegroundColor Gray
    Write-Host ""
    
    $selection = Read-Host "Select items (e.g., '1,3,5' or '1-5') and disposition (e.g., '1,3 D')"
    
    if ($selection -match '^q$|^quit$') {
        return @{ Action = "quit" }
    }
    
    # Parse selection
    if ($selection -match '^([\d,\-\s]+)\s+([DARWC])$') {
        $itemsStr = $matches[1].Trim()
        $disposition = $matches[2].ToUpper()
        
        $selectedItems = @()
        
        # Parse item numbers
        $itemsStr -split ',' | ForEach-Object {
            $range = $_.Trim()
            if ($range -match '^(\d+)-(\d+)$') {
                # Range selection
                $start = [int]$matches[1]
                $end = [int]$matches[2]
                for ($i = $start; $i -le $end; $i++) {
                    if ($i -ge 1 -and $i -le $MaxIndex) {
                        $selectedItems += $i
                    }
                }
            }
            elseif ($range -match '^\d+$') {
                # Single item
                $num = [int]$range
                if ($num -ge 1 -and $num -le $MaxIndex) {
                    $selectedItems += $num
                }
            }
        }
        
        return @{
            Action = "process"
            Items = $selectedItems | Sort-Object | Get-Unique
            Disposition = $disposition
        }
    }
    
    Write-Host "Invalid selection format. Use format like '1,3,5 D' or '1-5 W'" -ForegroundColor Red
    return @{ Action = "invalid" }
}

function Process-Disposition {
    param(
        [array]$Items,
        [array]$SelectedIndices,
        [string]$Disposition,
        [hashtable]$Config,
        [switch]$WhatIf
    )
    
    $selectedItems = $Items | Where-Object { $_.Index -in $SelectedIndices }
    $vaultRoot = $Config.system.vault_root
    
    Write-Host "`nProcessing $($selectedItems.Count) items with disposition: $Disposition" -ForegroundColor Cyan
    
    foreach ($item in $selectedItems) {
        $sourcePath = $item.FullPath
        
        switch ($Disposition) {
            "D" {
                # Delete
                if ($WhatIf) {
                    Write-Host "Would delete: $($item.FileName)" -ForegroundColor Yellow
                }
                else {
                    Remove-Item $sourcePath -Force
                    Write-Log "Deleted item: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "🗑️  Deleted: $($item.FileName)" -ForegroundColor Red
                }
            }
            
            "A" {
                # Archive
                $targetPath = Join-Path "$vaultRoot/$($Config.folders.archive)" $item.FileName
                if ($WhatIf) {
                    Write-Host "Would archive: $($item.FileName) -> $targetPath" -ForegroundColor Yellow
                }
                else {
                    # Update frontmatter
                    $content = Get-Content $sourcePath -Raw
                    $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "archived"'
                    $updatedContent = $updatedContent -replace 'review_status:\s*.*', 'review_status: archived'
                    
                    # Add archive metadata
                    $archiveDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
                    $updatedContent = $updatedContent -replace '(---\s*\n)', "`$1archive_date: $archiveDate`narchive_reason: triaged_from_inbox`n"
                    
                    Set-Content -Path $targetPath -Value $updatedContent -Encoding UTF8
                    Remove-Item $sourcePath -Force
                    
                    Write-Log "Archived item: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "📦 Archived: $($item.FileName)" -ForegroundColor Yellow
                }
            }
            
            "R" {
                # Move to Raw
                $targetPath = Join-Path "$vaultRoot/$($Config.folders.raw)" $item.FileName
                if ($WhatIf) {
                    Write-Host "Would move to raw: $($item.FileName) -> $targetPath" -ForegroundColor Yellow
                }
                else {
                    $content = Get-Content $sourcePath -Raw
                    $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "raw"'
                    
                    Set-Content -Path $targetPath -Value $updatedContent -Encoding UTF8
                    Remove-Item $sourcePath -Force
                    
                    Write-Log "Moved to raw: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "📄 Moved to raw: $($item.FileName)" -ForegroundColor Blue
                }
            }
            
            "W" {
                # Move to Working
                $targetPath = Join-Path "$vaultRoot/$($Config.folders.working)" $item.FileName
                if ($WhatIf) {
                    Write-Host "Would move to working: $($item.FileName) -> $targetPath" -ForegroundColor Yellow
                }
                else {
                    $content = Get-Content $sourcePath -Raw
                    $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "working"'
                    
                    Set-Content -Path $targetPath -Value $updatedContent -Encoding UTF8
                    Remove-Item $sourcePath -Force
                    
                    Write-Log "Moved to working: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "📝 Moved to working: $($item.FileName)" -ForegroundColor Green
                }
            }
            
            "C" {
                # Wiki candidate (stays in inbox but marked)
                if ($WhatIf) {
                    Write-Host "Would mark as wiki candidate: $($item.FileName)" -ForegroundColor Yellow
                }
                else {
                    $content = Get-Content $sourcePath -Raw
                    $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "wiki-candidate"'
                    
                    Set-Content -Path $sourcePath -Value $updatedContent -Encoding UTF8
                    
                    Write-Log "Marked as wiki candidate: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "⭐ Marked as wiki candidate: $($item.FileName)" -ForegroundColor Magenta
                }
            }
        }
    }
}

try {
    # Load configuration
    $config = Get-Config -Project $Project
    
    # Validate directory structure
    if (!(Test-DirectoryStructure $config)) {
        Write-Log "Directory structure validation failed. Run setup-system.ps1 first." "ERROR"
        exit 2
    }
    
    $inboxPath = "$($config.system.vault_root)/$($config.folders.inbox)"
    
    # Get inbox items with filters
    $items = Get-InboxItems -InboxPath $inboxPath -FilterSourceType $SourceType -FilterProject $Project -FilterOlderThan $OlderThan
    
    if ($items.Count -eq 0) {
        Write-Host "📭 No inbox items found matching criteria." -ForegroundColor Yellow
        exit 0
    }
    
    # Interactive triage loop
    do {
        Show-InboxItems $items
        $selection = Get-UserSelection $items.Count
        
        switch ($selection.Action) {
            "quit" {
                Write-Host "Triage cancelled." -ForegroundColor Gray
                exit 0
            }
            
            "process" {
                if ($selection.Items.Count -eq 0) {
                    Write-Host "No valid items selected." -ForegroundColor Red
                    continue
                }
                
                Process-Disposition -Items $items -SelectedIndices $selection.Items -Disposition $selection.Disposition -Config $config -WhatIf:$WhatIf
                
                if (!$WhatIf) {
                    # Refresh items list
                    $items = Get-InboxItems -InboxPath $inboxPath -FilterSourceType $SourceType -FilterOlderThan $OlderThan
                    
                    if ($items.Count -eq 0) {
                        Write-Host "`n✅ All items processed! Inbox is now empty." -ForegroundColor Green
                        exit 0
                    }
                    
                    # Re-index remaining items
                    for ($i = 0; $i -lt $items.Count; $i++) {
                        $items[$i].Index = $i + 1
                    }
                }
                else {
                    exit 0
                }
            }
            
            "invalid" {
                # Continue loop for retry
            }
        }
    } while ($true)
}
catch {
    Write-Log "Triage failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Triage failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
