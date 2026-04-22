# Pester tests for config-loader.ps1

$script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:LoaderPath = Join-Path $script:Root "scripts/lib/config-loader.ps1"
. $script:LoaderPath

Describe "Convert-YamlValue - type coercion" {
    It "converts 'true' to boolean true" {
        $val = Convert-YamlValue "true"
        $val | Should Be $true
        ($val -is [bool]) | Should Be $true
    }

    It "converts 'false' to boolean false" {
        $val = Convert-YamlValue "false"
        $val | Should Be $false
        ($val -is [bool]) | Should Be $true
    }

    It "converts integer strings to int" {
        $val = Convert-YamlValue "42"
        $val | Should Be 42
        ($val -is [int]) | Should Be $true
    }

    It "strips double quotes from strings" {
        Convert-YamlValue '"hello world"' | Should Be "hello world"
    }

    It "strips single quotes from strings" {
        Convert-YamlValue "'hello world'" | Should Be "hello world"
    }

    It "returns plain strings unchanged" {
        Convert-YamlValue "./knowledge" | Should Be "./knowledge"
    }

    It "returns null for 'null'" {
        $val = Convert-YamlValue "null"
        $val | Should BeNullOrEmpty
    }
}

Describe "Read-YamlConfig - YAML parsing" {
    BeforeEach {
        $script:TempDir = $TestDrive
    }

    It "returns null for non-existent file" {
        $result = Read-YamlConfig -Path (Join-Path $script:TempDir "nonexistent.yaml")
        $result | Should BeNullOrEmpty
    }

    It "parses top-level scalar values" {
        $file = Join-Path $script:TempDir "scalar.yaml"
        Set-Content $file "project: MyProject`nversion: 1.0"
        $result = Read-YamlConfig -Path $file
        $result.project | Should Be "MyProject"
    }

    It "parses nested sections" {
        $file = Join-Path $script:TempDir "nested.yaml"
        Set-Content $file "system:`n  vault_root: ./knowledge`n  script_root: ./scripts"
        $result = Read-YamlConfig -Path $file
        ($result.system -ne $null) | Should Be $true
        $result.system.vault_root | Should Be "./knowledge"
        $result.system.script_root | Should Be "./scripts"
    }

    It "parses boolean values in sections" {
        $file = Join-Path $script:TempDir "bools.yaml"
        Set-Content $file "search:`n  include_archived: false`n  case_sensitive: true"
        $result = Read-YamlConfig -Path $file
        $result.search.include_archived | Should Be $false
        $result.search.case_sensitive | Should Be $true
    }

    It "parses integer values in sections" {
        $file = Join-Path $script:TempDir "ints.yaml"
        Set-Content $file "review_cadence:`n  inbox_days: 7`n  working_days: 30"
        $result = Read-YamlConfig -Path $file
        $result.review_cadence.inbox_days | Should Be 7
        $result.review_cadence.working_days | Should Be 30
    }

    It "ignores comment lines" {
        $file = Join-Path $script:TempDir "comments.yaml"
        Set-Content $file "# This is a comment`nproject: Test`n# another comment"
        $result = Read-YamlConfig -Path $file
        $result.project | Should Be "Test"
    }

    It "parses the real pinky-config.yaml without error" {
        $realConfig = Join-Path $script:Root "config/pinky-config.yaml"
        $result = Read-YamlConfig -Path $realConfig
        ($result -ne $null) | Should Be $true
        ($result.system -ne $null) | Should Be $true
        ($result.folders -ne $null) | Should Be $true
    }

    It "parses nested project overrides" {
        $file = Join-Path $script:TempDir "project-overrides.yaml"
        Set-Content $file "projects:`n  overrides:`n    alpha:`n      search:`n        max_results: 42"
        $result = Read-YamlConfig -Path $file
        $result.projects.overrides.alpha.search.max_results | Should Be 42
    }

    It "reports invalid YAML with a line number" {
        $file = Join-Path $script:TempDir "invalid.yaml"
        Set-Content $file "system:`n   vault_root: ./bad"
        { Read-YamlConfig -Path $file } | Should Throw "line 2"
    }

    It "strips UTF-8 BOM from first line" {
        $file = Join-Path $script:TempDir "bom.yaml"
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        $body = [System.Text.Encoding]::UTF8.GetBytes("project: BomTest")
        [System.IO.File]::WriteAllBytes($file, $bom + $body)
        $result = Read-YamlConfig -Path $file
        $result.project | Should Be "BomTest"
    }

    It "skips YAML list items and continues parsing" {
        $file = Join-Path $script:TempDir "list.yaml"
        Set-Content $file "project: Test`n- item one`n- item two"
        $result = Read-YamlConfig -Path $file
        $result.project | Should Be "Test"
    }
}

Describe "Get-DefaultConfig - default values" {
    It "returns a hashtable with all required sections" {
        $defaults = Get-DefaultConfig
        ($defaults -ne $null) | Should Be $true
        ($defaults.system -ne $null) | Should Be $true
        ($defaults.folders -ne $null) | Should Be $true
        ($defaults.file_naming -ne $null) | Should Be $true
        ($defaults.review_cadence -ne $null) | Should Be $true
        ($defaults.health_checks -ne $null) | Should Be $true
        ($defaults.ai_handoff -ne $null) | Should Be $true
        ($defaults.projects -ne $null) | Should Be $true
        ($defaults.search -ne $null) | Should Be $true
    }

    It "has correct default vault_root" {
        (Get-DefaultConfig).system.vault_root | Should Be "./knowledge"
    }

    It "has correct default review cadence" {
        $defaults = Get-DefaultConfig
        $defaults.review_cadence.inbox_days | Should Be 7
        $defaults.review_cadence.working_days | Should Be 30
        $defaults.review_cadence.wiki_days | Should Be 90
    }

    It "has correct boolean defaults" {
        $defaults = Get-DefaultConfig
        $defaults.search.include_archived | Should Be $false
        $defaults.ai_handoff.exclude_private | Should Be $true
    }
}

Describe "Merge-Config - merging logic" {
    It "fills missing keys from defaults" {
        $defaults = @{ a = @{ x = 1; y = 2 }; b = "hello" }
        $overrides = @{ a = @{ x = 99 } }
        $merged = Merge-Config -Defaults $defaults -Overrides $overrides
        $merged.a.x | Should Be 99
        $merged.a.y | Should Be 2
        $merged.b | Should Be "hello"
    }

    It "override wins over default for scalar values" {
        $defaults = @{ section = @{ key = "default" } }
        $overrides = @{ section = @{ key = "custom" } }
        $merged = Merge-Config -Defaults $defaults -Overrides $overrides
        $merged.section.key | Should Be "custom"
    }

    It "includes extra keys from overrides not in defaults" {
        $defaults = @{ a = 1 }
        $overrides = @{ a = 1; b = 2 }
        $merged = Merge-Config -Defaults $defaults -Overrides $overrides
        $merged.b | Should Be 2
    }

    It "keeps hashtable default when override provides a scalar" {
        $defaults = @{ section = @{ key = "value" } }
        $overrides = @{ section = "scalar" }
        $merged = Merge-Config -Defaults $defaults -Overrides $overrides
        ($merged.section -is [hashtable]) | Should Be $true
        $merged.section.key | Should Be "value"
    }
}

Describe "Load-Config - config loading" {
    It "returns defaults when config file does not exist" {
        $fakePath = Join-Path $TestDrive "no-dir/nonexistent.yaml"
        $config = Load-Config -ConfigPath $fakePath
        ($config -ne $null) | Should Be $true
        $config.system.vault_root | Should Be "./knowledge"
    }

    It "loads and merges values from a valid config file" {
        $file = Join-Path $TestDrive "custom.yaml"
        Set-Content $file "system:`n  vault_root: ./my-vault`n"
        $config = Load-Config -ConfigPath $file
        $config.system.vault_root | Should Be "./my-vault"
        $config.folders.inbox | Should Be "inbox"
    }

    It "applies environment variable overrides" {
        $oldValue = [Environment]::GetEnvironmentVariable("PINKY_VAULT_ROOT")
        try {
            [Environment]::SetEnvironmentVariable("PINKY_VAULT_ROOT", "./env-vault")
            $config = Load-Config -ConfigPath (Join-Path $script:Root "config/pinky-config.yaml")
            $config.system.vault_root | Should Be "./env-vault"
        }
        finally {
            [Environment]::SetEnvironmentVariable("PINKY_VAULT_ROOT", $oldValue)
        }
    }

    It "applies boolean env var override with non-standard true value" {
        $old = [Environment]::GetEnvironmentVariable("PINKY_SEARCH_INCLUDE_ARCHIVED")
        try {
            [Environment]::SetEnvironmentVariable("PINKY_SEARCH_INCLUDE_ARCHIVED", "yes")
            $config = Load-Config -ConfigPath (Join-Path $script:Root "config/pinky-config.yaml")
            $config.search.include_archived | Should Be $true
        }
        finally {
            [Environment]::SetEnvironmentVariable("PINKY_SEARCH_INCLUDE_ARCHIVED", $old)
        }
    }

    It "applies project-specific overrides" {
        $file = Join-Path $TestDrive "project.yaml"
        Set-Content $file "projects:`n  default_project: general`n  create_subfolders: true`n  overrides:`n    alpha:`n      search:`n        max_results: 42"
        $config = Load-Config -ConfigPath $file -Project "alpha"
        $config.search.max_results | Should Be 42
    }
}

Describe "Test-ConfigValues - value validation" {
    It "passes for default config with no errors" {
        $errors = Test-ConfigValues -Config (Get-DefaultConfig)
        $errors.Count | Should Be 0
    }

    It "reports error when inbox_days is out of range" {
        $config = Get-DefaultConfig
        $config.review_cadence.inbox_days = 999
        $errors = Test-ConfigValues -Config $config
        $match = @($errors | Where-Object { $_ -like "*inbox_days*" })
        ($match.Count -gt 0) | Should Be $true
    }

    It "reports error when inbox_pattern is missing {title}" {
        $config = Get-DefaultConfig
        $config.file_naming.inbox_pattern = "YYYY-MM-DD"
        $errors = Test-ConfigValues -Config $config
        $match = @($errors | Where-Object { $_ -like "*inbox_pattern*" })
        ($match.Count -gt 0) | Should Be $true
    }

    It "reports error when conversation_pattern is missing {service}" {
        $config = Get-DefaultConfig
        $config.file_naming.conversation_pattern = "YYYY-MM-DD-{title}"
        $errors = Test-ConfigValues -Config $config
        $match = @($errors | Where-Object { $_ -like "*conversation_pattern*" })
        ($match.Count -gt 0) | Should Be $true
    }

    It "reports error when working_pattern is missing {title}" {
        $config = Get-DefaultConfig
        $config.file_naming.working_pattern = "no-placeholder"
        $errors = Test-ConfigValues -Config $config
        $match = @($errors | Where-Object { $_ -like "*working_pattern*" })
        ($match.Count -gt 0) | Should Be $true
    }

    It "reports error when wiki_pattern is missing {title}" {
        $config = Get-DefaultConfig
        $config.file_naming.wiki_pattern = "no-placeholder"
        $errors = Test-ConfigValues -Config $config
        $match = @($errors | Where-Object { $_ -like "*wiki_pattern*" })
        ($match.Count -gt 0) | Should Be $true
    }

    It "reports error when required string is empty" {
        $config = Get-DefaultConfig
        $config.system.vault_root = ""
        $errors = Test-ConfigValues -Config $config
        $match = @($errors | Where-Object { $_ -like "*vault_root*" })
        ($match.Count -gt 0) | Should Be $true
    }
}
