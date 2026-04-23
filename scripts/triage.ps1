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

if (Test-Path "$PSScriptRoot/lib/git-operations.ps1") {
    . "$PSScriptRoot/lib/git-operations.ps1"
}

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
                $ageReference = $file.LastWriteTime
                if ($frontmatter.ContainsKey("captured_date")) {
                    $parsedCaptureDate = [datetime]::MinValue
                    if ([datetime]::TryParse($frontmatter.captured_date, [ref]$parsedCaptureDate)) {
                        $ageReference = $parsedCaptureDate
                    }
                }

                $fileAge = (Get-Date) - $ageReference
                if ($fileAge.TotalDays -lt $FilterOlderThan) {
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
        Write-Host "$($item.FileName)" -NoNewline -ForegroundColor Green
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

    $selection = Get-TriagePromptValue -EnvironmentVariable "PINKY_TRIAGE_SELECTION" -Prompt "Select items (e.g., '1,3,5', '1-5', or 'all') and disposition (e.g., '1,3 D' or 'all W')" -DefaultValue "q"
    
    if ($selection -match '^q$|^quit$') {
        return @{ Action = "quit" }
    }

    if ($selection -match '^all\s+([DARWC])$') {
        return @{
            Action = "process"
            Items = 1..$MaxIndex
            Disposition = $matches[1].ToUpper()
        }
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

function Test-TriageInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }

    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Get-TriagePromptValue {
    param(
        [string]$EnvironmentVariable,
        [string]$Prompt,
        [string]$DefaultValue = ""
    )

    $envValue = [Environment]::GetEnvironmentVariable($EnvironmentVariable)
    if ($null -ne $envValue -and $envValue -ne "") {
        [Environment]::SetEnvironmentVariable($EnvironmentVariable, $null)
        return $envValue
    }

    if (Test-TriageInteractive) {
        return Read-Host $Prompt
    }

    return $DefaultValue
}

function Ensure-TriageTargetDirectory {
    param([string]$TargetPath)

    $targetDir = Split-Path $TargetPath -Parent
    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Log "Created missing folder: $targetDir" "INFO" "logs/triage-actions.log"
    }
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
    $changedFiles = @()
    
    Write-Host "`nProcessing $($selectedItems.Count) items with disposition: $Disposition" -ForegroundColor Cyan
    
    switch ($Disposition) {
        "D" {
            Write-Host "`nItems to be deleted:" -ForegroundColor Yellow
            foreach ($i in $selectedItems) {
                Write-Host "  - $($i.FileName)" -ForegroundColor Red
            }

            $confirm = Get-TriagePromptValue -EnvironmentVariable "PINKY_CONFIRM_DELETE" -Prompt "Confirm deletion? (y/N)" -DefaultValue "N"
            if ($confirm -notmatch '^[yY]$') {
                Write-Host "Deletion cancelled." -ForegroundColor Gray
                break
            }

            $deletedNames = @()
            $failedNames = @()
            foreach ($item in $selectedItems) {
                if ($WhatIf) {
                    Write-Host "Would delete: $($item.FileName)" -ForegroundColor Yellow
                    continue
                }

                try {
                    Remove-Item $item.FullPath -Force -ErrorAction Stop
                    $deletedNames += $item.FileName
                    $changedFiles += $item.FullPath
                    Write-Log "Deleted item: $($item.FileName)" "INFO" "logs/triage-actions.log"
                }
                catch {
                    $failedNames += $item.FileName
                    Write-Log "Failed to delete $($item.FileName): $($_.Exception.Message)" "WARN" "logs/triage-actions.log"
                    Write-Host "⚠️  Could not delete $($item.FileName): $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            if ($deletedNames.Count -gt 0) {
                Write-Host "🗑️  Deleted $($deletedNames.Count) items: $($deletedNames -join ', ')" -ForegroundColor Red
            }
            if ($failedNames.Count -gt 0) {
                Write-Host "Check file permissions or run as administrator for: $($failedNames -join ', ')" -ForegroundColor Yellow
            }
        }

        "A" {
            $customReason = Get-TriagePromptValue -EnvironmentVariable "PINKY_ARCHIVE_REASON" -Prompt "Archive reason (press Enter to use default 'triaged_from_inbox')" -DefaultValue ""
            $archiveReasonValue = if (![string]::IsNullOrWhiteSpace($customReason)) { $customReason.Trim() } else { "triaged_from_inbox" }

            foreach ($item in $selectedItems) {
                $sourcePath = $item.FullPath
                $targetPath = Join-Path "$vaultRoot/$($Config.folders.archive)" $item.FileName
                if ($WhatIf) {
                    Write-Host "Would archive: $($item.FileName) -> $targetPath" -ForegroundColor Yellow
                    continue
                }

                try {
                    Ensure-TriageTargetDirectory -TargetPath $targetPath
                    $content = Get-Content $sourcePath -Raw
                    $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "archived"'
                    $updatedContent = $updatedContent -replace 'review_status:\s*.*', 'review_status: archived'
                    $archiveDate = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
                    $updatedContent = $updatedContent -replace '(---\s*\n)', "`$1archive_date: $archiveDate`narchive_reason: triaged_from_inbox`n"
                    $updatedContent = $updatedContent.Replace("archive_reason: triaged_from_inbox", "archive_reason: $archiveReasonValue")
                    Set-Content -Path $targetPath -Value $updatedContent -Encoding UTF8
                    Remove-Item $sourcePath -Force -ErrorAction Stop
                    $changedFiles += $sourcePath
                    $changedFiles += $targetPath
                    Write-Log "Archived item: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "📦 Archived: $($item.FileName)" -ForegroundColor Yellow
                }
                catch {
                    Write-Log "Failed to archive $($item.FileName): $($_.Exception.Message)" "WARN" "logs/triage-actions.log"
                    Write-Host "⚠️  Could not archive $($item.FileName): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        "R" {
            foreach ($item in $selectedItems) {
                $sourcePath = $item.FullPath
                $targetPath = Join-Path "$vaultRoot/$($Config.folders.raw)" $item.FileName
                if ($WhatIf) {
                    Write-Host "Would move to raw: $($item.FileName) -> $targetPath" -ForegroundColor Yellow
                    continue
                }

                try {
                    Ensure-TriageTargetDirectory -TargetPath $targetPath
                    $content = Get-Content $sourcePath -Raw
                    $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "raw"'
                    Set-Content -Path $targetPath -Value $updatedContent -Encoding UTF8
                    Remove-Item $sourcePath -Force -ErrorAction Stop
                    $changedFiles += $sourcePath
                    $changedFiles += $targetPath
                    Write-Log "Moved to raw: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "📄 Moved to raw: $($item.FileName)" -ForegroundColor Blue
                }
                catch {
                    Write-Log "Failed to move $($item.FileName) to raw: $($_.Exception.Message)" "WARN" "logs/triage-actions.log"
                    Write-Host "⚠️  Could not move $($item.FileName) to raw: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        "W" {
            foreach ($item in $selectedItems) {
                $sourcePath = $item.FullPath
                $targetPath = Join-Path "$vaultRoot/$($Config.folders.working)" $item.FileName
                if ($WhatIf) {
                    Write-Host "Would move to working: $($item.FileName) -> $targetPath" -ForegroundColor Yellow
                    continue
                }

                try {
                    Ensure-TriageTargetDirectory -TargetPath $targetPath
                    $content = Get-Content $sourcePath -Raw
                    $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "working"'
                    Set-Content -Path $targetPath -Value $updatedContent -Encoding UTF8
                    Remove-Item $sourcePath -Force -ErrorAction Stop
                    $changedFiles += $sourcePath
                    $changedFiles += $targetPath
                    Write-Log "Moved to working: $($item.FileName)" "INFO" "logs/triage-actions.log"
                    Write-Host "📝 Moved to working: $($item.FileName)" -ForegroundColor Green
                }
                catch {
                    Write-Log "Failed to move $($item.FileName) to working: $($_.Exception.Message)" "WARN" "logs/triage-actions.log"
                    Write-Host "⚠️  Could not move $($item.FileName) to working: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }

        "C" {
            foreach ($item in $selectedItems) {
                $sourcePath = $item.FullPath
                if ($WhatIf) {
                    Write-Host "Would mark as wiki candidate: $($item.FileName)" -ForegroundColor Yellow
                    continue
                }

                $content = Get-Content $sourcePath -Raw
                $updatedContent = $content -replace 'disposition:\s*.*', 'disposition: "wiki-candidate"'
                Set-Content -Path $sourcePath -Value $updatedContent -Encoding UTF8
                $changedFiles += $sourcePath
                Write-Log "Marked as wiki candidate: $($item.FileName)" "INFO" "logs/triage-actions.log"
                Write-Host "⭐ Marked as wiki candidate: $($item.FileName)" -ForegroundColor Magenta
            }
        }
    }

    return $changedFiles
}

try {
    # Load configuration
    $config = Get-Config -Project $Project

    $inboxPath = "$($config.system.vault_root)/$($config.folders.inbox)"
    if (!(Test-Path $inboxPath)) {
        Write-Log "Inbox folder not found at '$inboxPath'. Run .\scripts\setup-system.ps1 to initialize the system." "ERROR"
        exit 2
    }
    
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
                
                $changedPaths = Process-Disposition -Items $items -SelectedIndices $selection.Items -Disposition $selection.Disposition -Config $config -WhatIf:$WhatIf

                if (!$WhatIf) {
                    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
                        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
                        $changedFiles = @($changedPaths | ForEach-Object {
                            $resolvedPath = [System.IO.Path]::GetFullPath($_)
                            if ($resolvedPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $resolvedPath.Replace($repoRoot, '').TrimStart('/\').Replace('\', '/')
                            }
                        } | Where-Object { $_ })
                        $count = $selection.Items.Count
                        $dispMap = @{ D = "deleted"; A = "archived"; R = "moved to raw"; W = "moved to working"; C = "marked wiki-candidate" }
                        $dispDesc = if ($dispMap.ContainsKey($selection.Disposition)) { $dispMap[$selection.Disposition] } else { $selection.Disposition }
                        Invoke-GitCommit -Files $changedFiles -Message "Knowledge triage: $dispDesc $count item(s) from inbox" -RepoPath $repoRoot | Out-Null
                    }

                    # Refresh items list
                    $items = Get-InboxItems -InboxPath $inboxPath -FilterSourceType $SourceType -FilterProject $Project -FilterOlderThan $OlderThan
                    
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
