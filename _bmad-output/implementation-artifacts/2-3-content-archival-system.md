# Story 2.3: Content Archival System

Status: done

## Story

As Reno,
I want to archive stale or replaced content with proper metadata,
so that outdated information doesn't pollute active knowledge while remaining accessible for history.

## Acceptance Criteria

**AC1 — Archive with required reason**
Given I identify content to archive (stale, replaced, low-confidence, no-longer-relevant, or duplicate)
When I run the archive workflow
Then I must provide a reason from the predefined categories
And I can optionally provide a replacement link
And the content is moved to `knowledge/archive/` with archive metadata written to its frontmatter

**AC2 — Replacement tracking**
Given content is archived with a `-ReplacedBy` link
When archival completes
Then the archived file's frontmatter includes `replaced_by` pointing to the replacement
And any updated references in other files include the replacement path or an inline archive notice

**AC3 — Reference discovery before archival**
Given I archive content that other files reference
When the archive workflow runs
Then I am shown all files in `knowledge/wiki/`, `knowledge/working/`, and `knowledge/raw/` that link to the target file
And no file is silently modified without my explicit choice

**AC4 — Reference handling choice**
Given reference files have been surfaced
When I am prompted per referencing file (or globally)
Then I can choose to update the reference (to point to replacement or mark as archived)
Or I can choose to leave it and have it recorded as an orphaned reference
And the archive script writes orphaned entries to `knowledge/archive/orphaned-refs.md`
And orphaned references are NOT automatically repaired

**AC5 — Frontmatter integrity after archival**
Given any wiki page is archived
Then its frontmatter contains all 7 required fields from Story 2.2
And `status` is set to `"archived"`
And `archived_date`, `archive_reason`, and `replaced_by` (empty string if not provided) are present

## Tasks / Subtasks

- [x] Task 1: Create `scripts/archive-content.ps1` (AC: 1, 2, 3, 4, 5)
  - [x] 1.1 Define script parameters: `-File` (required), `-Reason` (required), `-ReplacedBy` (optional), `-WhatIf`, `-Help`
  - [x] 1.2 Validate `-Reason` against predefined enum; exit code 1 on invalid reason
  - [x] 1.3 Validate target file exists and is within `knowledge/wiki/` or `knowledge/working/`
  - [x] 1.4 Resolve frontmatter functions: dot-source from `update-wiki-metadata.ps1` OR extract shared functions to `scripts/lib/frontmatter.ps1` — do NOT reimplement from scratch
  - [x] 1.5 Scan reference files: search `knowledge/wiki/`, `knowledge/working/`, `knowledge/raw/` for `[[filename]]`, `[[filename|alias]]`, and markdown link patterns pointing to target
  - [x] 1.6 Display reference list to user with index numbers
  - [x] 1.7 Prompt user per-reference (or global apply-all): `[U]pdate reference`, `[O]rphan (track for cleanup)`, `[S]kip`
  - [x] 1.8 If updating: replace link text with replacement path (if provided) or append inline archive notice `[ARCHIVED]`
  - [x] 1.9 If orphaning: append row to `knowledge/archive/orphaned-refs.md` (create file if absent)
  - [x] 1.10 Write archive metadata to frontmatter using `Set-FrontmatterField` (not string replacement): `status`, `archived_date`, `archive_reason`, `replaced_by`
  - [x] 1.11 Move file to `knowledge/archive/` using `Move-Item`; preserve original filename
  - [x] 1.12 Git auto-commit via `Invoke-GitCommit` (optional, same pattern as Story 2.1)
  - [x] 1.13 Non-interactive mode: honour `$env:PINKY_FORCE_NONINTERACTIVE`; default unattended behaviour = orphan all references

- [x] Task 2: Create `scripts/list-orphaned-refs.ps1` (AC: 4)
  - [x] 2.1 Read `knowledge/archive/orphaned-refs.md` and render as formatted table
  - [x] 2.2 Accept `-File` filter to show orphans for a specific archived file
  - [x] 2.3 No repair logic — read-only listing only

- [x] Task 3: Create `tests/archive-content.Tests.ps1` (AC: 1–5)
  - [x] 3.1 Test: invalid reason → exit code 1, no files moved
  - [x] 3.2 Test: valid reason + file move → file appears in `knowledge/archive/`, absent from source
  - [x] 3.3 Test: frontmatter contains `status: archived`, `archived_date`, `archive_reason`, `replaced_by` after move
  - [x] 3.4 Test: reference scan returns correct referencing files
  - [x] 3.5 Test: orphan choice appends correct row to `knowledge/archive/orphaned-refs.md`
  - [x] 3.6 Test: update-reference choice rewrites link in referencing file
  - [x] 3.7 Test: non-interactive mode defaults to orphan-all, no prompts

- [x] Task 4: Update sprint status (AC: none — housekeeping)
  - [x] 4.1 Set `2-3-content-archival-system` to `done` in `sprint-status.yaml` after dev completes

## Dev Notes

### Predefined Archive Reason Categories

Hardcode this enum in `archive-content.ps1`; do not read from config (keeps it simple and inspectable):

```
stale            # content no longer current
replaced         # superseded by newer content
low-confidence   # insufficient evidence
no-longer-relevant  # domain/project shift
duplicate        # merged into another page
```

### Frontmatter Fields Added by This Story

All written via `Set-FrontmatterField` (reused from Story 2.2):

| Field | Type | Notes |
|---|---|---|
| `status` | string | Set to `"archived"` — already a valid value per Story 2.2 |
| `archived_date` | ISO timestamp | `(Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")` |
| `archive_reason` | string | One of the enum values above |
| `replaced_by` | string | Path or `""` if not provided |

The 7 required wiki metadata fields from Story 2.2 must all remain present and valid after archival. Run `-Validate` logic from `update-wiki-metadata.ps1` pattern to verify before committing.

### Reference Scanning Patterns

Scan these patterns (case-insensitive) in all `.md` files under `knowledge/wiki/`, `knowledge/working/`, `knowledge/raw/`:

```
[[<stem>]]                  # Obsidian wikilink (no extension)
[[<stem>|<alias>]]          # Obsidian aliased wikilink
[<text>](<relative-path>)   # Markdown link, path ends with filename
```

`<stem>` = filename without `.md` extension. Derive stem from `-File` parameter before scanning.

Do NOT scan `knowledge/archive/` — files there are already archived.

### Orphaned Refs Log Format

File: `knowledge/archive/orphaned-refs.md`

```markdown
# Orphaned References Log

| Archived File | Referencing File | Linked As | Archived Date |
|---|---|---|---|
| wiki/old-topic.md | working/my-note.md | `[[old-topic]]` | 2026-04-23 |
```

Append rows; never rewrite existing rows. If file does not exist, create it with the header first.

### Shared Frontmatter Functions

`Set-FrontmatterField`, `Get-FrontmatterData`, `Get-FrontmatterValue`, `Get-SourceList`, `Set-SourceList` were implemented in `scripts/update-wiki-metadata.ps1` (Story 2.2). Do NOT reimplement them.

**Recommended approach:** extract these functions into `scripts/lib/frontmatter.ps1` and dot-source from both `update-wiki-metadata.ps1` and `archive-content.ps1`. This is a small, justified refactor — do not duplicate. If extraction is blocked, dot-source `update-wiki-metadata.ps1` directly (confirm it is safe to source without side-effects first).

### Script Boilerplate (from Story 2.1 — follow exactly)

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(...)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
# dot-source frontmatter lib or update-wiki-metadata
```

Exit codes: `0` = success or user-cancelled, `1` = user/validation error, `2` = system error.

All file writes: `Set-Content -Path $path -Value $content -Encoding UTF8`

Interactive guard: check `$env:PINKY_FORCE_NONINTERACTIVE` or `[Environment]::UserInteractive` before prompting.

Git auto-commit: `if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue)` — optional, same as Story 2.1.

### Scope Boundaries

- **IN scope**: archiving wiki and working-layer content; reference discovery and user-choice handling; orphan log maintenance; archive metadata
- **OUT of scope (do not implement)**:
  - Search/retrieval that excludes archived content — that is Epic 3 (Story 3.1)
  - Health-check integration — that is Epic 6
  - Bulk archive sweeps — that is Epic 6 monthly maintenance
  - Archive restoration / un-archive — not specified in this story

### Config Keys in Use (from prior stories)

```
$config.system.vault_root     # "./knowledge"
$config.folders.wiki          # "wiki"
$config.system.template_root  # "./templates"
```

No new config keys are required for this story.

### Project Structure Notes

- New script: `scripts/archive-content.ps1`
- New script: `scripts/list-orphaned-refs.ps1`
- New tests: `tests/archive-content.Tests.ps1`
- New log file: `knowledge/archive/orphaned-refs.md` (created on first orphan)
- Optional new lib: `scripts/lib/frontmatter.ps1` (extraction from 2.2)
- No changes to `knowledge/wiki/` or `knowledge/working/` folder structure

Files moved during execution go to `knowledge/archive/<original-filename>.md` — flat, no subfolder per layer. If naming collisions arise (same filename from different layers), prefix with layer: `wiki-<filename>.md`, `working-<filename>.md`.

### References

- Archive reason enum and AC: [Source: _bmad-output/planning-artifacts/epics.md — Story 2.3]
- Archive folder path: [Source: _bmad-output/planning-artifacts/architecture.md — Folder Structure]
- Frontmatter functions and 7 required fields: [Source: _bmad-output/implementation-artifacts/2-2-wiki-metadata-management.md]
- Script boilerplate and exit codes: [Source: _bmad-output/implementation-artifacts/2-1-wiki-promotion-workflow.md]
- Orphan detection concept: [Source: _bmad-output/planning-artifacts/architecture.md — Validation Rules]
- `status: "archived"` as valid metadata value: [Source: _bmad-output/implementation-artifacts/2-2-wiki-metadata-management.md — 7 Required Fields]

## Dev Agent Record

### Agent Model Used

gpt-5

### Debug Log References

- Red baseline: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\archive-content.Tests.ps1"` (failed before archive scripts existed)
- Focused validation: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\archive-content.Tests.ps1"` (passed: 6/6)
- Regression validation after shared-helper extraction: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"` (passed: 19/19)
- Focused code review: reviewed `scripts/archive-content.ps1`, `scripts/list-orphaned-refs.ps1`, `scripts/lib/frontmatter.ps1`, `scripts/update-wiki-metadata.ps1`, `tests/archive-content.Tests.ps1`, and Story 2.3 tracking updates; no confirmed findings

### Completion Notes List

- Implemented `scripts/archive-content.ps1` for archiving wiki and working-layer files with predefined reasons, replacement tracking, reference discovery, orphan logging, archive metadata, and git-backed commits.
- Implemented `scripts/list-orphaned-refs.ps1` as the read-only orphan log viewer with optional file filtering.
- Extracted shared frontmatter helpers into `scripts/lib/frontmatter.ps1` and updated `scripts/update-wiki-metadata.ps1` to consume them so Story 2.3 does not duplicate metadata logic.
- Added focused Pester coverage in `tests/archive-content.Tests.ps1` for invalid reasons, file moves, archive metadata, orphan/default handling, reference rewriting, orphan listing, and the git commit path.
- Ran focused regression on `tests/wiki-metadata.Tests.ps1` after the helper extraction; Story 2.2 behavior remains green.
- Ran a focused review pass on the Story 2.3 changes and found no confirmed issues requiring follow-up or Claude second-opinion review.

### File List

- `scripts/archive-content.ps1` — NEW
- `scripts/list-orphaned-refs.ps1` — NEW
- `scripts/lib/frontmatter.ps1` — NEW
- `scripts/update-wiki-metadata.ps1` — UPDATED
- `tests/archive-content.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/2-3-content-archival-system.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED
