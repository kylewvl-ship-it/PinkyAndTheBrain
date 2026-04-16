# Pester tests for capture.ps1

Describe "capture.ps1 - manual type routes to knowledge/inbox" {
    BeforeEach {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:Script = Join-Path $script:Root "scripts/capture.ps1"
        $script:InboxDir = Join-Path $script:Root "knowledge/inbox"
        $script:RawDir = Join-Path $script:Root "knowledge/raw"
        New-Item -ItemType Directory -Path $script:InboxDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:RawDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root "logs") -Force | Out-Null
    }

    It "creates file in inbox when Type is manual" {
        $before = @(Get-ChildItem $script:InboxDir -Filter "*.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        & $script:Script -Title "Test Manual Note" -Content "Some content" -Type manual
        $after = @(Get-ChildItem $script:InboxDir -Filter "*.md" | Select-Object -ExpandProperty FullName)
        $new = @($after | Where-Object { $_ -notin $before })
        $new.Count | Should Be 1
        $new[0] -like "*knowledge*inbox*" | Should Be $true
        Remove-Item $new[0] -Force
    }
}

Describe "capture.ps1 - conversation type routes to knowledge/raw" {
    BeforeEach {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:Script = Join-Path $script:Root "scripts/capture.ps1"
        $script:RawDir = Join-Path $script:Root "knowledge/raw"
        New-Item -ItemType Directory -Path $script:RawDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root "logs") -Force | Out-Null
    }

    It "creates file in raw when Type is conversation" {
        $before = @(Get-ChildItem $script:RawDir -Filter "*.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        & $script:Script -Title "Test Conversation" -Content "Dialog content" -Type conversation -Service "claude"
        $after = @(Get-ChildItem $script:RawDir -Filter "*.md" | Select-Object -ExpandProperty FullName)
        $new = @($after | Where-Object { $_ -notin $before })
        $new.Count | Should Be 1
        $new[0] -like "*knowledge*raw*" | Should Be $true
        Remove-Item $new[0] -Force
    }
}

Describe "capture.ps1 - conversation schema includes required fields" {
    BeforeEach {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:Script = Join-Path $script:Root "scripts/capture.ps1"
        $script:RawDir = Join-Path $script:Root "knowledge/raw"
        New-Item -ItemType Directory -Path $script:RawDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root "logs") -Force | Out-Null
    }

    It "conversation file contains ai_derived and promotion_blocked" {
        $before = @(Get-ChildItem $script:RawDir -Filter "*.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        & $script:Script -Title "Schema Check" -Content "content" -Type conversation -Service "chatgpt"
        $after = @(Get-ChildItem $script:RawDir -Filter "*.md" | Select-Object -ExpandProperty FullName)
        $new = @($after | Where-Object { $_ -notin $before })
        $content = Get-Content $new[0] -Raw
        $content -match "ai_derived: true" | Should Be $true
        $content -match "promotion_blocked: true" | Should Be $true
        Remove-Item $new[0] -Force
    }
}

Describe "capture.ps1 - conversation type with -File parameter" {
    BeforeEach {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        $script:Script = Join-Path $script:Root "scripts/capture.ps1"
        $script:RawDir = Join-Path $script:Root "knowledge/raw"
        New-Item -ItemType Directory -Path $script:RawDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:Root "logs") -Force | Out-Null
    }

    It "reads content from -File when provided" {
        $tmpFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmpFile -Value "file content here" -Encoding UTF8
        try {
            $before = @(Get-ChildItem $script:RawDir -Filter "*.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
            & $script:Script -Title "File Import Test" -Type conversation -Service "claude" -File $tmpFile
            $after = @(Get-ChildItem $script:RawDir -Filter "*.md" | Select-Object -ExpandProperty FullName)
            $new = @($after | Where-Object { $_ -notin $before })
            $new.Count | Should Be 1
            (Get-Content $new[0] -Raw) -match "file content here" | Should Be $true
            Remove-Item $new[0] -Force
        } finally {
            Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "capture.ps1 - Test-TemplateValid function" {
    BeforeEach {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        # Dot-source to get helper functions; suppress output from the script execution
        . (Join-Path $script:Root "scripts/capture.ps1") -Title "dummy" -Content "x" -Type manual *>$null
    }

    It "returns false and emits error when required fields are missing" {
        $fields = @{ captured_date = "2026-01-01"; source_type = "manual" }
        $result = Test-TemplateValid -Fields $fields -RequiredKeys @("captured_date", "source_type", "review_status", "disposition")
        $result | Should Be $false
    }
}
