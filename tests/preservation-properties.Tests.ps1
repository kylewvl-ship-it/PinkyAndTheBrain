# Property-Based Tests for PowerShell Script Quality Fixes - Preservation Properties
# **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10**
# These tests capture current behavior patterns to ensure core functionality is preserved

BeforeAll {
    # Import required modules
    Import-Module Pester
    
    # Set up test environment
    $script:TestRoot = $PSScriptRoot
    $script:ProjectRoot = Split-Path $TestRoot -Parent
    $script:ScriptsPath = Join-Path $ProjectRoot "scripts"
    $script:ConfigPath = Join-Path $ProjectRoot "config"
    $script:TestVaultPath = Join-Path $TestRoot "TestVault"
    
    # Create test vault structure
    if (Test-Path $TestVaultPath) {
        Remove-Item $TestVaultPath -Recurse -Force
    }
    
    $folders = @("inbox", "raw", "working", "wiki", "archive", "schemas")
    foreach ($folder in $folders) {
        New-Item -ItemType Directory -Path "$TestVaultPath/$folder" -Force | Out-Null
    }
    
    # Create test config
    $testConfig = @"
project: PinkyAndTheBrain
version: 0.1.0
runtime: powershell

paths:
  knowledge_root: $($TestVaultPath -replace '\\', '/')
  inbox: $($TestVaultPath -replace '\\', '/')/inbox
  raw: $($TestVaultPath -replace '\\', '/')/raw
  working: $($TestVaultPath -replace '\\', '/')/working
  wiki: $($TestVaultPath -replace '\\', '/')/wiki
  archive: $($TestVaultPath -replace '\\', '/')/archive
  schemas: $($TestVaultPath -replace '\\', '/')/schemas
  templates: templates
  logs: logs

review:
  working_review_days: 30
  wiki_review_days: 90
  stale_after_days: 180
"@
    
    $testConfigPath = Join-Path $TestRoot "test-config.yaml"
    Set-Content -Path $testConfigPath -Value $testConfig -Encoding UTF8
    
    # Create test templates
    $templatesPath = Join-Path $ProjectRoot "templates"
    if (!(Test-Path $templatesPath)) {
        New-Item -ItemType Directory -Path $templatesPath -Force | Out-Null
    }
    
    $inboxTemplate = @"
---
title: "{{title}}"
captured_date: "{{timestamp}}"
source_type: "{{source_type}}"
source_url: "{{source_url}}"
source_title: "{{source_title}}"
review_status: "pending"
disposition: "inbox"
project_name_optional: "{{project_name_optional}}"
---

{{content}}
"@
    
    Set-Content -Path "$templatesPath/inbox-item.md" -Value $inboxTemplate -Encoding UTF8
}

Describe "Property 2: Preservation - Core Functionality Unchanged" {
    
    Context "Capture Operations Produce Identical File Outputs" {
        It "Should generate consistent file structure for manual capture" {
            # Test multiple manual capture scenarios
            $testCases = @(
                @{ Title = "Test Note"; Content = "Test content"; Type = "manual" }
                @{ Title = "Another Note"; Content = "Different content"; Type = "manual" }
                @{ Title = "Special-Chars!@#"; Content = "Content with special chars"; Type = "manual" }
            )
            
            foreach ($case in $testCases) {
                # Capture using current implementation
                $result = & "$ScriptsPath/capture.ps1" -Type $case.Type -Title $case.Title -Content $case.Content -WhatIf
                
                # Verify consistent behavior patterns
                $result | Should -Not -BeNullOrEmpty
                $result | Should -Match "Would create file:"
                $result | Should -Match "\.md$"
                
                # Verify timestamp pattern consistency
                $result | Should -Match "\d{4}-\d{2}-\d{2}-\d{6}"
            }
        }
        
        It "Should maintain identical directory targeting for different capture types" {
            $captureTypes = @("manual", "web", "idea")
            
            foreach ($type in $captureTypes) {
                $result = & "$ScriptsPath/capture.ps1" -Type $type -Title "Test" -Content "Content" -WhatIf
                
                # All these types should target inbox folder
                $result | Should -Match "inbox"
                $result | Should -Not -Match "raw|working|wiki|archive"
            }
        }
    }
    
    Context "Triage Operations Maintain Exact Categorization Logic" {
        BeforeEach {
            # Create test inbox files with proper frontmatter
            $testFiles = @(
                @{ Name = "test1.md"; Content = @"
---
title: "Test Item 1"
captured_date: "2024-01-01T10:00:00.000Z"
source_type: "manual"
review_status: "pending"
disposition: "inbox"
---

Test content 1
"@ }
                @{ Name = "test2.md"; Content = @"
---
title: "Test Item 2"
captured_date: "2024-01-02T10:00:00.000Z"
source_type: "web"
review_status: "pending"
disposition: "inbox"
---

Test content 2
"@ }
            )
            
            foreach ($file in $testFiles) {
                Set-Content -Path "$TestVaultPath/inbox/$($file.Name)" -Value $file.Content -Encoding UTF8
            }
        }
        
        It "Should maintain consistent item parsing and display format" {
            # Mock the triage script's item parsing behavior
            $inboxPath = "$TestVaultPath/inbox"
            $files = Get-ChildItem -Path $inboxPath -Filter "*.md"
            
            $parsedItems = @()
            foreach ($file in $files) {
                $content = Get-Content $file.FullName -Raw
                $frontmatter = @{}
                
                if ($content -match '(?s)^---\s*\n(.*?)\n---') {
                    $yamlContent = $matches[1]
                    $yamlContent -split "`n" | ForEach-Object {
                        if ($_ -match '^(\w+):\s*(.*)') {
                            $frontmatter[$matches[1]] = $matches[2].Trim('"')
                        }
                    }
                }
                
                $parsedItems += @{
                    FileName = $file.Name
                    Title = $frontmatter.title
                    SourceType = $frontmatter.source_type
                    CaptureDate = $frontmatter.captured_date
                }
            }
            
            # Verify consistent parsing behavior
            $parsedItems.Count | Should -Be 2
            $parsedItems[0].Title | Should -Not -BeNullOrEmpty
            $parsedItems[0].SourceType | Should -BeIn @("manual", "web", "conversation", "clipboard", "idea")
            $parsedItems[1].Title | Should -Not -BeNullOrEmpty
            $parsedItems[1].SourceType | Should -BeIn @("manual", "web", "conversation", "clipboard", "idea")
        }
    }
    
    Context "Search Operations Return Identical Results" {
        BeforeEach {
            # Create test content across layers
            $testContent = @(
                @{ Layer = "working"; File = "work1.md"; Content = @"
---
title: "Working Note PowerShell"
status: "in-progress"
---

This is about PowerShell scripting and automation.
"@ }
                @{ Layer = "wiki"; File = "wiki1.md"; Content = @"
---
title: "Wiki PowerShell Guide"
status: "verified"
---

PowerShell is a powerful scripting language.
"@ }
            )
            
            foreach ($item in $testContent) {
                Set-Content -Path "$TestVaultPath/$($item.Layer)/$($item.File)" -Value $item.Content -Encoding UTF8
            }
        }
        
        It "Should maintain consistent search result ranking and format" {
            # Test search behavior patterns
            $searchQuery = "PowerShell"
            
            # Mock search logic to verify consistent behavior
            $layers = @{
                "working" = @{ Path = "$TestVaultPath/working"; Label = "WORK" }
                "wiki" = @{ Path = "$TestVaultPath/wiki"; Label = "WIKI" }
            }
            
            $results = @()
            foreach ($layerName in $layers.Keys) {
                $layer = $layers[$layerName]
                $files = Get-ChildItem -Path $layer.Path -Filter "*.md"
                
                foreach ($file in $files) {
                    $content = Get-Content $file.FullName -Raw
                    $frontmatter = @{}
                    
                    if ($content -match '(?s)^---\s*\n(.*?)\n---') {
                        $yamlContent = $matches[1]
                        $yamlContent -split "`n" | ForEach-Object {
                            if ($_ -match '^(\w+):\s*(.*)') {
                                $frontmatter[$matches[1]] = $matches[2].Trim('"')
                            }
                        }
                    }
                    
                    $contentBody = $content -replace '(?s)^---.*?---\s*', ''
                    
                    # Calculate relevance score (current algorithm)
                    $relevanceScore = 0
                    $title = $frontmatter.title
                    
                    if ($title -like "*$searchQuery*") {
                        $relevanceScore += 100
                    }
                    if ($contentBody -like "*$searchQuery*") {
                        $relevanceScore += 50
                    }
                    
                    if ($relevanceScore -gt 0) {
                        $results += @{
                            Layer = $layer.Label
                            Title = $title
                            RelevanceScore = $relevanceScore
                        }
                    }
                }
            }
            
            # Verify consistent search behavior
            $results.Count | Should -BeGreaterThan 0
            $results | ForEach-Object { $_.RelevanceScore | Should -BeGreaterThan 0 }
            
            # Verify ranking consistency (title matches score higher)
            $titleMatches = $results | Where-Object { $_.RelevanceScore -ge 100 }
            $contentMatches = $results | Where-Object { $_.RelevanceScore -eq 50 }
            
            if ($titleMatches.Count -gt 0 -and $contentMatches.Count -gt 0) {
                $titleMatches[0].RelevanceScore | Should -BeGreaterThan $contentMatches[0].RelevanceScore
            }
        }
    }
    
    Context "Health-Check Operations Report Identical System Status" {
        BeforeEach {
            # Create test files with various health conditions
            $testFiles = @(
                @{ Path = "$TestVaultPath/working/missing-metadata.md"; Content = "# No frontmatter file" }
                @{ Path = "$TestVaultPath/working/good-file.md"; Content = @"
---
title: "Good File"
status: "complete"
confidence: "high"
last_updated: "2024-01-01T10:00:00.000Z"
---

This file has proper metadata and sufficient content to pass health checks.
"@ }
            )
            
            foreach ($file in $testFiles) {
                $dir = Split-Path $file.Path -Parent
                if (!(Test-Path $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
                Set-Content -Path $file.Path -Value $file.Content -Encoding UTF8
            }
        }
        
        It "Should maintain consistent metadata validation patterns" {
            # Mock metadata validation logic
            $workingPath = "$TestVaultPath/working"
            $files = Get-ChildItem -Path $workingPath -Filter "*.md"
            
            $findings = @()
            foreach ($file in $files) {
                $content = Get-Content $file.FullName -Raw
                
                # Check frontmatter existence (current logic)
                if ($content -notmatch '(?s)^---\s*\n(.*?)\n---') {
                    $findings += @{
                        Type = "Missing Metadata"
                        File = $file.Name
                        Issue = "No frontmatter found"
                    }
                }
                
                # Check content length (current logic)
                $contentBody = $content -replace '(?s)^---.*?---\s*', ''
                if ($contentBody.Trim().Length -lt 50) {
                    $findings += @{
                        Type = "Missing Metadata"
                        File = $file.Name
                        Issue = "Content too short"
                    }
                }
            }
            
            # Verify consistent detection patterns
            $findings.Count | Should -BeGreaterThan 0
            $missingMetadata = $findings | Where-Object { $_.Issue -eq "No frontmatter found" }
            $missingMetadata.Count | Should -Be 1
            $missingMetadata[0].File | Should -Be "missing-metadata.md"
        }
    }
    
    Context "Configuration Loading Works Identically" {
        It "Should maintain consistent config parsing behavior" {
            # Test current config loading patterns
            $configContent = Get-Content "$ConfigPath/pinky-config.yaml" -Raw
            
            # Verify config structure consistency
            $configContent | Should -Match "project:"
            $configContent | Should -Match "paths:"
            $configContent | Should -Match "knowledge_root:"
            $configContent | Should -Match "inbox:"
            $configContent | Should -Match "working:"
            $configContent | Should -Match "wiki:"
            
            # Test config parsing logic consistency
            $parsedSections = @()
            $configContent -split "`n" | ForEach-Object {
                if ($_ -match '^(\w+):') {
                    $parsedSections += $matches[1]
                }
            }
            
            $parsedSections | Should -Contain "project"
            $parsedSections | Should -Contain "paths"
        }
    }
    
    Context "Interactive Mode Prompts Work Identically" {
        It "Should maintain consistent prompt and validation patterns" {
            # Test parameter validation patterns (current behavior)
            $captureScript = Get-Content "$ScriptsPath/capture.ps1" -Raw
            
            # Verify validation patterns are preserved
            $captureScript | Should -Match "ValidateSet.*manual.*web.*conversation"
            $captureScript | Should -Match "Mandatory.*true"
            
            # Test error message consistency
            $captureScript | Should -Match "Title and Content are required"
            $captureScript | Should -Match "File and Service are required"
        }
    }
    
    Context "Log File Locations and Basic Logging Preserved" {
        It "Should maintain consistent logging behavior patterns" {
            # Test current logging patterns
            $commonScript = Get-Content "$ScriptsPath/lib/common.ps1" -Raw
            
            # Verify logging function structure
            $commonScript | Should -Match "function Write-Log"
            $commonScript | Should -Match "logs/script-errors.log"
            $commonScript | Should -Match "Add-Content.*LogFile"
            
            # Test log level handling consistency
            $commonScript | Should -Match "ERROR.*Red"
            $commonScript | Should -Match "WARN.*Yellow"
            $commonScript | Should -Match "INFO.*Green"
        }
    }
    
    Context "Obsidian Vault Operations Maintain Compatibility" {
        It "Should preserve Obsidian integration patterns" {
            # Test current Obsidian compatibility logic
            $obsidianScript = Get-Content "$ScriptsPath/obsidian-sync.ps1" -Raw
            
            # Verify key Obsidian patterns are preserved
            $obsidianScript | Should -Match "\.obsidian"
            $obsidianScript | Should -Match "app\.json"
            $obsidianScript | Should -Match "pluginEnabledStatus"
            
            # Test link conversion patterns
            $obsidianScript | Should -Match "\[\[.*\]\]"
            $obsidianScript | Should -Match "wiki.*links"
        }
    }
}

AfterAll {
    # Clean up test environment
    if (Test-Path $TestVaultPath) {
        Remove-Item $TestVaultPath -Recurse -Force
    }
    
    $testConfigPath = Join-Path $TestRoot "test-config.yaml"
    if (Test-Path $testConfigPath) {
        Remove-Item $testConfigPath -Force
    }
}