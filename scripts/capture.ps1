#!/usr/bin/env pwsh
# PinkyAndTheBrain Content Capture Script
# Captures knowledge items with proper templates and metadata

param(
    [ValidateSet("manual", "web", "conversation", "clipboard", "idea")]
    [string]$Type = "",
    
    [string]$Title = "",
    [string]$Content = "",
    [string]$Url = "",
    [string]$File = "",
    [string]$Service = "",
    [string]$Project = "",
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
    Show-Usage "capture.ps1" "Capture knowledge items into the inbox or raw folders" @(
        ".\scripts\capture.ps1 -Type manual -Title 'My Note' -Content 'Note content'"
        ".\scripts\capture.ps1 -Type web -Title 'Article' -Url 'https://example.com' -Content 'My notes'"
        ".\scripts\capture.ps1 -Type conversation -File 'conversation.txt' -Service 'claude'"
        ".\scripts\capture.ps1 -Type clipboard"
        ".\scripts\capture.ps1 -Type idea -Title 'New Idea' -Content 'Idea description'"
    )
    exit 0
}

function Test-TemplateValid {
    param(
        [hashtable]$Fields,
        [string[]]$RequiredKeys
    )

    foreach ($key in $RequiredKeys) {
        if (!$Fields.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$Fields[$key])) {
            Write-Log "Template validation failed. Missing required field: $key" "ERROR"
            return $false
        }
    }
    return $true
}

function Resolve-CaptureTitle {
    param(
        [string]$Title,
        [string]$Prompt
    )

    if (![string]::IsNullOrWhiteSpace($Title)) {
        return $Title
    }

    if (Test-CaptureInteractive) {
        return Read-Host $Prompt
    }

    return ""
}

function Test-CaptureInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }

    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Set-CaptureContent {
    param(
        [string]$Path,
        [string]$Value
    )

    $lockPath = "$Path.lock"
    $lockStream = $null

    try {
        if (Test-Path $lockPath) {
            $lockItem = Get-Item $lockPath -ErrorAction SilentlyContinue
            if ($null -ne $lockItem -and $lockItem.LastWriteTime -lt (Get-Date).AddMinutes(-5)) {
                Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
                Write-Log "Removed stale capture lock: $lockPath" "WARN"
            }
        }

        for ($i = 0; $i -lt 10; $i++) {
            try {
                $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                break
            }
            catch [System.IO.IOException] {
                Start-Sleep -Milliseconds 100
            }
        }

        if ($null -eq $lockStream) {
            Write-Log "Could not acquire file lock after retries: $lockPath" "ERROR"
            exit 2
        }

        Set-Content -Path $Path -Value $Value -Encoding UTF8
    }
    finally {
        if ($null -ne $lockStream) {
            $lockStream.Close()
            $lockStream.Dispose()
        }
        if (Test-Path $lockPath) {
            Remove-Item $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-UniqueCapturePath {
    param(
        [string]$Path
    )

    if (!(Test-Path $Path) -and !(Test-Path "$Path.lock")) {
        return $Path
    }

    $directory = Split-Path $Path -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)

    for ($i = 1; $i -le 100; $i++) {
        $candidate = Join-Path $directory ("{0}-{1}{2}" -f $baseName, $i, $extension)
        if (!(Test-Path $candidate) -and !(Test-Path "$candidate.lock")) {
            return $candidate
        }
    }

    Write-Log "Unable to derive a unique capture path for '$Path' after 100 attempts." "ERROR"
    exit 2
}

if ([string]::IsNullOrEmpty($Type)) {
    Write-Log "Type parameter is required. Use -Help for usage information." "ERROR"
    exit 1
}

try {
    # Load configuration
    $effectiveProject = if ([string]::IsNullOrWhiteSpace($Project)) { "" } else { $Project }
    $config = Get-Config -Project $effectiveProject
    if ([string]::IsNullOrWhiteSpace($effectiveProject)) {
        $effectiveProject = $config.projects.default_project
    }

    $pipedContent = $null
    if ($MyInvocation.ExpectingInput) {
        $pipedContent = $input | Out-String
    }

    if ($Type -ne "conversation") {
        $inboxPath = "$($config.system.vault_root)/$($config.folders.inbox)"
        if (!(Test-Path $inboxPath)) {
            Write-Log "Inbox folder not found at '$inboxPath'. Run .\scripts\setup-system.ps1 to initialize the system." "ERROR"
            exit 2
        }
    }
    
    # Validate directory structure
    if (!(Test-DirectoryStructure $config)) {
        Write-Log "Directory structure validation failed. Run setup-system.ps1 first." "ERROR"
        exit 2
    }
    
    # Handle different capture types
    switch ($Type) {
        "manual" {
            $Title = Resolve-CaptureTitle -Title $Title -Prompt "Enter title for captured content"
            $effectiveContent = if (![string]::IsNullOrEmpty($pipedContent)) { $pipedContent } else { $Content }

            if ([string]::IsNullOrEmpty($Title) -or [string]::IsNullOrEmpty($effectiveContent)) {
                Write-Log "Title and Content are required for manual capture" "ERROR"
                Show-Usage "capture.ps1" "Manual capture requires Title and Content" @(
                    ".\scripts\capture.ps1 -Type manual -Title 'My Note' -Content 'Note content'"
                    "Get-Content file.txt | .\scripts\capture.ps1 -Type manual -Title 'My Note'"
                )
                exit 1
            }
            
            $targetFolder = "$($config.system.vault_root)/$($config.folders.inbox)"
            $filename = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.inbox_pattern
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "inbox-item" @{
                title = $Title
                content = $effectiveContent
                source_type = "manual"
                source_url = $Url
                source_title = ""
                project_name_optional = $effectiveProject
            } -Config $config
        }
        
        "web" {
            $Title = Resolve-CaptureTitle -Title $Title -Prompt "Enter title for web content"
            $effectiveContent = if (![string]::IsNullOrEmpty($pipedContent)) { $pipedContent } else { $Content }

            if ([string]::IsNullOrEmpty($Title)) {
                Write-Log "Title is required for web capture" "ERROR"
                exit 1
            }
            
            $targetFolder = "$($config.system.vault_root)/$($config.folders.inbox)"
            $filename = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.inbox_pattern
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "inbox-item" @{
                title = $Title
                content = $effectiveContent
                source_type = "web"
                source_url = $Url
                source_title = $Title
                project_name_optional = $effectiveProject
            } -Config $config
        }
        
        "conversation" {
            if ([string]::IsNullOrEmpty($Service) -or ([string]::IsNullOrEmpty($File) -and [string]::IsNullOrEmpty($Content))) {
                Write-Log "Service and either File or Content are required for conversation import" "ERROR"
                exit 1
            }
            
            if ($File -and !(Test-Path $File)) {
                Write-Log "Conversation file not found: $File" "ERROR"
                exit 1
            }
            
            $conversationContent = if ($File) { Get-Content $File -Raw } else { $Content }
            $targetFolder = "$($config.system.vault_root)/$($config.folders.raw)"
            $filename = Get-TimestampedFilename -Title "conversation-$Service" -Pattern $config.file_naming.conversation_pattern -Placeholders @{ service = $Service }
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "conversation-import" @{
                title = "AI Conversation - $Service"
                content = $conversationContent
                ai_service = $Service
                conversation_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
                import_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            } -Config $config
        }
        
        # Clipboard access with environment detection
        "clipboard" {
            try {
                $clipboardContent = $null
                if (![string]::IsNullOrEmpty($pipedContent)) {
                    $clipboardContent = $pipedContent
                }
                elseif (!(Test-CaptureInteractive)) {
                    Write-Log "Clipboard access not available in non-interactive environment" "ERROR"
                    exit 1
                }
                else {
                    $clipboardContent = Get-Clipboard -Raw
                }

                if ([string]::IsNullOrEmpty($clipboardContent)) {
                    Write-Log "Clipboard is empty" "ERROR"
                    exit 1
                }
                
                $Title = Resolve-CaptureTitle -Title $Title -Prompt "Enter title for clipboard content"
                if ([string]::IsNullOrEmpty($Title)) {
                    Write-Log "Title is required for clipboard capture" "ERROR"
                    exit 1
                }
                
                $targetFolder = "$($config.system.vault_root)/$($config.folders.inbox)"
                $filename = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.inbox_pattern
                $filePath = Join-Path $targetFolder $filename
                
                $template = Get-Template "inbox-item" @{
                    title = $Title
                    content = $clipboardContent
                    source_type = "clipboard"
                    source_url = ""
                    source_title = ""
                    project_name_optional = $effectiveProject
                } -Config $config
            }
            catch {
                Write-Log "Failed to access clipboard: $($_.Exception.Message)" "ERROR"
                exit 2
            }
        }
        
        "idea" {
            $Title = Resolve-CaptureTitle -Title $Title -Prompt "Enter title for idea"
            $effectiveContent = if (![string]::IsNullOrEmpty($pipedContent)) { $pipedContent } else { $Content }

            if ([string]::IsNullOrEmpty($Title)) {
                Write-Log "Title is required for idea capture" "ERROR"
                exit 1
            }
            
            $targetFolder = "$($config.system.vault_root)/$($config.folders.inbox)"
            $filename = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.inbox_pattern
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "inbox-item" @{
                title = $Title
                content = $effectiveContent
                source_type = "idea"
                source_url = ""
                source_title = ""
                project_name_optional = $effectiveProject
            } -Config $config
        }
    }

    $filePath = Get-UniqueCapturePath -Path $filePath
    
    # Validate template was generated
    if ([string]::IsNullOrEmpty($template)) {
        Write-Log "Failed to generate template for capture type: $Type" "ERROR"
        exit 2
    }
    
    # Check for content size limit (configurable, default 10MB)
    $maxSizeRaw = if ($config.limits -and $config.limits.ContainsKey('max_content_size')) { $config.limits.max_content_size } else { $null }
    $maxSize = if ($null -ne $maxSizeRaw -and $maxSizeRaw -gt 0) { $maxSizeRaw } else { 10MB }
    if ($template.Length -gt $maxSize) {
        $actualSizeMB = [Math]::Round($template.Length / 1MB, 2)
        $limitMB = [Math]::Round($maxSize / 1MB, 2)
        Write-Log "Oversized capture attempt: $($actualSizeMB)MB (limit: $($limitMB)MB), target: $filePath" "WARN"
        if (!(Test-CaptureInteractive)) {
            Write-Log "Non-interactive mode: capture aborted, content $($actualSizeMB)MB exceeds limit" "ERROR"
            exit 1
        }

        Write-Host "Content size is $($actualSizeMB)MB, which exceeds the $($limitMB)MB limit." -ForegroundColor Yellow
        Write-Host "Options:"
        Write-Host "  [T] Truncate to $($limitMB)MB and save"
        Write-Host "  [S] Save full content to a separate file"
        Write-Host "  [C] Cancel capture"
        $oversizeResponse = Read-Host "Choose [T/S/C]"

        switch ($oversizeResponse.ToUpper()) {
            "T" {
                $template = $template.Substring(0, $maxSize)
                Write-Log "Content truncated to $($limitMB)MB for capture" "WARN"
            }
            "S" {
                $rawPath = $filePath -replace '\.md$', '-full-content.md'
                Set-CaptureContent -Path $rawPath -Value $template
                Write-Log "Full content saved separately to: $rawPath" "INFO"
                Write-Host "Full content saved to: $rawPath" -ForegroundColor Cyan
                $template = $template.Substring(0, $maxSize) + "`n`n> **Note:** Full content saved to $rawPath"
            }
            default {
                Write-Log "Oversized capture cancelled by user" "INFO"
                exit 0
            }
        }
    }
    
    # Write file (or show what would be written if WhatIf)
    if ($WhatIf) {
        Write-Output "Would create file: $filePath"
        Write-Host "Content preview:" -ForegroundColor Yellow
        Write-Host ($template.Substring(0, [Math]::Min(500, $template.Length))) -ForegroundColor Gray
        if ($template.Length -gt 500) {
            Write-Host "... (truncated)" -ForegroundColor Gray
        }
    }
    else {
        # Ensure target directory exists with error handling
        $targetDir = Split-Path $filePath -Parent
        if (!(Test-Path $targetDir)) {
            try {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            catch {
                Write-Log "Failed to create directory ${targetDir}: $($_.Exception.Message)" "ERROR"
                exit 2
            }
        }
        
        # Write the file with proper encoding and error handling
        try {
            Set-CaptureContent -Path $filePath -Value $template
            Write-Log "Successfully captured content to: $filePath" "INFO"
            Write-Host "✅ Content captured successfully!" -ForegroundColor Green
            Write-Host "📁 File: $filePath" -ForegroundColor Cyan

            if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
                $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
                $resolvedFilePath = [System.IO.Path]::GetFullPath($filePath)
                if ($resolvedFilePath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relPath = $resolvedFilePath.Replace($repoRoot, '').TrimStart('/\').Replace('\', '/')
                    $commitMsg = "Knowledge capture: $relPath from $Type"
                    Invoke-GitCommit -Files @($relPath) -Message $commitMsg -RepoPath $repoRoot | Out-Null
                }
            }

            # Return the file path for scripting
            return $filePath
        }
        catch {
            Write-Log "Failed to write file ${filePath}: $($_.Exception.Message)" "ERROR"
            exit 2
        }
    }
}
catch {
    Write-Log "Capture failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Capture failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
