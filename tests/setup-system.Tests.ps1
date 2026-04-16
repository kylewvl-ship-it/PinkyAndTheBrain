# Pester tests for setup-system.ps1

Describe "setup-system.ps1" {
    BeforeEach {
        $script:SetupScript = Join-Path $PSScriptRoot "../scripts/setup-system.ps1"
        $script:TestRoot = Join-Path $PSScriptRoot "TestDrive"
        
        # Create a clean test environment
        if (Test-Path $script:TestRoot) {
            Remove-Item $script:TestRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null
    }
    Context "Fresh system initialization" {
        It "Should create all required folders" {
            # Arrange
            $testDir = Join-Path $script:TestRoot "fresh-test"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Act - Use Force flag and specify root path for testing
                & $script:SetupScript -Force -RootPath $testDir
                
                # Assert
                $expectedDirs = @(
                    "knowledge/inbox", "knowledge/raw", "knowledge/working", 
                    "knowledge/wiki", "knowledge/schemas", "knowledge/archive",
                    "scripts", "templates", ".ai/handoffs", "config"
                )
                
                foreach ($dir in $expectedDirs) {
                    $fullPath = Join-Path $testDir $dir
                    Test-Path $fullPath | Should Be $true
                }
            }
            finally {
                # No need to pop location since we're not changing it
            }
        }
        
        It "Should create index.md files in knowledge folders" {
            # Arrange
            $testDir = Join-Path $script:TestRoot "index-test"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            try {
                # Act - Use Force flag and specify root path
                & $script:SetupScript -Force -RootPath $testDir
                
                # Assert
                $expectedIndexFiles = @(
                    "knowledge/inbox/index.md", "knowledge/raw/index.md",
                    "knowledge/working/index.md", "knowledge/wiki/index.md",
                    "knowledge/archive/index.md", "knowledge/schemas/index.md"
                )
                
                foreach ($file in $expectedIndexFiles) {
                    $fullPath = Join-Path $testDir $file
                    Test-Path $fullPath | Should Be $true
                    (Get-Content $fullPath -Raw).Length | Should BeGreaterThan 0
                }
            }
            finally {
                # No need to pop location
            }
        }
    }
    
    Context "Existing directory protection" {
        It "Should create backup when existing files are present" {
            # Arrange
            $testDir = Join-Path $script:TestRoot "backup-test"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            # Create existing file
            New-Item -ItemType Directory -Path (Join-Path $testDir "knowledge") -Force | Out-Null
            Set-Content -Path (Join-Path $testDir "knowledge/existing-file.txt") -Value "existing content"

            # Act - Use Force flag and specify root path
            & $script:SetupScript -Force -RootPath $testDir

            # Assert - @() forces array so [0] returns the item, not its first character
            $backupDirs = @(Get-ChildItem -Path $testDir -Directory -Name "backup-*")
            $backupDirs.Count | Should BeGreaterThan 0

            $backupPath = Join-Path $testDir $backupDirs[0]

            # Original file should be preserved in backup
            Test-Path (Join-Path $backupPath "knowledge/existing-file.txt") | Should Be $true
        }
        
        It "Should exit non-zero when disk space check fails" {
            # Non-existent drive triggers pre-flight failure and exit 1
            & $script:SetupScript -Force -SkipBackup -RootPath "Q:\nonexistent" 2>&1 | Out-Null
            $LASTEXITCODE | Should Be 1
        }

        It "Should provide rollback option after backup creation" {
            # Arrange
            $testDir = Join-Path $script:TestRoot "rollback-test"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            # Create existing content so backup is triggered
            New-Item -ItemType Directory -Path (Join-Path $testDir "knowledge") -Force | Out-Null
            Set-Content -Path (Join-Path $testDir "knowledge/original.txt") -Value "original content"

            # Act - run setup (Force skips confirmation prompt)
            & $script:SetupScript -Force -RootPath $testDir

            # @() forces array so [0] returns the item, not its first character
            $backupDirs = @(Get-ChildItem -Path $testDir -Directory -Name "backup-*")
            $backupDirs.Count | Should BeGreaterThan 0
            $backupPath = Join-Path $testDir $backupDirs[0]

            # Overwrite the file so we can verify rollback restores it
            Set-Content -Path (Join-Path $testDir "knowledge/original.txt") -Value "overwritten"

            # Verify rollback restores original file
            & $script:SetupScript -Rollback -BackupPath $backupPath -RootPath $testDir
            $LASTEXITCODE | Should Be 0
            Test-Path (Join-Path $testDir "knowledge/original.txt") | Should Be $true
            (Get-Content (Join-Path $testDir "knowledge/original.txt") -Raw).Trim() | Should Be "original content"
        }

        It "Should exit non-zero when write permission check fails" {
            # Create directory then deny write access
            $testDir = Join-Path $script:TestRoot "perm-denied"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            try {
                # Deny write permission for current user
                icacls $testDir /deny "${env:USERNAME}:(W,M)" /T /Q 2>&1 | Out-Null

                & $script:SetupScript -Force -SkipBackup -RootPath $testDir 2>&1 | Out-Null
                $LASTEXITCODE | Should Be 1
            }
            finally {
                # Restore write permission for cleanup
                icacls $testDir /grant "${env:USERNAME}:(F)" /T /Q 2>&1 | Out-Null
            }
        }
    }
}