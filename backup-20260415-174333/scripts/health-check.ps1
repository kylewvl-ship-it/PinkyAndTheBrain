param(
    [ValidateSet("all", "metadata", "links", "stale", "sources", "orphans")]
    [string]$Type = "all",
    [switch]$IncludeArchive,
    [switch]$WriteReport
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$KnowledgeRoot = Join-Path $Root "knowledge"
$ReviewsDir = Join-Path $KnowledgeRoot "reviews"
$LogDir = Join-Path $Root "logs"
$Now = Get-Date

function Get-Frontmatter {
    param([string]$Path)
    $lines = Get-Content -Path $Path
    $result = @{}
    if ($lines.Count -lt 3 -or $lines[0] -ne "---") { return $result }

    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq "---") { break }
        if ($lines[$i] -match '^\s*([^:#]+):\s*(.*)\s*$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim().Trim('"')
            if ([string]::IsNullOrWhiteSpace($value) -and ($i + 1) -lt $lines.Count -and $lines[$i + 1] -match '^\s+-\s+') {
                $value = "__list__"
            }
            $result[$key] = $value
        }
    }
    return $result
}

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]]$Findings,
        [string]$FindingType,
        [string]$Path,
        [string]$Severity,
        [string]$Rule,
        [string]$Action
    )
    $Findings.Add([PSCustomObject]@{
        finding_type = $FindingType
        file_path = $Path
        severity = $Severity
        rule_triggered = $Rule
        suggested_repair_action = $Action
    }) | Out-Null
}

function Get-MarkdownFiles {
    $files = Get-ChildItem -Path $KnowledgeRoot -Recurse -Filter "*.md" -File
    if (-not $IncludeArchive) {
        $archivePath = Join-Path $KnowledgeRoot "archive"
        $files = $files | Where-Object { -not $_.FullName.StartsWith($archivePath, [StringComparison]::OrdinalIgnoreCase) }
    }
    return $files
}

function Resolve-WikiLink {
    param(
        [string]$Target,
        [System.IO.FileInfo[]]$Files
    )
    $clean = ($Target -split '\|')[0].Trim()
    $clean = ($clean -split '#')[0].Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { return $true }
    $normalized = $clean -replace '/', [System.IO.Path]::DirectorySeparatorChar
    foreach ($file in $Files) {
        if ($file.BaseName -ieq $normalized -or $file.FullName.EndsWith("$normalized.md", [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-IsScaffoldFile {
    param([System.IO.FileInfo]$File)
    if ($File.Name -in @("README.md", "index.md")) { return $true }
    if ($File.FullName -like "*\knowledge\schemas\*") { return $true }
    return $false
}

try {
    New-Item -ItemType Directory -Path $ReviewsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    $findings = [System.Collections.Generic.List[object]]::new()
    $files = @(Get-MarkdownFiles)
    $requiredWorking = "status", "confidence", "last_updated", "review_trigger", "source_list"
    $requiredWiki = "status", "owner", "confidence", "last_updated", "last_verified", "review_trigger", "source_list"

    if ($Type -in @("all", "metadata", "sources", "stale")) {
        foreach ($file in $files) {
            if (Test-IsScaffoldFile $file) { continue }
            $frontmatter = Get-Frontmatter $file.FullName
            $relative = Resolve-Path -Relative $file.FullName
            $required = @()
            if ($file.FullName -like "*\knowledge\working\*") { $required = $requiredWorking }
            if ($file.FullName -like "*\knowledge\wiki\*") { $required = $requiredWiki }

            if ($required.Count -gt 0 -and $frontmatter.Count -eq 0) {
                Add-Finding $findings "Missing Metadata" $relative "high" "required frontmatter absent" "Add YAML frontmatter using the matching template."
                continue
            }

            foreach ($field in $required) {
                if (-not $frontmatter.ContainsKey($field) -or [string]::IsNullOrWhiteSpace([string]$frontmatter[$field])) {
                    Add-Finding $findings "Missing Metadata" $relative "high" "missing required field: $field" "Add '$field' to YAML frontmatter."
                }
            }

            if ($Type -in @("all", "sources") -and $file.FullName -like "*\knowledge\wiki\*") {
                $content = Get-Content -Raw -Path $file.FullName
                $hasSources = ($frontmatter.ContainsKey("source_list") -and $frontmatter["source_list"] -notin @("", "[]")) -or $content -match '(?m)^## Sources'
                if (-not $hasSources) {
                    Add-Finding $findings "Unsupported Claims" $relative "medium" "wiki page lacks source_list or Sources section" "Add source_list frontmatter and concrete source links."
                }
            }

            if ($Type -in @("all", "stale") -and $frontmatter.ContainsKey("review_trigger") -and $frontmatter["review_trigger"]) {
                [DateTime]$reviewDate = [DateTime]::MinValue
                if ([DateTime]::TryParse($frontmatter["review_trigger"], [ref]$reviewDate) -and $reviewDate -lt $Now.Date) {
                    Add-Finding $findings "Stale Review Dates" $relative "medium" "review_trigger is overdue" "Review the note and update review_trigger."
                }
            }
        }
    }

    if ($Type -in @("all", "links")) {
        foreach ($file in $files) {
            if (Test-IsScaffoldFile $file) { continue }
            $content = Get-Content -Raw -Path $file.FullName
            $matches = [regex]::Matches($content, '\[\[([^\]]+)\]\]')
            foreach ($match in $matches) {
                $target = $match.Groups[1].Value
                if (-not (Resolve-WikiLink $target $files)) {
                    Add-Finding $findings "Broken Links" (Resolve-Path -Relative $file.FullName) "high" "missing wiki link target: $target" "Create the target note or replace the link with a valid path."
                }
            }
        }
    }

    if ($Type -in @("all", "orphans")) {
        $linkTargets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in $files) {
            if (Test-IsScaffoldFile $file) { continue }
            $content = Get-Content -Raw -Path $file.FullName
            [regex]::Matches($content, '\[\[([^\]]+)\]\]') | ForEach-Object {
                $target = ($_.Groups[1].Value -split '\|')[0] -split '#'
                if ($target[0]) { $linkTargets.Add($target[0].Trim()) | Out-Null }
            }
        }
        foreach ($file in $files) {
            if ((Test-IsScaffoldFile $file) -or -not $file.FullName.Contains("\knowledge\wiki\")) { continue }
            if (-not $linkTargets.Contains($file.BaseName)) {
                Add-Finding $findings "Orphaned Pages" (Resolve-Path -Relative $file.FullName) "low" "no incoming wiki links found" "Link this note from an index or related page, or archive it if unused."
            }
        }
    }

    $order = "Missing Metadata", "Broken Links", "Stale Review Dates", "Duplicate Titles", "Unsupported Claims", "Orphaned Pages"
    $lines = @("# PinkyAndTheBrain Health Report", "", "Generated: $(Get-Date -Format o)", "", "Scope: $Type", "Include archive: $IncludeArchive", "")

    if ($findings.Count -eq 0) {
        $lines += "No findings."
    }
    else {
        $lines += "Found $($findings.Count) findings."
        foreach ($group in $order) {
            $items = @($findings | Where-Object { $_.finding_type -eq $group })
            if ($items.Count -eq 0) { continue }
            $lines += ""
            $lines += "## $group"
            foreach ($item in $items) {
                $lines += "- [$($item.severity)] $($item.file_path) - $($item.rule_triggered). Repair: $($item.suggested_repair_action)"
            }
        }
    }

    $lines | ForEach-Object { Write-Host $_ }

    if ($WriteReport) {
        $reportPath = Join-Path $ReviewsDir "health-report-$(Get-Date -Format yyyy-MM-dd-HHmmss).md"
        Set-Content -Path $reportPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
        Write-Host ""
        Write-Host "Report written: $reportPath" -ForegroundColor Green
    }

    Add-Content -Path (Join-Path $LogDir "health-check.log") -Value "[$(Get-Date -Format o)] type=$Type findings=$($findings.Count)"
    if ($findings.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Error "Health check failed: $($_.Exception.Message)"
    exit 1
}
