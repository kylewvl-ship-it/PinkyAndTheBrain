#!/usr/bin/env pwsh
# PinkyAndTheBrain Content Capture Script
# Captures knowledge items with proper templates and metadata

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("manual", "web", "conversation", "clipboard", "idea")]
    [string]$Type,
    
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

try {
    # Load configuration
    $config = Get-Config
    
    # Validate directory structure
    if (!(Test-DirectoryStructure $config)) {
        Write-Log "Directory structure validation failed. Run setup-system.ps1 first." "ERROR"
        exit 2
    }
    
    # Handle different capture types
    switch ($Type) {
        "manual" {
            if ([string]::IsNullOrEmpty($Title) -or [string]::IsNullOrEmpty($Content)) {
                Write-Log "Title and Content are required for manual capture" "ERROR"
                Show-Usage "capture.ps1" "Manual capture requires Title and Content" @(
                    ".\scripts\capture.ps1 -Type manual -Title 'My Note' -Content 'Note content'"
                )
                exit 1
            }
            
            $targetFolder = "$($config.system.vault_root)/$($config.folders.inbox)"
            $filename = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.inbox_pattern
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "inbox-item" @{
                title = $Title
                content = $Content
                source_type = "manual"
                source_url = $Url
                source_title = ""
                project_name_optional = $Project
            }
        }
        
        "web" {
            if ([string]::IsNullOrEmpty($Title)) {
                Write-Log "Title is required for web capture" "ERROR"
                exit 1
            }
            
            $targetFolder = "$($config.system.vault_root)/$($config.folders.inbox)"
            $filename = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.inbox_pattern
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "inbox-item" @{
                title = $Title
                content = $Content
                source_type = "web"
                source_url = $Url
                source_title = $Title
                project_name_optional = $Project
            }
        }
        
        "conversation" {
            if ([string]::IsNullOrEmpty($File) -or [string]::IsNullOrEmpty($Service)) {
                Write-Log "File and Service are required for conversation import" "ERROR"
                exit 1
            }
            
            if (!(Test-Path $File)) {
                Write-Log "Conversation file not found: $File" "ERROR"
                exit 1
            }
            
            $conversationContent = Get-Content $File -Raw
            $targetFolder = "$($config.system.vault_root)/$($config.folders.raw)"
            $filename = Get-TimestampedFilename -Title "conversation-$Service" -Pattern $config.file_naming.conversation_pattern
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "conversation-import" @{
                title = "AI Conversation - $Service"
                content = $conversationContent
                ai_service = $Service
                conversation_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
                import_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ")
            }
        }
        
        # Clipboard access with environment detection
        "clipboard" {
            try {
                # Check if running in interactive environment
                if ([Environment]::UserInteractive -eq $false) {
                    Write-Log "Clipboard access not available in non-interactive environment" "ERROR"
                    exit 1
                }
                
                $clipboardContent = Get-Clipboard -Raw
                if ([string]::IsNullOrEmpty($clipboardContent)) {
                    Write-Log "Clipboard is empty" "ERROR"
                    exit 1
                }
                
                if ([string]::IsNullOrEmpty($Title)) {
                    $Title = Read-Host "Enter title for clipboard content"
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
                    project_name_optional = $Project
                }
            }
            catch {
                Write-Log "Failed to access clipboard: $($_.Exception.Message)" "ERROR"
                exit 2
            }
        }
        
        "idea" {
            if ([string]::IsNullOrEmpty($Title)) {
                Write-Log "Title is required for idea capture" "ERROR"
                exit 1
            }
            
            $targetFolder = "$($config.system.vault_root)/$($config.folders.inbox)"
            $filename = Get-TimestampedFilename -Title $Title -Pattern $config.file_naming.inbox_pattern
            $filePath = Join-Path $targetFolder $filename
            
            $template = Get-Template "inbox-item" @{
                title = $Title
                content = $Content
                source_type = "idea"
                source_url = ""
                source_title = ""
                project_name_optional = $Project
            }
        }
    }
    
    # Validate template was generated
    if ([string]::IsNullOrEmpty($template)) {
        Write-Log "Failed to generate template for capture type: $Type" "ERROR"
        exit 2
    }
    
    # Check for content size limit (configurable, default 10MB)
    $maxSize = if ($config.limits.max_content_size) { $config.limits.max_content_size } else { 10MB }
    if ($template.Length -gt $maxSize) {
        Write-Log "Content exceeds $($maxSize/1MB)MB limit. Consider splitting into multiple files." "WARN"
        $response = Read-Host "Continue anyway? (y/N)"
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Log "Capture cancelled by user" "INFO"
            exit 0
        }
    }
    
    # Write file (or show what would be written if WhatIf)
    if ($WhatIf) {
        Write-Host "Would create file: $filePath" -ForegroundColor Yellow
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
                Write-Log "Failed to create directory $targetDir: $($_.Exception.Message)" "ERROR"
                exit 2
            }
        }
        
        # Write the file with proper encoding and error handling
        try {
            Set-Content -Path $filePath -Value $template -Encoding UTF8
            Write-Log "Successfully captured content to: $filePath" "INFO"
            Write-Host "✅ Content captured successfully!" -ForegroundColor Green
            Write-Host "📁 File: $filePath" -ForegroundColor Cyan
            
            # Return the file path for scripting
            return $filePath
        }
        catch {
            Write-Log "Failed to write file $filePath: $($_.Exception.Message)" "ERROR"
            exit 2
        }
    }
}
catch {
    Write-Log "Capture failed: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Capture failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}