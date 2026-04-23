# Story 2.2: Wiki Metadata Management

**Story ID:** 2.2  
**Epic:** 2 - Knowledge Quality & Promotion  
**Status:** done  
**Created:** 2026-04-23  

---

## User Story

As Reno,  
I want to mark wiki knowledge with comprehensive metadata and manage it over time,  
So that I can track status, confidence, sources, and review schedules for all wiki pages.

---

## Acceptance Criteria

### Scenario: Metadata validation on existing wiki page

- **Given** I have a wiki page in `knowledge/wiki/`
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -Validate`
- **Then** the script checks for all 7 required fields: `status`, `owner`, `confidence`, `last_updated`, `last_verified`, `review_trigger`, and `source_list`
- **And** it reports which required fields are missing or empty
- **And** it exits 0 with "All required metadata present" if everything is valid
- **And** it exits 1 with a specific list of missing/empty fields if validation fails
- **And** no files are modified

### Scenario: Update metadata fields

- **Given** I want to update one or more metadata fields on an existing wiki page
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -Status "verified" -Confidence "high"`
- **Then** the specified fields are updated in the frontmatter
- **And** `last_updated` is automatically set to the current ISO timestamp regardless of which fields changed
- **And** all other frontmatter fields and the page body are preserved unchanged
- **And** the script prints a summary of what changed and exits 0
- **And** the change is committed to Git with message `"Wiki metadata: updated my-topic.md"`

### Scenario: Mark wiki page as verified

- **Given** I have reviewed a wiki page and want to record verification
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -MarkVerified`
- **Then** `last_verified` is set to the current ISO timestamp
- **And** `last_updated` is set to the current ISO timestamp
- **And** `review_trigger` is reset to today + `review_cadence.wiki_days` (default 90 days)
- **And** the script prints `"Marked verified. Next review: YYYY-MM-DD"` and exits 0

### Scenario: Extend the review period

- **Given** a wiki page's `review_trigger` is approaching but the content is still valid
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -ExtendReview 30`
- **Then** `review_trigger` is extended by 30 days from the current `review_trigger` date (not from today)
- **And** `last_updated` is set to the current ISO timestamp
- **And** the script prints `"Review extended to: YYYY-MM-DD"` and exits 0
- **And** if `review_trigger` is empty or unparseable, extension is calculated from today instead, with a warning

### Scenario: Review queue — listing overdue and upcoming reviews

- **Given** I want to see which wiki pages are due for review
- **When** I run `.\scripts\list-wiki-reviews.ps1`
- **Then** I see all wiki pages where `review_trigger` is today or in the past, sorted by most-overdue first
- **And** each row shows: filename, title, confidence, status, review_trigger date, days overdue
- **And** pages with no `review_trigger` set are listed separately at the bottom with label `[NO TRIGGER SET]`
- **And** the script exits 0 (even if the list is empty)

- **Given** I want to see upcoming reviews as well
- **When** I run `.\scripts\list-wiki-reviews.ps1 -DaysAhead 14`
- **Then** I see all pages overdue PLUS pages whose `review_trigger` falls within the next 14 days
- **And** upcoming pages show days-until-due (positive number) rather than days-overdue

### Scenario: Add a source to the source list

- **Given** I want to add a new source reference to a wiki page
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -AddSource "knowledge/working/my-research.md"`
- **Then** the value is appended to the `source_list` array in frontmatter if not already present
- **And** the script checks accessibility of the added source:
  - For local file paths: `Test-Path` is used; missing file prints `WARNING: Source not found: <path>`
  - For strings starting with `http://` or `https://`: format is accepted as-is (no HTTP request); prints `NOTE: URL source added — verify it is still accessible`
  - For other strings: accepted as-is (e.g., "Book: Title by Author")
- **And** `last_updated` is set to the current ISO timestamp
- **And** the script commits with message `"Wiki metadata: updated source list in my-topic.md"`

### Scenario: Remove a source from the source list

- **Given** I want to remove a source reference from a wiki page
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -RemoveSource "knowledge/working/old-research.md"`
- **Then** the matching entry is removed from `source_list`
- **And** if the value is not found in `source_list`, the script warns: `WARNING: Source not found in list: <value>` and exits 0 without modifying the file

### Scenario: Source validation on existing source list

- **Given** a wiki page has a `source_list` with one or more entries
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -ValidateSources`
- **Then** every entry in `source_list` is checked for accessibility using the same rules as `-AddSource`
- **And** the script reports: accessible sources (no output), missing local paths (WARNING), and URL entries (NOTE: not verified)
- **And** the script exits 0 if no broken local paths are found, exits 1 if one or more local paths are missing
- **And** no files are modified by this check

### Scenario: Missing required fields on existing wiki page

- **Given** a wiki page is missing one or more required metadata fields (e.g., created before Story 2.2)
- **When** I run `.\scripts\update-wiki-metadata.ps1 -File "knowledge/wiki/my-topic.md" -Status "draft"`
- **Then** the update proceeds normally for the fields specified
- **And** after the update, if any of the 7 required fields are still absent, the script prints: `NOTICE: Page is missing required fields: <field1>, <field2>. Run with -Validate to see full report.`
- **And** the script still exits 0 (the update succeeded; the notice is informational)

### Error Scenario: File not found or not in wiki folder

- **Given** I provide a path that does not exist or is not under `knowledge/wiki/`
- **When** the script validates the input
- **Then** it prints `ERROR: File not found or not a wiki page: <path>`
- **And** exits 1 without making any changes

### Error Scenario: Corrupted frontmatter

- **Given** the target wiki page has no frontmatter block (no opening `---` delimiter or no closing `---`)
- **When** the script tries to parse it
- **Then** it prints `ERROR: Cannot parse frontmatter in <path>. File may be corrupted.`
- **And** exits 1 without making any changes

---

## Technical Requirements

### New scripts

Two files are NET NEW for this story:

```
scripts/
  update-wiki-metadata.ps1    # NEW — metadata update, validation, source management
  list-wiki-reviews.ps1       # NEW — review queue listing
tests/
  wiki-metadata.Tests.ps1     # NEW — Pester coverage
```

No existing scripts require modification.

### Script boilerplate — follow exactly

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

Reference pattern: `capture.ps1`, `triage.ps1`, `create-working-note.ps1`, `promote-to-wiki.ps1` — all follow this exactly.

### Parameters — `update-wiki-metadata.ps1`

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$File,
    [string]$Status,
    [string]$Confidence,
    [string]$Owner,
    [string]$ReviewTrigger,   # date string YYYY-MM-DD
    [switch]$MarkVerified,
    [int]$ExtendReview,       # days to extend
    [string[]]$AddSource,
    [string[]]$RemoveSource,
    [switch]$ValidateSources,
    [switch]$Validate,
    [switch]$WhatIf,
    [switch]$Help
)
```

### Parameters — `list-wiki-reviews.ps1`

```powershell
param(
    [int]$DaysAhead = 0,
    [switch]$All,     # show ALL wiki pages regardless of review_trigger date
    [switch]$Help
)
```

### The 7 required wiki metadata fields (FR-006)

```
status         — valid values: "draft", "verified", "needs_review", "archived"
owner          — non-empty string (default "Reno" per template)
confidence     — valid values: "low", "medium", "high"
last_updated   — ISO timestamp (managed automatically)
last_verified  — ISO timestamp or empty string (empty is valid — means never verified)
review_trigger — date YYYY-MM-DD or empty
source_list    — array (empty array [] is valid)
```

`last_updated` is ALWAYS set by the script when any change is written. It is never set by the user directly via parameter.

### Frontmatter parsing — reuse the exact pattern from `promote-to-wiki.ps1`

Do NOT use `Get-Template` or any YAML library. Copy these helpers verbatim from `promote-to-wiki.ps1`:

```powershell
function Get-FrontmatterData {
    param([string]$Content)
    $normalized = $Content -replace "`r`n", "`n"
    if ($normalized -notmatch '(?s)^---\n(.*?)\n---\n?(.*)$') {
        return $null
    }
    return @{
        Frontmatter = $matches[1]
        Body        = $matches[2]
    }
}

function Get-FrontmatterValue {
    param([string]$Frontmatter, [string]$Key)
    $pattern = '(?m)^' + [regex]::Escape($Key) + '\s*:\s*["'']?(.+?)["'']?\s*$'
    $match = [regex]::Match($Frontmatter, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ""
}
```

### Frontmatter field update pattern

Use line-by-line rewrite (established in `promote-to-working.ps1` and reused in `promote-to-wiki.ps1`). To update a scalar field:

```powershell
function Set-FrontmatterField {
    param([string]$Frontmatter, [string]$Key, [string]$Value)
    $pattern = '(?m)^(' + [regex]::Escape($Key) + '\s*:\s*).*$'
    if ($Frontmatter -match $pattern) {
        return $Frontmatter -replace $pattern, "${Key}: `"$Value`""
    }
    # Field absent — append before the end of frontmatter lines
    return $Frontmatter + "`n${Key}: `"$Value`""
}
```

`last_updated` update at write time:

```powershell
$now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"
$frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Key 'last_updated' -Value $now
```

### source_list parsing and serialization

`source_list` uses YAML flow-sequence syntax: `source_list: []` or `source_list: ["a", "b"]`.

Read:
```powershell
function Get-SourceList {
    param([string]$Frontmatter)
    $pattern = '(?m)^source_list\s*:\s*\[(.*?)\]\s*$'
    $match = [regex]::Match($Frontmatter, $pattern)
    if (-not $match.Success) { return @() }
    $inner = $match.Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($inner)) { return @() }
    return ($inner -split ',') | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ -ne '' }
}
```

Write:
```powershell
function Set-SourceList {
    param([string]$Frontmatter, [string[]]$Sources)
    $encoded = ($Sources | ForEach-Object { '"' + $_ + '"' }) -join ', '
    $serialized = "source_list: [$encoded]"
    $pattern = '(?m)^source_list\s*:.*$'
    if ($Frontmatter -match $pattern) {
        return $Frontmatter -replace $pattern, $serialized
    }
    return $Frontmatter + "`n$serialized"
}
```

### Source accessibility validation logic

```powershell
function Test-SourceAccessibility {
    param([string]$Source)
    # URLs: accept format only (no HTTP request — local-first system)
    if ($Source -match '^https?://') {
        Write-Host "NOTE: URL source added — verify it is still accessible: $Source"
        return $true
    }
    # Local paths
    if (Test-Path $Source) { return $true }
    # Try relative to vault root
    $vaultPath = Join-Path $config.system.vault_root $Source
    if (Test-Path $vaultPath) { return $true }
    Write-Host "WARNING: Source not found: $Source"
    return $false
}
```

Call this for every entry in `-AddSource` and for every local-path entry during `-ValidateSources`. For `-ValidateSources`, collect broken paths and exit 1 if any broken.

### Review trigger date arithmetic

```powershell
# Get wiki_days from config with fallback
$reviewDays = 90
if ($config.review_cadence -and $config.review_cadence.ContainsKey('wiki_days') -and $config.review_cadence.wiki_days -gt 0) {
    $reviewDays = $config.review_cadence.wiki_days
}

# For -MarkVerified: reset from today
$newTrigger = (Get-Date).AddDays($reviewDays).ToString("yyyy-MM-dd")

# For -ExtendReview: extend from current trigger date (fallback to today on parse failure)
$currentTrigger = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'review_trigger'
$baseDate = $null
if (-not [datetime]::TryParse($currentTrigger, [ref]$baseDate)) {
    Write-Host "WARNING: Could not parse current review_trigger '$currentTrigger'. Extending from today."
    $baseDate = Get-Date
}
$newTrigger = $baseDate.AddDays($ExtendReview).ToString("yyyy-MM-dd")
```

### Interactive guard — use the same pattern as Story 2.1

Copy `Test-WikiInteractive` verbatim from `promote-to-wiki.ps1`:

```powershell
function Test-WikiInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }
    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}
```

`update-wiki-metadata.ps1` and `list-wiki-reviews.ps1` do not prompt the user, so this function is not strictly needed — but include it for consistency with the lib pattern in case future prompts are added.

### Git auto-commit

```powershell
if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
    $repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $relPath   = Get-RelativeRepoPath -Path $filePath -RepoRoot $repoRoot
    Invoke-GitCommit -Message ("Wiki metadata: updated $([System.IO.Path]::GetFileName($filePath))") `
                     -Files @($relPath) -RepoPath $repoRoot | Out-Null
}
```

Copy `Get-RelativeRepoPath` verbatim from `promote-to-wiki.ps1`. Git commit fires only when files are actually written (not on `-Validate`, `-ValidateSources`, or `-WhatIf`).

### Architecture compliance

- PowerShell 5.1 — no `??`, no `? :`, no `?.`; use explicit `if/else` throughout
- All file writes: `Set-Content -Path $path -Value $content -Encoding UTF8`
- Logging: `Write-Log` from `scripts/lib/common.ps1`
- Exit codes: 0 = success or clean validation pass, 1 = user error (bad input, validation failed, source broken), 2 = system error (config load failure)
- `$PSScriptRoot` for all lib path resolution
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at script top

### File structure

```
scripts/
  update-wiki-metadata.ps1   # NEW
  list-wiki-reviews.ps1      # NEW
tests/
  wiki-metadata.Tests.ps1    # NEW
```

No changes to: `promote-to-wiki.ps1`, `health-check.ps1`, `capture.ps1`, `triage.ps1`, `common.ps1`, `config-loader.ps1`, `git-operations.ps1`, or any other existing script.

---

## Testing Requirements

Follow the exact test file structure from `tests/wiki-promotion.Tests.ps1` — same `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"` conventions.

New test file: `tests/wiki-metadata.Tests.ps1`

**Required test cases:**

| Test | What to verify |
|------|----------------|
| Validate: all fields present | `-Validate` exits 0 when all 7 required fields are present |
| Validate: missing fields | `-Validate` exits 1 and lists missing field names |
| Update: status changed | `status:` updated in frontmatter |
| Update: confidence changed | `confidence:` updated in frontmatter |
| Update: last_updated auto-set | `last_updated` is always set to current timestamp on any write |
| Update: body preserved | Page body content unchanged after frontmatter update |
| MarkVerified: last_verified set | `last_verified` = current ISO timestamp |
| MarkVerified: review_trigger reset | `review_trigger` = today + 90 days |
| ExtendReview: trigger extended | `review_trigger` extended by N days from current trigger date |
| ExtendReview: fallback to today | If `review_trigger` empty, extends from today with warning |
| AddSource: entry appended | New value appears in `source_list` |
| AddSource: local path missing | WARNING printed for non-existent local path |
| AddSource: URL accepted | NOTE printed, URL added to source_list |
| AddSource: duplicate not added twice | Adding same source twice results in one entry |
| RemoveSource: entry removed | Value removed from `source_list` |
| RemoveSource: not found warning | Warning printed when value not in list; no file change |
| ValidateSources: broken local path | Exits 1 when a local source path does not exist |
| ValidateSources: no file modification | No file written during source validation |
| WhatIf: no files written | Prints intended action, exits 0 without modifying files |
| File not found | Exits 1 with clear error |
| Corrupted frontmatter | Exits 1 with parse error, no file written |
| list-wiki-reviews: overdue pages | Pages with past `review_trigger` appear sorted by most overdue |
| list-wiki-reviews: DaysAhead | Upcoming pages within window also appear |
| list-wiki-reviews: no trigger | Pages missing `review_trigger` listed separately |
| Git commit fires | Git commit called after successful write (mock `Invoke-GitCommit` via env guard) |

Run focused validation before marking done:
```powershell
Invoke-Pester tests\wiki-metadata.Tests.ps1
```

---

## Previous Story Intelligence (Story 2.1)

Directly applicable from `promote-to-wiki.ps1`:

- **`Get-FrontmatterData`** — copy verbatim; handles `\r\n` normalization
- **`Get-FrontmatterValue`** — copy verbatim for reading scalar fields
- **`Get-RelativeRepoPath`** — copy verbatim for git commit path building
- **`Test-WikiInteractive`** — copy verbatim for consistency
- **PowerShell 5.1**: `??` is NOT supported; use `if ($x) { $y } else { $z }` everywhere
- **Template placeholder syntax**: `<key>` not `{{key}}` — irrelevant here (no template loading), but do NOT call `Get-Template`
- **`source_list` is a YAML flow-sequence**: parse and write as `["a", "b"]` inline, not as YAML block sequence with `-` lines (the wiki-page template uses `source_list: []`)
- **`Invoke-GitCommit` signature**: `-Message`, `-Files`, `-RepoPath` — same as `promote-to-wiki.ps1`
- **Frontmatter field absent**: append the field before rebuilding the frontmatter block, not at the raw end of file
- **`Set-StrictMode -Version Latest`** + `$ErrorActionPreference = 'Stop'` catches PowerShell 5.1 issues early — leave these in
- **11 pre-existing unrelated test failures** exist in the full suite; run focused test only: `Invoke-Pester tests\wiki-metadata.Tests.ps1`

---

## Git Intelligence

All Epic 1 and Epic 2 Story 2.1 scripts were implemented following a consistent pattern:
- Single sprint commit: `feat(epic-N): complete <story-name>`
- Scripts use the standard boilerplate exactly
- Focused Pester tests run via `Invoke-Pester tests\<story>.Tests.ps1`
- No modifications to existing scripts in the same commit

Story 2.2 should follow the same approach: implement both scripts, write `wiki-metadata.Tests.ps1`, run focused Pester, mark done.

---

## Scope Boundaries

**In scope:**
- Reading and writing the 7 required frontmatter fields on existing wiki pages
- Automatic `last_updated` management on every write
- `-MarkVerified` and `-ExtendReview` for review trigger lifecycle
- `-AddSource` / `-RemoveSource` / `-ValidateSources` for source list management
- Local file path accessibility check (`Test-Path`)
- URL format acceptance (no HTTP requests)
- `list-wiki-reviews.ps1` review queue display
- Git auto-commit for all writes

**Explicitly out of scope for this story:**
- Fuzzy/edit-distance duplicate detection (Epic 6 health checks)
- Full-text search or retrieval across knowledge layers (Epic 3)
- Content archival or archive metadata (Story 2.3)
- File-watcher / on-save hooks for automatic `last_updated` (optional integration, not MVP)
- HTTP accessibility checks for URL sources (local-first; format validation only)
- AI handoff context generation or confidence-based filtering (Epic 3)
- Bulk metadata repair across all wiki pages (Epic 6 / Story 7.2)
- Review queue integration with health-check report output (Story 6.1 / 7.2 will consume `review_trigger`)

---

## Definition of Done

- [x] `scripts/update-wiki-metadata.ps1` accepts `-File` (required) plus `-Status`, `-Confidence`, `-Owner`, `-ReviewTrigger`, `-MarkVerified`, `-ExtendReview`, `-AddSource`, `-RemoveSource`, `-ValidateSources`, `-Validate`, `-WhatIf`, `-Help`
- [x] `-Validate` exits 0 when all 7 required fields present; exits 1 with field list when missing
- [x] Any write operation automatically sets `last_updated` to current ISO timestamp
- [x] `-MarkVerified` sets `last_verified` and resets `review_trigger` to today + `wiki_days`
- [x] `-ExtendReview <N>` extends `review_trigger` by N days from current value (fallback to today with warning)
- [x] `-AddSource` appends to `source_list`, validates local path accessibility, accepts URLs with NOTE
- [x] `-RemoveSource` removes from `source_list`, warns if not found, makes no change
- [x] `-ValidateSources` checks all local path sources, exits 1 on any broken path, no file written
- [x] File not found or outside `knowledge/wiki/` exits 1
- [x] Corrupted frontmatter exits 1, no file written
- [x] Git auto-commit fires after any successful write
- [x] `scripts/list-wiki-reviews.ps1` shows overdue pages sorted by most-overdue first
- [x] `-DaysAhead <N>` includes upcoming pages within N days
- [x] Pages with no `review_trigger` listed separately
- [x] All scripts follow PowerShell 5.1 compatibility (no `??`, no ternary, no `?.`)
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] Pester tests in `tests/wiki-metadata.Tests.ps1` cover all required cases and pass
- [x] Pre-existing full-suite failure count does not increase under focused-story validation baseline

---

## Tasks / Subtasks

- [x] Task 1: Implement `scripts/update-wiki-metadata.ps1`
  - [x] Param block with all parameters listed above
  - [x] Standard boilerplate (dot-source libs, load config, `Test-DirectoryStructure`)
  - [x] File validation: exists, under `knowledge/wiki/`, parseable frontmatter
  - [x] Copy `Get-FrontmatterData`, `Get-FrontmatterValue`, `Get-RelativeRepoPath`, `Test-WikiInteractive` from `promote-to-wiki.ps1`
  - [x] Implement `Set-FrontmatterField` for scalar field updates
  - [x] Implement `Get-SourceList` and `Set-SourceList` for array field management
  - [x] Implement `Test-SourceAccessibility` for local path and URL handling
  - [x] `-Validate` path: check 7 required fields, report missing, exit 0 or 1
  - [x] `-ValidateSources` path: validate all source_list entries, no write, exit 0 or 1
  - [x] Field update path: apply `-Status`, `-Confidence`, `-Owner`, `-ReviewTrigger` changes
  - [x] `-MarkVerified` path: set `last_verified`, reset `review_trigger`
  - [x] `-ExtendReview` path: parse current trigger, add days, fallback to today with warning
  - [x] `-AddSource` path: append to source_list, validate accessibility
  - [x] `-RemoveSource` path: remove from source_list, warn if not found
  - [x] Post-update notice for still-missing required fields
  - [x] Set `last_updated` before every write
  - [x] Reconstruct and write frontmatter + body with `Set-Content -Encoding UTF8`
  - [x] Git auto-commit both files
  - [x] `-WhatIf` path: print intended changes, exit 0 without writing

- [x] Task 2: Implement `scripts/list-wiki-reviews.ps1`
  - [x] Param block: `-DaysAhead`, `-All`, `-Help`
  - [x] Standard boilerplate
  - [x] Scan `knowledge/wiki/*.md`, read `review_trigger` from each
  - [x] Separate files into: overdue, upcoming (within DaysAhead), no-trigger-set
  - [x] Sort overdue by days-overdue descending
  - [x] Print formatted table with filename, title, confidence, status, review_trigger, days
  - [x] Print `[NO TRIGGER SET]` section for pages missing review_trigger
  - [x] Exit 0

- [x] Task 3: Write `tests/wiki-metadata.Tests.ps1`
  - [x] All test cases from the Testing Requirements table above
  - [x] Run `Invoke-Pester tests\wiki-metadata.Tests.ps1` and confirm pass

---

## File List

- `scripts/update-wiki-metadata.ps1` — NEW
- `scripts/list-wiki-reviews.ps1` — NEW
- `tests/wiki-metadata.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/2-2-wiki-metadata-management.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED

---

## Dev Agent Record

### Agent Model Used

gpt-5

### Debug Log References

- Red baseline: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"` (failed before the new scripts existed)
- Focused validation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"` (passed: 19/19)
- Focused code review: reviewed `scripts/update-wiki-metadata.ps1`, `scripts/list-wiki-reviews.ps1`, `tests/wiki-metadata.Tests.ps1`, and Story 2.2 tracking updates; no confirmed findings

### Completion Notes List

- Implemented `scripts/update-wiki-metadata.ps1` for wiki metadata validation, field updates, review lifecycle actions, source-list management, and git-backed write tracking.
- Implemented `scripts/list-wiki-reviews.ps1` for overdue, upcoming, and no-trigger review queue reporting on existing wiki pages.
- Added focused Pester coverage in `tests/wiki-metadata.Tests.ps1` for validation, updates, source handling, review listing, WhatIf behavior, and the isolated git commit path.
- Kept Story 2.2 scoped to metadata management on existing wiki pages; no archival behavior, search/retrieval features, or bulk repair workflows were added.
- Ran a focused review pass after validation and found no confirmed issues requiring follow-up or Claude second-opinion review.

### Change Log

- 2026-04-23: Story created — ready-for-dev
- 2026-04-23: Implemented wiki metadata update and review-listing scripts with focused Pester coverage
- 2026-04-23: Passed focused validation and completed story review with no confirmed findings
