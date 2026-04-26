#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('web','book','meeting','video','article','idea')]
    [string]$SourceType,

    [string]$Title = "",
    [string]$Url = "",
    [string]$Author = "",
    [string]$SourceDate = "",
    [AllowEmptyString()]
    [string]$Notes = "",
    [switch]$Private,
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

function Get-UnknownDefault {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "unknown"
    }

    return $Value
}

function ConvertTo-TemplateValueMap {
    param(
        [string]$SourceType,
        [string]$Title,
        [string]$Url,
        [string]$Author,
        [string]$SourceDate,
        [string]$Notes,
        [string]$CapturedDate,
        [string]$PrivateValue
    )

    $values = @{
        source_type = $SourceType
        title = $Title
        source_title = $Title
        source_url = $Url
        author = $Author
        participants = $Author
        source_date = $SourceDate
        captured_date = $CapturedDate
        my_notes = $Notes
        private = $PrivateValue
    }

    return $values
}

function Expand-SourceTemplate {
    param(
        [string]$TemplateContent,
        [hashtable]$Values
    )

    $expanded = $TemplateContent
    foreach ($key in $Values.Keys) {
        $replacement = $Values[$key]
        if ($null -eq $replacement) {
            $replacement = ""
        }

        $expanded = $expanded.Replace("{{$key}}", [string]$replacement)
    }

    return $expanded
}

function New-WebSourceDocument {
    param(
        [string]$SourceUrl,
        [string]$SourceTitle,
        [string]$CapturedDate,
        [string]$Notes,
        [string]$PrivateValue
    )

    $frontmatter = @(
        'source_type: "web"'
        ('source_url: "{0}"' -f $SourceUrl)
        ('source_title: "{0}"' -f $SourceTitle)
        ('captured_date: "{0}"' -f $CapturedDate)
        'review_status: "pending"'
        ('private: {0}' -f $PrivateValue)
    ) -join "`n"

    $body = @(
        ('# Web: {0}' -f $SourceTitle)
        ""
        "## My Notes"
        ""
        $Notes
    ) -join "`n"

    return Build-Document -Frontmatter $frontmatter -Body $body
}

function New-OfflineSourceDocument {
    param(
        [hashtable]$Config,
        [string]$SourceType,
        [hashtable]$Values
    )

    $templateRoot = [string]$Config.system.template_root
    $templatePath = Join-Path $templateRoot ("source-{0}.md" -f $SourceType.ToLowerInvariant())
    if (Test-Path $templatePath) {
        $templateContent = Get-Content -Path $templatePath -Raw -Encoding UTF8
        return Expand-SourceTemplate -TemplateContent $templateContent -Values $Values
    }

    $frontmatterLines = @(
        ('source_type: "{0}"' -f $SourceType)
        ('title: "{0}"' -f $Values.title)
    )

    if ($SourceType -eq 'meeting') {
        $frontmatterLines += ('participants: "{0}"' -f $Values.participants)
    }
    elseif ($SourceType -ne 'idea') {
        $frontmatterLines += ('author: "{0}"' -f $Values.author)
    }

    if ($SourceType -ne 'idea') {
        $frontmatterLines += ('source_date: "{0}"' -f $Values.source_date)
    }

    $frontmatterLines += ('captured_date: "{0}"' -f $Values.captured_date)
    $frontmatterLines += 'review_status: "pending"'
    $frontmatterLines += ('private: {0}' -f $Values.private)

    $bodyLines = @(
        ('# {0}: {1}' -f $SourceType, $Values.title)
        ""
        "## My Notes"
        ""
        [string]$Values.my_notes
        ""
        "## Source Context"
        ""
    )

    if ($SourceType -eq 'meeting') {
        $bodyLines += ('Participants: {0}' -f $Values.participants)
        $bodyLines += ('Meeting date: {0}' -f $Values.source_date)
    }
    elseif ($SourceType -ne 'idea') {
        $bodyLines += ('Author: {0}' -f $Values.author)
        $bodyLines += ('Date: {0}' -f $Values.source_date)
    }

    return Build-Document -Frontmatter ($frontmatterLines -join "`n") -Body ($bodyLines -join "`n")
}

if ($Help) {
    Show-Usage "capture-source.ps1" "Capture a non-AI source into the inbox" @(
        ".\scripts\capture-source.ps1 -SourceType web -Url 'https://example.com' -Title 'Article Title' -Notes 'My notes'"
        ".\scripts\capture-source.ps1 -SourceType book -Title 'Book Title' -Author 'Author' -Notes 'My notes'"
        ".\scripts\capture-source.ps1 -SourceType meeting -Title 'Planning' -Author 'Reno, Team' -Private"
    )
    exit 0
}

try {
    $config = Get-Config
    $inboxFolder = [System.IO.Path]::GetFullPath((Join-Path $config.system.vault_root $config.folders.inbox))
    if (!(Test-Path $inboxFolder)) {
        Write-Log "Inbox folder not found at '$inboxFolder'. Run .\scripts\setup-system.ps1 to initialize." "ERROR"
        exit 2
    }

    $capturedDate = (Get-Date).ToString("yyyy-MM-dd")
    $effectiveTitle = Get-UnknownDefault -Value $Title
    $effectiveAuthor = Get-UnknownDefault -Value $Author
    $effectiveSourceDate = Get-UnknownDefault -Value $SourceDate
    $effectiveUrl = Get-UnknownDefault -Value $Url
    $privateValue = if ($Private) { "true" } else { "false" }

    $fileTitle = if ([string]::IsNullOrWhiteSpace($Title)) { $SourceType } else { $Title }
    $fileName = Get-TimestampedFilename -Title $fileTitle -Pattern $config.file_naming.inbox_pattern
    $outputPath = Join-Path $inboxFolder $fileName

    $values = ConvertTo-TemplateValueMap -SourceType $SourceType -Title $effectiveTitle -Url $effectiveUrl -Author $effectiveAuthor -SourceDate $effectiveSourceDate -Notes $Notes -CapturedDate $capturedDate -PrivateValue $privateValue

    if ($SourceType -eq 'web') {
        $document = New-WebSourceDocument -SourceUrl $effectiveUrl -SourceTitle $effectiveTitle -CapturedDate $capturedDate -Notes $Notes -PrivateValue $privateValue
    }
    else {
        $document = New-OfflineSourceDocument -Config $config -SourceType $SourceType -Values $values
    }
    $document = $document -replace "`r?`n", "`r`n"

    if ($WhatIfPreference) {
        Write-Output "Would capture $SourceType source to: $outputPath"
        exit 0
    }

    if (-not $PSCmdlet.ShouldProcess($outputPath, "Capture $SourceType source")) {
        exit 0
    }

    Set-Content -Path $outputPath -Value $document -Encoding UTF8
    Write-Log "Captured $SourceType source to: $outputPath" "INFO"
    Write-Host "Captured source: $outputPath" -ForegroundColor Green

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $repoRoot = Get-RepoRoot
        $relativePath = Get-RelativeRepoPath -Path $outputPath -RepoRoot $repoRoot
        if (-not [string]::IsNullOrWhiteSpace($relativePath)) {
            Invoke-GitCommit -Message "inbox: capture $SourceType source" -Files @($relativePath) -RepoPath $repoRoot | Out-Null
        }
    }

    Write-Output $outputPath
    exit 0
}
catch {
    $lineNumber = if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 }
    Write-Log "Source capture failed at line ${lineNumber}: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: line ${lineNumber}: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
