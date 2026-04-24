# Story 4.1: AI Conversation Import

**Story ID:** 4.1
**Epic:** 4 - Advanced Capture & Sources
**Status:** done
**Created:** 2026-04-24

---

## User Story

As Reno,
I want to import AI conversation logs into structured raw sessions,
So that valuable AI interactions are preserved with proper context and metadata.

---

## Acceptance Criteria

### Scenario: Import AI conversation from file

- **Given** I have a conversation file (plain text, markdown, or JSON)
- **When** I run `.\scripts\import-conversation.ps1 -File "conversation.txt" -Service "claude"`
- **Then** the conversation is saved to `knowledge/raw/` with filename format `YYYY-MM-DD-HH-MM-conversation-claude.md`
- **And** the import preserves the exact conversation text without modification
- **And** the frontmatter includes: `conversation_date`, `ai_service`, `import_date`, `review_status: "pending"`

### Scenario: Import AI conversation via pasted text

- **Given** I want to import a conversation by pasting text
- **When** I run `.\scripts\import-conversation.ps1 -Service "chatgpt"` and provide text via clipboard or stdin
- **Then** the pasted content is written to `knowledge/raw/` with the same filename format and frontmatter
- **And** `import_method: "paste"` is recorded in frontmatter

### Scenario: Preserve mixed content (code blocks, URLs, turns)

- **Given** I import a conversation containing code blocks, URLs, and user/assistant turns
- **When** the import is processed
- **Then** fenced code blocks are preserved with their language identifiers
- **And** URLs are preserved as-is (not converted)
- **And** the conversation structure (user/assistant turns) is maintained with `---` separators between turns where turn boundaries are detected
- **And** `**User:**` / `**Assistant:**` prefixes are added to turns when the source format makes roles discernible

### Scenario: Import method recorded

- **Given** I import conversations from different entry points (file, paste, clipboard)
- **When** each conversation is imported
- **Then** `import_method` is recorded as `"file"`, `"paste"`, or `"clipboard"` in frontmatter
- **And** `source_format` is recorded as `"json"`, `"markdown"`, or `"text"` based on detected format

### Scenario: Handle JSON conversation format

- **Given** I import a JSON conversation file (e.g., ChatGPT export format)
- **When** the import processes the JSON
- **Then** the script detects the `messages` array structure and converts it to markdown turns
- **And** each message role and content is rendered as a turn block
- **And** if the JSON structure is unrecognized, the raw JSON is preserved in a fenced code block with a note

### Scenario: Malformed import saved with error notes rather than rejected

- **Given** I attempt to import a file with corrupted content or unreadable encoding
- **When** the import processes the file
- **Then** the import is saved to `knowledge/raw/` with whatever content could be read
- **And** a `## Import Errors` section at the end of the body documents what went wrong
- **And** frontmatter includes `import_errors: true`
- **And** the script does NOT exit non-zero for malformed content — only for system errors (missing config, missing raw folder)

### Scenario: Source conversation remains unchanged

- **Given** I have imported a conversation file
- **When** I later review the raw file
- **Then** the original conversation file on disk is unchanged (import is a read+copy, not a move)
- **And** any content promoted downstream must reference back to the raw conversation filename
- **And** the raw file itself is NOT auto-promoted

### Error Scenario: Missing raw folder

- **Given** `knowledge/raw/` does not exist
- **When** I attempt to import
- **Then** the script exits with code 2 and tells the user to run `.\scripts\setup-system.ps1`

### Error Scenario: File not found

- **Given** I specify `-File` but the path does not exist
- **When** the script validates input
- **Then** it exits code 1 with a clear message identifying the missing file path

---

## Technical Requirements

### What already exists (do NOT reimplement)

- `scripts/capture.ps1` — basic `-Type conversation` path already routes to `knowledge/raw/`. **This story does NOT modify `capture.ps1`.** `import-conversation.ps1` is the full-featured import path.
- `scripts/lib/common.ps1` — `Get-Config`, `Write-Log`, `Get-TimestampedFilename`, `Test-DirectoryStructure`
- `scripts/lib/config-loader.ps1` — config loading with env overrides
- `scripts/lib/git-operations.ps1` — `Invoke-GitCommit`
- `scripts/lib/frontmatter.ps1` — `Set-FrontmatterField`, `Get-FrontmatterData`, `Get-FrontmatterValue` (extracted Story 2.3); use these for any frontmatter manipulation
- `templates/conversation-import.md` — conversation template with frontmatter scaffold (from Story 0.2)
- `config/pinky-config.yaml` — `file_naming.conversation_pattern: "YYYY-MM-DD-HHMMSS-conversation-{service}"` — use this; do NOT hardcode the pattern

### New file: `scripts/import-conversation.ps1`

**Script boilerplate — follow exactly (from Stories 2.2, 2.3):**

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(...)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
. "$PSScriptRoot\lib\frontmatter.ps1"
if (Test-Path "$PSScriptRoot\lib\git-operations.ps1") {
    . "$PSScriptRoot\lib\git-operations.ps1"
}

$config = Get-Config
```

**Parameters:**

```powershell
param(
    [string]$File,               # Path to conversation file
    [string]$Service = "unknown",# AI service: claude, chatgpt, gemini, etc.
    [string]$ConversationDate,   # ISO date YYYY-MM-DD; defaults to today if omitted
    [ValidateSet('file', 'paste', 'clipboard')]
    [string]$Method,             # Override import method label; auto-detected if omitted
    [switch]$WhatIf,
    [switch]$Help
)
```

**Stdin/clipboard detection — same pattern as Story 1.1 capture.ps1:**

```powershell
$pipedContent = $null
if ($MyInvocation.ExpectingInput) {
    $pipedContent = $input | Out-String
}
```

If neither `-File` nor piped input is provided, attempt clipboard:

```powershell
if ([string]::IsNullOrEmpty($File) -and [string]::IsNullOrEmpty($pipedContent)) {
    if ([Environment]::UserInteractive) {
        $rawText = [System.Windows.Forms.Clipboard]::GetText()
        if (-not [string]::IsNullOrWhiteSpace($rawText)) {
            $pipedContent = $rawText
            $effectiveMethod = 'clipboard'
        } else {
            Write-Log "No -File specified and clipboard is empty. Provide -File or pipe content." "ERROR"
            exit 1
        }
    } else {
        Write-Log "No -File specified and non-interactive mode detected. Provide -File or pipe content." "ERROR"
        exit 1
    }
}
```

**Filename generation — use config pattern:**

```powershell
$rawFolder = Join-Path $config.system.vault_root $config.folders.raw
if (!(Test-Path $rawFolder)) {
    Write-Log "Raw folder not found at '$rawFolder'. Run .\scripts\setup-system.ps1 to initialize." "ERROR"
    exit 2
}

$pattern = $config.file_naming.conversation_pattern
# Replace {service} placeholder
$serviceSlug = $Service.ToLower() -replace '[^a-z0-9]', '-'
$timestamp = Get-Date -Format "yyyy-MM-dd-HH-mm"
$fileName = $pattern -replace 'YYYY-MM-DD-HHMMSS', $timestamp `
                     -replace 'YYYY-MM-DD-HH-MM', $timestamp `
                     -replace '\{service\}', $serviceSlug
$fileName = $fileName.TrimEnd('.md') + '.md'
$outputPath = Join-Path $rawFolder $fileName
```

Note: `Get-TimestampedFilename` in `common.ps1` is optimized for millisecond-precision inbox names. For conversation imports, build the name directly from the pattern with second-level precision (collisions are not a concern for manual import).

**Format detection:**

```powershell
function Get-ConversationFormat {
    param([string]$Content)
    $trimmed = $Content.Trim()
    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) { return 'json' }
    if ($trimmed.StartsWith('---')) { return 'markdown' }
    return 'text'
}
```

**JSON parsing:**

```powershell
function Convert-JsonConversation {
    param([string]$JsonContent)
    $errors = @()
    try {
        $data = $JsonContent | ConvertFrom-Json
        $messages = $null
        if ($data.PSObject.Properties['messages']) { $messages = $data.messages }
        elseif ($data -is [array]) { $messages = $data }

        if ($null -eq $messages) {
            $errors += "Unrecognized JSON structure — no 'messages' array found."
            return @{ Body = "``````json`n$JsonContent`n``````"; Errors = $errors }
        }

        $turns = @()
        foreach ($msg in $messages) {
            $role = if ($msg.role) { $msg.role } else { 'unknown' }
            $content = if ($msg.content) { $msg.content } else { '' }
            $label = switch ($role.ToLower()) {
                'user'      { '**User:**' }
                'assistant' { '**Assistant:**' }
                'system'    { '**System:**' }
                default     { "**${role}:**" }
            }
            $turns += "$label`n`n$content"
        }
        return @{ Body = ($turns -join "`n`n---`n`n"); Errors = $errors }
    } catch {
        $errors += "JSON parse error: $_"
        return @{ Body = "``````json`n$JsonContent`n``````"; Errors = $errors }
    }
}
```

**Turn detection for plain text:**

```powershell
function Format-PlainTextConversation {
    param([string]$Content)
    # Detect role-prefixed turns (Human:, User:, Assistant:, Claude:, GPT:)
    $rolePattern = '(?m)^(Human|User|Assistant|Claude|GPT|You|AI)\s*:'
    if ($Content -match $rolePattern) {
        # Replace bare "Human:" / "User:" with bold markers
        $formatted = $Content `
            -replace '(?m)^(Human|User|You)\s*:', '**User:**' `
            -replace '(?m)^(Assistant|Claude|GPT|AI)\s*:', '**Assistant:**'
        return $formatted
    }
    return $Content
}
```

**Frontmatter construction:**

```powershell
$convDate = if ($ConversationDate) { $ConversationDate } else { (Get-Date).ToString("yyyy-MM-dd") }
$importDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
$sourceFormat = Get-ConversationFormat -Content $rawText

$frontmatter = @"
conversation_date: "$convDate"
ai_service: "$Service"
import_date: "$importDate"
import_method: "$effectiveMethod"
source_format: "$sourceFormat"
review_status: "pending"
"@
```

If errors occurred during import, also append:

```powershell
$frontmatter += "`nimport_errors: true"
```

Body structure:

```
---
{frontmatter}
---

# AI Conversation — {Service} — {convDate}

{converted body}

## Import Errors
{error notes if any}
```

**Git auto-commit — same pattern as Story 2.2:**

```powershell
if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $relPath  = $outputPath.Replace($repoRoot, '').TrimStart('\').TrimStart('/')
    Invoke-GitCommit -Message "raw: import conversation from $Service" `
                     -Files @($relPath) -RepoPath $repoRoot | Out-Null
}
```

### Architecture compliance

- PowerShell 5.1 — **no** `??`, **no** `? :`, **no** `?.`; use explicit `if/else` throughout
- All file writes: `Set-Content -Path $outputPath -Value $content -Encoding UTF8`
- Logging: `Write-Log` from `scripts/lib/common.ps1`
- Exit codes: `0` = success or WhatIf, `1` = user input error, `2` = system error (missing folder/config)
- `$PSScriptRoot` for all lib path resolution
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at script top
- NFR-003: imported conversation is saved to `raw/` with `review_status: "pending"` — **never** to wiki or working; no auto-promotion logic in this script
- Inspectability (NFR-010): write only what is reviewable; no hidden state changes

### File structure

```
scripts/
  import-conversation.ps1    # NEW — full AI conversation import workflow
tests/
  import-conversation.Tests.ps1  # NEW — Pester coverage
```

No changes to: `capture.ps1`, `common.ps1`, `config-loader.ps1`, `frontmatter.ps1`, `git-operations.ps1`, or any existing script.

---

## Testing Requirements

Follow the exact test file conventions from `tests/archive-content.Tests.ps1` and `tests/wiki-metadata.Tests.ps1`:
- Use `$TestDrive` for isolated vault root
- Set `$env:PINKY_VAULT_ROOT` and `$env:PINKY_FORCE_NONINTERACTIVE = "1"`
- Mock `Invoke-GitCommit` via env-guard pattern

New test file: `tests/import-conversation.Tests.ps1`

**Required test cases:**

| Test | What to verify |
|------|----------------|
| File import | Output file exists in `knowledge/raw/`, exits 0 |
| Filename format | Filename matches `YYYY-MM-DD-HH-MM-conversation-<service>.md` pattern |
| Frontmatter fields | `conversation_date`, `ai_service`, `import_date`, `import_method`, `source_format`, `review_status: "pending"` all present |
| Source file unchanged | Source file on disk is not modified or deleted after import |
| Plain text format detection | `source_format: "text"` in frontmatter |
| Markdown format detection | `source_format: "markdown"` when input starts with `---` |
| JSON format detection | `source_format: "json"` when input starts with `{` |
| JSON well-formed | ChatGPT-style `messages` array produces `**User:**`/`**Assistant:**` turns in body |
| JSON malformed | Bad JSON produces fenced code block + `import_errors: true` in frontmatter |
| Turn detection | Plain text with `Human:` prefix gets converted to `**User:**` |
| Mixed content preserved | Code fences and URLs in source appear unchanged in output body |
| Missing raw folder | Exits code 2 with message containing `setup-system.ps1` |
| File not found | Exits code 1 with clear path error |
| WhatIf | Prints intended action, no file written, exits 0 |
| Malformed import saved | Corrupted input results in saved file (not rejected), `import_errors: true` |
| Git commit fires | `Invoke-GitCommit` called after successful write (mock via env guard) |
| Service slug | Service name with spaces/caps is slugified in filename |

Run focused validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\import-conversation.Tests.ps1"
```

---

## Previous Story Intelligence

**From Story 0.3 (PowerShell Script Implementation):**
- `capture.ps1 -Type conversation` already does basic raw capture. **Do NOT modify it.** `import-conversation.ps1` is the richer import path — they coexist.
- The conversation template `templates/conversation-import.md` exists from Story 0.2 — load it via `Get-Template` from `common.ps1` if needed, or construct frontmatter directly.
- `$PSScriptRoot` resolves lib paths reliably from any working directory.

**From Story 1.1 (Quick Knowledge Capture):**
- `$MyInvocation.ExpectingInput` is the correct PowerShell 5.1 way to detect piped stdin.
- `[Environment]::UserInteractive` guards all `Read-Host` / clipboard calls.
- Exit codes 0/1/2 are established — maintain them.
- Stale `.lock` file cleanup pattern (>5 min): apply if file collision protection is needed, though manual import collisions are unlikely.

**From Story 2.2 (Wiki Metadata Management):**
- `Get-FrontmatterData`, `Get-FrontmatterValue`, `Set-FrontmatterField` — these are now in `scripts/lib/frontmatter.ps1` (extracted Story 2.3). Do NOT copy them into the new script — dot-source `frontmatter.ps1`.
- `Invoke-GitCommit` call signature: `-Message`, `-Files`, `-RepoPath`.
- Use `Get-RelativeRepoPath` from `frontmatter.ps1` or implement inline (one-liner: `$outputPath.Replace($repoRoot, '').TrimStart('\').TrimStart('/')`).

**From Story 2.3 (Content Archival System):**
- `scripts/lib/frontmatter.ps1` was created in Story 2.3. It is the canonical location for shared frontmatter helpers. Always dot-source it rather than reimplementing.
- `$env:PINKY_FORCE_NONINTERACTIVE = "1"` disables all prompts in test context — honor it.
- Focused Pester only: full-suite has pre-existing failures unrelated to this story.

**From Story 3.x (Discovery & Retrieval):**
- The search and AI handoff scripts read `review_status` from frontmatter to filter raw/pending content. Set `review_status: "pending"` so conversations are searchable but flagged as unreviewed. This is consistent with NFR-003.

---

## Git Intelligence

Established patterns from recent commits:
- Sprint commit format: `feat(epic-N): complete <story-name>`
- Dev stories commit scripts + tests in one commit
- Focused Pester run: `Invoke-Pester tests\<story>.Tests.ps1`
- Pre-existing full-suite failures exist — do not attempt to fix them; run only the new focused test file

---

## Scope Boundaries

**In scope for this story:**
- `scripts/import-conversation.ps1` with file/paste/clipboard input
- Plain text, markdown, and JSON format detection and rendering
- Frontmatter with `conversation_date`, `ai_service`, `import_date`, `import_method`, `source_format`, `review_status: "pending"`
- Turn structure preservation (role detection from common patterns)
- Malformed import handling (save with error notes, not reject)
- Git auto-commit after successful write
- Pester tests covering all cases above

**Explicitly out of scope:**
- Promotion of conversations to working notes or wiki (Epic 7 / Story 7.1 governs the review gate for AI content promotion)
- Non-AI source capture (Story 4.2)
- Capture configuration changes (Story 4.3)
- Modifying `capture.ps1` — the basic `-Type conversation` path remains intact
- HTTP requests or AI-assisted turn detection
- Multi-turn conversation splitting or summarization

---

## Definition of Done

- [x] `scripts/import-conversation.ps1` exists and runs on PowerShell 5.1 without errors
- [x] File import: `-File` reads the source file; source file is unchanged after import
- [x] Paste/stdin import: piped content used as conversation body
- [x] Clipboard import: clipboard content used when no file or piped input provided
- [x] Filename built from `config.file_naming.conversation_pattern` with `{service}` replaced
- [x] Output written to `knowledge/raw/` per `config.folders.raw`
- [x] Frontmatter contains all 6 required fields: `conversation_date`, `ai_service`, `import_date`, `import_method`, `source_format`, `review_status: "pending"`
- [x] JSON format: `messages` array rendered as `**User:**`/`**Assistant:**` turns; unknown structure → fenced code block
- [x] Plain text: `Human:`/`User:` and `Assistant:` prefixes converted to bold markers
- [x] Malformed/partial imports saved with `## Import Errors` section and `import_errors: true`
- [x] Missing `knowledge/raw/` exits code 2 and references `setup-system.ps1`
- [x] `-File` not found exits code 1
- [x] `-WhatIf` prints action without writing
- [x] Git auto-commit fires after successful write
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` present
- [x] No `??`, no ternary `? :`, no `?.` operators
- [x] `frontmatter.ps1` dot-sourced (not copied) — no duplicate helper functions
- [x] Pester tests pass: `Invoke-Pester tests\import-conversation.Tests.ps1`

---

## Tasks / Subtasks

- [x] Task 1: Implement `scripts/import-conversation.ps1`
  - [x] 1.1 Param block: `-File`, `-Service`, `-ConversationDate`, `-Method`, `-WhatIf`, `-Help`
  - [x] 1.2 Standard boilerplate: dot-source libs, `Get-Config`, raw-folder existence check (exit 2)
  - [x] 1.3 Input resolution: piped stdin, clipboard fallback, and `-File` handling with exit 1 on missing input
  - [x] 1.4 Format detection: `Get-ConversationFormat` returning `json`/`markdown`/`text`
  - [x] 1.5 Format conversion: JSON messages array → turn blocks; plain text turn detection
  - [x] 1.6 Filename generation from config pattern with `{service}` replacement
  - [x] 1.7 Frontmatter construction with all 6 required fields
  - [x] 1.8 Body assembly: frontmatter + heading + converted body + `## Import Errors` (if any)
  - [x] 1.9 Write output file with `Set-Content -Encoding UTF8`
  - [x] 1.10 Git auto-commit via `Invoke-GitCommit` pattern
  - [x] 1.11 `-WhatIf` path: print action, exit 0 without writing

- [x] Task 2: Write `tests/import-conversation.Tests.ps1`
  - [x] 2.1 All test cases from Testing Requirements table, including clipboard coverage
  - [x] 2.2 Use `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"`
  - [x] 2.3 Run `Invoke-Pester tests\import-conversation.Tests.ps1` and confirm pass

- [x] Task 3: Update sprint status
  - [x] 3.1 Set `4-1-ai-conversation-import` to `done` in `sprint-status.yaml` after dev completes

---

## File List

- `scripts/import-conversation.ps1` — NEW
- `tests/import-conversation.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/4-1-ai-conversation-import.md` — UPDATED (status, tasks, validation record)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED (`4-1-ai-conversation-import` → `done`)

---

## Review Findings

- No confirmed Story 4.1 defects remained after implementation and re-validation.

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\import-conversation.Tests.ps1"`
- Direct manual validation: PowerShell pipeline input using `Get-Content` piped into `scripts/import-conversation.ps1`
- Direct manual validation: clipboard import path using `Set-Clipboard` followed by `scripts/import-conversation.ps1`

### Completion Notes

- Implemented `scripts/import-conversation.ps1` as a new raw-layer import path without changing `scripts/capture.ps1`.
- Added deterministic handling for file, stdin, and clipboard inputs with frontmatter/provenance metadata and `review_status: "pending"`.
- Added JSON turn rendering, plain-text role detection, malformed-import preservation with `## Import Errors`, and story-scoped git commit behavior.
- Added focused Pester coverage for file, stdin, clipboard, format detection, malformed input, WhatIf, error exits, and git commit behavior.
- Ran BMAD code review on the Story 4.1 change set and did not confirm any remaining defects.

## Change Log

- 2026-04-24: Implemented Story 4.1 AI conversation import, validated with focused Pester coverage, and cleared code review.
