# Story 1.3: Working Note Creation and Management

**Story ID:** 1.3
**Epic:** 1 - Basic Knowledge Lifecycle
**Status:** done
**Created:** 2026-04-23

## User Story

As Reno,
I want to create structured working notes using templates and PowerShell commands,
So that I can develop ideas with proper metadata and source tracking.

## Acceptance Criteria

### Scenario: New working note from scratch

- **Given** I want to create a new working note from scratch
- **When** I run `.\scripts\create-working-note.ps1 -Title "My Topic" -Project "research"`
- **Then** a new file is created in `knowledge/working/` using the working-note template
- **And** the filename is `my-topic.md` (title converted to kebab-case, no timestamp prefix)
- **And** frontmatter includes: `status: "draft"`, `confidence: "low"`, `last_updated: <ISO timestamp>`, `project: "research"`, `review_trigger: <today + 30 days>`
- **And** all template sections are present (see Template Section Names below)
- **And** the script returns the full file path for confirmation

### Scenario: Working note from existing content (promote-to-working)

- **Given** I create a working note from an inbox or raw item
- **When** I run `.\scripts\promote-to-working.ps1 -SourceFile "knowledge/inbox/my-item.md" -Title "Working Topic"`
- **Then** a new working note is generated with the source item's **body content** placed in the `Evidence` section
- **And** the source item's file path is listed in the `Source Pointers` section
- **And** the source item's frontmatter is updated with `promoted_to: "knowledge/working/working-topic.md"`
- **And** the working note frontmatter includes `source_list: ["knowledge/inbox/my-item.md"]`
- **And** `last_updated` and `review_trigger` are set using the same rules as `create-working-note.ps1`

### Scenario: Metadata management via scripts

- **Given** I have a working note created or updated via a script
- **When** the script writes the file
- **Then** `last_updated` is set to the current ISO timestamp
- **And** `review_trigger` is set to today + `review_cadence.working_days` days (default: 30) from `config/pinky-config.yaml`
- **And** required fields (`status`, `confidence`, `last_updated`) are present; if any are missing at creation time the script exits 1 with a message identifying the missing fields
- **And** invalid `status` values (anything outside `draft`, `active`, `promoted`, `archived`) trigger a warning to stderr but do not abort creation

### Scenario: Working note evolution tracking (summary)

- **Given** I have a working note with git history
- **When** I run `.\scripts\working-note-summary.ps1 -File "my-topic.md"`
- **Then** the script prints a summary of git commits that touched `knowledge/working/my-topic.md`
- **And** each entry shows: commit date, short hash, and commit message
- **And** if the file has no git history, the script prints a clear message: "No git history found for this file"

### Scenario: Working note management overview

- **Given** I want to manage multiple working notes
- **When** I run `.\scripts\list-working-notes.ps1`
- **Then** I see all working notes with: title (from frontmatter `title:` field), status, confidence, last_updated, and days until review (or "OVERDUE N days" when past `review_trigger`)
- **And** overdue notes are printed in red (`Write-Host ... -ForegroundColor Red`)
- **And** I can filter by status: `.\scripts\list-working-notes.ps1 -Status active`
- **And** I can sort output: `.\scripts\list-working-notes.ps1 -SortBy last_updated` or `-SortBy confidence`
- **And** if `knowledge/working/` is empty, the script prints "No working notes found" and exits 0

### Error Scenario: Duplicate title

- **Given** I try to create a working note where `knowledge/working/my-topic.md` already exists
- **When** `create-working-note.ps1` or `promote-to-working.ps1` runs
- **Then** the script does NOT overwrite the existing file
- **And** it suggests at least two alternative filenames (e.g., `my-topic-2.md`, `my-topic-3.md`)
- **And** in interactive mode it asks: "Open existing note instead? (y/N)" — if yes, it runs `Invoke-Item` on the file and exits 0

### Error Scenario: Corrupted source file during promotion

- **Given** the source file for `promote-to-working.ps1` has corrupted or unreadable frontmatter
- **When** I run the promotion script
- **Then** the script attempts to read and extract whatever body content is readable (everything after the first `---` block, or the whole file if no frontmatter delimiters are found)
- **And** it creates the working note with the extracted content in `Evidence` and appends `# WARNING: Source frontmatter unreadable` above Evidence
- **And** it logs the corruption details to `logs/script-errors.log` via `Write-Log`
- **And** it exits 0 (the working note was still created)

---

## Technical Requirements

### All four scripts are NET NEW

None of these files exist yet:

```
scripts/
  create-working-note.ps1     # NEW
  promote-to-working.ps1      # NEW
  list-working-notes.ps1      # NEW
  working-note-summary.ps1    # NEW
tests/
  working-notes.Tests.ps1     # NEW
```

No existing scripts need modification **except**: if `health-check.ps1` does not currently scan `knowledge/working/` for overdue `review_trigger` dates, add that layer to the staleness check. Verify by inspection — do not modify health-check.ps1 if it already covers working notes.

### Script structure — follow the established boilerplate

Every script in this project starts with:
```powershell
param(...)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/lib/config-loader.ps1"
if (Test-Path "$PSScriptRoot/lib/git-operations.ps1") {
    . "$PSScriptRoot/lib/git-operations.ps1"
}

$config = Get-Config
if (!(Test-DirectoryStructure $config)) { exit 2 }
```
Follow this exactly — `capture.ps1` and `triage.ps1` are the canonical reference.

### Template loading and variable substitution

The working-note template (`templates/working-note.md`) uses `<title>`, `<timestamp>`, and `<date>` placeholder syntax, **not** `{{key}}` syntax. `Get-Template` in `common.ps1` only handles `{{key}}` placeholders, so **do NOT use `Get-Template` for working note creation**.

Instead, load and replace directly:
```powershell
$template = Get-Content (Join-Path $config.system.template_root "working-note.md") -Raw -Encoding UTF8
$template = $template.Replace('<title>', $Title)
$template = $template.Replace('<timestamp>', (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"))
$template = $template.Replace('<date>', (Get-Date).AddDays($reviewDays).ToString("yyyy-MM-dd"))
```
Use `.Replace()` — not `-replace` — to avoid regex backreference issues (established pattern from Story 0.3).

### Template section names (authoritative — use as-is from the template file)

The **actual** `templates/working-note.md` section names differ from what the epics document:

| Epic says | Template uses |
|-----------|---------------|
| Current Interpretation | **What I Think** |
| Tensions | **Tensions / Contradictions** |
| (not in epic) | **Prompt / Trigger** |

Use the **template file sections verbatim**. Do NOT rename or add sections.

### Frontmatter for new working notes

`create-working-note.ps1` must set these fields, overriding template defaults:

```yaml
status: "draft"          # epic AC requires "draft", not the template's "active"
confidence: "low"
last_updated: "2026-04-23T13:00:00.000Z"   # current ISO timestamp
review_trigger: "2026-05-23"               # today + review_cadence.working_days
project: "research"      # from -Project param; empty string if omitted
```

Get `review_cadence.working_days` from `$config.review_cadence.working_days` — default to `30` if not present.

### Filename generation for working notes

Working note filenames use title-only kebab-case (no timestamp prefix). The `config/pinky-config.yaml` `file_naming.working_pattern` is `"{title}"`. Reuse `Get-TimestampedFilename` with the working pattern OR implement inline:

```powershell
$safeTitle = $Title -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '-+', '-'
$safeTitle = $safeTitle.Trim('-').ToLower()
$fileName  = "$safeTitle.md"
$filePath  = Join-Path (Join-Path $config.system.vault_root $config.folders.working) $fileName
```

No file lock mechanism needed (working notes are not concurrently written like inbox captures).

### Promote-to-working: source file handling

```powershell
# 1. Read source
$sourceContent = Get-Content $SourceFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue

# 2. Parse frontmatter (lines between first pair of '---' delimiters)
$hasFrontmatter = $sourceContent -match '(?s)^---\s*\n(.*?)\n---\s*\n(.*)'
if ($hasFrontmatter) {
    $sourceFrontmatter = $matches[1]
    $sourceBody        = $matches[2].Trim()
} else {
    Write-Log "Source file has no parseable frontmatter: $SourceFile" "WARN" "logs/script-errors.log"
    $sourceFrontmatter = ""
    $sourceBody        = $sourceContent.Trim()
    $corruptionWarning = $true
}

# 3. Build working note — place $sourceBody into Evidence section
# 4. Update source file's promoted_to field using string replacement on frontmatter
```

To update `promoted_to` in the source file: read it, replace `promoted_to: ""` or `promoted_to:` with `promoted_to: "knowledge/working/$fileName"` using `.Replace()`. If `promoted_to` field doesn't exist in the source frontmatter, append it before the closing `---`.

### List-working-notes: calculating days-until-review

```powershell
$today          = (Get-Date).Date
$reviewDate     = [datetime]::ParseExact($fm.review_trigger, "yyyy-MM-dd", $null)
$daysUntilReview = ($reviewDate - $today).Days
if ($daysUntilReview -lt 0) {
    $reviewDisplay = "OVERDUE $([Math]::Abs($daysUntilReview)) days"
    $color         = "Red"
} else {
    $reviewDisplay = "$daysUntilReview days"
    $color         = "White"
}
```

If `review_trigger` is missing or unparseable, display `"unknown"` in white.

### List-working-notes: frontmatter parsing

Parse frontmatter using a simple line-by-line scan — no YAML library available:
```powershell
function Get-FrontmatterValue {
    param([string]$Content, [string]$Key)
    $match = $Content | Select-String -Pattern "^$Key\s*:\s*[`"']?(.+?)[`"']?\s*$" -Multiline
    if ($match) { return $match.Matches[0].Groups[1].Value.Trim('"').Trim("'") }
    return ""
}
```
This pattern is already used implicitly in `triage.ps1` and `capture.ps1` — do not introduce a YAML parser.

### Working-note-summary: git log call

```powershell
$workingDir  = Join-Path $config.system.vault_root $config.folders.working
$relFilePath = "knowledge/working/$File"   # relative to repo root
$gitLog = git log --oneline --follow -- $relFilePath 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitLog)) {
    Write-Host "No git history found for this file" -ForegroundColor Yellow
    exit 0
}
Write-Host $gitLog
```

`working-note-summary.ps1 -File "my-topic.md"` takes the filename only (no path). The script resolves the full relative path for git.

### Git auto-commit

After each successful file write in `create-working-note.ps1` and `promote-to-working.ps1`, call `Invoke-GitCommit` from `scripts/lib/git-operations.ps1`:
```powershell
if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
    Invoke-GitCommit -Message "Working note: created $fileName" -Files @($filePath)
}
```
For promote, commit both the new working note and the modified source file:
```powershell
Invoke-GitCommit -Message "Working note: promoted from $([System.IO.Path]::GetFileName($SourceFile))" -Files @($targetPath, $SourceFile)
```

`list-working-notes.ps1` and `working-note-summary.ps1` are read-only — no git commit needed.

### Architecture compliance

- PowerShell 5.1 — no `??`, no `? :`, no `?.`; use `if ($x) { $y } else { $z }` everywhere
- All file writes: `Set-Content -Path $path -Value $content -Encoding UTF8`
- All logging: `Write-Log` from `scripts/lib/common.ps1`
- Exit codes: 0 = success, 1 = user error (bad args, duplicate title rejected), 2 = system error (missing folders, unreadable config)
- `[Environment]::UserInteractive` guard before every `Read-Host` call
- `$PSScriptRoot` for all lib path resolution

### File structure

```
scripts/
  create-working-note.ps1    # NEW — all creation logic
  promote-to-working.ps1     # NEW — promotion from inbox/raw
  list-working-notes.ps1     # NEW — listing, filtering, sorting
  working-note-summary.ps1   # NEW — git history summary
tests/
  working-notes.Tests.ps1    # NEW — Pester coverage
```

No changes to: `capture.ps1`, `triage.ps1`, `common.ps1`, `config-loader.ps1`, `git-operations.ps1`
Possible change to: `health-check.ps1` (only if it doesn't already cover `knowledge/working/` staleness)

### Testing requirements

- Follow the exact test file structure from `tests/triage.Tests.ps1` and `tests/capture.Tests.ps1`
- Use `$TestDrive` for isolated vault roots; set `$env:PINKY_VAULT_ROOT` so scripts resolve paths correctly
- Use `$env:PINKY_FORCE_NONINTERACTIVE = "1"` to suppress interactive prompts (established convention)
- New test file: `tests/working-notes.Tests.ps1`

**Required test cases:**

| Test | What to verify |
|------|---------------|
| Create: kebab filename | `My Topic` → `my-topic.md` in `knowledge/working/` |
| Create: frontmatter fields | `status: "draft"`, `confidence: "low"`, `last_updated`, `review_trigger` all present |
| Create: review_trigger date | `review_trigger` = today + 30 days (or config value) |
| Create: duplicate → no overwrite | Running twice does not overwrite; script suggests alternative names |
| Promote: Evidence populated | Source body appears under `## Evidence` in the working note |
| Promote: source_list | Working note frontmatter `source_list` contains source file path |
| Promote: promoted_to in source | Source file frontmatter updated with `promoted_to:` pointing to new working note |
| Promote: corrupted source | Creates working note with warning text; logs to `logs/script-errors.log`; exits 0 |
| List: empty folder | Prints "No working notes found"; exits 0 |
| List: overdue displayed red | Mocked file with past `review_trigger` shows `OVERDUE N days` |
| List: -Status filter | Only shows notes with matching status |
| List: -SortBy last_updated | Output order matches sort |
| Summary: no history | Prints "No git history found for this file" |

Run focused validation before marking done:
```powershell
Invoke-Pester tests\working-notes.Tests.ps1
```

### Out of scope for this story

- Wiki promotion from working notes (Epic 2, Story 2.1)
- File watcher / VS Code save hook for auto-updating `last_updated` on manual edits (optional integration; not required)
- `update-working-note.ps1` helper for updating `last_updated` on manual edits — defer unless time allows (not in AC)
- Importing AI conversations into raw layer (Epic 4)
- `knowledge/working/` subfolder support per project (Epic 5)

---

## Previous Story Intelligence

### From Story 1.2 (Inbox Triage Workflow) — directly applicable:

- PowerShell 5.1 `??` is NOT supported — verified again in Story 1.2; use `if/else` throughout
- Per-item `try/catch` pattern prevents one file failure from aborting a batch — apply this in `promote-to-working.ps1` when updating source frontmatter
- `[Environment]::UserInteractive` guard is mandatory before `Read-Host`
- Auto-create missing folder pattern: `if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }` — use same pattern before writing working notes (in case `knowledge/working/` was deleted)
- `Write-Log` third param is the log file path; default is `logs/script-errors.log`

### From Story 1.1 (Quick Knowledge Capture) — directly applicable:

- `Get-TimestampedFilename` in `common.ps1` handles kebab-case title sanitization — inspect it before reimplementing inline
- Template injection uses `.Replace()` not `-replace` to avoid regex backreference issues — **critical** for frontmatter manipulation
- `$PSScriptRoot` resolves `lib/` paths reliably
- Exit codes 0/1/2 are established; maintain them
- 11 pre-existing unrelated test failures exist in the full suite; run focused test, not `Invoke-Pester tests\`

### From Story 0.3 (Script Implementation):

- `triage.ps1` outer `try/catch` swallows all exceptions and exits 2 — this is startup-error-only; per-file errors need their own inner `try/catch`
- Git auto-commit is dot-sourced with graceful degradation: `if (Test-Path "$PSScriptRoot/lib/git-operations.ps1")`
- `Invoke-GitCommit` signature from git-operations.ps1: call by name with `-Message` and `-Files` params

### From Story 0.2 (Template System):

- `templates/working-note.md` uses `<title>`, `<timestamp>`, `<date>` placeholders — NOT `{{key}}` format
- Do NOT use `Get-Template` from `common.ps1` for working notes (it handles `{{key}}` only)
- Template status default is `"active"` — override to `"draft"` in `create-working-note.ps1`

### Template discrepancy — Epic vs. actual template:

The epic refers to a "Current Interpretation" section. The actual `templates/working-note.md` has **"What I Think"** instead. Use the template as-is. Do not add a "Current Interpretation" section.

---

## Definition of Done

- [x] `create-working-note.ps1` creates `knowledge/working/<kebab-title>.md` with `status: "draft"`, `confidence: "low"`, all required frontmatter fields, and all template sections
- [x] `create-working-note.ps1` prevents overwrite on duplicate title; suggests alternatives; offers to open existing in interactive mode
- [x] `promote-to-working.ps1` creates working note with source body in Evidence, source path in Source Pointers, `source_list` in frontmatter, and updates source file's `promoted_to` field
- [x] `promote-to-working.ps1` handles corrupted source gracefully: creates note with warning, logs error, exits 0
- [x] `list-working-notes.ps1` lists all working notes with title, status, confidence, last_updated, days-until-review; overdue shown in red
- [x] `list-working-notes.ps1` supports `-Status` filter and `-SortBy` sort parameter
- [x] `working-note-summary.ps1` outputs git history for the specified file; handles no-history case
- [x] All scripts follow PowerShell 5.1 compatibility (no `??`, no ternary `? :`, no `?.`)
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] Git auto-commit fires after `create-working-note.ps1` and `promote-to-working.ps1` success when the written files are inside the repo
- [x] `[Environment]::UserInteractive` guard wraps all `Read-Host` calls
- [x] Pester tests in `tests/working-notes.Tests.ps1` cover all required test cases and pass
- [x] Pre-existing full-suite failure count does not increase under the approved focused-story validation baseline

## Tasks / Subtasks

- [x] Task 1: Implement `scripts/create-working-note.ps1`
  - [x] Param block: `-Title` (required), `-Project` (optional), `-WhatIf` (optional switch)
  - [x] Standard script boilerplate (dot-source libs, load config, `Test-DirectoryStructure`)
  - [x] Kebab-case filename generation; duplicate detection + alternative suggestions
  - [x] Load template via `Get-Content` + `.Replace()` chain; set `status: "draft"`, `confidence: "low"`
  - [x] Calculate `review_trigger` from `$config.review_cadence.working_days` (default 30)
  - [x] Write file with `Set-Content -Encoding UTF8`; git auto-commit; print full path

- [x] Task 2: Implement `scripts/promote-to-working.ps1`
  - [x] Param block: `-SourceFile` (required), `-Title` (required), `-WhatIf` (optional switch)
  - [x] Validate source file exists; parse frontmatter + body; handle corruption gracefully
  - [x] Build working note with source body in Evidence and source path in Source Pointers
  - [x] Update source file `promoted_to` field via line-based frontmatter rewrite
  - [x] Duplicate title handling (same logic as Task 1)
  - [x] Write both files; git auto-commit; print created file path

- [x] Task 3: Implement `scripts/list-working-notes.ps1`
  - [x] Param block: `-Status` (optional), `-SortBy` (optional, valid: `last_updated`, `confidence`, `title`)
  - [x] Scan `knowledge/working/*.md`; parse frontmatter per file
  - [x] Calculate days-until-review; flag overdue in red
  - [x] Apply `-Status` filter; apply `-SortBy` sort
  - [x] Print tabular output; handle empty folder

- [x] Task 4: Implement `scripts/working-note-summary.ps1`
  - [x] Param block: `-File` (required — filename only, no path)
  - [x] Run git history against `knowledge/working/<file>`
  - [x] Print output; handle no-history case

- [x] Task 5: Verify `health-check.ps1` covers `knowledge/working/` staleness
  - [x] Inspect `health-check.ps1` for review_trigger scanning scope
  - [x] No change needed; working notes are already included in stale-content checks

- [x] Task 6: Write `tests/working-notes.Tests.ps1`
  - [x] All test cases from the Testing Requirements table above
  - [x] Run `Invoke-Pester tests\working-notes.Tests.ps1` and confirm pass

## File List

- `scripts/create-working-note.ps1` — NEW
- `scripts/promote-to-working.ps1` — NEW
- `scripts/list-working-notes.ps1` — NEW
- `scripts/working-note-summary.ps1` — NEW
- `tests/working-notes.Tests.ps1` — NEW
- `health-check.ps1` — POSSIBLE CHANGE (staleness scope only, if needed)

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6

### Debug Log References

- Focused validation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\working-notes.Tests.ps1"`

### Completion Notes List

- Added four new scripts for working-note creation, promotion, listing, and git-history summaries.
- Used the existing `templates/working-note.md` section names verbatim and loaded it via `Get-Content` plus `.Replace()` because the template uses `<...>` placeholders rather than `{{...}}`.
- Implemented duplicate-title protection with alternative suggestions and optional interactive open-existing behavior.
- Implemented promotion from inbox/raw with evidence population, `source_list`, and source-file `promoted_to` tracking; corrupted source frontmatter now degrades gracefully with a warning note and logged warning.
- Verified `health-check.ps1` already covers working-note staleness and `review_trigger`, so no health-check change was required.
- Added focused Pester coverage for all Story 1.3 behaviors and passed the full focused suite.

### File List

- `scripts/create-working-note.ps1` — NEW
- `scripts/promote-to-working.ps1` — NEW
- `scripts/list-working-notes.ps1` — NEW
- `scripts/working-note-summary.ps1` — NEW
- `tests/working-notes.Tests.ps1` — NEW

### Change Log

- 2026-04-23: Story created — ready-for-dev
- 2026-04-23: Implemented working-note creation, promotion, listing, and summary scripts
- 2026-04-23: Passed focused Story 1.3 validation and marked story done
