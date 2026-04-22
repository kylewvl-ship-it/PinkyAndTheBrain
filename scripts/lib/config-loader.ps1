# Config loader for PinkyAndTheBrain
# Provides YAML parsing and configuration management functions.

function Convert-YamlValue {
    param([string]$Value)
    if ($Value -match '^"(.*)"$' -or $Value -match "^'(.*)'$") { return $Matches[1] }
    if ($Value -eq 'true') { return $true }
    if ($Value -eq 'false') { return $false }
    if ($Value -eq 'null' -or $Value -eq '~' -or $Value -eq '') { return $null }
    if ($Value -match '^\d+$') { return [int]$Value }
    if ($Value -match '^\d+\.\d+$') { return [double]$Value }
    return $Value
}

function Read-YamlConfig {
    param([string]$Path)

    if (!(Test-Path $Path)) { return $null }

    $result = @{}
    $stack = New-Object System.Collections.ArrayList
    [void]$stack.Add(@{ Indent = -1; Value = $result })
    $lineNumber = 0

    foreach ($rawLine in (Get-Content $Path -Encoding UTF8)) {
        $lineNumber++
        if ($rawLine -match '^\s*$' -or $rawLine -match '^\s*#') { continue }
        if ($rawLine -match "`t") { throw "YAML parse error at line ${lineNumber}: tabs are not supported; use spaces" }

        $indent = ($rawLine -replace '^(\s*).*', '$1').Length
        if (($indent % 2) -ne 0) { throw "YAML parse error at line ${lineNumber}: indentation must use multiples of two spaces" }

        $content = $rawLine.Trim()

        while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Indent -ge $indent) {
            $stack.RemoveAt($stack.Count - 1)
        }

        if ($stack.Count -eq 0 -or $stack[$stack.Count - 1].Value -isnot [hashtable]) {
            throw "YAML parse error at line ${lineNumber}: invalid nesting"
        }

        if ($content -notmatch '^([\w-]+):\s*(.*)$') {
            throw "YAML parse error at line ${lineNumber}: expected 'key: value'"
        }

        $parent = $stack[$stack.Count - 1].Value
        $key = $Matches[1]
        $value = $Matches[2].Trim()

        if ($value -eq '') {
            $parent[$key] = @{}
            [void]$stack.Add(@{ Indent = $indent; Value = $parent[$key] })
        }
        else {
            $parent[$key] = Convert-YamlValue $value
        }
    }

    return $result
}

function Get-DefaultConfig {
    return @{
        project = "PinkyAndTheBrain"
        version = "0.2.0"
        system = @{
            vault_root    = "./knowledge"
            script_root   = "./scripts"
            template_root = "./templates"
        }
        folders = @{
            inbox    = "inbox"
            raw      = "raw"
            working  = "working"
            wiki     = "wiki"
            archive  = "archive"
            schemas  = "schemas"
            reviews  = "reviews"
            handoffs = ".ai/handoffs"
            logs     = "logs"
        }
        file_naming = @{
            inbox_pattern        = "YYYY-MM-DD-HHMMSS-{title}"
            conversation_pattern = "YYYY-MM-DD-HHMMSS-conversation-{service}"
            working_pattern      = "{title}"
            wiki_pattern         = "{title}"
        }
        review_cadence = @{
            inbox_days   = 7
            working_days = 30
            wiki_days    = 90
        }
        health_checks = @{
            stale_threshold_months = 6
            min_content_length     = 100
            similarity_threshold   = 3
        }
        ai_handoff = @{
            max_context_tokens      = 3000
            max_wiki_tokens_per_page = 500
            exclude_private         = $true
        }
        projects = @{
            default_project  = "general"
            create_subfolders = $true
            overrides = @{}
        }
        search = @{
            max_results      = 20
            include_archived = $false
            case_sensitive   = $false
        }
        privacy = @{
            private_excluded_from_handoffs = $true
            do_not_promote_blocks_wiki     = $true
        }
        limits = @{
            max_content_size = 10485760
        }
    }
}

function Merge-Config {
    param(
        [hashtable]$Defaults,
        [hashtable]$Overrides
    )

    $merged = @{}
    foreach ($key in $Defaults.Keys) {
        if ($Overrides.ContainsKey($key) -and $Overrides[$key] -is [hashtable] -and $Defaults[$key] -is [hashtable]) {
            $merged[$key] = Merge-Config -Defaults $Defaults[$key] -Overrides $Overrides[$key]
        }
        elseif ($Overrides.ContainsKey($key)) {
            $merged[$key] = $Overrides[$key]
        }
        else {
            $merged[$key] = $Defaults[$key]
        }
    }
    foreach ($key in $Overrides.Keys) {
        if (!$merged.ContainsKey($key)) { $merged[$key] = $Overrides[$key] }
    }
    return $merged
}

function Initialize-Config {
    param([string]$ConfigPath = "config/pinky-config.yaml")

    $dir = Split-Path $ConfigPath -Parent
    if ($dir -and !(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $defaultPath = Join-Path (Split-Path $ConfigPath -Parent) "default-config.yaml"
    if (Test-Path $defaultPath) {
        Copy-Item $defaultPath $ConfigPath -Force
    }
    else {
        $content = Get-Content "$PSScriptRoot/../../config/default-config.yaml" -Raw -ErrorAction SilentlyContinue
        if ($content) { Set-Content $ConfigPath $content -Encoding UTF8 }
    }

    Write-Host "[INFO] Created default configuration at: $ConfigPath" -ForegroundColor Green
}

function Set-ConfigValue {
    param(
        [hashtable]$Config,
        [string]$Section,
        [string]$Key,
        $Value
    )

    if (!$Config.ContainsKey($Section) -or $Config[$Section] -isnot [hashtable]) {
        $Config[$Section] = @{}
    }
    $Config[$Section][$Key] = $Value
}

function Apply-EnvironmentOverrides {
    param([hashtable]$Config)

    $overrides = @(
        @{ Env = 'PINKY_VAULT_ROOT'; Section = 'system'; Key = 'vault_root' }
        @{ Env = 'PINKY_SCRIPT_ROOT'; Section = 'system'; Key = 'script_root' }
        @{ Env = 'PINKY_TEMPLATE_ROOT'; Section = 'system'; Key = 'template_root' }
        @{ Env = 'PINKY_SEARCH_MAX_RESULTS'; Section = 'search'; Key = 'max_results'; Type = 'integer' }
        @{ Env = 'PINKY_SEARCH_INCLUDE_ARCHIVED'; Section = 'search'; Key = 'include_archived'; Type = 'boolean' }
        @{ Env = 'PINKY_SEARCH_CASE_SENSITIVE'; Section = 'search'; Key = 'case_sensitive'; Type = 'boolean' }
    )

    foreach ($override in $overrides) {
        $raw = [Environment]::GetEnvironmentVariable($override.Env)
        if ([string]::IsNullOrEmpty($raw)) { continue }

        $value = switch ($override.Type) {
            'integer' { [int]$raw }
            'boolean' { [System.Convert]::ToBoolean($raw) }
            default { $raw }
        }
        Set-ConfigValue -Config $Config -Section $override.Section -Key $override.Key -Value $value
    }

    return $Config
}

function Resolve-ProjectConfig {
    param(
        [hashtable]$Config,
        [string]$Project
    )

    if ([string]::IsNullOrWhiteSpace($Project)) { return $Config }
    if (!$Config.projects -or !$Config.projects.overrides -or $Config.projects.overrides -isnot [hashtable]) { return $Config }
    if (!$Config.projects.overrides.ContainsKey($Project)) { return $Config }

    return Merge-Config -Defaults $Config -Overrides $Config.projects.overrides[$Project]
}

function Load-Config {
    param(
        [string]$ConfigPath = "config/pinky-config.yaml",
        [string]$Project = ""
    )

    $defaults = Get-DefaultConfig

    if (!(Test-Path $ConfigPath)) {
        Write-Host "[WARN] Config not found ($ConfigPath). Creating default and continuing." -ForegroundColor Yellow
        Initialize-Config -ConfigPath $ConfigPath
        return Resolve-ProjectConfig -Config (Apply-EnvironmentOverrides -Config $defaults) -Project $Project
    }

    try {
        $parsed = Read-YamlConfig -Path $ConfigPath
        if ($null -eq $parsed) {
            Write-Host "[WARN] Config file is empty. Using defaults." -ForegroundColor Yellow
            return Resolve-ProjectConfig -Config (Apply-EnvironmentOverrides -Config $defaults) -Project $Project
        }
        $config = Merge-Config -Defaults $defaults -Overrides $parsed
        $config = Apply-EnvironmentOverrides -Config $config
        return Resolve-ProjectConfig -Config $config -Project $Project
    }
    catch {
        Write-Host "[ERROR] Failed to parse $ConfigPath`: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[WARN] Falling back to defaults. Run .\scripts\validate-config.ps1 for details." -ForegroundColor Yellow
        return Resolve-ProjectConfig -Config (Apply-EnvironmentOverrides -Config $defaults) -Project $Project
    }
}

function Test-ConfigPaths {
    param([hashtable]$Config)

    $errors = @()
    $vaultRoot = $Config.system.vault_root

    $pathsToCheck = @($vaultRoot, $Config.system.script_root, $Config.system.template_root)
    foreach ($p in $pathsToCheck) {
        if (!(Test-Path $p)) {
            $errors += "Path does not exist: $p"
        }
    }

    return $errors
}

function Test-ConfigValues {
    param([hashtable]$Config)

    $errors = @()

    $intChecks = @(
        @{ Section = 'review_cadence'; Key = 'inbox_days';   Min = 1;  Max = 365 }
        @{ Section = 'review_cadence'; Key = 'working_days'; Min = 1;  Max = 365 }
        @{ Section = 'review_cadence'; Key = 'wiki_days';    Min = 1;  Max = 730 }
        @{ Section = 'health_checks';  Key = 'stale_threshold_months'; Min = 1; Max = 36 }
        @{ Section = 'health_checks';  Key = 'min_content_length';     Min = 0; Max = 10000 }
        @{ Section = 'health_checks';  Key = 'similarity_threshold';   Min = 1; Max = 20 }
        @{ Section = 'ai_handoff';     Key = 'max_context_tokens';     Min = 100; Max = 100000 }
        @{ Section = 'ai_handoff';     Key = 'max_wiki_tokens_per_page'; Min = 100; Max = 10000 }
        @{ Section = 'search';         Key = 'max_results'; Min = 1; Max = 1000 }
    )

    foreach ($chk in $intChecks) {
        $val = $Config[$chk.Section][$chk.Key]
        if ($val -isnot [int]) {
            $errors += "$($chk.Section).$($chk.Key) must be an integer (got: $val)"
        }
        elseif ($val -lt $chk.Min -or $val -gt $chk.Max) {
            $errors += "$($chk.Section).$($chk.Key) must be between $($chk.Min) and $($chk.Max) (got: $val)"
        }
    }

    $patternChecks = @(
        @{ Section = 'file_naming'; Key = 'inbox_pattern';        MustContain = '{title}' }
        @{ Section = 'file_naming'; Key = 'conversation_pattern'; MustContain = '{service}' }
    )

    foreach ($chk in $patternChecks) {
        $val = $Config[$chk.Section][$chk.Key]
        if ($val -notlike "*$($chk.MustContain)*") {
            $errors += "$($chk.Section).$($chk.Key) must contain placeholder '$($chk.MustContain)' (got: $val)"
        }
    }

    return $errors
}
