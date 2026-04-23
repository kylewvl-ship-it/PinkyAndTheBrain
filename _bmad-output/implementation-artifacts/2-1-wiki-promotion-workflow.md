# Story 2.1: Wiki Promotion Workflow

**Story ID:** 2.1
**Epic:** 2 - Knowledge Quality & Promotion
**Status:** done
**Created:** 2026-04-23

## User Story

As Reno,
I want to promote reviewed working knowledge into wiki-ready Markdown,
So that valuable insights become permanent, searchable knowledge.

## Acceptance Criteria

### Scenario: Duplicate detection during promotion

- **Given** I have a working note that I want to promote to wiki
- **When** I run `.\scripts\promote-to-wiki.ps1 -SourceFile "knowledge/working/my-topic.md"`
- **Then** the script scans `knowledge/wiki/*.md` for title and filename similarity to the working note's title
- **And** if potential duplicates are found, I am warned with the matching filenames
- **And** I am presented with choices: `[U]pdate existing`, `[M]erge — open both for manual merge`, `[C]reate new page`, `[Q]uit`
- **And** if I choose Update, the existing wiki page path is printed and the script exits 0 with message "Open the existing wiki page to update it manually"
- **And** if I choose Merge, both file paths are printed and the script exits 0 with message "Open both files to merge content manually"
- **And** if I choose Create, promotion continues to the next step

### Scenario: Successful wiki promotion

- **Given** I proceed with wiki promotion (no blocking duplicates, or user chose Create)
- **When** the promotion is processed
- **Then** a new wiki page is created at `knowledge/wiki/<kebab-title>.md` using `templates/wiki-page.md`
- **And** the wiki frontmatter fields are populated: `title`, `status: "draft"`, `owner: "Reno"`, `confidence` (from working note), `last_updated` (current ISO timestamp), `review_trigger` (today + `review_cadence.wiki_days` days, default 90), `source_list` (from working note `source_list`)
- **And** the wiki `## Sources` section contains the working note's `## Source Pointers` content verbatim
- **And** the working note `status` is updated to `"promoted"` and `promoted_to` is set to `"knowledge/wiki/<filename>.md"`
- **And** the script prints the created wiki page path and exits 0

### Scenario: Human approval gate

- **Given** the promotion is ready to write
- **When** running in interactive mode (`[Environment]::UserInteractive` is true and `PINKY_FORCE_NONINTERACTIVE` is not `"1"`)
- **Then** the script prints a summary of what will be created (wiki filename, source working note, source count)
- **And** prompts: `Promote to wiki? (y/N)`
- **And** if the user enters `N` or empty, the script exits 0 with message "Promotion cancelled — no files changed"
- **And** if the user enters `y`, promotion proceeds and files are written

### Scenario: Handling contradictions and uncertainties

- **Given** the working note has content in `## Tensions / Contradictions`
- **When** the wiki page is created
- **Then** the `## Contradictions / Caveats` section of the wiki page contains the working note's `## Tensions / Contradictions` content verbatim
- **And** the section is not empty (a placeholder comment `<!-- No contradictions recorded -->` is used only when the working note section is blank)
- **And** competing claims and their source references are preserved without auto-resolution
- **And** the working note's `confidence` level is carried into the wiki frontmatter unchanged

### Scenario: Source validation — insufficient sources

- **Given** the working note `source_list` is empty (`[]`) or has no entries
- **When** the promotion workflow runs
- **Then** the script warns: `Working note has no sources in source_list. Add sources before promoting.`
- **And** asks: `Save as draft wiki page for now? (y/N)` in interactive mode (non-interactive defaults to yes)
- **And** if yes, the wiki page is written with `status: "draft"` and a `<!-- REVIEW: No sources — add provenance before marking verified -->` comment prepended to `## Sources`
- **And** if no, the script exits 0 with message "Promotion deferred — add sources to the working note first"
- **And** any claim-like paragraphs in the working note body are preserved verbatim (the dev must not attempt to detect or flag individual unsupported claims in this story)

### Error Scenario: Corrupted or missing working note frontmatter

- **Given** the working note has missing or unparseable frontmatter (no opening `---` delimiter, or no closing `---` delimiter, or missing required fields)
- **When** I attempt promotion
- **Then** the script identifies which required fields are absent or unreadable
- **And** prints specific repair guidance, e.g.:
  ```
  ERROR: Working note frontmatter is missing required fields: title, confidence
  Repair template:
  ---
  title: "Your Title Here"
  status: "draft"
  confidence: "low"
  source_list: []
  promoted_to: ""
  ---
  ```
- **And** exits 1 (user error) without creating any wiki file or modifying the working note

### Error Scenario: Wiki folder inaccessible

- **Given** `knowledge/wiki/` does not exist or is not writable
- **When** the promotion attempts to create the wiki page
- **Then** the script prints a clear error: `ERROR: Wiki folder is inaccessible: <path>. Check folder permissions and disk space.`
- **And** saves a retry record to `.ai/handoffs/promote-retry-<timestamp>.md` containing: source working note path, intended wiki title, current ISO timestamp
- **And** exits 2 (system error) without modifying the working note

---

## Technical Requirements

### New script

Only one file is NET NEW for this story:

```
scripts/
  promote-to-wiki.ps1        # NEW
tests/
  wiki-promotion.Tests.ps1   # NEW
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

Reference: `capture.ps1`, `triage.ps1`, `create-working-note.ps1`, `promote-to-working.ps1` — all follow this pattern exactly.

### Parameters

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceFile,        # Path to working note
    [switch]$WhatIf,
    [switch]$Help
)
```

No `-Title` parameter: the wiki title is derived from the working note's frontmatter `title:` field.

### Template loading — use `.Replace()`, not `-replace`

The wiki-page template at `templates/wiki-page.md` uses `<title>`, `<timestamp>`, `<date>` placeholder syntax. Load and replace directly:

```powershell
$template = Get-Content (Join-Path $config.system.template_root "wiki-page.md") -Raw -Encoding UTF8
$template = $template.Replace('<title>', $wikiTitle)
$template = $template.Replace('<timestamp>', (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffZ"))
$template = $template.Replace('<date>', (Get-Date).AddDays($reviewDays).ToString("yyyy-MM-dd"))
```

Use `.Replace()` — not `-replace` — to avoid regex backreference issues (established pattern from Stories 0.3 and 1.3).

Do NOT use `Get-Template` from `common.ps1` — it handles `{{key}}` placeholders only.

### Wiki page template sections (authoritative — from `templates/wiki-page.md`)

```
## Summary
## Why It Matters
## Key Concepts
## Details
## Relationships
## Contradictions / Caveats
## Sources
```

Map working note content into wiki sections as follows:

| Working note section | → Wiki section |
|---|---|
| `## What I Think` | `## Summary` (primary content) |
| `## Evidence` | `## Details` (append after existing content) |
| `## Connections` | `## Relationships` |
| `## Tensions / Contradictions` | `## Contradictions / Caveats` |
| `## Source Pointers` | `## Sources` |
| `## Prompt / Trigger`, `## Open Questions`, `## Next Moves` | omit from wiki output |

Set the wiki `## Why It Matters` and `## Key Concepts` sections to placeholder text:
```markdown
## Why It Matters

<!-- Promoted from working note — fill in why this matters -->

## Key Concepts

<!-- Promoted from working note — fill in key concepts -->
```

### Frontmatter parsing

Use the same line-by-line regex scan established in Story 1.3 — no YAML library:

```powershell
function Get-FrontmatterValue {
    param([string]$Content, [string]$Key)
    $match = $Content | Select-String -Pattern "^$Key\s*:\s*[`"']?(.+?)[`"']?\s*$" -Multiline
    if ($match) { return $match.Matches[0].Groups[1].Value.Trim('"').Trim("'") }
    return ""
}
```

Required working note fields to validate before proceeding:
- `title` (non-empty)
- `status` (non-empty)
- `confidence` (non-empty)

If any are missing or the frontmatter block itself is absent, print repair guidance and exit 1.

### Duplicate detection

Scan `knowledge/wiki/*.md`. For each file, extract its frontmatter `title:` and compare to the working note title using case-insensitive equality and kebab-case filename comparison:

```powershell
$wikiKebab = ($wikiTitle -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '-+', '-').Trim('-').ToLower()
$existingKebab = [System.IO.Path]::GetFileNameWithoutExtension($wikiFile)
$duplicate = ($existingKebab -eq $wikiKebab) -or ($existingTitle -ieq $wikiTitle)
```

Collect all matches; present them all. Do not apply edit-distance fuzzy matching in this story (that belongs to Epic 3 / health-check fuzzy duplicate detection).

### Working note `status` and `promoted_to` update

After writing the wiki page, update the working note frontmatter using the same line-by-line rewrite pattern from `promote-to-working.ps1` (`Update-SourcePromotedTo`). Update two fields:

- `status:` → `"promoted"`
- `promoted_to:` → `"knowledge/wiki/<filename>.md"`

If either field is absent from the frontmatter, append it before the closing `---`.

### Filename generation for wiki pages

```powershell
$wikiKebab = $wikiTitle -replace '[^\w\s-]', '' -replace '\s+', '-' -replace '-+', '-'
$wikiKebab = $wikiKebab.Trim('-').ToLower()
$wikiFileName = "$wikiKebab.md"
$wikiPath     = Join-Path (Join-Path $config.system.vault_root $config.folders.wiki) $wikiFileName
```

Config path: `$config.folders.wiki` (value: `"wiki"`). Pattern matches `file_naming.wiki_pattern: "{title}"`.

If the wiki file already exists (and user chose Create after duplicate warning), append `-2`, `-3` etc. to find a free name.

### Review cadence

```powershell
$reviewDays = 90
if ($config.review_cadence -and $config.review_cadence.ContainsKey('wiki_days') -and $config.review_cadence.wiki_days -gt 0) {
    $reviewDays = $config.review_cadence.wiki_days
}
```

### Interactive guard — use the same pattern as Story 1.3

```powershell
function Test-WikiInteractive {
    if ([Environment]::GetEnvironmentVariable('PINKY_FORCE_NONINTERACTIVE') -eq '1') {
        return $false
    }
    return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
}
```

Wrap every `Read-Host` with `if (Test-WikiInteractive)`.

### Retry record format

When wiki folder is inaccessible, write `.ai/handoffs/promote-retry-<timestamp>.md`:

```markdown
---
type: promote-retry
created: <ISO timestamp>
source_file: <relative path to working note>
intended_title: <wiki title>
---

# Promotion Retry Record

Promotion of working note failed due to inaccessible wiki folder.

- Source: <working note path>
- Intended wiki title: <title>
- Attempted: <ISO timestamp>

Run `.\scripts\promote-to-wiki.ps1 -SourceFile "<path>"` again once the wiki folder is accessible.
```

### Git auto-commit

After successfully writing both the wiki page and the updated working note:

```powershell
if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $filesToCommit = @($wikiRepoPath, $sourceRepoPath)
    Invoke-GitCommit -Message ("Wiki: promoted from $([System.IO.Path]::GetFileName($SourceFile))") -Files $filesToCommit -RepoPath $repoRoot | Out-Null
}
```

Use the same `Get-RelativeRepoPath` helper pattern from `promote-to-working.ps1`.

### Architecture compliance

- PowerShell 5.1 — no `??`, no `? :`, no `?.`; use `if ($x) { $y } else { $z }` everywhere
- All file writes: `Set-Content -Path $path -Value $content -Encoding UTF8`
- Logging: `Write-Log` from `scripts/lib/common.ps1`
- Exit codes: 0 = success or user-cancelled, 1 = user error (bad args, frontmatter repair needed), 2 = system error (folder inaccessible, missing template)
- `[Environment]::UserInteractive` guard before every `Read-Host`
- `$PSScriptRoot` for all lib path resolution
- Auto-create missing `.ai/handoffs/` folder before writing retry record (same `New-Item -ItemType Directory -Force` pattern)

### File structure

```
scripts/
  promote-to-wiki.ps1         # NEW — all promotion logic
tests/
  wiki-promotion.Tests.ps1    # NEW — Pester coverage
```

No changes to: `capture.ps1`, `triage.ps1`, `common.ps1`, `config-loader.ps1`, `git-operations.ps1`, `promote-to-working.ps1`, `create-working-note.ps1`, `list-working-notes.ps1`, `health-check.ps1`

### Testing requirements

Follow the exact test file structure from `tests/working-notes.Tests.ps1` — same `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"` conventions.

New test file: `tests/wiki-promotion.Tests.ps1`

**Required test cases:**

| Test | What to verify |
|------|---------------|
| Promote: wiki created | `knowledge/wiki/<kebab-title>.md` created from valid working note |
| Promote: frontmatter fields | `status: "draft"`, `owner: "Reno"`, `confidence`, `last_updated`, `review_trigger`, `source_list` all present |
| Promote: review_trigger date | `review_trigger` = today + 90 days (or config value) |
| Promote: source_list preserved | Wiki `source_list` matches working note `source_list` |
| Promote: contradictions preserved | Working note `## Tensions / Contradictions` content appears in wiki `## Contradictions / Caveats` |
| Promote: working note updated | Working note `status: "promoted"` and `promoted_to:` pointing to new wiki page |
| Duplicate detection | Script outputs duplicate warning when wiki file with matching title already exists |
| Duplicate: non-interactive defaults to Create | With `PINKY_FORCE_NONINTERACTIVE=1`, no interactive prompt fires; script proceeds to approval step |
| Approval gate: non-interactive proceeds | With `PINKY_FORCE_NONINTERACTIVE=1`, promotion writes files without `Read-Host` |
| Source validation: empty source_list | Warns about missing sources; non-interactive saves as draft |
| Draft flag | Wiki page with `status: "draft"` and `<!-- REVIEW: No sources -->` comment when source_list is empty |
| Corrupted frontmatter | Prints repair guidance, exits 1, no wiki file created |
| Missing required field | Identifies specific missing field(s) in error output |
| Wiki folder missing | Creates retry record in `.ai/handoffs/`, exits 2 |
| WhatIf switch | Prints intended action, no files written, exits 0 |

Run focused validation before marking done:
```powershell
Invoke-Pester tests\wiki-promotion.Tests.ps1
```

### Out of scope for this story

- Automatic metadata management for existing wiki pages (Story 2.2)
- Archival behavior or archive workflow (Story 2.3)
- Search or retrieval across knowledge layers (Epic 3)
- Fuzzy/edit-distance duplicate detection (Epic 6 health checks)
- Updating `last_updated` on manual wiki edits via file watcher (optional hook, not required)
- `do_not_promote: true` enforcement: if the working note has `do_not_promote: true` in frontmatter, print a warning and exit 1 (this is within 2.1 scope as a guard; it is NOT the full privacy/exclusion system from Story 5.1)

---

## Previous Story Intelligence

### From Story 1.3 (Working Note Creation and Management) — directly applicable:

- PowerShell 5.1 `??` is NOT supported — verified through multiple stories; use `if/else` throughout
- Template placeholder syntax in `templates/working-note.md` (and `wiki-page.md`) is `<key>` not `{{key}}` — do NOT use `Get-Template`, load with `Get-Content` + `.Replace()`
- Duplicate-title protection pattern: `Get-AlternativeWorkingFileNames` — reuse or copy this inline for wiki filename conflict resolution
- `[Environment]::UserInteractive` + `PINKY_FORCE_NONINTERACTIVE` guard is mandatory before every `Read-Host`
- Frontmatter line-by-line rewrite pattern is in `promote-to-working.ps1:Update-SourcePromotedTo` — adapt for two-field update (`status` + `promoted_to`)
- `Invoke-GitCommit` signature: `-Message`, `-Files`, `-RepoPath` — same call pattern as `promote-to-working.ps1`
- `Get-RelativeRepoPath` helper for building repo-relative paths for git commit — copy from `promote-to-working.ps1`
- Auto-create missing folders: `if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }` — use before writing `.ai/handoffs/` retry record and wiki directory
- 11 pre-existing unrelated test failures exist in the full suite; run focused test only: `Invoke-Pester tests\wiki-promotion.Tests.ps1`

### From Story 0.3 (Script Implementation):

- Outer `try/catch` is for startup errors only; it is acceptable here since promotion is a single-file operation
- Git auto-commit is dot-sourced with graceful degradation: `if (Test-Path "$PSScriptRoot/lib/git-operations.ps1")`

### From Story 1.2 (Inbox Triage):

- `Write-Log` third param is the log file path; default is `logs/script-errors.log`

### Config keys for this story:

- `$config.system.vault_root` → `"./knowledge"`
- `$config.folders.wiki` → `"wiki"`
- `$config.folders.handoffs` → `".ai/handoffs"` (for retry record)
- `$config.system.template_root` → `"./templates"`
- `$config.review_cadence.wiki_days` → `90`
- `$config.file_naming.wiki_pattern` → `"{title}"`

---

## Git Intelligence

Recent commits show all four Story 1.3 scripts were implemented and tested in a single sprint:
- `feat(epic-1): complete working note creation and management`
- All scripts followed the boilerplate strictly
- `Set-StrictMode -Version Latest` + `$ErrorActionPreference = 'Stop'` caught several PowerShell 5.1 issues during development

Story 2.1 should follow the same implementation approach: implement the script fully, write focused Pester tests, run `Invoke-Pester tests\wiki-promotion.Tests.ps1`, mark done.

---

## Definition of Done

- [x] `scripts/promote-to-wiki.ps1` accepts `-SourceFile` (required) and `-WhatIf`, `-Help` switches
- [x] Script validates working note frontmatter and exits 1 with repair guidance when required fields (`title`, `status`, `confidence`) are missing or frontmatter block is absent
- [x] Duplicate detection scans `knowledge/wiki/` and surfaces user choice (Update / Merge / Create / Quit) in interactive mode; non-interactive defaults to Create
- [x] Human approval prompt fires in interactive mode before writing any files; non-interactive skips prompt and proceeds
- [x] Wiki page created at `knowledge/wiki/<kebab-title>.md` using `templates/wiki-page.md`
- [x] Wiki frontmatter populated: `title`, `status: "draft"`, `owner: "Reno"`, `confidence` (from working note), `last_updated`, `review_trigger` (today + `wiki_days`), `source_list` (from working note)
- [x] Working note `## Tensions / Contradictions` content appears verbatim in wiki `## Contradictions / Caveats`
- [x] Working note `## Source Pointers` content appears verbatim in wiki `## Sources`
- [x] Working note `status` updated to `"promoted"` and `promoted_to` set to `"knowledge/wiki/<filename>.md"` after successful promotion
- [x] Empty `source_list` triggers source warning; non-interactive saves draft with `<!-- REVIEW: No sources -->` comment
- [x] Wiki folder inaccessible → retry record written to `.ai/handoffs/promote-retry-<timestamp>.md`; exits 2; working note not modified
- [x] `WhatIf` switch prints intended action without writing files
- [x] Git auto-commit fires after successful promotion when files are inside the repo
- [x] All scripts follow PowerShell 5.1 compatibility (no `??`, no ternary `? :`, no `?.`)
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] Pester tests in `tests/wiki-promotion.Tests.ps1` cover all required test cases and pass
- [x] Pre-existing full-suite failure count does not increase under the approved focused-story validation baseline

## Tasks / Subtasks

- [x] Task 1: Implement `scripts/promote-to-wiki.ps1`
  - [x] Param block: `-SourceFile` (required), `-WhatIf` (optional switch), `-Help` (optional switch)
  - [x] Standard boilerplate (dot-source libs, load config, `Test-DirectoryStructure`)
  - [x] Read and validate working note frontmatter; exit 1 with repair guidance on missing fields
  - [x] `do_not_promote: true` guard: warn and exit 1
  - [x] Duplicate detection: scan `knowledge/wiki/` for title/filename match; present choices interactively (non-interactive: skip to Create)
  - [x] Source validation: warn if `source_list` is empty; offer draft save
  - [x] Human approval gate: interactive confirmation before writing
  - [x] Load wiki template via `Get-Content` + `.Replace()` chain; populate frontmatter and map sections
  - [x] Write wiki page with `Set-Content -Encoding UTF8`
  - [x] Update working note `status` → `"promoted"` and `promoted_to` → wiki path
  - [x] Git auto-commit both files
  - [x] Wiki folder inaccessible: write retry record; exit 2
  - [x] `WhatIf` path: print intended action, exit 0 without writes

- [x] Task 2: Write `tests/wiki-promotion.Tests.ps1`
  - [x] All test cases from the Testing Requirements table above
  - [x] Run `Invoke-Pester tests\wiki-promotion.Tests.ps1` and confirm pass

## File List

- `scripts/promote-to-wiki.ps1` — NEW
- `tests/wiki-promotion.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/2-1-wiki-promotion-workflow.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED

## Dev Agent Record

### Agent Model Used

gpt-5

### Debug Log References

- Red baseline: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-promotion.Tests.ps1"` (failed before `scripts/promote-to-wiki.ps1` existed)
- Focused validation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-promotion.Tests.ps1"` (passed: 12/12)
- Focused code review: reviewed `scripts/promote-to-wiki.ps1`, `tests/wiki-promotion.Tests.ps1`, and Story 2.1 tracking updates; no confirmed findings

### Completion Notes List

- Implemented `scripts/promote-to-wiki.ps1` for working-note to wiki promotion using the existing PowerShell-first script conventions.
- Added duplicate detection, interactive update/merge/create/quit branching, non-interactive default-create behavior, and pre-write approval gating.
- Preserved working-note confidence, contradictions, and source pointers in the generated wiki page while leaving Story 2.2 metadata automation out of scope.
- Added draft-save handling for missing `source_list`, `do_not_promote` blocking, frontmatter repair guidance, retry-record generation for inaccessible wiki folders, and `WhatIf` behavior.
- Added focused Pester coverage in `tests/wiki-promotion.Tests.ps1`; the Story 2.1 suite passes 12/12.
- Ran a focused review pass on the story changes and found no confirmed issues requiring follow-up or Claude second-opinion review.

### Change Log

- 2026-04-23: Story created — ready-for-dev
- 2026-04-23: Implemented wiki promotion script and focused Pester coverage
- 2026-04-23: Passed focused validation and completed story review with no confirmed findings
