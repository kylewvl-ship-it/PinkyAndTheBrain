#!/usr/bin/env pwsh
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$List,
    [switch]$Validate,
    [switch]$Add,
    [string]$TypeName = "",
    [string]$TemplatePath = "",
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
if (Test-Path "$PSScriptRoot\lib\git-operations.ps1") {
    . "$PSScriptRoot\lib\git-operations.ps1"
}

function Get-RepoRoot {
    $envRepoRoot = [Environment]::GetEnvironmentVariable('PINKY_GIT_REPO_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($envRepoRoot)) {
        return [System.IO.Path]::GetFullPath($envRepoRoot)
    }

    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ConfigPath {
    $envConfigPath = [Environment]::GetEnvironmentVariable('PINKY_CONFIG_PATH')
    if (-not [string]::IsNullOrWhiteSpace($envConfigPath)) {
        return $envConfigPath
    }

    return Join-Path (Get-RepoRoot) "config\pinky-config.yaml"
}

function Get-ConfiguredSourceTypes {
    param([hashtable]$Config)

    if ($Config.ContainsKey('source_types') -and $Config.source_types -is [hashtable]) {
        return $Config.source_types
    }

    return @{}
}

function Test-ModeSelection {
    param(
        [bool]$ListMode,
        [bool]$ValidateMode,
        [bool]$AddMode
    )

    $selectedCount = 0
    if ($ListMode) { $selectedCount++ }
    if ($ValidateMode) { $selectedCount++ }
    if ($AddMode) { $selectedCount++ }

    return ($selectedCount -eq 1)
}

function Add-SourceTypeToConfigText {
    param(
        [string]$ConfigText,
        [string]$Name,
        [string]$Template
    )

    $newEntry = @(
        ("  {0}:" -f $Name)
        ("    template: ""{0}""" -f $Template)
    ) -join "`r`n"

    if ($ConfigText -match '(?m)^source_types:\s*$') {
        if ($ConfigText -match ("(?m)^  " + [regex]::Escape($Name) + ":\s*$")) {
            throw "Source type '$Name' already exists."
        }

        $blockStart = [regex]::Match($ConfigText, '(?m)^source_types:\s*$').Index
        $afterHeader = $blockStart + [regex]::Match($ConfigText.Substring($blockStart), "^source_types:\s*\r?\n", 'Multiline').Length
        $rest = $ConfigText.Substring($afterHeader)
        $nextSectionMatch = [regex]::Match($rest, '(?m)^[A-Za-z0-9_-]+:\s*$')
        if ($nextSectionMatch.Success) {
            $insertAt = $afterHeader + $nextSectionMatch.Index
            return $ConfigText.Substring(0, $insertAt) + $newEntry + "`r`n" + $ConfigText.Substring($insertAt)
        }

        $trimmed = $ConfigText.TrimEnd("`r", "`n")
        return $trimmed + "`r`n" + $newEntry + "`r`n"
    }

    $trimmedConfig = $ConfigText.TrimEnd("`r", "`n")
    return $trimmedConfig + "`r`n`r`nsource_types:`r`n" + $newEntry + "`r`n"
}

if ($Help) {
    Show-Usage "manage-source-types.ps1" "Manage configured source types" @(
        ".\scripts\manage-source-types.ps1 -List"
        ".\scripts\manage-source-types.ps1 -Validate"
        ".\scripts\manage-source-types.ps1 -Add -TypeName podcast -TemplatePath templates/source-podcast.md"
    )
    exit 0
}

try {
    if (-not (Test-ModeSelection -ListMode $List -ValidateMode $Validate -AddMode $Add)) {
        Write-Log "Exactly one of -List, -Validate, or -Add must be provided." "ERROR"
        exit 1
    }

    if ($Add) {
        if ([string]::IsNullOrWhiteSpace($TypeName) -or [string]::IsNullOrWhiteSpace($TemplatePath)) {
            Write-Log "-Add requires both -TypeName and -TemplatePath." "ERROR"
            exit 1
        }

        if ($TypeName -notmatch '^[a-z][a-z0-9-]*$') {
            Write-Log "Invalid TypeName '$TypeName'. Use lowercase letters, numbers, and hyphens only." "ERROR"
            exit 1
        }
    }

    $configPath = Get-ConfigPath
    $config = Get-Config -ConfigPath $configPath
    $sourceTypes = Get-ConfiguredSourceTypes -Config $config

    if ($List) {
        $rows = @()
        foreach ($typeName in ($sourceTypes.Keys | Sort-Object)) {
            $template = ""
            $exists = "NO"
            $entry = $sourceTypes[$typeName]
            if ($entry -is [hashtable] -and $entry.ContainsKey('template')) {
                $template = [string]$entry.template
                if (Test-Path $template) {
                    $exists = "YES"
                }
            }

            $rows += [pscustomobject]@{
                "Source Type" = $typeName
                "Template" = $template
                "Template Exists" = $exists
            }
        }

        if ($rows.Count -eq 0) {
            Write-Host "No source types configured." -ForegroundColor Yellow
        }
        else {
            Write-Output ($rows | Format-Table -AutoSize | Out-String -Width 4096)
        }

        exit 0
    }

    if ($Validate) {
        $errors = @()
        $warnings = @()

        foreach ($typeName in ($sourceTypes.Keys | Sort-Object)) {
            $entry = $sourceTypes[$typeName]
            if ($entry -isnot [hashtable] -or -not $entry.ContainsKey('template')) {
                $errors += "source_types.${typeName}: missing required 'template' key"
                Write-Host "ERROR: source_types.${typeName} missing 'template' key" -ForegroundColor Red
                continue
            }

            $template = [string]$entry.template
            if (-not (Test-Path $template)) {
                $warnings += "source_types.${typeName}: template file not found: $template"
                Write-Host "WARNING: source_types.${typeName} template not found: $template" -ForegroundColor Yellow
            }
        }

        if ($errors.Count -gt 0) {
            exit 1
        }

        exit 0
    }

    $configText = Get-Content -Path $configPath -Raw -Encoding UTF8
    $newContent = Add-SourceTypeToConfigText -ConfigText $configText -Name $TypeName -Template $TemplatePath
    $newContent = $newContent -replace "`r?`n", "`r`n"

    if ($WhatIfPreference) {
        Write-Output ("Would add source type '{0}' with template '{1}' to {2}" -f $TypeName, $TemplatePath, $configPath)
        exit 0
    }

    if (-not $PSCmdlet.ShouldProcess($configPath, "Add source type $TypeName")) {
        exit 0
    }

    Set-Content -Path $configPath -Value $newContent -Encoding UTF8
    Write-Log "Added source type '$TypeName' to $configPath" "INFO"
    Write-Host "Added source type: $TypeName" -ForegroundColor Green

    if (-not (Test-Path $TemplatePath)) {
        Write-Host "WARNING: template file does not exist yet: $TemplatePath" -ForegroundColor Yellow
    }

    if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
        $repoRoot = Get-RepoRoot
        Invoke-GitCommit -Message "config: add source type '$TypeName'" -Files @("config/pinky-config.yaml") -RepoPath $repoRoot | Out-Null
    }

    exit 0
}
catch {
    $lineNumber = if ($_.InvocationInfo) { $_.InvocationInfo.ScriptLineNumber } else { 0 }
    Write-Log "Source type management failed at line ${lineNumber}: $($_.Exception.Message)" "ERROR"
    Write-Host "ERROR: line ${lineNumber}: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
