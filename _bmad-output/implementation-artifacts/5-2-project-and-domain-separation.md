# Story 5.2: Project and Domain Separation

**Story ID:** 5.2
**Epic:** 5 - Privacy & Project Management
**Status:** done
**Created:** 2026-04-26

---

## User Story

As Reno,
I want to separate unrelated projects and learning domains during retrieval,
So that irrelevant knowledge doesn't contaminate my current work context.

---

## Acceptance Criteria

### Scenario: Tagging content with project and domain

- **Given** I create or edit any knowledge file
- **When** I set metadata in the frontmatter
- **Then** I can set `project: "work"` (single string) or `project: ["work", "research"]` (array) in the frontmatter
- **And** I can set `domain: "accounting"` or `domain: ["accounting", "tax"]` for broader topic categorization
- **And** I can set `shared: true` to explicitly mark files as cross-project references

### Scenario: Search with project scope

- **Given** I perform a search with project filter
- **When** I run `.\scripts\search.ps1 -Query "budget" -Project work`
- **Then** search results only include files where the `project` frontmatter field matches `work` (scalar string or array element)
- **And** files without a `project` field are excluded from scoped results
- **And** files with `shared: true` are included regardless of their project tag
- **And** I can combine project filter with layer flags: `.\scripts\search.ps1 -Query "budget" -Project work -Wiki`

### Scenario: Search with domain scope

- **Given** I perform a search with domain filter
- **When** I run `.\scripts\search.ps1 -Query "depreciation" -Domain accounting`
- **Then** search results only include files where the `domain` frontmatter field matches `accounting` (scalar or array)
- **And** files without a `domain` field are excluded from domain-scoped results
- **And** files with `shared: true` are included regardless of their domain tag

### Scenario: AI handoff with project scope

- **Given** I generate AI handoff context for a specific project
- **When** I run `.\scripts\generate-handoff.ps1 -Topic "quarterly review" -Project work`
- **Then** only files with matching `project` tag (or `shared: true`) are included in the context package
- **And** the handoff footer already shows `**Project scope:** work` (this behavior exists — must not be broken)
- **And** when I add `-Domain accounting`, only files matching both project AND domain are included

### Scenario: AI handoff with domain scope

- **Given** I generate AI handoff context with a domain filter
- **When** I run `.\scripts\generate-handoff.ps1 -Topic "tax notes" -Domain accounting`
- **Then** only files with matching `domain` tag (or `shared: true`) are included
- **And** the handoff footer shows `**Domain scope:** accounting` in addition to the project scope line

### Scenario: Project overview

- **Given** I want to see my project organization
- **When** I run `.\scripts\list-projects.ps1`
- **Then** I see all distinct project values with file counts (already works — must not be broken)
- **And** I see an `(untagged)` row at the bottom showing how many files have no `project` field
- **And** when I pass `-Domain`, I see domain values with file counts instead of project values

### Scenario: Bulk-assign project tags

- **Given** I want to tag untagged files in a folder
- **When** I run `.\scripts\manage-project-tags.ps1 -SetProject work -Folder "knowledge/inbox/work-notes"`
- **Then** all `.md` files in the specified folder that have no `project` value get `project: "work"` written to frontmatter
- **And** files that already have a `project` value are skipped (not overwritten)
- **And** each updated file is git-committed using `Invoke-GitCommit`
- **And** I can also pass `-SetDomain` to set the domain field by the same folder/pattern rules
- **And** `-WhatIf` prints the intended changes without writing

---

## Technical Requirements

### What already exists — do NOT reimplement

- `scripts/search.ps1` — has `-Project` param (line 7); filters at lines 302–308 using `Get-FrontmatterValue` (scalar only); this story makes it array-aware and adds `-Domain`
- `scripts/generate-handoff.ps1` — has `-Project` param with `Get-FrontmatterValues` (array-aware, lines 130–151) and project scope in footer; this story adds `-Domain` and `shared: true` bypass
- `scripts/list-projects.ps1` — lists projects with counts; works but reads scalar `project:` only; this story adds untagged count and `-Domain` flag
- `scripts/lib/frontmatter.ps1` — `Get-FrontmatterValue` (scalar), `Get-FrontmatterData`, `Set-FrontmatterField`
- `scripts/lib/common.ps1` — `Get-Config`, `Write-Log`, `Get-TimestampedFilename`
- `scripts/lib/config-loader.ps1` — `Read-YamlConfig`, `Merge-Config`, `Get-DefaultConfig`
- `scripts/lib/git-operations.ps1` — `Invoke-GitCommit`
- `scripts/manage-source-types.ps1` — **reference implementation** for new script boilerplate
- `scripts/privacy-audit.ps1` — **reference implementation** for bulk frontmatter update pattern (Story 5.1)
- Templates (`inbox-item.md`, `working-note.md`, `wiki-page.md`) — already have `project` field; `working-note.md` and `wiki-page.md` already have `domain` field
- `templates/inbox-item.md` — has `project` but NOT `domain` — this story adds `domain: ""`

### `Get-FrontmatterValues` — copy/reuse pattern

`Get-FrontmatterValues` is defined **inline in `generate-handoff.ps1`** (not in lib). For `search.ps1` and `manage-project-tags.ps1`, use the same pattern locally or extract to lib — do NOT import from generate-handoff.ps1 by dot-sourcing. Pattern:

```powershell
function Get-FrontmatterValuesLocal {
    param([string]$Frontmatter, [string]$Key)
    $value = Get-FrontmatterValue -Frontmatter $Frontmatter -Key $Key
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }
    $trimmed = $value.Trim()
    if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
        return @(($trimmed.Trim('[', ']') -split ',') |
            ForEach-Object { $_.Trim().Trim('"').Trim("'") } |
            Where-Object { $_ -ne '' })
    }
    return @($trimmed.Trim('"').Trim("'"))
}
```

### New files

```
scripts/
  manage-project-tags.ps1         # NEW — bulk-assign project/domain tags to untagged files
tests/
  manage-project-tags.Tests.ps1   # NEW — Pester coverage
```

### Modified files

```
templates/inbox-item.md           # ADD domain: "" after project field
scripts/search.ps1                # SURGICAL: array-aware project filter + add -Domain param
scripts/generate-handoff.ps1      # SURGICAL: add -Domain param + shared: true bypass
scripts/list-projects.ps1         # SURGICAL: add untagged count + -Domain flag
```

---

### Template change: `templates/inbox-item.md`

Add `domain: ""` immediately after the `project:` line:

```yaml
project: "{{project_name_optional}}"
domain: ""
```

Keep all other fields unchanged. Do not reformat or reorder.

---

### Script modification: `scripts/search.ps1`

**Change 1 — array-aware project filter:**

The existing filter at line ~306:
```powershell
if ($Project -and $frontmatterValues.project -ne $Project) {
    continue
}
```

Replace with (do NOT change any surrounding logic):
```powershell
if (-not [string]::IsNullOrWhiteSpace($Project)) {
    $projValues = Get-FrontmatterValuesLocal -Frontmatter $frontmatter -Key 'project'
    $isShared = (Get-FrontmatterValue -Frontmatter $frontmatter -Key 'shared') -eq 'true'
    if (-not $isShared) {
        $matchesProj = @($projValues | Where-Object {
            $_.Equals($Project, [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if (-not $matchesProj) { continue }
    }
}
```

**Change 2 — add `-Domain` param and filter:**

Add to the param block (after existing `-Project`):
```powershell
[string]$Domain = "",
```

In the same filtering section, immediately after the project filter block above:
```powershell
if (-not [string]::IsNullOrWhiteSpace($Domain)) {
    $domainValues = Get-FrontmatterValuesLocal -Frontmatter $frontmatter -Key 'domain'
    $isShared = (Get-FrontmatterValue -Frontmatter $frontmatter -Key 'shared') -eq 'true'
    if (-not $isShared) {
        $matchesDomain = @($domainValues | Where-Object {
            $_.Equals($Domain, [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if (-not $matchesDomain) { continue }
    }
}
```

Add the helper function `Get-FrontmatterValuesLocal` (see above) near the top of the file after the dot-source block.

Also add `-Domain` to the `Search-Files` function signature (line ~269) and pass it from the call site at line ~887:
```powershell
# Function signature addition:
[string]$Domain,
# Call site update:
$results = @(Search-Files -Layers $selectedLayers -Query $Query -Project $Project -Domain $Domain -CaseSensitive:$CaseSensitive -MaxResults $MaxResults)
```

Do NOT change result ranking, layer filtering, preview logic, or any other search behavior.

---

### Script modification: `scripts/generate-handoff.ps1`

**Change 1 — add `-Domain` param:**

Add to param block after `-Project`:
```powershell
[string]$Domain = "",
```

**Change 2 — add domain filter in `Get-HandoffCandidates`:**

The `Get-HandoffCandidates` function signature (line ~173) already has `-Project`. Add `-Domain`:
```powershell
param([string]$Topic, [string]$Project, [string]$Domain, [hashtable]$Config)
```

In the file-inclusion loop, after the existing project filter block (lines ~217–225), add:
```powershell
if (-not [string]::IsNullOrWhiteSpace($Domain)) {
    $domainValues = @(Get-FrontmatterValues -Frontmatter $frontmatter -Key 'domain')
    $isSharedForDomain = (Get-FrontmatterValue -Frontmatter $frontmatter -Key 'shared') -eq 'true'
    if (-not $isSharedForDomain) {
        $matchesDomain = @($domainValues | Where-Object {
            $_.Equals($Domain, [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if (-not $matchesDomain) { continue }
    }
}
```

**Change 3 — add `shared: true` bypass in existing project filter:**

The existing project filter (lines ~217–225) already skips files without matching project. Add shared bypass:
```powershell
if (-not [string]::IsNullOrWhiteSpace($Project)) {
    $isShared = (Get-FrontmatterValue -Frontmatter $frontmatter -Key 'shared') -eq 'true'
    if (-not $isShared) {
        if ($projectValues.Count -eq 0) { continue }
        $matchesProject = @($projectValues | Where-Object {
            $_.Equals($Project, [System.StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if (-not $matchesProject) { continue }
    }
}
```

**Change 4 — pass `-Domain` through call sites and show in footer:**

Update `Write-HandoffFile` signature to accept `[string]$Domain` and add to footer:
```powershell
"**Domain scope:** $(if ([string]::IsNullOrWhiteSpace($Domain)) { 'all' } else { $Domain })"
```

Update all call sites to pass `-Domain $Domain`. Do not change the token count, retrieval priority, or output structure.

---

### Script modification: `scripts/list-projects.ps1`

**Change 1 — array-aware project reading:**

The existing loop reads a single `project:` value. Replace the frontmatter reading section with array-aware parsing. Use the same pattern as `Get-FrontmatterValuesLocal` above — call it for each file and add all returned values to `$projectCounts`.

**Change 2 — add untagged count:**

Track whether each file had a tag while scanning (use a `[bool]$hasTag` per file). Accumulate a separate `$untaggedCount` counter incremented when `$hasTag` is false after frontmatter parsing. Do NOT compute untagged from `$totalFiles - sum($projectCounts)` — that breaks for multi-project files that would be counted multiple times.

After the sorted project list is printed:
```powershell
if ($untaggedCount -gt 0) {
    Write-Host "  (untagged)".PadRight($maxLen + 4) "$untaggedCount file(s)" -ForegroundColor DarkGray
}
```

**Change 3 — add `-Domain` switch:**

Add to param block:
```powershell
[switch]$Domain
```

When `-Domain` is set, scan for `domain:` field values instead of `project:` field values, using identical logic. The output header changes from `"PinkyAndTheBrain Projects"` to `"PinkyAndTheBrain Domains"`.

---

### Script: `scripts/manage-project-tags.ps1`

**Boilerplate — follow exactly (same pattern as `manage-source-types.ps1` and `privacy-audit.ps1`):**

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SetProject = "",
    [string]$SetDomain = "",
    [string]$Folder = "",
    [string]$Pattern = "*.md",
    [switch]$WhatIf,
    [switch]$Help
)
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

**Behavior:**

- Require at least one of `-SetProject` or `-SetDomain`; exit 1 with message if neither provided
- Require `-Folder`; validate it exists; exit 1 if not
- Collect all `.md` files matching `-Pattern` in `-Folder` (non-recursive by default)
- For each file:
  - Parse frontmatter using `Get-FrontmatterData`
  - Check if the target field (`project` or `domain`) already has a non-empty, non-`""` value
  - **Skip** files that already have a value — do not overwrite
  - For files without a value: use `Set-FrontmatterField` from `lib/frontmatter.ps1` to write the new value
  - Write back with `Set-Content -Path ... -Encoding UTF8`
  - If `-WhatIf`, print intended action and skip write
  - If git operations available, call `Invoke-GitCommit` per file:
    ```powershell
    Invoke-GitCommit -Message "project-tags: set project=$SetProject in $relPath" `
                     -Files @($relPath) -RepoPath $repoRoot | Out-Null
    ```
- Print summary: `Tagged 5 file(s). Skipped 3 file(s) (already tagged).`
- Exit 0

**PowerShell 5.1 constraints:** No `??`, no `? :`, no `?.` — explicit `if/else` throughout.

---

## Testing Requirements

Follow conventions from `tests/manage-source-types.Tests.ps1` and `tests/privacy-audit.Tests.ps1`:
- Use `$TestDrive` for isolated vault roots
- Set `$env:PINKY_VAULT_ROOT` and `$env:PINKY_FORCE_NONINTERACTIVE = "1"`
- Mock `Invoke-GitCommit` via env-guard pattern

New test file: `tests/manage-project-tags.Tests.ps1`

**Required test cases — `manage-project-tags.Tests.ps1`:**

| Test | What to verify |
|------|----------------|
| `-SetProject` tags untagged file | File gets `project: "work"`, git commit fires |
| `-SetProject` skips already-tagged file | Existing project value preserved |
| `-SetDomain` tags untagged file | File gets `domain: "accounting"` |
| `-WhatIf` prints action, no write | File unchanged, exits 0 |
| Missing `-Folder` | Exits 1 with message |
| Non-existent `-Folder` | Exits 1 identifying bad path |
| Neither `-SetProject` nor `-SetDomain` | Exits 1 |
| Mixed tagged/untagged batch | Only untagged files are updated |

**Required test cases — `search.Tests.ps1` additions (add to existing file):**

| Test | What to verify |
|------|----------------|
| `-Project` scalar match | File with `project: "work"` returned; `project: "other"` excluded |
| `-Project` array match | File with `project: ["work","research"]` returned when `-Project work` |
| `-Project` excludes untagged | File with no `project:` field excluded from scoped results |
| `-Project` shared bypass | File with `shared: true` returned even without matching project tag |
| `-Domain accounting` filter | Only files with `domain: "accounting"` or `domain: ["accounting","tax"]` returned |
| `-Domain` shared bypass | File with `shared: true` returned even without matching domain tag |

**Required test cases — `generate-handoff.Tests.ps1` additions (add to existing file):**

| Test | What to verify |
|------|----------------|
| `-Domain` filter | Only files with matching domain included in handoff |
| `-Domain` footer line | Handoff file contains `**Domain scope:** accounting` |
| `shared: true` project bypass | File with `shared: true` included even when `-Project work` and file has different project |
| `shared: true` domain bypass | File with `shared: true` included even when `-Domain accounting` and file has different domain |
| Regression: project filter unchanged | Existing `-Project` scoping still works after changes |

**Regression guard — run after all changes:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\generate-handoff.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\manage-project-tags.Tests.ps1"
```

---

## Architecture Compliance

- PowerShell 5.1 — no `??`, no `? :`, no `?.` — explicit `if/else` throughout
- All file writes: `Set-Content -Path ... -Value ... -Encoding UTF8`
- Logging: `Write-Log` from `scripts/lib/common.ps1`
- Exit codes: `0` = success or WhatIf, `1` = user input error, `2` = system error
- `$PSScriptRoot` for all lib path resolution
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at script top
- Config loaded via `Get-Config` — never bypassed
- **NFR-001/NFR-002**: No hosted service; project/domain metadata lives in Markdown frontmatter only
- **NFR-010**: Bulk tag updates are committed to git; no silent state changes
- **NFR-006**: Retrieval output preserves source pointers (do not strip provenance in project-scoped results)
- Local-first: no derived indexes required for project scoping — all filtering is frontmatter-read-time

---

## Scope Boundaries

**In scope:**
- `templates/inbox-item.md` — add `domain: ""` field
- `scripts/search.ps1` — array-aware project filter + `-Domain` param
- `scripts/generate-handoff.ps1` — `-Domain` param + `shared: true` bypass + domain footer line
- `scripts/list-projects.ps1` — untagged count + `-Domain` flag + array-aware project reading
- `scripts/manage-project-tags.ps1` — NEW: bulk-assign project/domain to untagged files by folder
- `tests/manage-project-tags.Tests.ps1` — NEW: Pester tests

**Explicitly out of scope:**
- Vault import preview or execution (Stories 5.3, 5.4)
- Import rollback (Story 5.5)
- AI content review gates (Story 7.1)
- Modifying privacy controls from Story 5.1 — `private`, `exclude_from_ai`, `redacted_sections` behavior must remain unchanged
- Folder-based physical separation of projects (subdirectories) — metadata-only scoping is sufficient
- Any changes to `capture.ps1`, `capture-source.ps1`, or `import-conversation.ps1` — they already write `project` field from config defaults; no changes needed

---

## Previous Story Intelligence

**From Story 5.1 (Sensitive Content Controls):**
- `privacy-audit.ps1` is the reference for bulk frontmatter updates with per-file git commits — use the same pattern for `manage-project-tags.ps1`
- `Set-FrontmatterField` from `lib/frontmatter.ps1` is the correct tool for writing frontmatter fields — do NOT use raw string substitution for new fields; use this function
- `Invoke-GitCommit` availability is guarded with `Get-Command 'Invoke-GitCommit'` — follow the same guard pattern
- `Set-StrictMode -Version Latest` + `$ErrorActionPreference = 'Stop'` must be at top of every new script

**From Story 4.3 (Capture Configuration Management):**
- `manage-source-types.ps1` is the boilerplate reference for new management scripts
- YAML editing for config goes through `Read-YamlConfig` / string replacement — for frontmatter, use `Set-FrontmatterField`

**From Story 3.3 (AI Handoff Context Generation):**
- `generate-handoff.ps1` already has array-aware `Get-FrontmatterValues` defined inline (lines 130–151) — do NOT duplicate into lib; use the existing function within that file
- The project scope footer line already exists — only ADD the domain scope line alongside it; do not reorder or remove the project line

**From Story 3.1 (Cross-Layer Knowledge Search):**
- `search.ps1` outputs `[WIKI]`, `[WORK]`, `[RAW]`, `[ARCH]`, `[TASK]` layer indicators — do not add project/domain indicators to the result line; scoping is a filter, not a display tag

**From Story 4.2 (Non-AI Source Capture):**
- `capture-source.ps1` writes `project:` field from frontmatter; it does NOT write `domain:` — files captured via this script will have `domain: ""` from the template; `manage-project-tags.ps1` is the mechanism to bulk-fill domain after the fact

---

## Definition of Done

- [x] `templates/inbox-item.md` has `domain: ""` after `project:` line
- [x] `search.ps1` project filter handles both scalar and array project values
- [x] `search.ps1` respects `shared: true` as bypass for project filter
- [x] `search.ps1 -Domain accounting` filters results to matching domain values (scalar or array)
- [x] `search.ps1 -Domain accounting` respects `shared: true` as bypass
- [x] `generate-handoff.ps1 -Domain accounting` filters candidates to matching domain
- [x] `generate-handoff.ps1` shared bypass applied to both project AND domain filters
- [x] `generate-handoff.ps1` footer shows `**Domain scope:**` line
- [x] `list-projects.ps1` shows `(untagged)` count at bottom
- [x] `list-projects.ps1 -Domain` lists domain values with counts
- [x] `scripts/manage-project-tags.ps1` exists and runs on PowerShell 5.1
- [x] `-SetProject` tags only untagged files; skips already-tagged
- [x] `-SetDomain` tags only untagged files; skips already-tagged
- [x] `-WhatIf` prints without writing; exits 0
- [x] Each updated file is git-committed individually
- [x] `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in new script
- [x] No `??`, no ternary `? :`, no `?.` operators
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] `Invoke-Pester tests\manage-project-tags.Tests.ps1` passes
- [x] `Invoke-Pester tests\search.Tests.ps1` still passes (no regressions)
- [x] `Invoke-Pester tests\generate-handoff.Tests.ps1` still passes (no regressions)

---

## Tasks / Subtasks

- [x] Task 1: Update template
  - [x] 1.1 Add `domain: ""` to `templates/inbox-item.md` after `project:` line

- [x] Task 2: Update `scripts/search.ps1`
  - [x] 2.1 Add `Get-FrontmatterValuesLocal` helper function after dot-source block
  - [x] 2.2 Replace scalar project filter with array-aware + `shared: true` bypass
  - [x] 2.3 Add `-Domain` param and domain filter block (same pattern, `domain` field)

- [x] Task 3: Update `scripts/generate-handoff.ps1`
  - [x] 3.1 Add `-Domain` param to script and `Get-HandoffCandidates` function
  - [x] 3.2 Add `shared: true` bypass to existing project filter
  - [x] 3.3 Add domain filter block after project filter
  - [x] 3.4 Add `**Domain scope:**` line to handoff footer in `Write-HandoffFile`
  - [x] 3.5 Pass `-Domain $Domain` through all call sites

- [x] Task 4: Update `scripts/list-projects.ps1`
  - [x] 4.1 Make project reading array-aware (handle `project: ["p1","p2"]`)
  - [x] 4.2 Add `(untagged)` count line to output
  - [x] 4.3 Add `-Domain` switch — when set, scan `domain` field instead of `project`

- [x] Task 5: Implement `scripts/manage-project-tags.ps1`
  - [x] 5.1 Standard boilerplate: dot-source libs, `Get-Config`
  - [x] 5.2 `-Folder` validation and file collection
  - [x] 5.3 Per-file: skip if already tagged; write field if untagged; git-commit
  - [x] 5.4 `-WhatIf` path: print action, skip writes
  - [x] 5.5 Summary output: tagged count + skipped count

- [x] Task 6: Write `tests/manage-project-tags.Tests.ps1`
  - [x] 6.1 All test cases from Testing Requirements table
  - [x] 6.2 Regression runs for `search.ps1` and `generate-handoff.Tests.ps1`

- [x] Task 7: Update sprint status
  - [x] 7.1 Set `5-2-project-and-domain-separation` to `done` in `sprint-status.yaml`

### Review Findings

- [x] [Review][Patch] Constrain bulk tag folder resolution to the repo/vault [scripts/manage-project-tags.ps1:40]
- [x] [Review][Patch] Treat empty frontmatter arrays as untagged values [scripts/manage-project-tags.ps1:52]
- [x] [Review][Patch] Reject malformed frontmatter instead of wrapping it in a new document [scripts/manage-project-tags.ps1:70]
- [x] [Review][Patch] Count skipped files, not skipped fields, in combined project/domain runs [scripts/manage-project-tags.ps1:124]

---

## File List

- `templates/inbox-item.md` — MODIFIED (add `domain: ""`)
- `scripts/search.ps1` — MODIFIED (array-aware project filter + `-Domain` param)
- `scripts/generate-handoff.ps1` — MODIFIED (`-Domain` param + `shared: true` bypass + footer)
- `scripts/list-projects.ps1` — MODIFIED (untagged count + `-Domain` flag)
- `scripts/manage-project-tags.ps1` — NEW
- `tests/manage-project-tags.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/5-2-project-and-domain-separation.md` — this file
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED (`5-2-project-and-domain-separation` → `done`)

---

## Dev Agent Record

### Agent Model Used

GPT-5

### Debug Log References

- 2026-04-28: `Invoke-Pester tests\manage-project-tags.Tests.ps1` — Passed: 8, Failed: 0
- 2026-04-28: `Invoke-Pester tests\search.Tests.ps1` — Passed: 14, Failed: 0
- 2026-04-28: `Invoke-Pester tests\generate-handoff.Tests.ps1` — Passed: 21, Failed: 0
- 2026-04-28: `.\scripts\list-projects.ps1` and `.\scripts\list-projects.ps1 -Domain` smoke checks — passed
- 2026-04-28: `Invoke-Pester tests` — story-related tests passed; repo-wide run reported 11 unrelated existing failures in `BugConditionExploration.Tests.ps1`, `preservation-properties.Tests.ps1`, and `PreservationProperty.Tests.ps1`
- 2026-04-28: Post-review `Invoke-Pester tests\manage-project-tags.Tests.ps1` — Passed: 13, Failed: 0

### Completion Notes List

- Added `domain: ""` to the inbox item template without reordering existing fields.
- Made search project filtering array-aware and added domain filtering with `shared: true` bypass for both scopes.
- Added domain filtering, shared bypass, and `**Domain scope:**` footer output to AI handoff generation.
- Updated project listing to support array values, untagged counts, and `-Domain` mode.
- Added `manage-project-tags.ps1` for non-recursive bulk project/domain tagging with `-WhatIf` and per-file git commits.
- Added Pester coverage for bulk tagging plus project/domain search and handoff behavior.
- Resolved review findings for folder containment, empty array tags, malformed frontmatter rejection, and combined project/domain summary counts.

### File List

- `templates/inbox-item.md`
- `scripts/search.ps1`
- `scripts/generate-handoff.ps1`
- `scripts/list-projects.ps1`
- `scripts/manage-project-tags.ps1`
- `tests/manage-project-tags.Tests.ps1`
- `tests/search.Tests.ps1`
- `tests/generate-handoff.Tests.ps1`
- `_bmad-output/implementation-artifacts/5-2-project-and-domain-separation.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`

### Change Log

- 2026-04-28: Implemented Story 5.2 project/domain separation and moved story to review.
- 2026-04-28: Resolved code review findings and moved story to done.
