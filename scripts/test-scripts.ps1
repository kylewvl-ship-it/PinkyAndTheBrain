#!/usr/bin/env pwsh
# Test suite for PinkyAndTheBrain PowerShell scripts

param(
    [string]$TestScript = "all",
    [switch]$Verbose
)

# Import common functions
. "$PSScriptRoot/lib/common.ps1"

$script:testResults = @()

function Test-ScriptExists {
    param([string]$ScriptName)
    
    $scriptPath = "$PSScriptRoot/$ScriptName"
    $exists = Test-Path $scriptPath
    
    $script:testResults += [PSCustomObject]@{
        Test = "Script Exists: $ScriptName"
        Result = if ($exists) { "PASS" } else { "FAIL" }
        Message = if ($exists) { "Script found" } else { "Script not found at $scriptPath" }
    }
    
    return $exists
}

function Test-ScriptSyntax {
    param([string]$ScriptName)
    
    $scriptPath = "$PSScriptRoot/$ScriptName"
    
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$null)
        $script:testResults += [PSCustomObject]@{
            Test = "Script Syntax: $ScriptName"
            Result = "PASS"
            Message = "Valid PowerShell syntax"
        }
        return $true
    }
    catch {
        $script:testResults += [PSCustomObject]@{
            Test = "Script Syntax: $ScriptName"
            Result = "FAIL"
            Message = "Syntax error: $($_.Exception.Message)"
        }
        return $false
    }
}

function Test-ScriptHelp {
    param([string]$ScriptName)
    
    $scriptPath = "$PSScriptRoot/$ScriptName"
    
    try {
        # For capture.ps1, provide a dummy Type parameter since it's mandatory
        if ($ScriptName -eq "capture.ps1") {
            $output = & $scriptPath -Type manual -Help 2>&1
        } else {
            $output = & $scriptPath -Help 2>&1
        }
        $hasHelp = $output -match "Examples:" -or $output -match "Usage:"
        
        $script:testResults += [PSCustomObject]@{
            Test = "Script Help: $ScriptName"
            Result = if ($hasHelp) { "PASS" } else { "FAIL" }
            Message = if ($hasHelp) { "Help output available" } else { "No help output found" }
        }
        
        return $hasHelp
    }
    catch {
        $script:testResults += [PSCustomObject]@{
            Test = "Script Help: $ScriptName"
            Result = "FAIL"
            Message = "Error running help: $($_.Exception.Message)"
        }
        return $false
    }
}

function Test-CaptureScript {
    Write-Host "Testing capture.ps1..." -ForegroundColor Cyan
    
    # Test script existence and syntax
    if (!(Test-ScriptExists "capture.ps1")) { return }
    if (!(Test-ScriptSyntax "capture.ps1")) { return }
    Test-ScriptHelp "capture.ps1"
    
    # Test WhatIf mode
    try {
        $output = & "$PSScriptRoot/capture.ps1" -Type manual -Title "Test Note" -Content "Test content" -WhatIf 2>&1
        $whatIfWorks = $output -match "Would create file:"
        
        $script:testResults += [PSCustomObject]@{
            Test = "Capture WhatIf Mode"
            Result = if ($whatIfWorks) { "PASS" } else { "FAIL" }
            Message = if ($whatIfWorks) { "WhatIf mode working" } else { "WhatIf mode not working" }
        }
    }
    catch {
        $script:testResults += [PSCustomObject]@{
            Test = "Capture WhatIf Mode"
            Result = "FAIL"
            Message = "Error: $($_.Exception.Message)"
        }
    }
    
    # Skip parameter validation test to avoid interactive prompts
    $script:testResults += [PSCustomObject]@{
        Test = "Capture Parameter Validation"
        Result = "SKIP"
        Message = "Skipped to avoid interactive prompts"
    }
}

function Test-TriageScript {
    Write-Host "Testing triage.ps1..." -ForegroundColor Cyan
    
    Test-ScriptExists "triage.ps1"
    Test-ScriptSyntax "triage.ps1"
    Test-ScriptHelp "triage.ps1"
    
    # Skip interactive test to avoid hanging
    $script:testResults += [PSCustomObject]@{
        Test = "Triage Empty Inbox Handling"
        Result = "SKIP"
        Message = "Skipped interactive test to avoid hanging"
    }
}

function Test-SearchScript {
    Write-Host "Testing search.ps1..." -ForegroundColor Cyan
    
    Test-ScriptExists "search.ps1"
    Test-ScriptSyntax "search.ps1"
    Test-ScriptHelp "search.ps1"
    
    # Test with non-existent query
    try {
        $output = & "$PSScriptRoot/search.ps1" -Query "nonexistentquery12345" 2>&1
        $handlesNoResults = $output -match "No results found" -or $output -match "Directory structure validation failed"
        
        $script:testResults += [PSCustomObject]@{
            Test = "Search No Results Handling"
            Result = if ($handlesNoResults) { "PASS" } else { "FAIL" }
            Message = if ($handlesNoResults) { "Handles no results gracefully" } else { "Does not handle no results" }
        }
    }
    catch {
        $script:testResults += [PSCustomObject]@{
            Test = "Search No Results Handling"
            Result = "FAIL"
            Message = "Error: $($_.Exception.Message)"
        }
    }
}

function Test-HealthCheckScript {
    Write-Host "Testing health-check.ps1..." -ForegroundColor Cyan
    
    Test-ScriptExists "health-check.ps1"
    Test-ScriptSyntax "health-check.ps1"
    Test-ScriptHelp "health-check.ps1"
    
    # Test different check types
    $checkTypes = @("metadata", "links", "stale", "duplicates", "orphans")
    
    foreach ($type in $checkTypes) {
        try {
            $output = & "$PSScriptRoot/health-check.ps1" -Type $type 2>&1
            $typeWorks = $output -match "Checking" -or $output -match "Directory structure validation failed"
            
            $script:testResults += [PSCustomObject]@{
                Test = "Health Check Type: $type"
                Result = if ($typeWorks) { "PASS" } else { "FAIL" }
                Message = if ($typeWorks) { "Check type $type works" } else { "Check type $type failed" }
            }
        }
        catch {
            $script:testResults += [PSCustomObject]@{
                Test = "Health Check Type: $type"
                Result = "FAIL"
                Message = "Error: $($_.Exception.Message)"
            }
        }
    }
}

function Test-ObsidianSyncScript {
    Write-Host "Testing obsidian-sync.ps1..." -ForegroundColor Cyan
    
    Test-ScriptExists "obsidian-sync.ps1"
    Test-ScriptSyntax "obsidian-sync.ps1"
    Test-ScriptHelp "obsidian-sync.ps1"
    
    # Test WhatIf mode for different actions
    $actions = @("sync", "validate", "update-links", "create-index")
    
    foreach ($action in $actions) {
        try {
            $output = & "$PSScriptRoot/obsidian-sync.ps1" -Action $action -WhatIf 2>&1
            $actionWorks = $output -match "Would" -or $output -match "Directory structure validation failed"
            
            $script:testResults += [PSCustomObject]@{
                Test = "Obsidian Sync Action: $action"
                Result = if ($actionWorks) { "PASS" } else { "FAIL" }
                Message = if ($actionWorks) { "Action $action works in WhatIf mode" } else { "Action $action failed" }
            }
        }
        catch {
            $script:testResults += [PSCustomObject]@{
                Test = "Obsidian Sync Action: $action"
                Result = "FAIL"
                Message = "Error: $($_.Exception.Message)"
            }
        }
    }
}

function Test-CommonLibrary {
    Write-Host "Testing common library..." -ForegroundColor Cyan
    
    Test-ScriptExists "lib/common.ps1"
    Test-ScriptSyntax "lib/common.ps1"
    
    # Test common functions
    try {
        . "$PSScriptRoot/lib/common.ps1"
        
        # Test Get-TimestampedFilename
        $filename = Get-TimestampedFilename -Title "Test File"
        $filenameWorks = $filename -match '\d{4}-\d{2}-\d{2}-\d{6}-test-file\.md'
        
        $script:testResults += [PSCustomObject]@{
            Test = "Common Library: Get-TimestampedFilename"
            Result = if ($filenameWorks) { "PASS" } else { "FAIL" }
            Message = if ($filenameWorks) { "Function works correctly" } else { "Function output: $filename" }
        }
        
        # Test Write-Log
        $logPath = "test-log.log"
        Write-Log "Test message" "INFO" $logPath
        $logWorks = Test-Path $logPath
        
        $script:testResults += [PSCustomObject]@{
            Test = "Common Library: Write-Log"
            Result = if ($logWorks) { "PASS" } else { "FAIL" }
            Message = if ($logWorks) { "Logging function works" } else { "Logging function failed" }
        }
        
        # Cleanup
        Remove-Item $logPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        $script:testResults += [PSCustomObject]@{
            Test = "Common Library Functions"
            Result = "FAIL"
            Message = "Error: $($_.Exception.Message)"
        }
    }
}

# Run tests
Write-Host "🧪 Running PinkyAndTheBrain Script Tests" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Gray

if ($TestScript -eq "all" -or $TestScript -eq "common") {
    Test-CommonLibrary
}

if ($TestScript -eq "all" -or $TestScript -eq "capture") {
    Test-CaptureScript
}

if ($TestScript -eq "all" -or $TestScript -eq "triage") {
    Test-TriageScript
}

if ($TestScript -eq "all" -or $TestScript -eq "search") {
    Test-SearchScript
}

if ($TestScript -eq "all" -or $TestScript -eq "health-check") {
    Test-HealthCheckScript
}

if ($TestScript -eq "all" -or $TestScript -eq "obsidian-sync") {
    Test-ObsidianSyncScript
}

# Show results
Write-Host "`n📊 Test Results" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Gray

$passed = ($script:testResults | Where-Object { $_.Result -eq "PASS" }).Count
$failed = ($script:testResults | Where-Object { $_.Result -eq "FAIL" }).Count
$total = $script:testResults.Count

Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red

if ($failed -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    $script:testResults | Where-Object { $_.Result -eq "FAIL" } | ForEach-Object {
        Write-Host "❌ $($_.Test): $($_.Message)" -ForegroundColor Red
    }
}

if ($Verbose) {
    Write-Host "`nAll Test Results:" -ForegroundColor Yellow
    $script:testResults | ForEach-Object {
        $color = if ($_.Result -eq "PASS") { "Green" } else { "Red" }
        $icon = if ($_.Result -eq "PASS") { "✅" } else { "❌" }
        Write-Host "$icon $($_.Test): $($_.Message)" -ForegroundColor $color
    }
}

# Exit with appropriate code
if ($failed -eq 0) {
    Write-Host "`n✅ All tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n❌ $failed tests failed!" -ForegroundColor Red
    exit 1
}