# Pester tests for project/domain bulk tag management

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:ManageScript = Join-Path $script:Root "scripts/manage-project-tags.ps1"

function Initialize-ProjectTagsWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    $script:TargetRoot = Join-Path $script:VaultRoot "inbox/work-notes"

    New-Item -ItemType Directory -Path $script:TargetRoot -Force | Out-Null
    foreach ($folder in @("raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function New-ProjectTagDocument {
    param(
        [string]$Name,
        [string[]]$FrontmatterLines = @()
    )

    $path = Join-Path $script:TargetRoot $Name
    $lines = @("---")
    $lines += 'title: "tag test"'
    $lines += $FrontmatterLines
    $lines += "---"
    $lines += ""
    $lines += "tag body"
    Set-Content -Path $path -Value ($lines -join "`r`n") -Encoding UTF8
    return $path
}

function Invoke-ManageProjectTagsScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:ManageScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function Initialize-GitRepo {
    Push-Location $script:WorkRoot
    try {
        & git init | Out-Null
        & git config user.email "test@example.com" | Out-Null
        & git config user.name "Test User" | Out-Null
        Set-Content -Path (Join-Path $script:WorkRoot ".gitkeep") -Value "baseline" -Encoding UTF8
        & git add . | Out-Null
        & git commit -m "baseline" | Out-Null
    }
    finally {
        Pop-Location
    }
}

Describe "manage-project-tags.ps1 - Story 5.2" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "tags untagged files with SetProject and commits" {
        Initialize-ProjectTagsWorkspace
        Initialize-GitRepo
        $path = New-ProjectTagDocument -Name "untagged.md"

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", "knowledge/inbox/work-notes")
        $content = Get-Content -Path $path -Raw -Encoding UTF8
        Push-Location $script:WorkRoot
        try {
            $log = & git log --oneline -1 | Out-String
        }
        finally {
            Pop-Location
        }

        $result.ExitCode | Should Be 0
        $content | Should Match 'project: "work"'
        $log | Should Match 'project-tags: set project=work'
    }

    It "skips files that already have project tags" {
        Initialize-ProjectTagsWorkspace
        $path = New-ProjectTagDocument -Name "tagged.md" -FrontmatterLines @('project: "home"')

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", "knowledge/inbox/work-notes")
        $content = Get-Content -Path $path -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $content | Should Match 'project: "home"'
        $content | Should Not Match 'project: "work"'
    }

    It "tags untagged files with SetDomain" {
        Initialize-ProjectTagsWorkspace
        $path = New-ProjectTagDocument -Name "domain.md"

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetDomain", "accounting", "-Folder", "knowledge/inbox/work-notes")
        $content = Get-Content -Path $path -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $content | Should Match 'domain: "accounting"'
    }

    It "supports WhatIf without writing" {
        Initialize-ProjectTagsWorkspace
        $path = New-ProjectTagDocument -Name "whatif.md"
        $before = Get-Content -Path $path -Raw -Encoding UTF8

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", "knowledge/inbox/work-notes", "-WhatIf")
        $after = Get-Content -Path $path -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Would set project=work'
        $after | Should Be $before
    }

    It "fails when Folder is missing" {
        Initialize-ProjectTagsWorkspace

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match '-Folder is required'
    }

    It "fails when Folder does not exist" {
        Initialize-ProjectTagsWorkspace

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", "missing")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'Folder not found'
    }

    It "fails when neither project nor domain is provided" {
        Initialize-ProjectTagsWorkspace

        $result = Invoke-ManageProjectTagsScript -Arguments @("-Folder", "knowledge/inbox/work-notes")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'At least one of -SetProject or -SetDomain is required'
    }

    It "updates only untagged files in mixed batches" {
        Initialize-ProjectTagsWorkspace
        $untagged = New-ProjectTagDocument -Name "untagged.md"
        $tagged = New-ProjectTagDocument -Name "tagged.md" -FrontmatterLines @('project: "home"')

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", "knowledge/inbox/work-notes")

        $result.ExitCode | Should Be 0
        (Get-Content -Path $untagged -Raw -Encoding UTF8) | Should Match 'project: "work"'
        (Get-Content -Path $tagged -Raw -Encoding UTF8) | Should Match 'project: "home"'
        $result.Output | Should Match 'Tagged 1 file\(s\). Skipped 1 file\(s\)'
    }

    It "treats empty array project tags as untagged" {
        Initialize-ProjectTagsWorkspace
        $path = New-ProjectTagDocument -Name "empty-array.md" -FrontmatterLines @('project: []')

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", "knowledge/inbox/work-notes")
        $content = Get-Content -Path $path -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $content | Should Match 'project: "work"'
    }

    It "rejects malformed frontmatter instead of wrapping it" {
        Initialize-ProjectTagsWorkspace
        $path = Join-Path $script:TargetRoot "broken.md"
        Set-Content -Path $path -Value "---`r`ntitle: broken`r`nbody without closing delimiter" -Encoding UTF8
        $before = Get-Content -Path $path -Raw -Encoding UTF8

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", "knowledge/inbox/work-notes")
        $content = Get-Content -Path $path -Raw -Encoding UTF8

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'malformed frontmatter'
        $content | Should Be $before
    }

    It "rejects folders outside the repository or configured vault" {
        Initialize-ProjectTagsWorkspace
        $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -Path (Join-Path $outside "outside.md") -Value "---`r`ntitle: outside`r`n---`r`nbody" -Encoding UTF8

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-Folder", $outside)

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'inside the repository or configured vault'
    }

    It "counts skipped files once when both fields are already tagged" {
        Initialize-ProjectTagsWorkspace
        New-ProjectTagDocument -Name "already.md" -FrontmatterLines @('project: "home"', 'domain: "legal"') | Out-Null

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-SetDomain", "accounting", "-Folder", "knowledge/inbox/work-notes")

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Tagged 0 file\(s\). Skipped 1 file\(s\)'
    }

    It "does not count a partially updated file as skipped" {
        Initialize-ProjectTagsWorkspace
        $path = New-ProjectTagDocument -Name "partial.md" -FrontmatterLines @('project: "home"')

        $result = Invoke-ManageProjectTagsScript -Arguments @("-SetProject", "work", "-SetDomain", "accounting", "-Folder", "knowledge/inbox/work-notes")
        $content = Get-Content -Path $path -Raw -Encoding UTF8

        $result.ExitCode | Should Be 0
        $content | Should Match 'project: "home"'
        $content | Should Match 'domain: "accounting"'
        $result.Output | Should Match 'Tagged 1 file\(s\). Skipped 0 file\(s\)'
    }
}
