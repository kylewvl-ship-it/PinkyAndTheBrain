# Shared Git utility functions for PinkyAndTheBrain
# All functions degrade gracefully when Git is unavailable

function Test-GitAvailable {
    try {
        $null = git --version 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Test-GitRepository {
    param([string]$Path = ".")
    try {
        Push-Location $Path
        $null = git rev-parse --git-dir 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
    finally {
        Pop-Location
    }
}

function Invoke-GitCommit {
    param(
        [string[]]$Files,
        [string]$Message,
        [string]$RepoPath = ".",
        [string]$LogFile = "logs/git-operations.log",
        [switch]$IncludeAll
    )

    if (-not (Test-GitAvailable)) {
        Write-Log "Git not available - skipping version control commit" "WARN" $LogFile
        return $false
    }

    if (-not (Test-GitRepository -Path $RepoPath)) {
        Write-Log "No Git repository at $RepoPath - skipping commit" "WARN" $LogFile
        return $false
    }

    try {
        Push-Location $RepoPath

        if ($Files -and $Files.Count -gt 0) {
            foreach ($file in $Files) {
                git add -- $file 2>&1 | Out-Null
            }
        }
        elseif ($IncludeAll) {
            git add -A 2>&1 | Out-Null
        }
        else {
            Write-Log "No files supplied for Git commit: $Message" "WARN" $LogFile
            return $false
        }

        # Check if there's anything to commit
        $status = git status --porcelain 2>&1
        if ([string]::IsNullOrWhiteSpace($status)) {
            return $true
        }

        git commit -m $Message 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Git commit failed for: $Message" "WARN" $LogFile
            return $false
        }

        Write-Log "Git commit: $Message" "INFO" $LogFile
        return $true
    }
    catch {
        Write-Log "Git operation error: $($_.Exception.Message)" "WARN" $LogFile
        return $false
    }
    finally {
        Pop-Location
    }
}

function Get-GitLog {
    param(
        [string]$RepoPath = ".",
        [int]$Count = 20,
        [string]$FilePath = "",
        [string]$Format = "%h|%ad|%s"
    )

    if (-not (Test-GitAvailable) -or -not (Test-GitRepository -Path $RepoPath)) {
        return @()
    }

    try {
        Push-Location $RepoPath
        $gitArgs = @("log", "--date=short", "--format=$Format", "-n", $Count)
        if ($FilePath) { $gitArgs += "--", $FilePath }

        $output = & git @gitArgs 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }

        return $output | Where-Object { $_ -match '\S' }
    }
    catch {
        return @()
    }
    finally {
        Pop-Location
    }
}

function Get-GitUncommitted {
    param([string]$RepoPath = ".")

    if (-not (Test-GitAvailable) -or -not (Test-GitRepository -Path $RepoPath)) {
        return @()
    }

    try {
        Push-Location $RepoPath
        $output = git status --porcelain 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }
        return $output | Where-Object { $_ -match '\S' }
    }
    catch {
        return @()
    }
    finally {
        Pop-Location
    }
}

function Get-GitFileHistory {
    param(
        [string]$FilePath,
        [string]$RepoPath = ".",
        [int]$Count = 10
    )

    return Get-GitLog -RepoPath $RepoPath -Count $Count -FilePath $FilePath
}

function Invoke-GitInit {
    param([string]$RepoPath = ".")

    if (-not (Test-GitAvailable)) {
        Write-Log "Git not available - cannot initialize repository" "WARN"
        return $false
    }

    try {
        Push-Location $RepoPath
        git init 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
    finally {
        Pop-Location
    }
}
