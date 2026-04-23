function Get-RelativeRepoPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    if ($resolvedPath.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath.Replace($RepoRoot, '').TrimStart('/\').Replace('\', '/')
    }

    return ""
}

function Get-FrontmatterData {
    param([string]$Content)

    $normalized = $Content -replace "`r`n", "`n"
    if ($normalized -notmatch '(?s)^---\n(.*?)\n---\n?(.*)$') {
        return $null
    }
    return @{
        Frontmatter = $matches[1]
        Body = $matches[2]
    }
}

function Get-FrontmatterValue {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    $pattern = '(?m)^' + [regex]::Escape($Key) + '\s*:\s*["'']?(.*?)["'']?\s*$'
    $match = [regex]::Match($Frontmatter, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return ""
}

function Test-FrontmatterFieldPresent {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    return [regex]::IsMatch($Frontmatter, '(?m)^' + [regex]::Escape($Key) + '\s*:')
}

function Set-FrontmatterField {
    param(
        [string]$Frontmatter,
        [string]$Key,
        [string]$Value
    )

    $lines = $Frontmatter -split "`n"
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^' + [regex]::Escape($Key) + '\s*:') {
            $lines[$i] = ('{0}: "{1}"' -f $Key, $Value)
            $updated = $true
            break
        }
    }

    if (!$updated) {
        $lines += ('{0}: "{1}"' -f $Key, $Value)
    }

    return ($lines -join "`n")
}

function Get-SourceList {
    param([string]$Frontmatter)

    $pattern = '(?m)^source_list\s*:\s*\[(.*?)\]\s*$'
    $match = [regex]::Match($Frontmatter, $pattern)
    if (-not $match.Success) {
        return @()
    }
    $inner = $match.Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($inner)) {
        return @()
    }
    return ($inner -split ',') | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ -ne '' }
}

function Set-SourceList {
    param(
        [string]$Frontmatter,
        [string[]]$Sources
    )

    $encoded = ($Sources | ForEach-Object { '"' + $_ + '"' }) -join ', '
    $serialized = "source_list: [$encoded]"
    $lines = $Frontmatter -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^source_list\s*:') {
            $lines[$i] = $serialized
            return ($lines -join "`n")
        }
    }
    return $Frontmatter + "`n$serialized"
}

function Build-Document {
    param(
        [string]$Frontmatter,
        [string]$Body
    )

    $normalizedFrontmatter = ($Frontmatter.Trim() -replace "`n", "`r`n")
    $normalizedBody = (($Body.TrimStart("`n").TrimEnd("`r", "`n")) -replace "`n", "`r`n") + "`r`n"
    return ("---`r`n{0}`r`n---`r`n{1}" -f $normalizedFrontmatter, $normalizedBody)
}
