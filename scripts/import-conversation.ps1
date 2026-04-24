#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$File = "",
    [string]$Service = "unknown",
    [string]$ConversationDate = "",
    [ValidateSet('file', 'paste', 'clipboard')]
    [string]$Method = "",
    [Parameter(ValueFromPipeline = $true)]
    [AllowEmptyString()]
    [string]$PipelineInputObject = "",
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
. "$PSScriptRoot\lib\frontmatter.ps1"
if (Test-Path "$PSScriptRoot\lib\git-operations.ps1") {
    . "$PSScriptRoot\lib\git-operations.ps1"
}

function Get-RepoRoot {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (![string]::IsNullOrWhiteSpace($envRepoRoot)) {
        return [System.IO.Path]::GetFullPath($envRepoRoot)
    }

    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Test-InteractiveSession {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }

    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}

function Get-ClipboardTextSafe {
    if (Get-Command 'Get-Clipboard' -ErrorAction SilentlyContinue) {
        return Get-Clipboard -Raw
    }

    Add-Type -AssemblyName System.Windows.Forms
    return [System.Windows.Forms.Clipboard]::GetText()
}

function Get-ConversationFormat {
    param([string]$Content)

    $trimmed = $Content.Trim()
    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) { return 'json' }
    if ($trimmed.StartsWith('---')) { return 'markdown' }
    return 'text'
}

function Read-ConversationFile {
    param([string]$Path)

    $errors = @()
    try {
        return @{
            Content = (Get-Content -Path $Path -Raw -Encoding UTF8)
            Errors = @()
        }
    }
    catch {
        $errors += "File read warning: $($_.Exception.Message)"
        try {
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $decoded = [System.Text.Encoding]::UTF8.GetString($bytes)
            return @{
                Content = $decoded
                Errors = $errors
            }
        }
        catch {
            $errors += "Fallback byte read failed: $($_.Exception.Message)"
            return @{
                Content = ""
                Errors = $errors
            }
        }
    }
}

function Get-RoleLabel {
    param([string]$Role)

    switch ($Role.ToLowerInvariant()) {
        'human' { return '**User:**' }
        'user' { return '**User:**' }
        'you' { return '**User:**' }
        'assistant' { return '**Assistant:**' }
        'claude' { return '**Assistant:**' }
        'gpt' { return '**Assistant:**' }
        'ai' { return '**Assistant:**' }
        'system' { return '**System:**' }
        default { return ('**{0}:**' -f $Role) }
    }
}

function Format-PlainTextConversation {
    param([string]$Content)

    $lines = $Content -split "`r?`n"
    $turns = @()
    $currentRole = ""
    $currentLines = @()
    $inFence = $false
    $roleRegex = '^(Human|User|Assistant|Claude|GPT|You|AI|System)\s*:\s*(.*)$'

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('```')) {
            $inFence = -not $inFence
            $currentLines += $line
            continue
        }

        if (-not $inFence -and $line -match $roleRegex) {
            if ($currentRole -or $currentLines.Count -gt 0) {
                $turnBody = ($currentLines -join "`n").TrimEnd()
                $turns += ((Get-RoleLabel -Role $currentRole) + "`n`n" + $turnBody).Trim()
            }

            $currentRole = $Matches[1]
            $currentLines = @()
            if (-not [string]::IsNullOrWhiteSpace($Matches[2])) {
                $currentLines += $Matches[2]
            }
            continue
        }

        $currentLines += $line
    }

    if ($currentRole -or $currentLines.Count -gt 0) {
        $turnBody = ($currentLines -join "`n").TrimEnd()
        if ($currentRole) {
            $turns += ((Get-RoleLabel -Role $currentRole) + "`n`n" + $turnBody).Trim()
        }
    }

    if ($turns.Count -ge 2) {
        return ($turns -join "`n`n---`n`n")
    }

    return $Content
}

function Convert-JsonConversation {
    param([string]$JsonContent)

    $errors = @()
    try {
        $data = $JsonContent | ConvertFrom-Json
        $messages = $null

        if ($null -ne $data -and $data.PSObject.Properties['messages']) {
            $messages = @($data.messages)
        }
        elseif ($data -is [array]) {
            $messages = @($data)
        }

        if ($null -eq $messages -or $messages.Count -eq 0) {
            $errors += "Unrecognized JSON structure - no 'messages' array found."
            return @{
                Body = (@('```json', $JsonContent, '```') -join "`n")
                Errors = $errors
            }
        }

        $turns = @()
        foreach ($msg in $messages) {
            $role = if ($null -ne $msg.PSObject.Properties['role'] -and -not [string]::IsNullOrWhiteSpace([string]$msg.role)) { [string]$msg.role } else { 'unknown' }
            $content = ""

            if ($null -ne $msg.PSObject.Properties['content']) {
                if ($msg.content -is [array]) {
                    $contentParts = @()
                    foreach ($part in $msg.content) {
                        if ($null -eq $part) {
                            continue
                        }

                        if ($part -is [string]) {
                            $contentParts += $part
                        }
                        elseif ($part.PSObject.Properties['text']) {
                            $contentParts += [string]$part.text
                        }
                        else {
                            $contentParts += ($part | ConvertTo-Json -Compress)
                        }
                    }
                    $content = ($contentParts -join "`n").Trim()
                }
                else {
                    $content = [string]$msg.content
                }
            }

            $turns += ((Get-RoleLabel -Role $role) + "`n`n" + $content).Trim()
        }

        return @{
            Body = ($turns -join "`n`n---`n`n")
            Errors = $errors
        }
    }
    catch {
        $errors += "JSON parse error: $($_.Exception.Message)"
        return @{
            Body = (@('```json', $JsonContent, '```') -join "`n")
            Errors = $errors
        }
    }
}

function Get-ImportedConversationBody {
    param(
        [string]$Content,
        [string]$SourceFormat
    )

    if ($SourceFormat -eq 'json') {
        return (Convert-JsonConversation -JsonContent $Content)
    }

    if ($SourceFormat -eq 'text') {
        return @{
            Body = (Format-PlainTextConversation -Content $Content)
            Errors = @()
        }
    }

    return @{
        Body = $Content
        Errors = @()
    }
}

function New-ConversationFrontmatter {
    param(
        [string]$ConversationDate,
        [string]$Service,
        [string]$ImportMethod,
        [string]$SourceFormat,
        [string[]]$Errors
    )

    $frontmatter = @(
        ('conversation_date: "{0}"' -f $ConversationDate)
        ('ai_service: "{0}"' -f $Service)
        ('import_date: "{0}"' -f ((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")))
        ('import_method: "{0}"' -f $ImportMethod)
        ('source_format: "{0}"' -f $SourceFormat)
        'review_status: "pending"'
    ) -join "`n"

    if ($Errors.Count -gt 0) {
        $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key 'import_errors' -Value 'true'
    }

    return $frontmatter
}

function New-ConversationDocument {
    param(
        [string]$Frontmatter,
        [string]$Service,
        [string]$ConversationDate,
        [string]$ConversationBody,
        [string[]]$Errors
    )

    $bodyLines = @(
        "# AI Conversation - $Service - $ConversationDate"
        ""
        $ConversationBody.TrimEnd()
    )

    if ($Errors.Count -gt 0) {
        $bodyLines += ""
        $bodyLines += "## Import Errors"
        $bodyLines += ""
        foreach ($errorMessage in $Errors) {
            $bodyLines += ('- {0}' -f $errorMessage)
        }
    }

    return Build-Document -Frontmatter $Frontmatter -Body ($bodyLines -join "`n")
}

if ($Help) {
    Show-Usage "import-conversation.ps1" "Import an AI conversation into the raw knowledge layer" @(
        ".\scripts\import-conversation.ps1 -File 'conversation.txt' -Service 'claude'"
        "Get-Content conversation.md -Raw | .\scripts\import-conversation.ps1 -Service 'chatgpt'"
        ".\scripts\import-conversation.ps1 -Service 'claude' -WhatIf"
    )
    exit 0
}

try {
    $config = Get-Config
    $rawFolder = [System.IO.Path]::GetFullPath((Join-Path $config.system.vault_root $config.folders.raw))

    if (!(Test-Path $rawFolder)) {
        Write-Log "Raw folder not found at '$rawFolder'. Run .\scripts\setup-system.ps1 to initialize." "ERROR"
        exit 2
    }

    $pipedContent = ""
    if ($MyInvocation.ExpectingInput) {
        $pipedContent = ($input | Out-String).TrimEnd("`r", "`n")
    }
    elseif ([Console]::IsInputRedirected) {
        $pipedContent = [Console]::In.ReadToEnd().TrimEnd("`r", "`n")
    }

    $effectiveMethod = ""
    $rawText = ""
    $errors = @()

    if (-not [string]::IsNullOrWhiteSpace($File)) {
        if (!(Test-Path $File)) {
            Write-Log "Conversation file not found: $File" "ERROR"
            exit 1
        }

        $fileRead = Read-ConversationFile -Path $File
        $rawText = [string]$fileRead.Content
        $errors += @($fileRead.Errors)
        $effectiveMethod = 'file'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($pipedContent)) {
        $rawText = $pipedContent
        $effectiveMethod = 'paste'
    }
    else {
        if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
            Write-Log "No -File specified and non-interactive mode detected. Provide -File or pipe content." "ERROR"
            exit 1
        }

        $clipboardText = ""
        try {
            $clipboardText = Get-ClipboardTextSafe
        }
        catch {
            $clipboardText = ""
        }

        if (-not [string]::IsNullOrWhiteSpace($clipboardText)) {
            $rawText = $clipboardText
            $effectiveMethod = 'clipboard'
        }
        else {
            Write-Log "No -File specified and clipboard is empty. Provide -File or pipe content." "ERROR"
            exit 1
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Method)) {
        $effectiveMethod = $Method
    }

    $conversationDateValue = if ([string]::IsNullOrWhiteSpace($ConversationDate)) { (Get-Date).ToString("yyyy-MM-dd") } else { $ConversationDate }
    $sourceFormat = Get-ConversationFormat -Content $rawText
    $converted = Get-ImportedConversationBody -Content $rawText -SourceFormat $sourceFormat
    $errors += @($converted.Errors)

    $serviceSlug = $Service.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $serviceSlug = $serviceSlug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($serviceSlug)) {
        $serviceSlug = 'unknown'
    }

    $pattern = [string]$config.file_naming.conversation_pattern
    $timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm"
    $fileName = $pattern -replace 'YYYY-MM-DD-HH-MM', $timestamp
    $fileName = $fileName -replace 'YYYY-MM-DD-HHMMSS', $timestamp
    $fileName = $fileName -replace '\{service\}', $serviceSlug
    if (-not $fileName.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
        $fileName += '.md'
    }

    $outputPath = Join-Path $rawFolder $fileName
    $frontmatter = New-ConversationFrontmatter -ConversationDate $conversationDateValue -Service $Service -ImportMethod $effectiveMethod -SourceFormat $sourceFormat -Errors $errors
    $document = New-ConversationDocument -Frontmatter $frontmatter -Service $Service -ConversationDate $conversationDateValue -ConversationBody $converted.Body -Errors $errors

    if ($WhatIfPreference) {
        Write-Output "Would import conversation to: $outputPath"
        exit 0
    }

    if (-not $PSCmdlet.ShouldProcess($outputPath, "Import conversation")) {
        exit 0
    }

    Set-Content -Path $outputPath -Value $document -Encoding UTF8
    Write-Log "Imported conversation to: $outputPath" "INFO"
    Write-Host "Imported conversation: $outputPath" -ForegroundColor Green

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $repoRoot = Get-RepoRoot
        $relativePath = Get-RelativeRepoPath -Path $outputPath -RepoRoot $repoRoot
        if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
            Invoke-GitCommit -Message "raw: import conversation from $Service" -Files @($relativePath) -RepoPath $repoRoot | Out-Null
        }
    }

    Write-Output $outputPath
    exit 0
}
catch {
    $lineNumber = if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 }
    Write-Log "Conversation import failed at line ${lineNumber}: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: line ${lineNumber}: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
