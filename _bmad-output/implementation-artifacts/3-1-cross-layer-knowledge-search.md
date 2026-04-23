# Story 3.1: Cross-Layer Knowledge Search

Status: done

## Story

As Reno,
I want to search across wiki pages, working notes, raw logs, archive, and task files,
so that I can find relevant knowledge regardless of where it's stored.

## Acceptance Criteria

**AC1 — Cross-layer search with ranked results**
Given I perform a text search query
When I run `.\scripts\search.ps1 -Query "search term"`
Then results are returned from all active knowledge layers (wiki, working, raw, tasks)
And results are ranked: exact title match (score +100) > exact content match (score +50) > partial content match > metadata match (score +25 per matching field)
And each result shows: result number, layer indicator, title, filename, last modified date, and 2-line preview
And maximum 20 results are returned (from `$config.search.max_results`, default 20)
And archive is excluded from default results unless `--archive` switch is used

**AC2 — Layer indicators and layer-specific metadata**
Given search results include content from different knowledge layers
When results are displayed
Then each result is prefixed with its layer indicator: `[WIKI]`, `[WORK]`, `[RAW]`, `[ARCH]`, `[TASK]`
And wiki results show `confidence` from frontmatter if present (e.g., `[high]`)
And archived results show `archived_date` and `archive_reason` from frontmatter
And working note results show `status` from frontmatter (e.g., `draft`, `active`, `promoted`)

**AC3 — Layer filter switches**
Given I want to filter results by layer
When I use layer switches: `--wiki`, `--working`, `--raw`, `--archive`, `--tasks`
Then search returns results only from specified layers
And multiple layer switches can be combined (e.g., `--wiki --working`)
And `--archive` is the only way to include archived content in results
And archived content is never returned when no layer filter or `--archive` is omitted

**AC4 — Open result with highlighted content**
Given I select a result number to open
When I pass `-Open <result_number>` after a search (or combine with `-Query`)
Then the full file content is displayed in the terminal
And each line containing the search term has the term visually highlighted (coloured output)
And a source metadata block is shown above the content: layer, file path, last modified, and key frontmatter fields relevant to the layer
And internal links (`[[wikilink]]` and `[text](path)` patterns) are checked: missing targets are displayed as `[BROKEN LINK: target]` inline

**AC5 — Archive boundary preserved**
Given content has been archived by Story 2.3
When a default search (no `--archive` flag) is executed
Then zero archived files appear in results regardless of query relevance
And when `--archive` is explicitly passed, archived files appear with `[ARCH]` prefix and their `archive_reason` shown

## Tasks / Subtasks

- [x] Task 1: Refactor `scripts/search.ps1` to add layer switch params and boilerplate compliance (AC: 1, 2, 3, 5)
  - [x] 1.1 Add `[CmdletBinding(SupportsShouldProcess)]`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` at top — align with Story 2.3 boilerplate
  - [x] 1.2 Replace `-Layers` string param with individual switch params: `-Wiki`, `-Working`, `-Raw`, `-Archive`, `-Tasks` (keep `-Layers` as deprecated alias or remove per dev judgement; prefer switches)
  - [x] 1.3 Add `[TASK]` layer mapped to `.ai/handoffs/` directory; include `.md` files from that folder
  - [x] 1.4 Ensure archive layer is excluded by default; only included when `-Archive` switch is present or layer explicitly requested
  - [x] 1.5 Add layer-specific metadata display in `Show-SearchResults`: wiki confidence colour-coded, archive date+reason, working status field

- [x] Task 2: Implement open-result functionality (AC: 4)
  - [x] 2.1 Add `-Open <int>` parameter; requires `-Query` to be run first (pass both in one command or accept result index after prior search)
  - [x] 2.2 Implement `Show-FileContent` function: reads full file, writes lines to terminal; for lines matching query, use `Write-Host` with highlight colour (e.g., Yellow foreground)
  - [x] 2.3 Display source metadata block before content: `[LAYER] path/to/file | Last modified: YYYY-MM-DD | <layer-specific fields>`
  - [x] 2.4 Implement `Test-InternalLinks` function: scan content for `[[stem]]`, `[[stem|alias]]`, and `[text](relpath)` patterns; for each, check if target `.md` exists under `knowledge/`; replace missing targets inline with `[BROKEN LINK: stem]` in terminal output (do NOT modify the file)

- [x] Task 3: Create `tests/search.Tests.ps1` (AC: 1–5)
  - [x] 3.1 Test: default search returns results from wiki, working, raw, tasks; no archive results
  - [x] 3.2 Test: `-Archive` switch returns archived files with `[ARCH]` label
  - [x] 3.3 Test: `-Wiki` alone returns only wiki-layer results
  - [x] 3.4 Test: ranking — title match outranks content match outranks metadata match
  - [x] 3.5 Test: result count capped at 20 (or config value)
  - [x] 3.6 Test: wiki result shows `confidence` field; archived result shows `archive_reason`
  - [x] 3.7 Test: broken internal link detection marks missing targets correctly (does not modify file)

- [x] Task 4: Update sprint status (AC: none — housekeeping)
  - [x] 4.1 Set `3-1-cross-layer-knowledge-search` to `done` in `sprint-status.yaml` after dev completes
  - [x] 4.2 Set `epic-3` to `in-progress` in `sprint-status.yaml`

### Review Findings

- [x] [Review][Patch] Archive exclusion can be bypassed with `-IncludeArchived`, which violates the story rule that `-Archive` is the only way to include archived results. [scripts/search.ps1:13]
- [x] [Review][Patch] Partial title matches are scored above exact content matches, which breaks the required ranking order `exact title > exact content > partial content > metadata`. [scripts/search.ps1:209]

## Dev Notes

### Existing `scripts/search.ps1` — What to Preserve vs. Change

`search.ps1` was stubbed in Story 0.3 and has working logic for:
- `Get-LayerFolders` — maps layer names to paths (keep, extend with tasks layer)
- `Search-Files` — scoring loop with title/content/metadata matching (keep scoring logic, 100/50/25 weights)
- `Show-SearchResults` — coloured terminal output (keep structure, add layer-specific metadata display)
- Config integration via `Get-Config` from `scripts/lib/common.ps1`

**Do NOT rewrite from scratch.** Extend the existing file surgically.

### Script Boilerplate (from Story 2.3 — follow exactly)

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(...)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
```

Exit codes: `0` = success, `1` = user/validation error, `2` = system error.
Interactive guard: check `$env:PINKY_FORCE_NONINTERACTIVE` or `[Environment]::UserInteractive` before prompting.
File writes: `Set-Content -Path $path -Value $content -Encoding UTF8` (read-only in this story — no writes to knowledge files).

### Layer Definitions

| Switch | Label | Path | Notes |
|--------|-------|------|-------|
| `-Wiki` | `[WIKI]` | `$config.system.vault_root/$config.folders.wiki` | Confidence from frontmatter |
| `-Working` | `[WORK]` | `$config.system.vault_root/$config.folders.working` | Status from frontmatter |
| `-Raw` | `[RAW]` | `$config.system.vault_root/$config.folders.raw` | No layer-specific extra field |
| `-Archive` | `[ARCH]` | `$config.system.vault_root/$config.folders.archive` | Show `archived_date` + `archive_reason` |
| `-Tasks` | `[TASK]` | `.ai/handoffs/` | Relative to repo root, not vault_root |

Default (no switches): wiki + working + raw + tasks. Archive always excluded unless `-Archive` specified.

### Layer-Specific Metadata Display

In `Show-SearchResults`, after the title line, show one extra line of metadata per layer:

- `[WIKI]`: if `confidence` field present → `Confidence: high/medium/low` (colour: green/yellow/red)
- `[ARCH]`: `Archived: <archived_date> | Reason: <archive_reason>`
- `[WORK]`: `Status: <status>` (e.g., `draft`, `active`, `promoted`)
- `[RAW]`, `[TASK]`: no extra line

### Ranking Algorithm (preserve from existing implementation)

```
Title exact match:    +100
Content match:        +50
Metadata field match: +25 per field
```

Sort descending by score. Cap at `$MaxResults` (default: `$config.search.max_results` = 20).

### Broken Link Detection (Open Result)

Patterns to scan in displayed content (case-insensitive):
```
[[stem]]           → check knowledge/**/<stem>.md exists
[[stem|alias]]     → check knowledge/**/<stem>.md exists
[text](relpath)    → check relpath exists relative to repo root
```

Detection is display-only. Never modify the source file. Output broken links inline as:
```
[BROKEN LINK: stem]
```
in the terminal line where the link appears (replace the wikilink pattern in displayed output, not in file).

### Source Metadata Block (Open Result)

Display above file content when `-Open` is used:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[WIKI] knowledge/wiki/my-topic.md
Last modified: 2026-04-20 14:32
Confidence: high | Status: verified | Owner: Reno
Sources: 3 listed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Show only fields present in frontmatter; omit absent fields gracefully.

### Shared Library Usage

Dot-source in this order:
```powershell
. "$PSScriptRoot\lib\common.ps1"       # Get-Config, Write-Log, Show-Usage, Test-DirectoryStructure
. "$PSScriptRoot\lib\frontmatter.ps1"  # Get-FrontmatterData, Get-FrontmatterValue (from Story 2.3)
```

Use `Get-FrontmatterValue` (from `scripts/lib/frontmatter.ps1`, created in Story 2.3) to extract `confidence`, `status`, `archived_date`, `archive_reason`, `replaced_by` — do NOT re-parse YAML manually.

### Config Keys in Use

```
$config.system.vault_root     # "./knowledge"
$config.folders.wiki          # "wiki"
$config.folders.working       # "working"
$config.folders.raw           # "raw"
$config.folders.archive       # "archive"
$config.search.max_results    # 20
$config.search.include_archived  # false (default)
$config.search.case_sensitive    # false (default)
```

Tasks layer path is `.ai/handoffs/` relative to the repo root (not vault_root). Derive with:
```powershell
$tasksPath = Join-Path (Split-Path $PSScriptRoot -Parent) ".ai\handoffs"
```

### Scope Boundaries

**IN scope:**
- Extending `scripts/search.ps1` with layer switches, tasks layer, layer-specific metadata display
- Open-result display with highlighted terms, source metadata block, broken link detection
- Pester tests for the above

**OUT of scope — do not implement:**
- `--diagnose` flag or alias/canonical-name suggestions — that is Story 3.2
- AI handoff context generation — that is Story 3.3
- Health check integration or repair workflows — that is Epic 6
- Modifying source files during broken link detection
- Search indexing or persistent search state

### Example CLI Usage

```powershell
# Default search (wiki + working + raw + tasks)
.\scripts\search.ps1 -Query "PowerShell"

# Filter to wiki and working only
.\scripts\search.ps1 -Query "metadata" -Wiki -Working

# Include archive
.\scripts\search.ps1 -Query "old topic" -Archive

# Open result #2 from a search
.\scripts\search.ps1 -Query "frontmatter" -Open 2

# All layers including archive
.\scripts\search.ps1 -Query "review" -Wiki -Working -Raw -Archive -Tasks
```

### Regression Guard

After changes to `search.ps1`, verify:
1. `tests/search.Tests.ps1` passes (new)
2. Any existing Pester tests that exercise `search.ps1` still pass
3. `scripts/lib/frontmatter.ps1` was not modified (Story 2.2/2.3 regression)

Run regression baseline:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\archive-content.Tests.ps1"
```

### References

- Layer structure and folder paths: `_bmad-output/planning-artifacts/architecture.md — Folder Structure`
- AC and FR-007: `_bmad-output/planning-artifacts/epics.md — Story 3.1`
- Script boilerplate, exit codes, interactive guard: `_bmad-output/implementation-artifacts/2-3-content-archival-system.md — Script Boilerplate`
- `Get-FrontmatterValue`, `Get-FrontmatterData`: `scripts/lib/frontmatter.ps1` (Story 2.3)
- Config structure: `config/pinky-config.yaml`
- Archive boundary (excluded by default): `_bmad-output/planning-artifacts/epics.md — Story 2.3 AC` and NFR-007
- Tasks layer location `.ai/handoffs/`: observed repo structure

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search.Tests.ps1"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\archive-content.Tests.ps1"`

### Completion Notes List

- Added PowerShell-first layer switches for wiki, working, raw, archive, and tasks while preserving the tasks layer at `.ai/handoffs/`.
- Extended result rendering with layer-specific metadata, capped result output, and archive exclusion by default.
- Implemented `-Open` result rendering with source metadata, highlighted matching lines, and inline broken-link detection without modifying source files.
- Added Pester coverage for default layer search, archive inclusion rules, ranking behavior, result capping, metadata display, and broken-link rendering.
- Fixed review findings by making `-IncludeArchived` a deprecated no-op unless `-Archive` is explicitly selected and by sorting with match tiers so exact content stays above partial matches.

### File List

- `scripts/search.ps1` — UPDATED
- `tests/search.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/3-1-cross-layer-knowledge-search.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED
