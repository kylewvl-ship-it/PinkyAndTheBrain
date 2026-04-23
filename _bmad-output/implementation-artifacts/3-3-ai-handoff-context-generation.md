# Story 3.3: AI Handoff Context Generation

Status: done

## Story

As Reno,
I want to generate focused context packages for AI sessions,
so that agents receive relevant background within token limits.

## Acceptance Criteria

**AC1 — Keyword/task-based content search and ranking**
Given I request context generation for a topic or task
When I run `.\scripts\generate-handoff.ps1 -Topic "keyword or task description"`
Then the script searches wiki, working notes, and raw folders for files matching the topic (case-insensitive substring match against filename stem and first paragraph)
And candidates are ranked: wiki results first, then working notes, then raw files
And archive is excluded from candidate selection
And files marked `private: true` or `exclude_from_ai: true` in frontmatter are excluded before ranking

**AC2 — Token-budgeted content assembly**
Given multiple relevant files are found
When the context package is assembled
Then wiki pages under 500 tokens are included in full; wiki pages at or above 500 tokens contribute only their first paragraph
And working notes contribute: first paragraph + all lines in `## Current Interpretation`, `## Evidence`, and `## Key Points` sections (first 3 non-empty lines of each)
And raw files contribute: title line + first paragraph only
And the assembler stops adding items when the running token total would exceed 3000 tokens
And token count is estimated as `[Math]::Ceiling($text.Length / 4)` (deterministic, not model-dependent)

**AC3 — Contradiction flagging**
Given assembled context includes multiple items
When two or more included items share the query keyword in their title or first heading AND have differing `confidence` or `status` frontmatter values (e.g., one `confidence: high` and another `confidence: low` or `status: needs_review`)
Then each affected item's block in the output is prefixed with `[CONFLICTING INFO]`
And if a working note's `## Tensions & Contradictions` section contains non-empty content, that item is prefixed with `[CONFLICTING INFO: see tensions section]`

**AC4 — Structured markdown output file**
Given the context package is assembled
When the handoff file is written
Then it is saved to `.ai/handoffs/handoff-YYYY-MM-DD-HHMMSS-<slug>.md` where slug is the first 30 characters of the topic with spaces replaced by hyphens
And the file structure is:
```
# AI Handoff Context: <Topic>

**Generated:** YYYY-MM-DD HH:MM
**Topic:** <topic>
**Project scope:** <project name or "all">
**Token budget used:** X / 3000

## Wiki Knowledge
...

## Working Notes
...

## Raw References
...

## Source File List
- <relative/path/to/file.md> [WIKI | X tokens]
- <relative/path/to/file.md> [WORK | X tokens]

## Token Summary
Total tokens used: X / 3000
Items included: N
Items excluded (budget): N
Items excluded (private): N
```
And the script prints the output file path and token summary to the console on completion

**AC5 — Project scope filter**
Given I want context scoped to a specific project
When I run `.\scripts\generate-handoff.ps1 -Topic "keyword" -Project "project-name"`
Then only files whose frontmatter `project` field matches the given project name (case-insensitive) are considered
And files with no `project` frontmatter field are excluded from scoped searches
And if `-Project` is omitted, all non-private files across all layers are candidates

## Tasks / Subtasks

- [x] Task 1: Create `scripts/generate-handoff.ps1` with boilerplate and params (AC: 1, 4, 5)
  - [x] 1.1 Add `[CmdletBinding(SupportsShouldProcess)]`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` at top
  - [x] 1.2 Dot-source: `. "$PSScriptRoot\lib\common.ps1"` and `. "$PSScriptRoot\lib\frontmatter.ps1"` — do NOT re-implement frontmatter parsing
  - [x] 1.3 Declare params: `[string]$Topic` (mandatory), `[string]$Project` (optional), `[switch]$Help`
  - [x] 1.4 Load config via `Get-Config`; derive layer paths from `$config.system.vault_root` and `$config.folders.*`
  - [x] 1.5 Guard: if `$Topic` is empty or whitespace, display usage and exit with code 1
  - [x] 1.6 Exit codes: `0` = success (even if zero candidates), `1` = user/validation error, `2` = system error

- [x] Task 2: Implement candidate discovery (AC: 1, 4, 5)
  - [x] 2.1 Define `Get-HandoffCandidates` function accepting `$Topic`, `$Project`, `$Config`
  - [x] 2.2 Scan each layer folder (`wiki`, `working`, `raw`) with `Get-ChildItem -Path $layerPath -Filter *.md -Recurse -ErrorAction SilentlyContinue`
  - [x] 2.3 For each file, call `Get-FrontmatterData` from `scripts/lib/frontmatter.ps1`; skip files where `private -eq $true` or `exclude_from_ai -eq $true`
  - [x] 2.4 If `-Project` supplied: skip files where frontmatter `project` field does not match (case-insensitive); files with no `project` field are also excluded
  - [x] 2.5 Match: case-insensitive substring check of `$Topic` against `[System.IO.Path]::GetFileNameWithoutExtension($file.Name)` and first paragraph of file content (first non-empty, non-frontmatter lines up to the first blank line)
  - [x] 2.6 Return ordered list: wiki matches first, then working, then raw — within each layer, sort by filename (alphabetical)
  - [x] 2.7 Do NOT call `search.ps1` as a subprocess; use the same direct `Get-ChildItem` pattern established in Stories 3.1 and 3.2

- [x] Task 3: Implement `Get-TokenEstimate` helper (AC: 2)
  - [x] 3.1 Function signature: `function Get-TokenEstimate { param([string]$Text); return [Math]::Ceiling($Text.Length / 4) }`
  - [x] 3.2 Place inside `generate-handoff.ps1` (not exported to lib in this story)
  - [x] 3.3 Use consistently for all budget math — no alternative estimation method

- [x] Task 4: Implement content extraction per layer (AC: 2)
  - [x] 4.1 Add `Get-WikiContent` function: read full file text (strip frontmatter block); if `Get-TokenEstimate($bodyText) -lt 500`, return full body; otherwise return first paragraph only
  - [x] 4.2 Add `Get-WorkingNoteContent` function: extract first paragraph; then scan for `## Current Interpretation`, `## Evidence`, `## Key Points` headings — collect up to 3 non-empty lines below each heading; concatenate with section label
  - [x] 4.3 Add `Get-RawContent` function: return `# <filename stem>` + first paragraph only
  - [x] 4.4 Strip frontmatter block (`---`…`---`) from all extracted content before token estimation

- [x] Task 5: Implement token-budgeted assembly (AC: 2, 3)
  - [x] 5.1 Add `Invoke-ContentAssembly` function accepting ranked candidates, config, topic
  - [x] 5.2 Iterate candidates in rank order; for each, estimate tokens; skip if running total + item tokens > 3000
  - [x] 5.3 Track: included list, excluded-by-budget list, excluded-by-private count
  - [x] 5.4 After assembling all included items, run `Test-ConflictingInfo` (see Task 6) on the included set
  - [x] 5.5 Accumulate results into `$wikiBlocks`, `$workingBlocks`, `$rawBlocks` lists with per-item token count

- [x] Task 6: Implement deterministic conflict detection (AC: 3)
  - [x] 6.1 Add `Test-ConflictingInfo` function accepting the included items list
  - [x] 6.2 Group included items that share the topic keyword in their filename stem (case-insensitive)
  - [x] 6.3 Within each group, check for confidence/status divergence: if any two items have different non-null `confidence` values (e.g., `high` vs `low`) OR one has `status: needs_review`, mark both with conflict flag
  - [x] 6.4 For working notes in the included set: if their extracted content block contains text from `## Tensions & Contradictions` section (non-empty after the heading), mark with `[CONFLICTING INFO: see tensions section]`
  - [x] 6.5 Conflict prefix applies to the rendered output block — prepend to the content block string before writing to file; do NOT modify source files

- [x] Task 7: Implement output file generation (AC: 4)
  - [x] 7.1 Add `Write-HandoffFile` function accepting assembled blocks, metadata, config
  - [x] 7.2 Derive output path: `.ai/handoffs/handoff-<YYYY-MM-DD-HHmmss>-<slug>.md`; slug = first 30 chars of `$Topic` with `[^a-zA-Z0-9]` replaced by `-`, lowercased
  - [x] 7.3 Ensure `.ai/handoffs/` directory exists (`New-Item -ItemType Directory -Force`)
  - [x] 7.4 Write file using `Set-Content -Path $outputPath -Value $content -Encoding UTF8`
  - [x] 7.5 Source File List section: paths relative to repo root; format: `- knowledge/wiki/my-page.md [WIKI | 312 tokens]`
  - [x] 7.6 Print to console: file path + token summary (use `Write-Host`, not `Write-Output`)

- [x] Task 8: Create `tests/generate-handoff.Tests.ps1` (AC: 1–5)
  - [x] 8.1 Test: private files (`private: true`) are never included regardless of topic match
  - [x] 8.2 Test: `exclude_from_ai: true` files are excluded
  - [x] 8.3 Test: wiki candidates rank before working, working before raw in output
  - [x] 8.4 Test: wiki page under 500 tokens → full body in output block
  - [x] 8.5 Test: wiki page at or above 500 tokens → only first paragraph in output block
  - [x] 8.6 Test: working note extraction includes lines from `## Current Interpretation` (up to 3 lines)
  - [x] 8.7 Test: total token usage does not exceed 3000 when many candidates exist
  - [x] 8.8 Test: `-Project "x"` excludes files without matching project tag; includes files with `project: x`
  - [x] 8.9 Test: conflict flag (`[CONFLICTING INFO]`) appears when two wiki items have differing confidence
  - [x] 8.10 Test: output file is written to `.ai/handoffs/` with correct filename pattern
  - [x] 8.11 Test: source file list in output contains relative paths and layer+token annotations
  - [x] 8.12 Test: no knowledge source files are modified during script execution (check mtimes)
  - [x] 8.13 Test: `Get-TokenEstimate` returns ceiling of length/4 for known strings
  - [x] 8.14 Test: exit code 0 when topic yields zero candidates (empty context is valid)
  - [x] 8.15 Test: exit code 1 when `-Topic` is empty or whitespace

- [x] Task 9: Update sprint status (AC: none — housekeeping)
  - [x] 9.1 Set `3-3-ai-handoff-context-generation` to `done` in `sprint-status.yaml` after dev completes

### Review Findings

- [x] [Review][Patch] Conflict detection ignored status divergence unless one item was explicitly `needs_review`, so AC3 was only partially implemented. Fixed by treating differing non-empty `status` values as conflicts and adding regression coverage for `draft` vs `verified`. [scripts/generate-handoff.ps1:297]

## Dev Notes

### New Script: `scripts/generate-handoff.ps1`

This is a **new script** — do not modify `scripts/search.ps1` or any other existing script. Story 3.1 and 3.2 extended `search.ps1`; this story adds a separate script.

### Script Boilerplate (must match established pattern exactly)

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)][string]$Topic,
    [string]$Project = "",
    [switch]$Help
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\frontmatter.ps1"
```

Exit codes: `0` = success, `1` = user/validation error, `2` = system error.
File writes: `Set-Content -Path $path -Value $content -Encoding UTF8` for output file.
No interactive prompts — this script is designed for non-interactive invocation.

### Layer Paths (derive from config — do NOT hardcode)

```powershell
$config = Get-Config
$vaultRoot = $config.system.vault_root          # "./knowledge"
$wikiPath   = Join-Path $vaultRoot $config.folders.wiki      # "./knowledge/wiki"
$workingPath = Join-Path $vaultRoot $config.folders.working  # "./knowledge/working"
$rawPath    = Join-Path $vaultRoot $config.folders.raw       # "./knowledge/raw"
```

Tasks layer (`.ai/handoffs/`) is the **output** destination, not a search layer for this story.
Archive is excluded from candidate search (not scanned at all).

### Config Keys Used

```
$config.system.vault_root              # "./knowledge"
$config.folders.wiki                   # "wiki"
$config.folders.working                # "working"
$config.folders.raw                    # "raw"
$config.ai_handoff.max_context_tokens  # 3000
$config.ai_handoff.max_wiki_tokens_per_page  # 500
$config.ai_handoff.exclude_private     # true
```

Token budget and per-page limit come from config — do not hardcode 3000 or 500.

### Frontmatter Access (do NOT re-parse YAML)

Use `Get-FrontmatterData` and `Get-FrontmatterValue` from `scripts/lib/frontmatter.ps1` (established in Story 2.3, used in Stories 3.1 and 3.2).

```powershell
$fm = Get-FrontmatterData -Path $file.FullName     # returns hashtable or $null
$isPrivate = Get-FrontmatterValue -Frontmatter $fm -Key 'private'   # returns value or $null
$confidence = Get-FrontmatterValue -Frontmatter $fm -Key 'confidence'
$project = Get-FrontmatterValue -Frontmatter $fm -Key 'project'
```

If `Get-FrontmatterData` returns `$null`, treat the file as having no metadata (no private flag, no project tag, no confidence). It is still a valid candidate unless `-Project` is specified (in which case exclude it since it has no project tag to match).

### Stripping Frontmatter from Content

After reading file content with `Get-Content -Path $file.FullName -Raw`, remove the frontmatter block before token estimation and inclusion:

```powershell
function Remove-Frontmatter {
    param([string]$Content)
    if ($Content -match '(?s)^---\r?\n.*?\r?\n---\r?\n(.*)$') { return $Matches[1].TrimStart() }
    return $Content
}
```

### Token Estimation

```powershell
function Get-TokenEstimate {
    param([string]$Text)
    return [Math]::Ceiling($Text.Length / 4)
}
```

This is the **only** token counting method. Do not use any other formula, external library, or model-dependent approach.

### First Paragraph Extraction

```powershell
function Get-FirstParagraph {
    param([string]$Body)
    $lines = $Body -split '\r?\n'
    $para = @()
    $started = $false
    foreach ($line in $lines) {
        if ($line.Trim() -eq '' -and $started) { break }
        if ($line.Trim() -ne '') { $started = $true; $para += $line }
    }
    return ($para -join "`n")
}
```

Skip heading lines (starting with `#`) at the very beginning when extracting first paragraph.

### Working Note Section Extraction

Target sections (case-insensitive heading match): `## Current Interpretation`, `## Evidence`, `## Key Points`.
Collect up to 3 non-empty, non-heading lines immediately following the heading, stopping at the next `##` heading.

### Output File Location

`.ai/handoffs/` is relative to the repo root (same as the tasks layer in Stories 3.1 and 3.2). Derive with:

```powershell
$repoRoot = Split-Path $PSScriptRoot -Parent
$handoffsDir = Join-Path $repoRoot ".ai\handoffs"
```

### Output File Format (exact structure)

```markdown
# AI Handoff Context: <Topic>

**Generated:** 2026-04-23 14:32
**Topic:** <topic>
**Project scope:** <project or "all">
**Token budget used:** 1842 / 3000

## Wiki Knowledge

### knowledge/wiki/my-page.md
<content block — full text if <500 tokens, first paragraph if >=500 tokens>

## Working Notes

### knowledge/working/my-note.md
<summary: first paragraph + Current Interpretation + Evidence lines>

## Raw References

### knowledge/raw/some-raw.md
<title + first paragraph>

## Source File List

- knowledge/wiki/my-page.md [WIKI | 312 tokens]
- knowledge/working/my-note.md [WORK | 187 tokens]

## Token Summary

Total tokens used: 499 / 3000
Items included: 2
Items excluded (token budget): 1
Items excluded (private): 0
```

Sections with no items (e.g., no raw matches found) are **omitted** from output — do not write empty sections.

### Conflict Detection Logic (deterministic)

After assembling `$includedItems`, run conflict check:

```powershell
# Group by: filename stem contains topic keyword
# Within group: check confidence divergence
$conflictGroup = $includedItems | Where-Object {
    [System.IO.Path]::GetFileNameWithoutExtension($_.Path).IndexOf($Topic, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}
if ($conflictGroup.Count -ge 2) {
    $confidenceValues = $conflictGroup | ForEach-Object { $_.Confidence } | Where-Object { $_ -ne $null } | Select-Object -Unique
    if ($confidenceValues.Count -gt 1 -or ($conflictGroup | Where-Object { $_.Status -eq 'needs_review' })) {
        # mark all in group with [CONFLICTING INFO] prefix
    }
}
```

For working notes: check if extracted content contains the text `## Tensions & Contradictions` followed by non-empty lines. If so, prefix with `[CONFLICTING INFO: see tensions section]`.

### Project-Scope Filtering Rules

| Condition | Result |
|-----------|--------|
| `-Project` not specified | include all non-private files |
| `-Project "x"` and file has `project: x` | include |
| `-Project "x"` and file has `project: y` | exclude |
| `-Project "x"` and file has no `project` field | exclude |
| `-Project "x"` and file has `project: [x, y]` (array) | include (check each element) |

For array `project` values, cast to `@($fm['project'])` before comparing (same pattern as Stories 3.1/3.2 for array frontmatter).

### Regression Guard

After implementation, all existing Pester suites must continue to pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search-diagnostics.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\archive-content.Tests.ps1"
```

New suite:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\generate-handoff.Tests.ps1"
```

`generate-handoff.ps1` must NOT import or modify `search.ps1`. It uses the same library helpers via dot-source but is fully independent.

### Scope Boundaries

**IN scope:**
- `scripts/generate-handoff.ps1` (new)
- `tests/generate-handoff.Tests.ps1` (new)
- Output to `.ai/handoffs/`

**OUT of scope — do not implement:**
- Modifying `scripts/search.ps1` or any existing script
- Search indexing, caching, or embedding-based matching
- AI/LLM inference inside the script
- Health check integration or repair actions
- Privacy audit commands (Story 5.1)
- Project/domain separation commands (Story 5.2)
- Any ML, embedding, or non-deterministic inference

### Example CLI Usage

```powershell
# Generate context for a topic
.\scripts\generate-handoff.ps1 -Topic "frontmatter validation"

# Scoped to a project
.\scripts\generate-handoff.ps1 -Topic "capture workflow" -Project "work"

# Show help
.\scripts\generate-handoff.ps1 -Help
```

### Project Structure Notes

- New files: `scripts/generate-handoff.ps1`, `tests/generate-handoff.Tests.ps1`
- Output destination: `.ai/handoffs/` (already exists per Story 0.1 setup)
- No changes to any file under `knowledge/` or `scripts/lib/`
- Alignment with `config/pinky-config.yaml` keys: `ai_handoff.max_context_tokens`, `ai_handoff.max_wiki_tokens_per_page`, `ai_handoff.exclude_private`

### References

- FR-013: `_bmad-output/planning-artifacts/epics.md — Story 3.3 Acceptance Criteria`
- Token budget config: `_bmad-output/planning-artifacts/epics.md — Story 0.4 Configuration` (`ai_handoff` section)
- Script boilerplate and exit codes: `_bmad-output/implementation-artifacts/3-1-cross-layer-knowledge-search.md — Script Boilerplate`
- `Get-FrontmatterData`, `Get-FrontmatterValue`: `scripts/lib/frontmatter.ps1` (Story 2.3)
- Layer paths and folder config: `config/pinky-config.yaml` and `_bmad-output/implementation-artifacts/3-1-cross-layer-knowledge-search.md — Config Keys in Use`
- Archive boundary (excluded): `_bmad-output/implementation-artifacts/3-1-cross-layer-knowledge-search.md — AC5`
- `.ai/handoffs/` directory: `_bmad-output/planning-artifacts/architecture.md — Agent Integration Architecture`
- Array frontmatter handling: `_bmad-output/implementation-artifacts/3-2-search-diagnostics-and-troubleshooting.md — Frontmatter Parsing`
- Privacy field conventions: `_bmad-output/planning-artifacts/epics.md — Story 5.1 and Story 4.2`

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/generate-handoff.ps1 -Topic 'topic'`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester 'tests\\generate-handoff.Tests.ps1'"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester 'tests\\search.Tests.ps1'"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester 'tests\\search-diagnostics.Tests.ps1'"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester 'tests\\wiki-metadata.Tests.ps1'"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester 'tests\\archive-content.Tests.ps1'"`

### Completion Notes List

- Added a new standalone `generate-handoff.ps1` workflow for token-budgeted AI context generation across wiki, working, and raw layers.
- Implemented deterministic filtering, ranking, conflict-prefix handling, project scoping, and structured handoff file output without touching source knowledge files.
- Added a dedicated Pester suite for Story `3.3` and fixed scalar-vs-array edge cases discovered during implementation.

### File List

- `scripts/generate-handoff.ps1` — NEW
- `tests/generate-handoff.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/3-3-ai-handoff-context-generation.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED
