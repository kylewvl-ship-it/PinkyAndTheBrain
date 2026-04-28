# Pester tests for vault import preview

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:PreviewScript = Join-Path $script:Root "scripts/import-preview.ps1"

function Initialize-PreviewWorkspace {
    $script:WorkRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $script:SourceRoot = Join-Path $script:WorkRoot "source-vault"
    $script:VaultRoot = Join-Path $script:WorkRoot "knowledge"
    $script:PreviewRoot = Join-Path $script:WorkRoot ".ai/import-previews"

    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $script:SourceRoot -Force | Out-Null
    foreach ($folder in @("inbox", "raw", "working", "wiki", "archive", "schemas")) {
        New-Item -ItemType Directory -Path (Join-Path $script:VaultRoot $folder) -Force | Out-Null
    }

    $env:PINKY_VAULT_ROOT = $script:VaultRoot
    $env:PINKY_GIT_REPO_ROOT = $script:WorkRoot
    $env:PINKY_FORCE_NONINTERACTIVE = "1"
}

function Invoke-PreviewScript {
    param([string[]]$Arguments = @())

    Push-Location $script:WorkRoot
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:PreviewScript @Arguments 2>&1
        return @{
            Output = ($output | Out-String)
            ExitCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
}

function New-TestMarkdown {
    param(
        [string]$RelativePath,
        [string]$Content
    )

    $path = Join-Path $script:SourceRoot $RelativePath
    $directory = Split-Path $path -Parent
    if (!(Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

function New-KnowledgeMarkdown {
    param(
        [string]$RelativePath,
        [string]$Content
    )

    $path = Join-Path $script:WorkRoot $RelativePath
    $directory = Split-Path $path -Parent
    if (!(Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -Path $path -Value $Content -Encoding UTF8
    return $path
}

function Get-LatestPreviewJson {
    $file = Get-ChildItem -Path $script:PreviewRoot -Filter "import-preview-*.json" -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if ($null -eq $file) {
        return $null
    }

    return Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-LatestPreviewMarkdownPath {
    $file = Get-ChildItem -Path $script:PreviewRoot -Filter "import-preview-*.md" -File | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    if ($null -eq $file) {
        return ""
    }

    return $file.FullName
}

function Get-PreviewFileByRelativePath {
    param([object]$Preview, [string]$RelativePath)

    return @($Preview.files | Where-Object { $_.relative_path -eq $RelativePath })[0]
}

Describe "import-preview.ps1 - Story 5.3" {
    AfterEach {
        $env:PINKY_VAULT_ROOT = $null
        $env:PINKY_GIT_REPO_ROOT = $null
        $env:PINKY_FORCE_NONINTERACTIVE = $null
    }

    It "fails with exit code 1 for an invalid source vault" {
        Initialize-PreviewWorkspace

        $result = Invoke-PreviewScript -Arguments @("-SourceVault", "missing-vault")

        $result.ExitCode | Should Be 1
        $result.Output | Should Match "Source vault does not exist"
    }

    It "recursively scans markdown files, creates preview artifacts, and does not modify source or knowledge files" {
        Initialize-PreviewWorkspace
        $sourceOne = New-TestMarkdown -RelativePath "Nested/alpha.md" -Content "alpha body with enough words to avoid ambiguous classification and stay visible in preview output."
        $sourceTwo = New-TestMarkdown -RelativePath "beta.md" -Content "beta body with enough words to avoid ambiguous classification and stay visible in preview output."
        Set-Content -Path (Join-Path $script:SourceRoot "skip.txt") -Value "ignore me" -Encoding UTF8
        $knowledgeFile = New-KnowledgeMarkdown -RelativePath "knowledge/wiki/existing.md" -Content "---`ntitle: `"Existing`"`n---`nexisting body"
        $sourceOneBefore = Get-Content -Path $sourceOne -Raw -Encoding UTF8
        $sourceTwoBefore = Get-Content -Path $sourceTwo -Raw -Encoding UTF8
        $knowledgeBefore = Get-Content -Path $knowledgeFile -Raw -Encoding UTF8

        $result = Invoke-PreviewScript -Arguments @("-SourceVault", $script:SourceRoot)
        $preview = Get-LatestPreviewJson
        $markdownPath = Get-LatestPreviewMarkdownPath

        $result.ExitCode | Should Be 0
        $preview.summary.total_files | Should Be 2
        (Test-Path $markdownPath) | Should Be $true
        (Get-Content -Path $sourceOne -Raw -Encoding UTF8) | Should Be $sourceOneBefore
        (Get-Content -Path $sourceTwo -Raw -Encoding UTF8) | Should Be $sourceTwoBefore
        (Get-Content -Path $knowledgeFile -Raw -Encoding UTF8) | Should Be $knowledgeBefore
        $result.Output | Should Match "Preview JSON:"
        $result.Output | Should Match "Preview Report:"
    }

    It "classifies fixtures into category counts and reports unclassified files with reasons" {
        Initialize-PreviewWorkspace
        New-TestMarkdown -RelativePath "Templates/template.md" -Content "template body with enough words to count and be skipped safely." | Out-Null
        New-TestMarkdown -RelativePath "archive/old-note.md" -Content "archive body with enough words to count and be archived safely." | Out-Null
        New-TestMarkdown -RelativePath "Daily Notes/day-1.md" -Content "daily note body with enough words to count and be treated as captured material." | Out-Null
        New-TestMarkdown -RelativePath "MOCs/index.md" -Content "[[One]] [[Two]] [[Three]] [[Four]] [[Five]] [[Six]] [[Seven]] [[Eight]] [[Nine]] [[Ten]]" | Out-Null
        New-TestMarkdown -RelativePath "working.md" -Content @'
---
status: "active"
title: "Working Note"
project: ["work"]
domain: "research"
shared: "true"
---
This developed note has enough words to classify as active work and should preserve metadata fields in preview output.
'@ | Out-Null
        New-TestMarkdown -RelativePath "inbox.md" -Content "This note has enough words to be short, standalone, and still clear enough for inbox routing by fallback heuristics alone." | Out-Null
        New-TestMarkdown -RelativePath "empty.md" -Content "" | Out-Null

        $result = Invoke-PreviewScript -Arguments @("-SourceVault", $script:SourceRoot)
        $preview = Get-LatestPreviewJson
        $workingEntry = Get-PreviewFileByRelativePath -Preview $preview -RelativePath "working.md"
        $unclassifiedEntry = @($preview.unclassified | Where-Object { $_.relative_path -eq "empty.md" })[0]

        $result.ExitCode | Should Be 0
        $preview.category_counts.skip | Should Be 1
        $preview.category_counts.archive | Should Be 1
        $preview.category_counts.raw | Should Be 1
        $preview.category_counts.wiki | Should Be 1
        $preview.category_counts.working | Should Be 1
        $preview.category_counts.inbox | Should Be 1
        $preview.category_counts.unclassified | Should Be 1
        @($workingEntry.project).Count | Should Be 1
        @($workingEntry.project)[0] | Should Be "work"
        @($workingEntry.domain)[0] | Should Be "research"
        $workingEntry.shared | Should Be "true"
        $unclassifiedEntry.reasons[0] | Should Match "empty file"
    }

    It "applies mapping rules after scanning and records the override reason" {
        Initialize-PreviewWorkspace
        New-TestMarkdown -RelativePath "Daily Notes/planning.md" -Content "daily note body with enough words to be raw before override applies." | Out-Null

        $result = Invoke-PreviewScript -Arguments @("-SourceVault", $script:SourceRoot, "-MappingRules", "Daily Notes=wiki")
        $preview = Get-LatestPreviewJson
        $entry = Get-PreviewFileByRelativePath -Preview $preview -RelativePath "Daily Notes/planning.md"

        $result.ExitCode | Should Be 0
        $entry.proposed_category | Should Be "wiki"
        $entry.classification_reasons[0] | Should Match "mapping rule override"
    }

    It "saves a profile, reloads it on a later run, and lets explicit rules override the profile" {
        Initialize-PreviewWorkspace
        New-TestMarkdown -RelativePath "MOCs/roadmap.md" -Content "map note body with enough words and links [[A]] [[B]] [[C]] [[D]] [[E]] [[F]] [[G]] [[H]]." | Out-Null
        $profilePath = ".ai/import-previews/profile-work.json"

        $firstRun = Invoke-PreviewScript -Arguments @("-SourceVault", $script:SourceRoot, "-MappingRules", "MOCs=wiki", "-SaveProfile", $profilePath)
        $secondRun = Invoke-PreviewScript -Arguments @("-SourceVault", $script:SourceRoot, "-Profile", $profilePath, "-MappingRules", "MOCs=archive")
        $preview = Get-LatestPreviewJson
        $entry = Get-PreviewFileByRelativePath -Preview $preview -RelativePath "MOCs/roadmap.md"

        $firstRun.ExitCode | Should Be 0
        $secondRun.ExitCode | Should Be 0
        (Test-Path (Join-Path $script:WorkRoot $profilePath)) | Should Be $true
        $entry.proposed_category | Should Be "archive"
    }

    It "reports duplicate reasons for exact title, similar filename, and content overlap" {
        Initialize-PreviewWorkspace
        New-KnowledgeMarkdown -RelativePath "knowledge/wiki/existing-title.md" -Content "---`ntitle: `"Same Title`"`n---`nA body that lives in existing knowledge." | Out-Null
        New-KnowledgeMarkdown -RelativePath "knowledge/wiki/project-plan.md" -Content "---`ntitle: `"Plan`"`n---`nExisting body for filename similarity." | Out-Null
        New-KnowledgeMarkdown -RelativePath "knowledge/wiki/overlap.md" -Content "---`ntitle: `"Overlap Existing`"`n---`nalpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma" | Out-Null
        New-TestMarkdown -RelativePath "exact.md" -Content "---`ntitle: `"Same Title`"`n---`nDifferent note body for title match coverage." | Out-Null
        New-TestMarkdown -RelativePath "project-plam.md" -Content "---`ntitle: `"Different Title`"`n---`nDifferent body for similar filename coverage." | Out-Null
        New-TestMarkdown -RelativePath "overlap-source.md" -Content "---`ntitle: `"Overlap Source`"`n---`nalpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau" | Out-Null

        $result = Invoke-PreviewScript -Arguments @("-SourceVault", $script:SourceRoot)
        $preview = Get-LatestPreviewJson
        $duplicateReasons = @($preview.duplicates | ForEach-Object { $_.reasons } | ForEach-Object { $_ })

        $result.ExitCode | Should Be 0
        ($duplicateReasons -join " | ") | Should Match "exact title match"
        ($duplicateReasons -join " | ") | Should Match "similar filename"
        ($duplicateReasons -join " | ") | Should Match "content overlap estimate"
        @($preview.duplicates)[0].resolution_options.Count | Should Be 4
    }
}
