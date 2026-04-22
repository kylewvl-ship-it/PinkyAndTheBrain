# Bug Condition Exploration Test
# **Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13**
# CRITICAL: This test MUST FAIL on unfixed code - failure confirms quality issues exist
# DO NOT attempt to fix the test or code when it fails

Describe "PowerShell Script Quality Issues Exploration" {
    BeforeAll {
        # Get all PowerShell scripts to analyze
        $ScriptFiles = Get-ChildItem -Path "scripts" -Filter "*.ps1" -Recurse
        $ScriptContents = @{}
        foreach ($file in $ScriptFiles) {
            $ScriptContents[$file.Name] = Get-Content $file.FullName -Raw
        }
    }

    Context "Error Handling Pattern Inconsistencies" {
        It "Should use consistent error handling patterns across all scripts" {
            $ErrorPatterns = @()
            
            foreach ($script in $ScriptContents.Keys) {
                $content = $ScriptContents[$script]
                
                # Check for different error handling patterns
                $writeErrorCount = ($content | Select-String "Write-Error" -AllMatches).Matches.Count
                $throwCount = ($content | Select-String "\bthrow\b" -AllMatches).Matches.Count  
                $writeHostErrorCount = ($content | Select-String "Write-Host.*error" -AllMatches).Matches.Count
                
                if ($writeErrorCount -gt 0 -or $throwCount -gt 0 -or $writeHostErrorCount -gt 0) {
                    $ErrorPatterns += [PSCustomObject]@{
                        Script = $script
                        WriteError = $writeErrorCount
                        Throw = $throwCount
                        WriteHostError = $writeHostErrorCount
                    }
                }
            }
            
            # Test should FAIL: Scripts use inconsistent error handling
            $uniquePatterns = $ErrorPatterns | ForEach-Object { 
                if ($_.WriteError -gt 0) { "Write-Error" }
                if ($_.Throw -gt 0) { "throw" }  
                if ($_.WriteHostError -gt 0) { "Write-Host" }
            } | Sort-Object -Unique
            
            $uniquePatterns.Count | Should Be 1
        }
    }

    Context "Hardcoded Configuration Values" {
        It "Should use centralized configuration instead of hardcoded values" {
            $HardcodedValues = @()
            
            foreach ($script in $ScriptContents.Keys) {
                $content = $ScriptContents[$script]
                
                # Look for common hardcoded patterns
                $magicNumbers = $content | Select-String '\$\w+\s*=\s*\d+' -AllMatches
                $hardcodedPaths = $content | Select-String '["''][C-Z]:\\[^"'']*["'']' -AllMatches
                $hardcodedUrls = $content | Select-String 'https?://[^\s"'']+' -AllMatches
                
                if ($magicNumbers.Matches.Count -gt 0 -or $hardcodedPaths.Matches.Count -gt 0 -or $hardcodedUrls.Matches.Count -gt 0) {
                    $HardcodedValues += [PSCustomObject]@{
                        Script = $script
                        MagicNumbers = $magicNumbers.Matches.Count
                        HardcodedPaths = $hardcodedPaths.Matches.Count
                        HardcodedUrls = $hardcodedUrls.Matches.Count
                    }
                }
            }
            
            # Test should FAIL: Scripts contain hardcoded values
            $totalHardcoded = ($HardcodedValues | Measure-Object MagicNumbers, HardcodedPaths, HardcodedUrls -Sum).Sum
            $totalHardcoded | Should Be 0
        }
    }

    Context "Template Processing Security Vulnerabilities" {
        It "Should use secure template processing to prevent injection" {
            $VulnerableTemplates = @()
            
            foreach ($script in $ScriptContents.Keys) {
                $content = $ScriptContents[$script]
                
                # Look for unsafe string concatenation in templates
                $stringConcatenation = $content | Select-String '\$\w+\s*\+\s*\$\w+' -AllMatches
                $unsafeSubstitution = $content | Select-String '"\$\w+\$\w+"' -AllMatches
                $executeString = $content | Select-String 'Invoke-Expression|iex' -AllMatches
                
                if ($stringConcatenation.Matches.Count -gt 0 -or $unsafeSubstitution.Matches.Count -gt 0 -or $executeString.Matches.Count -gt 0) {
                    $VulnerableTemplates += [PSCustomObject]@{
                        Script = $script
                        StringConcatenation = $stringConcatenation.Matches.Count
                        UnsafeSubstitution = $unsafeSubstitution.Matches.Count
                        ExecuteString = $executeString.Matches.Count
                    }
                }
            }
            
            # Test should FAIL: Scripts have template injection vulnerabilities
            $totalVulnerabilities = ($VulnerableTemplates | Measure-Object StringConcatenation, UnsafeSubstitution, ExecuteString -Sum).Sum
            $totalVulnerabilities | Should Be 0
        }
    }

    Context "Search Performance Issues" {
        It "Should use optimized search algorithms for large datasets" {
            $PerformanceIssues = @()
            
            foreach ($script in $ScriptContents.Keys) {
                $content = $ScriptContents[$script]
                
                # Look for inefficient search patterns
                $nestedLoops = $content | Select-String 'foreach.*foreach' -AllMatches
                $linearSearch = $content | Select-String 'Where-Object.*-eq' -AllMatches  
                $noIndexing = $content | Select-String 'Get-ChildItem.*-Recurse' -AllMatches
                
                if ($nestedLoops.Matches.Count -gt 0 -or $linearSearch.Matches.Count -gt 0 -or $noIndexing.Matches.Count -gt 0) {
                    $PerformanceIssues += [PSCustomObject]@{
                        Script = $script
                        NestedLoops = $nestedLoops.Matches.Count
                        LinearSearch = $linearSearch.Matches.Count
                        NoIndexing = $noIndexing.Matches.Count
                    }
                }
            }
            
            # Test should FAIL: Scripts use inefficient search algorithms
            $totalIssues = ($PerformanceIssues | Measure-Object NestedLoops, LinearSearch, NoIndexing -Sum).Sum
            $totalIssues | Should Be 0
        }
    }

    Context "PowerShell Version Compatibility Issues" {
        It "Should handle PowerShell version differences properly" {
            $CompatibilityIssues = @()
            
            foreach ($script in $ScriptContents.Keys) {
                $content = $ScriptContents[$script]
                
                # Look for version-specific syntax that may cause issues
                $ps7Syntax = $content | Select-String '\?\?' -AllMatches  # Null coalescing operator
                $ps7Ternary = $content | Select-String '\?\s*.*\s*:\s*.*' -AllMatches  # Ternary operator
                $noVersionCheck = -not ($content | Select-String '\$PSVersionTable' -AllMatches).Matches.Count
                
                if ($ps7Syntax.Matches.Count -gt 0 -or $ps7Ternary.Matches.Count -gt 0 -or $noVersionCheck) {
                    $CompatibilityIssues += [PSCustomObject]@{
                        Script = $script
                        PS7Syntax = $ps7Syntax.Matches.Count
                        PS7Ternary = $ps7Ternary.Matches.Count
                        NoVersionCheck = $noVersionCheck
                    }
                }
            }
            
            # Test should FAIL: Scripts have compatibility issues
            $scriptsWithIssues = $CompatibilityIssues.Count
            $scriptsWithIssues | Should Be 0
        }
    }
}