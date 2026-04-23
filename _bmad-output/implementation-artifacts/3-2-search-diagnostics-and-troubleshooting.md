# Story 3.2: Search Diagnostics & Troubleshooting

Status: done

## Story

As Reno,
I want to diagnose search misses with basic checks,
so that I can understand why expected content isn't found.

## Acceptance Criteria

**AC1 — Diagnostic mode triggered by `-Diagnose` flag**
Given I perform a search that returns fewer than 3 results OR I want explicit diagnostic output
When I run `.\scripts\search.ps1 -Query "search term" -Diagnose`
Then the system displays normal search results first, then enters diagnostic mode
And it performs a case-insensitive search across all active layers (wiki, working, raw, tasks)
And it searches for partial filename matches across all layer folders
And it reports total file count per knowledge layer for context

**AC2 — No-match diagnostics: archive suggestion and similar filenames**
Given search diagnostics find no exact matches
When the diagnostic runs
Then it suggests checking archived content with the exact command: `.\scripts\search.ps1 -Query "<term>" -Archive`
And it shows if similar filenames exist (Levenshtein edit distance < 3 between the query and any filename stem, case-insensitive)
And it reports if the search term appears in any frontmatter metadata field across all active layers

**AC3 — Searched folder inventory and frontmatter health**
Given I expect content to exist but cannot find it
When I run `.\scripts\search.ps1 -Query "term" -Diagnose`
Then the system shows each searched folder path and its file count
And it indicates if any files have missing or corrupted frontmatter (YAML parse failure or absent `---` block)
And it suggests alternative search terms based on similar existing filenames (edit distance < 3)

**AC4 — Actionable suggestions with exact commands**
Given diagnostics reveal potential matches or gaps
When the diagnostic analysis completes
Then I get specific actionable suggestions, each with an exact PowerShell command to run
And the archive suggestion is always included regardless of whether archive matches are found
And no machine learning or complex inference is used — all checks are deterministic file-system operations

## Tasks / Subtasks

- [x] Task 1: Add `-Diagnose` switch to `scripts/search.ps1` (AC: 1, 4)
  - [x] 1.1 Add `[switch]$Diagnose` to the existing `param(...)` block — insert after the existing `[int]$Open` param, before `[switch]$Help`
  - [x] 1.2 After the normal search result display (after `Show-SearchResults` or equivalent call), check `if ($Diagnose)` and call `Invoke-SearchDiagnostics`
  - [x] 1.3 Display a diagnostic section header: `Write-Host "--- Search Diagnostics for `"$Query`" ---" -ForegroundColor Cyan`
  - [x] 1.4 Diagnostic mode is always non-interactive — no prompts regardless of `$env:PINKY_FORCE_NONINTERACTIVE`

- [x] Task 2: Implement `Invoke-SearchDiagnostics` function (AC: 1, 2, 3, 4)
  - [x] 2.1 Add new function `Invoke-SearchDiagnostics` at the bottom of `search.ps1` (before the main entry-point block)
  - [x] 2.2 Accept params: `[string]$Query`, `[hashtable]$Config`, `[ordered]$LayerDefs`
  - [x] 2.3 Reuse `Get-LayerDefinitions` (already exists in `search.ps1`) to get all five layer paths including archive — diagnostic always scans archive
  - [x] 2.4 For each layer, collect all `.md` files recursively using `Get-ChildItem -Path $layerPath -Filter *.md -Recurse -ErrorAction SilentlyContinue`
  - [x] 2.5 Report layer file counts even when the layer folder does not exist (show `0 files` with a note)

- [x] Task 3: Case-insensitive partial filename matching (AC: 1, 3)
  - [x] 3.1 For each `.md` file across all layers, extract the filename stem: `[System.IO.Path]::GetFileNameWithoutExtension($file.Name)`
  - [x] 3.2 Strip leading date-timestamp prefix if present (pattern: `^\d{4}-\d{2}-\d{2}-\d{6}-` or `^\d{4}-\d{2}-\d{2}-`) before comparison
  - [x] 3.3 Perform case-insensitive substring match: `$stem.IndexOf($Query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0`
  - [x] 3.4 Report matching filenames with their layer label, up to 5 results per layer

- [x] Task 4: Implement `Get-LevenshteinDistance` helper (AC: 2, 3)
  - [x] 4.1 Check whether `scripts/lib/common.ps1` already defines a Levenshtein or edit-distance function — if it does, reuse it; do NOT duplicate
  - [x] 4.2 If not present in lib, add `Get-LevenshteinDistance` as a private function inside `search.ps1` (not exported to lib in this story)
  - [x] 4.3 Implementation: standard DP matrix, case-insensitive (lowercase both inputs before computing)
  - [x] 4.4 Compare cleaned query against each filename stem across all layers; collect where distance is strictly < 3
  - [x] 4.5 Display at most 5 similar filename suggestions with layer label, relative path, and computed distance

- [x] Task 5: Frontmatter metadata term scan (AC: 2)
  - [x] 5.1 Use `Get-FrontmatterData` from `scripts/lib/frontmatter.ps1` (dot-sourced at script top) — do NOT re-parse YAML manually
  - [x] 5.2 For each file in all active layers, call `Get-FrontmatterData -Path $file.FullName`
  - [x] 5.3 For each returned hashtable key-value pair, check if the query string appears (case-insensitive substring) in the string representation of the value; for array values check each element
  - [x] 5.4 Report: file path, layer label, and the frontmatter field name where the match was found — up to 5 results total
  - [x] 5.5 Files where `Get-FrontmatterData` returns `$null` — count as corrupted frontmatter (handled in Task 6), skip silently

- [x] Task 6: Report missing/corrupted frontmatter (AC: 3)
  - [x] 6.1 During the cross-layer scan (Task 2), track files where `Get-FrontmatterData` returns `$null`
  - [x] 6.2 Count corrupted files per layer; report the count in the folder inventory line
  - [x] 6.3 List up to 3 corrupted file paths per layer below the count
  - [x] 6.4 Do NOT modify any files — all diagnostic operations are strictly read-only

- [x] Task 7: Generate actionable suggestions (AC: 4)
  - [x] 7.1 Always include: "Check archived content: `.\scripts\search.ps1 -Query "$Query" -Archive`"
  - [x] 7.2 If similar filenames found in a specific layer, add a layer-targeted suggestion (e.g., `-Wiki`)
  - [x] 7.3 If frontmatter metadata matches found, add: "Try the matched title as query: `.\scripts\search.ps1 -Query "<matched_value>"`"
  - [x] 7.4 If corrupted frontmatter files found in any layer, add: "Fix missing metadata: `.\scripts\health-check.ps1 -Type metadata`"
  - [x] 7.5 Format suggestions as a numbered list; each command on its own indented line; use `Write-Host` (not `Write-Output`) to avoid pipeline pollution

- [x] Task 8: Create `tests/search-diagnostics.Tests.ps1` (AC: 1–4)
  - [x] 8.1 Test: `-Diagnose` switch causes diagnostic section to appear in terminal output
  - [x] 8.2 Test: file count per layer reported correctly (create temp fixture folders with known file counts)
  - [x] 8.3 Test: case-insensitive partial filename match finds files that exact-match search missed
  - [x] 8.4 Test: `Get-LevenshteinDistance` returns 0 for identical strings; correct distance for known pairs (e.g., "cat"/"bat"=1, "kitten"/"sitting"=3)
  - [x] 8.5 Test: similar filename suggestions appear when edit distance is 1 or 2; not when distance >= 3
  - [x] 8.6 Test: frontmatter metadata scan reports the correct field name
  - [x] 8.7 Test: corrupted frontmatter files (no `---` block) are counted without causing script errors; exit code 0
  - [x] 8.8 Test: archive suggestion is always present in diagnostic output regardless of results
  - [x] 8.9 Test: no knowledge files are modified during diagnostic run (check file mtimes before/after)

- [x] Task 9: Update sprint status (AC: none — housekeeping)
  - [x] 9.1 Set `3-2-search-diagnostics-and-troubleshooting` to `done` in `sprint-status.yaml` after dev completes

### Review Findings

- [x] [Review][Patch] Diagnostic mode never performs the required case-insensitive search across active layers; it only scans filename stems and frontmatter, so body-only misses are invisible to the diagnostics output. [scripts/search.ps1:619]
- [x] [Review][Patch] Similar filename suggestions do not provide the required alternative search term commands; the current suggestions just rerun the original query against a layer instead of suggesting the nearby filename term itself. [scripts/search.ps1:771]

## Dev Notes

### Critical: Surgical Extension Only — Do NOT Rewrite `search.ps1`

Story 3.1 fully implemented `scripts/search.ps1`. The file currently has:
- `param(...)` block with `-Wiki`, `-Working`, `-Raw`, `-Archive`, `-Tasks`, `-IncludeArchived`, `-CaseSensitive`, `-Open`, `-Help` switches
- `Get-RepoRoot`, `Test-ContainsValue`, `Get-QueryTokens`, `Get-LayerDefinitions`, `Resolve-SelectedLayers` functions
- Ranking algorithm (title +100, content +50, metadata +25), `Show-SearchResults`, open-result with broken link detection

**Add only:**
1. `[switch]$Diagnose` to the existing `param(...)` block
2. A conditional call `if ($Diagnose) { Invoke-SearchDiagnostics ... }` after normal results
3. `Invoke-SearchDiagnostics` function (new, at bottom of file)
4. `Get-LevenshteinDistance` function (only if not already in `scripts/lib/common.ps1`)

**Touch nothing else.** Do not refactor, rename, or restructure any existing function.

### Script Boilerplate (already in place — verify, do not re-add)

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(...)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/lib/common.ps1"
. "$PSScriptRoot/lib/config-loader.ps1"
. "$PSScriptRoot/lib/frontmatter.ps1"
```

Exit codes: `0` = success (even if no results or no matches), `1` = user/validation error, `2` = system error.
Diagnostic never exits with code 1 or 2 on empty results — empty is valid.

### Layer Definitions (inherit from Story 3.1 — do not redefine)

`Get-LayerDefinitions` already returns an `[ordered]@{}` with wiki, working, raw, archive, tasks.
Call it with `$Config` (loaded via `Get-Config`). Archive is always included in diagnostic scan even though it is excluded from default search results.

Tasks layer path: derived inside `Get-LayerDefinitions` as:
```powershell
$handoffFolder = if ($Config.folders.ContainsKey('handoffs')) { [string]$Config.folders.handoffs } else { ".ai/handoffs" }
$tasksPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($repoRoot, $handoffFolder))
```
Use the same `Get-RepoRoot` function already in the file.

### Levenshtein Distance Implementation

If `scripts/lib/common.ps1` does not already have this, add inside `search.ps1`:

```powershell
function Get-LevenshteinDistance {
    param([string]$A, [string]$B)
    $a = $A.ToLower(); $b = $B.ToLower()
    $m = $a.Length; $n = $b.Length
    $d = New-Object 'int[,]' ($m + 1), ($n + 1)
    for ($i = 0; $i -le $m; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $n; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $m; $i++) {
        for ($j = 1; $j -le $n; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $d[$i, $j] = [Math]::Min([Math]::Min($d[$i - 1, $j] + 1, $d[$i, $j - 1] + 1), $d[$i - 1, $j - 1] + $cost)
        }
    }
    return $d[$m, $n]
}
```

Threshold: **strictly less than 3** (`$dist -lt 3`). Compare query against the cleaned filename stem (strip `.md`, strip leading `YYYY-MM-DD-HHMMSS-` date prefix).

### Frontmatter Parsing

`Get-FrontmatterData` (from `scripts/lib/frontmatter.ps1`, established in Story 2.3) returns a `[hashtable]` or `$null` on failure. Do not re-parse YAML.

For array frontmatter values (e.g., `tags: [foo, bar]`), the returned value may be a `System.Collections.ArrayList` or `string[]`. Cast to array before iterating:
```powershell
$values = @($fm[$key])
foreach ($v in $values) { ... }
```

### Diagnostic Output Format

```
--- Search Diagnostics for "your query" ---

Layer File Counts:
  [WIKI]  12 files  ->  knowledge/wiki
  [WORK]   8 files  ->  knowledge/working
  [RAW]    5 files  ->  knowledge/raw
  [TASK]   3 files  ->  .ai/handoffs
  [ARCH]   4 files  ->  knowledge/archive

Case-Insensitive Filename Matches:
  [WIKI]  knowledge/wiki/your-query-topic.md

Similar Filenames (edit distance < 3):
  [WORK]  knowledge/working/your-query.md  (distance: 2)

Frontmatter Metadata Matches:
  [WIKI]  knowledge/wiki/related-page.md  (field: title)

Files with Missing/Corrupted Frontmatter:
  [RAW]  2 file(s) with unreadable frontmatter:
    knowledge/raw/2026-01-15-imported.md
    knowledge/raw/broken-note.md

Actionable Suggestions:
  1. Check archived content:
       .\scripts\search.ps1 -Query "your query" -Archive
  2. Wiki layer has similar filename — try:
       .\scripts\search.ps1 -Query "your query" -Wiki
  3. Fix missing metadata affecting search coverage:
       .\scripts\health-check.ps1 -Type metadata
```

Use `Write-Host` throughout. Cyan for the header; default colour for body. No `Write-Output` (avoids pipeline pollution when caller pipes).

### Scope Boundaries

**IN scope:**
- `[switch]$Diagnose` param addition to `scripts/search.ps1`
- `Invoke-SearchDiagnostics` function in `search.ps1`
- `Get-LevenshteinDistance` helper (in `search.ps1` unless already in `lib/common.ps1`)
- `tests/search-diagnostics.Tests.ps1` Pester test suite

**OUT of scope — do not implement:**
- AI handoff context generation (Story 3.3)
- Health check repairs (Epic 6)
- Modifying any knowledge or source files during diagnostics
- Fuzzy content matching beyond simple case-insensitive substring
- Search indexing, caching, or persistent diagnostic state
- Any ML, embedding, or non-deterministic inference

### Regression Guard

After changes, all existing test suites must pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\archive-content.Tests.ps1"
```

New suite:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search-diagnostics.Tests.ps1"
```

### References

- Active layer definitions and `Get-LayerDefinitions`: `scripts/search.ps1` lines 71–106 (Story 3.1)
- Script boilerplate and exit codes: `_bmad-output/implementation-artifacts/3-1-cross-layer-knowledge-search.md — Script Boilerplate`
- `Get-FrontmatterData`, `Get-FrontmatterValue`: `scripts/lib/frontmatter.ps1` (Story 2.3)
- Archive boundary (excluded from default search; always scan in diagnostics): `_bmad-output/implementation-artifacts/3-1-cross-layer-knowledge-search.md — AC5` and NFR-007
- FR-008: `_bmad-output/planning-artifacts/epics.md — Story 3.2 Acceptance Criteria`
- Config keys: `config/pinky-config.yaml` and `_bmad-output/implementation-artifacts/3-1-cross-layer-knowledge-search.md — Config Keys in Use`
- Story 2.3 archive boundary: `_bmad-output/implementation-artifacts/2-3-content-archival-system.md`

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search-diagnostics.Tests.ps1"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search.Tests.ps1"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\wiki-metadata.Tests.ps1"`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\archive-content.Tests.ps1"`

### Completion Notes List

- Added `-Diagnose` mode to `scripts/search.ps1` and kept the normal search path intact before running diagnostics.
- Implemented deterministic diagnostics for layer inventory, partial filename matches, edit-distance suggestions, frontmatter metadata matches, and unreadable frontmatter reporting across all layers including archive.
- Added numbered actionable follow-up commands, always including the archive search command, and kept diagnostics read-only against knowledge files.
- Added `tests/search-diagnostics.Tests.ps1` to cover diagnostics output, distance calculation, metadata scanning, corrupted frontmatter reporting, and no-write behavior.
- Resolved code review findings by adding explicit content-match diagnostics and generating alternative search-term commands from the similar filename suggestions.

### File List

- `scripts/search.ps1` — UPDATED
- `tests/search-diagnostics.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/3-2-search-diagnostics-and-troubleshooting.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED
