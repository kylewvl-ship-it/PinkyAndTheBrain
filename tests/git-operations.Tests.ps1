# Pester tests for git-operations.ps1

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $script:Root "scripts/lib/common.ps1")
. (Join-Path $script:Root "scripts/lib/git-operations.ps1")

Describe "Test-GitAvailable" {
    It "returns a boolean" {
        $result = Test-GitAvailable
        ($result -is [bool]) | Should Be $true
    }
}

Describe "Test-GitRepository" {
    It "returns true for a valid git repository" {
        $result = Test-GitRepository -Path $script:Root
        $result | Should Be $true
    }

    It "returns false for a non-git directory" {
        $tempDir = Join-Path $TestDrive "not-a-repo"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $result = Test-GitRepository -Path $tempDir
        $result | Should Be $false
    }
}

Describe "Get-GitLog" {
    It "returns an array" {
        $result = Get-GitLog -RepoPath $script:Root -Count 5
        $result | Should Not BeNullOrEmpty
    }

    It "returns non-empty string entries" {
        $result = Get-GitLog -RepoPath $script:Root -Count 1
        if ($result.Count -gt 0) {
            [string]::IsNullOrWhiteSpace($result[0]) | Should Be $false
        }
    }

    It "returns empty array for non-git directory" {
        $tempDir = Join-Path $TestDrive "no-git"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $result = Get-GitLog -RepoPath $tempDir -Count 5
        $result.Count | Should Be 0
    }
}

Describe "Get-GitUncommitted" {
    It "returns an array" {
        $result = Get-GitUncommitted -RepoPath $script:Root
        $result -ne $null | Should Be $true
    }

    It "returns empty array for non-git directory" {
        $tempDir = Join-Path $TestDrive "no-git2"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $result = Get-GitUncommitted -RepoPath $tempDir
        $result.Count | Should Be 0
    }
}

Describe "Invoke-GitCommit - graceful degradation" {
    It "returns false for non-git directory without throwing" {
        $tempDir = Join-Path $TestDrive "no-git3"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $result = Invoke-GitCommit -Message "test commit" -RepoPath $tempDir
        $result | Should Be $false
    }
}

Describe "Get-GitFileHistory" {
    It "returns array for known file" {
        $result = Get-GitFileHistory -FilePath "scripts/lib/common.ps1" -RepoPath $script:Root -Count 5
        $result -ne $null | Should Be $true
    }

    It "returns empty for non-existent file" {
        $result = Get-GitFileHistory -FilePath "nonexistent/file.md" -RepoPath $script:Root -Count 5
        $result.Count | Should Be 0
    }
}
