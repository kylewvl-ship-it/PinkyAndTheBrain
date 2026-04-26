# Story 4.2: Non-AI Source Capture

**Story ID:** 4.2
**Epic:** 4 - Advanced Capture & Sources
**Status:** done
**Created:** 2026-04-24

---

## User Story

As Reno,
I want to capture articles, videos, documents, and other non-AI sources with provenance metadata,
so that all knowledge inputs are tracked regardless of origin.

---

## Acceptance Criteria

### Scenario: Web source capture

- **Given** I want to capture content from a web source
- **When** I run `.\scripts\capture-source.ps1 -SourceType web -Url "https://example.com" -Title "Article Title" -Notes "My summary or quotes"`
- **Then** the file is saved to `knowledge/inbox/` with filename `YYYY-MM-DD-HHMMSSfff-article-title.md`
- **And** frontmatter contains: `source_type: "web"`, `source_url`, `source_title`, `captured_date` (ISO date)
- **And** the content body contains only the user-supplied notes (no auto-generated content)
- **And** the script returns the full file path on success

### Scenario: Offline source capture — template-based entry

- **Given** I want to capture from an offline source
- **When** I run `.\scripts\capture-source.ps1 -SourceType book` (or `meeting`, `video`, `article`, `idea`)
- **Then** a new file is created in `knowledge/inbox/` using the appropriate source template (`templates/source-book.md`, etc.)
- **And** the frontmatter contains: `source_type`, `title`, `author` (or `participants` for meetings), `source_date`, `captured_date`
- **And** my notes are placed in the `## My Notes` body section
- **And** all fields are optional except `source_type` and `my_notes`

### Scenario: Missing metadata marked as unknown

- **Given** I omit optional frontmatter fields (title, author, source_date) during capture
- **When** the file is saved
- **Then** the capture succeeds without validation errors or failures
- **And** omitted string fields default to `"unknown"` rather than empty string or null
- **And** the resulting file is still editable; no field is locked or read-only

### Scenario: Private content

- **Given** I capture content containing sensitive information
- **When** I pass `-Private` to the script or manually add `private: true` to frontmatter
- **Then** the file has `private: true` in frontmatter
- **And** the file is excluded from AI handoff context generation (consistent with `generate-handoff.ps1` behavior in Story 3.3)
- **And** no other behavior changes — the file is still created in inbox, triageable, and searchable

### Scenario: Incomplete web capture (URL only)

- **Given** I provide only a URL with no title or notes
- **When** I run `.\scripts\capture-source.ps1 -SourceType web -Url "https://example.com"`
- **Then** the capture saves with `source_url` populated, `source_title: "unknown"`, `captured_date` set to today
- **And** the body contains an empty `## My Notes` section for me to fill in later
- **And** the script succeeds (exit 0); it does not require title or notes for web capture

### Error Scenario: Missing inbox folder

- **Given** `knowledge/inbox/` does not exist
- **When** I attempt any capture
- **Then** the script exits with code 2 and message identifies the missing inbox path and references `setup-system.ps1`

### Error Scenario: Invalid source type

- **Given** I provide a `-SourceType` value that is not one of: `web`, `book`, `meeting`, `video`, `article`, `idea`
- **When** the script validates input
- **Then** it exits with code 1 and displays the valid source types

---

## Technical Requirements

### What already exists — do NOT reimplement

- `scripts/capture.ps1` — handles `-Type web` basic web capture to inbox. **This story does NOT modify `capture.ps1`.** `capture-source.ps1` is the dedicated non-AI source path, parallel to `import-conversation.ps1`.
- `scripts/lib/common.ps1` — `Get-Config`, `Write-Log`, `Get-TimestampedFilename`, `Test-DirectoryStructure`
- `scripts/lib/config-loader.ps1` — config loading with env overrides
- `scripts/lib/git-operations.ps1` — `Invoke-GitCommit`
- `scripts/lib/frontmatter.ps1` — `Set-FrontmatterField`, `Get-FrontmatterData`, `Get-FrontmatterValue`
- `templates/inbox-item.md` — base inbox template with `captured_date`, `source_type`, `review_status`, `private`
- `config/pinky-config.yaml` — `file_naming.inbox_pattern: "YYYY-MM-DD-HHMMSSfff-{title}"` — use this; do NOT hardcode the pattern
- `generate-handoff.ps1` — already excludes files with `private: true` or `exclude_from_ai: true`; no changes needed there

### New files

```
scripts/
  capture-source.ps1              # NEW — dedicated non-AI source capture script

templates/
  source-book.md                  # NEW
  source-meeting.md               # NEW
  source-video.md                 # NEW
  source-article.md               # NEW
  source-idea.md                  # NEW

tests/
  capture-source.Tests.ps1        # NEW — Pester coverage
```

No changes to: `capture.ps1`, `common.ps1`, `config-loader.ps1`, `frontmatter.ps1`, `git-operations.ps1`, `generate-handoff.ps1`, or any existing script.

### Script: `scripts/capture-source.ps1`

**Boilerplate — follow exactly (same pattern as `import-conversation.ps1` from Story 4.1):**

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
    [Parameter(Mandatory)]
    [ValidateSet('web','book','meeting','video','article','idea')]
    [string]$SourceType,

    [string]$Title,                  # Page/item title; defaults to "unknown"
    [string]$Url,                    # Web URL (web source type)
    [string]$Author,                 # Author or participants
    [string]$SourceDate,             # Date of the source (not capture date) YYYY-MM-DD
    [string]$Notes,                  # User-supplied notes/summary/quotes; populates ## My Notes
    [switch]$Private,                # Sets private: true in frontmatter
    [switch]$WhatIf,
    [switch]$Help
)
```

**Inbox folder existence check (exit 2):**

```powershell
$inboxFolder = Join-Path $config.system.vault_root $config.folders.inbox
if (!(Test-Path $inboxFolder)) {
    Write-Log "Inbox folder not found at '$inboxFolder'. Run .\scripts\setup-system.ps1 to initialize." "ERROR"
    exit 2
}
```

**Filename generation — use config inbox_pattern:**

```powershell
$effectiveTitle = if ($Title) { $Title } else { $SourceType }
$fileName = Get-TimestampedFilename -Title $effectiveTitle -Pattern $config.file_naming.inbox_pattern
$outputPath = Join-Path $inboxFolder $fileName
```

**Frontmatter construction — apply "unknown" default for missing string fields:**

```powershell
$effectiveTitle    = if ($Title) { $Title } else { "unknown" }
$effectiveAuthor   = if ($Author) { $Author } else { "unknown" }
$effectiveSourceDate = if ($SourceDate) { $SourceDate } else { "unknown" }
$capturedDate      = (Get-Date).ToString("yyyy-MM-dd")
$privateValue      = if ($Private) { "true" } else { "false" }

# Web-specific fields
$effectiveUrl = if ($Url) { $Url } else { "unknown" }
```

Build frontmatter string based on source type:

- **web**: include `source_url`, `source_title`, `captured_date`, `source_type`, `review_status`, `private`
- **offline types** (book, meeting, video, article, idea): include `source_type`, `title`, `author` (or `participants` for meeting), `source_date`, `captured_date`, `review_status`, `private`

`review_status: "pending"` on all captures (consistent with the system's review-gate posture — captured material is source material, not auto-promoted knowledge).

**Body construction:**

Load the matching source template from `templates/source-{type}.md`. If not found, fall back to the inline structure:

```
---
{frontmatter}
---

# {source_type}: {effectiveTitle}

## My Notes

{$Notes if provided, otherwise empty}

## Source Context

{type-appropriate source context details}
```

The body body must never contain auto-generated summaries or AI-extracted content — only what the user supplied.

**Git auto-commit — same pattern as `import-conversation.ps1`:**

```powershell
if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $relPath  = $outputPath.Replace($repoRoot, '').TrimStart('\').TrimStart('/')
    Invoke-GitCommit -Message "inbox: capture $SourceType source" `
                     -Files @($relPath) -RepoPath $repoRoot | Out-Null
}
```

### Templates: `templates/source-*.md`

Each template provides the frontmatter scaffold and section structure. Field values are `{{placeholder}}` tokens. Mandatory fields (`source_type`, `my_notes`) are always included; all others default to `unknown` when not provided.

**`templates/source-book.md`:**
```yaml
---
source_type: "book"
title: "{{title}}"
author: "{{author}}"
source_date: "{{source_date}}"
captured_date: "{{captured_date}}"
review_status: "pending"
private: false
---

# Book: {{title}}

## My Notes

{{my_notes}}

## Source Context

Author: {{author}}
Date read / accessed: {{source_date}}
```

**`templates/source-meeting.md`:**
```yaml
---
source_type: "meeting"
title: "{{title}}"
participants: "{{participants}}"
source_date: "{{source_date}}"
captured_date: "{{captured_date}}"
review_status: "pending"
private: false
---

# Meeting: {{title}}

## My Notes

{{my_notes}}

## Source Context

Participants: {{participants}}
Meeting date: {{source_date}}
```

**`templates/source-video.md`:**
```yaml
---
source_type: "video"
title: "{{title}}"
author: "{{author}}"
source_date: "{{source_date}}"
captured_date: "{{captured_date}}"
review_status: "pending"
private: false
---

# Video: {{title}}

## My Notes

{{my_notes}}

## Source Context

Creator: {{author}}
Date: {{source_date}}
```

**`templates/source-article.md`:**
```yaml
---
source_type: "article"
title: "{{title}}"
author: "{{author}}"
source_date: "{{source_date}}"
captured_date: "{{captured_date}}"
review_status: "pending"
private: false
---

# Article: {{title}}

## My Notes

{{my_notes}}

## Source Context

Author: {{author}}
Published: {{source_date}}
```

**`templates/source-idea.md`:**
```yaml
---
source_type: "idea"
title: "{{title}}"
captured_date: "{{captured_date}}"
review_status: "pending"
private: false
---

# Idea: {{title}}

## My Notes

{{my_notes}}
```

### Architecture compliance

- PowerShell 5.1 — **no** `??`, **no** `? :`, **no** `?.`; use explicit `if/else` throughout
- All file writes: `Set-Content -Path $outputPath -Value $content -Encoding UTF8`
- Logging: `Write-Log` from `scripts/lib/common.ps1`
- Exit codes: `0` = success or WhatIf, `1` = user input error, `2` = system error (missing folder/config)
- `$PSScriptRoot` for all lib path resolution
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at script top
- Inbox output path (`config.system.vault_root` + `config.folders.inbox`) — never hardcoded
- Filename from `config.file_naming.inbox_pattern` via `Get-TimestampedFilename` — never hardcoded
- `review_status: "pending"` on all captures — captured material is not auto-promoted
- `private: true` exclusion is already implemented in `generate-handoff.ps1`; this story only needs to write the frontmatter field correctly
- Inspectability (NFR-010): write only what is reviewable; no hidden state changes
- NFR-001/NFR-002: output is a plain Markdown file with YAML frontmatter; Obsidian-compatible

---

## Testing Requirements

Follow the test file conventions established in `tests/capture.Tests.ps1` and `tests/import-conversation.Tests.ps1`:
- Use `$TestDrive` for isolated vault root
- Set `$env:PINKY_VAULT_ROOT` and `$env:PINKY_FORCE_NONINTERACTIVE = "1"`
- Mock `Invoke-GitCommit` via env-guard pattern

New test file: `tests/capture-source.Tests.ps1`

**Required test cases:**

| Test | What to verify |
|------|----------------|
| Web capture — file exists | Output file created in `knowledge/inbox/`, exits 0 |
| Web capture — frontmatter | `source_type: "web"`, `source_url`, `source_title`, `captured_date`, `review_status: "pending"` all present |
| Web capture — body | `## My Notes` section present; user notes in body |
| Web capture — URL only | `source_title: "unknown"`, exits 0, file written |
| Book capture | `source_type: "book"`, `author`, `source_date`, `title`, `captured_date` in frontmatter |
| Meeting capture | `source_type: "meeting"`, `participants` field (not `author`) in frontmatter |
| Filename pattern | Filename matches `YYYY-MM-DD-HHMMSSfff-*.md` from inbox_pattern |
| Missing fields default to unknown | Omitted `title`, `author`, `source_date` all appear as `"unknown"` not empty |
| Private flag | `-Private` → `private: true` in frontmatter |
| No auto-generated content | Body contains only user-supplied notes, not auto-summaries |
| Missing inbox folder | Exits code 2 with message containing `setup-system.ps1` |
| Invalid source type | Exits code 1; ValidateSet enforcement |
| WhatIf | Prints intended action, no file written, exits 0 |
| Git commit fires | `Invoke-GitCommit` called after successful write (mock via env guard) |
| review_status pending | All captures have `review_status: "pending"` in frontmatter |

Run focused validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\capture-source.Tests.ps1"
```

---

## Dev Notes

### Provenance and review-gate posture (align with Story 4.1)

- All captured files land in `knowledge/inbox/` with `review_status: "pending"` — they are source material, not knowledge.
- The inbox triage workflow (Story 1.2, `triage.ps1`) is the promotion path; this script does not triage.
- The AI handoff script (`generate-handoff.ps1`, Story 3.3) already checks `private: true` and `exclude_from_ai: true` before including files. Writing `private: true` here is sufficient — no changes to `generate-handoff.ps1`.

### "unknown" default convention

The requirement to default missing fields to `"unknown"` rather than empty string prevents YAML parsing surprises and makes it visually obvious that a field is unfilled without breaking frontmatter readers. Apply this only to optional string fields (`title`, `author`, `participants`, `source_date`, `source_title`, `source_url`). Boolean fields (`private`) default to `false`. `captured_date` is always auto-set.

### Template loading strategy

Load the template file if it exists; otherwise use an inline string as fallback. This prevents errors if the templates folder is incomplete while keeping behavior inspectable:

```powershell
$templatePath = Join-Path $config.system.template_root "source-$($SourceType.ToLower()).md"
if (Test-Path $templatePath) {
    $templateContent = Get-Content $templatePath -Raw -Encoding UTF8
    # Replace {{placeholder}} tokens
} else {
    # Build inline content string
}
```

### capture.ps1 is NOT modified

The existing `-Type web` path in `capture.ps1` remains intact and handles basic web captures from Story 1.1. `capture-source.ps1` is the richer, template-driven path for all non-AI source types. The two scripts coexist without conflict.

### Project Structure Notes

- Output: `knowledge/inbox/` (resolved via `config.system.vault_root` + `config.folders.inbox`)
- Templates: `templates/source-*.md` (new, parallel to existing `inbox-item.md`, `working-note.md`, etc.)
- No new config keys needed — all paths resolved from existing config structure (Story 0.4)
- Filename generated via `Get-TimestampedFilename` with `config.file_naming.inbox_pattern`

### References

- Epic 4 Story 4.2 requirements: [Source: _bmad-output/planning-artifacts/epics.md#Story-4.2]
- Inbox capture conventions: [Source: _bmad-output/implementation-artifacts/1-1-quick-knowledge-capture.md]
- Import script boilerplate: [Source: _bmad-output/implementation-artifacts/4-1-ai-conversation-import.md#Technical-Requirements]
- Private exclusion behavior: [Source: _bmad-output/implementation-artifacts/3-3-ai-handoff-context-generation.md#AC1]
- Config paths and patterns: [Source: config/pinky-config.yaml]

---

## Previous Story Intelligence

**From Story 1.1 (Quick Knowledge Capture):**
- `$MyInvocation.ExpectingInput` is the PowerShell 5.1 way to detect piped stdin (not needed here, but apply if adding piped notes later)
- `[Environment]::UserInteractive` guards interactive prompts
- Exit codes 0/1/2 are established conventions — maintain them
- `Get-TimestampedFilename` is in `common.ps1`; use it with the inbox_pattern from config

**From Story 4.1 (AI Conversation Import):**
- `import-conversation.ps1` is the canonical model for a "new dedicated capture script": new file, same boilerplate, same lib dot-sources, same exit-code conventions, same git commit pattern
- Do NOT modify `capture.ps1` — create a new `capture-source.ps1` following the same pattern
- `$env:PINKY_FORCE_NONINTERACTIVE = "1"` disables interactive prompts in test context — honor it
- Focused Pester only: full-suite has pre-existing failures unrelated to this story
- `frontmatter.ps1` is dot-sourced (not copied) — no duplicate helper functions

**From Story 3.3 (AI Handoff Context Generation):**
- `generate-handoff.ps1` already skips files with `private: true` or `exclude_from_ai: true`; this story only needs to write the flag — no changes to handoff generation
- `review_status: "pending"` is the correct status for all raw/unreviewed captures

**From Story 0.4 (Configuration Management):**
- All folder paths come from `config.system.vault_root` + `config.folders.*` — never hardcode paths
- `config.file_naming.inbox_pattern` (`YYYY-MM-DD-HHMMSSfff-{title}`) is the correct inbox filename pattern
- `Get-Config` from `common.ps1` loads the config reliably

---

## Git Intelligence

Established patterns from recent commits:
- Sprint commit format: `feat(epic-N): complete <story-name>`
- Dev stories commit scripts + tests in one commit
- Focused Pester run: `Invoke-Pester tests\<story>.Tests.ps1`
- Pre-existing full-suite failures exist — do not attempt to fix them; run only the new focused test file

---

## Scope Boundaries

**In scope:**
- `scripts/capture-source.ps1` with `-SourceType web|book|meeting|video|article|idea`
- Web captures: `source_url`, `source_title`, `captured_date`, `source_type: "web"`, user notes in body
- Offline captures: per-type templates with `source_type`, `title`, `author/participants`, `source_date`, `captured_date`
- `private: true` via `-Private` switch
- Missing fields default to `"unknown"` (not empty, not error)
- `review_status: "pending"` on all captures
- Templates: `templates/source-book.md`, `source-meeting.md`, `source-video.md`, `source-article.md`, `source-idea.md`
- Git auto-commit after successful write
- Pester tests covering all cases above

**Explicitly out of scope:**
- Modifying `capture.ps1` — basic `-Type web` path remains intact
- Project/domain separation (Story 5.2) — do not add project-routing or subdomain logic
- Privacy audit commands (Story 5.1) — only write `private: true`; no audit report
- Capture configuration management (Story 4.3) — use existing config; do not add new config keys
- AI-assisted title or summary generation — user-authored notes only
- Promotion from inbox to working/wiki — that is triage (Story 1.2)

---

## Definition of Done

- [x] `scripts/capture-source.ps1` exists and runs on PowerShell 5.1 without errors
- [x] Web capture: `source_type: "web"`, `source_url`, `source_title`, `captured_date`, `review_status: "pending"` in frontmatter
- [x] Web capture: URL-only (no title/notes) saves with `source_title: "unknown"`, exits 0
- [x] Offline capture: correct template used per source type; `source_type`, `title`, `author/participants`, `source_date`, `captured_date` present
- [x] Missing optional fields default to `"unknown"`, not empty string
- [x] `-Private` switch writes `private: true` in frontmatter
- [x] Body contains only user-supplied notes — no auto-generated content
- [x] Filename built from `config.file_naming.inbox_pattern` via `Get-TimestampedFilename`
- [x] Output written to `knowledge/inbox/` per `config.folders.inbox`
- [x] Missing `knowledge/inbox/` exits code 2 and references `setup-system.ps1`
- [x] Invalid `-SourceType` exits code 1
- [x] `-WhatIf` prints action without writing
- [x] Git auto-commit fires after successful write
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` present
- [x] No `??`, no ternary `? :`, no `?.` operators
- [x] `frontmatter.ps1` dot-sourced (not copied)
- [x] `capture.ps1` unchanged
- [x] `generate-handoff.ps1` unchanged
- [x] Templates created: `source-book.md`, `source-meeting.md`, `source-video.md`, `source-article.md`, `source-idea.md`
- [x] Pester tests pass: `Invoke-Pester tests\capture-source.Tests.ps1`

---

## Tasks / Subtasks

- [x] Task 1: Create source templates in `templates/`
  - [x] 1.1 `templates/source-book.md` — frontmatter scaffold + `## My Notes` + `## Source Context`
  - [x] 1.2 `templates/source-meeting.md` — uses `participants` not `author`
  - [x] 1.3 `templates/source-video.md`
  - [x] 1.4 `templates/source-article.md`
  - [x] 1.5 `templates/source-idea.md` — simpler; no `author`/`source_date` needed

- [x] Task 2: Implement `scripts/capture-source.ps1`
  - [x] 2.1 Param block: `-SourceType` (ValidateSet), `-Title`, `-Url`, `-Author`, `-SourceDate`, `-Notes`, `-Private`, `-WhatIf`, `-Help`
  - [x] 2.2 Standard boilerplate: dot-source libs, `Get-Config`, inbox-folder existence check (exit 2)
  - [x] 2.3 Apply "unknown" defaults to all missing optional string fields
  - [x] 2.4 Filename generation via `Get-TimestampedFilename` with `config.file_naming.inbox_pattern`
  - [x] 2.5 Frontmatter construction per source type; `private: true` when `-Private`; `review_status: "pending"` always
  - [x] 2.6 Body assembly: load source template (or inline fallback); inject `$Notes` into `## My Notes` section
  - [x] 2.7 Write output file with `Set-Content -Encoding UTF8`
  - [x] 2.8 Git auto-commit via `Invoke-GitCommit` pattern
  - [x] 2.9 `-WhatIf` path: print action, exit 0 without writing

- [x] Task 3: Write `tests/capture-source.Tests.ps1`
  - [x] 3.1 All test cases from Testing Requirements table
  - [x] 3.2 Use `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"`
  - [x] 3.3 Run `Invoke-Pester tests\capture-source.Tests.ps1` and confirm pass

- [x] Task 4: Update sprint status
  - [x] 4.1 Set `4-2-non-ai-source-capture` to `done` in `sprint-status.yaml` after dev completes

---

## File List

- `scripts/capture-source.ps1` — NEW
- `templates/source-book.md` — NEW
- `templates/source-meeting.md` — NEW
- `templates/source-video.md` — NEW
- `templates/source-article.md` — NEW
- `templates/source-idea.md` — NEW
- `tests/capture-source.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/4-2-non-ai-source-capture.md` — this file
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED (`4-2-non-ai-source-capture` → `ready-for-dev`)

---

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- 2026-04-26: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\capture-source.Tests.ps1"` — 15 passed, 0 failed.
- 2026-04-26: `rg -n "\?\?|\?\s*:|\?\." scripts\capture-source.ps1 tests\capture-source.Tests.ps1 templates --glob 'source-*.md'` — no matches.

### Completion Notes List

- Added dedicated non-AI source capture via `scripts/capture-source.ps1`, parallel to the existing AI conversation import path.
- Added source templates for book, meeting, video, article, and idea captures.
- Added focused Pester coverage for web/offline capture, missing metadata defaults, private flag, WhatIf, missing inbox, invalid source type, filename pattern, review status, and git auto-commit.
- BMAD code review found one web-path compliance issue: the body included source-context text for web captures. Fixed by keeping URL provenance in frontmatter only and tightening the regression test.

### File List

- `scripts/capture-source.ps1` — NEW
- `templates/source-book.md` — NEW
- `templates/source-meeting.md` — NEW
- `templates/source-video.md` — NEW
- `templates/source-article.md` — NEW
- `templates/source-idea.md` — NEW
- `tests/capture-source.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/4-2-non-ai-source-capture.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED
