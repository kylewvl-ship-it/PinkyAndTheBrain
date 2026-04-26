# Story 4.3: Capture Configuration Management

**Story ID:** 4.3
**Epic:** 4 - Advanced Capture & Sources
**Status:** done
**Created:** 2026-04-26

---

## User Story

As Reno,
I want to configure capture sources, folder paths, and processing rules,
So that the system adapts to my specific workflow and I can extend source types without changing scripts.

---

## Acceptance Criteria

### Scenario: List configured source types

- **Given** the system has a `source_types` section in `config/pinky-config.yaml`
- **When** I run `.\scripts\manage-source-types.ps1 -List`
- **Then** I see a table of all configured source types with their template paths and field definitions
- **And** the 6 MVP types (web, book, meeting, video, article, idea) are shown
- **And** the output indicates whether each type's template file exists on disk

### Scenario: Add a custom source type

- **Given** I want to capture content of a new type (e.g., `podcast`)
- **When** I run `.\scripts\manage-source-types.ps1 -Add -TypeName podcast -TemplatePath templates/source-podcast.md`
- **Then** the new type is written into the `source_types` section of `config/pinky-config.yaml`
- **And** the script reports the update and warns if the template file does not yet exist
- **And** the config file remains valid YAML after the update
- **And** `capture-source.ps1 -SourceType podcast` becomes valid immediately (no script changes needed)

### Scenario: Validate source type configuration

- **Given** the config has one or more source types defined
- **When** I run `.\scripts\manage-source-types.ps1 -Validate`
- **Then** any type whose template path does not exist on disk is reported as a warning (not an error)
- **And** any type entry missing required keys (`template`) is reported as an error
- **And** the script exits 0 if there are no errors (warnings are permitted)
- **And** the script exits 1 if any errors are found

### Scenario: Config validation includes source types

- **Given** I run `.\scripts\validate-config.ps1`
- **Then** the validator checks the `source_types` section when present
- **And** each source type entry with a `template` key is checked — a missing file is a warning, not an error
- **And** the validator reports the number of configured source types

### Scenario: Capture honors config-driven source types

- **Given** a custom source type `podcast` has been added to config via `manage-source-types.ps1`
- **When** I run `.\scripts\capture-source.ps1 -SourceType podcast -Title "Episode Title" -Notes "My notes"`
- **Then** the capture succeeds and writes to `knowledge/inbox/` with `source_type: "podcast"` in frontmatter
- **And** the script uses the template path from config if the file exists, otherwise falls back to inline structure

### Scenario: Invalid source type still fails cleanly

- **Given** I provide a `-SourceType` value not present in config's `source_types`
- **When** the script validates input at runtime
- **Then** it exits with code 1 and displays the valid source types (read from config)
- **And** the error message is identical in structure to the previous hardcoded ValidateSet behavior

### Scenario: config/pinky-config.yaml source_types section

- **Given** the config file is opened for inspection
- **Then** a `source_types` section is present with an entry for each of the 6 MVP types
- **And** each entry has at minimum a `template` key pointing to the corresponding `templates/source-*.md` path
- **And** the section is human-readable and editable without scripts

### Error Scenario: Config file missing source_types

- **Given** `config/pinky-config.yaml` has no `source_types` section
- **When** `capture-source.ps1` runs
- **Then** it falls back to the hardcoded list of 6 MVP types (web, book, meeting, video, article, idea)
- **And** no error is raised — the fallback is silent and backward-compatible

---

## Technical Requirements

### What already exists — do NOT reimplement

- `config/pinky-config.yaml` — existing config file; this story adds `source_types` section only
- `scripts/validate-config.ps1` — existing validator; this story enhances it to check `source_types`
- `scripts/capture-source.ps1` — existing capture script; this story makes one surgical change (runtime type validation from config instead of hardcoded ValidateSet)
- `scripts/lib/common.ps1` — `Get-Config`, `Write-Log`, `Get-TimestampedFilename`
- `scripts/lib/config-loader.ps1` — `Read-YamlConfig`, `Merge-Config`, `Get-DefaultConfig`
- `templates/source-book.md`, `source-meeting.md`, `source-video.md`, `source-article.md`, `source-idea.md` — created in Story 4.2

### New files

```
scripts/
  manage-source-types.ps1         # NEW — source type configuration management
templates/
  source-web.md                   # NEW — web source template (completes the 6-type set)
tests/
  manage-source-types.Tests.ps1   # NEW — Pester coverage
```

### Modified files

```
config/pinky-config.yaml          # ADD source_types section
scripts/validate-config.ps1       # ENHANCE to validate source_types section
scripts/capture-source.ps1        # SURGICAL: replace hardcoded ValidateSet with config-driven validation
```

---

### Config: `source_types` section in `config/pinky-config.yaml`

Add at the end of the file (before `limits:`):

```yaml
source_types:
  web:
    template: "templates/source-web.md"
  book:
    template: "templates/source-book.md"
  meeting:
    template: "templates/source-meeting.md"
  video:
    template: "templates/source-video.md"
  article:
    template: "templates/source-article.md"
  idea:
    template: "templates/source-idea.md"
```

Keep the section minimal. Field definitions are optional metadata for tooling; the `template` key is the only required key per type entry.

---

### Template: `templates/source-web.md`

Web captures previously used an inline structure. Adding the template completes the set and makes the web type config-inspectable:

```markdown
---
source_type: "web"
source_url: "{{source_url}}"
source_title: "{{source_title}}"
captured_date: "{{captured_date}}"
review_status: "pending"
private: false
---

# Web: {{source_title}}

## My Notes

{{my_notes}}
```

The body must contain only user-supplied notes — no auto-generated summaries. Matching the constraint from Story 4.2.

---

### Script: `scripts/manage-source-types.ps1`

**Boilerplate — follow exactly (same pattern as `capture-source.ps1`):**

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$List,
    [switch]$Validate,
    [switch]$Add,
    [string]$TypeName,
    [string]$TemplatePath,
    [switch]$WhatIf,
    [switch]$Help
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
if (Test-Path "$PSScriptRoot\lib\git-operations.ps1") {
    . "$PSScriptRoot\lib\git-operations.ps1"
}

$config = Get-Config
```

**Parameter validation:**

- `-List`, `-Validate`, `-Add` are mutually exclusive; exactly one must be provided
- `-Add` requires `-TypeName` and `-TemplatePath`; exit code 1 if either missing
- `-TypeName` must match `^[a-z][a-z0-9-]*$` (lowercase alphanumeric with hyphens); exit code 1 otherwise

**`-List` mode:**

Read `config.source_types` (may be null/absent — show empty table with a note). For each type, check whether the template file exists on disk. Output as a formatted table:

```
Source Type   Template                        Template Exists
-----------   --------                        ---------------
web           templates/source-web.md         YES
book          templates/source-book.md        YES
...
```

Exit 0 always.

**`-Validate` mode:**

For each entry in `config.source_types`:
- Error if entry has no `template` key
- Warning if `template` path does not exist on disk

Print errors (red) and warnings (yellow). Exit 1 if any errors; exit 0 if only warnings or none.

**`-Add` mode:**

1. Read the raw config YAML file as text (`config/pinky-config.yaml`)
2. If `source_types:` section exists, insert the new entry under it; if absent, append the section
3. Use `Set-Content -Path $configPath -Value $newContent -Encoding UTF8`
4. Warn if the template file does not exist (but still write the config)
5. If `-WhatIf`, print the intended change without writing

Config path: always `(Resolve-Path (Join-Path $PSScriptRoot "..")).Path + "\config\pinky-config.yaml"` — not hardcoded.

**YAML editing strategy:** Simple string manipulation on the raw YAML text — do NOT use a YAML library that would reformat or reorder the entire file. Append the new entry under the `source_types:` key using string operations. The file must remain human-readable and git-diffable after the edit.

PowerShell 5.1 constraints: no `??`, no `? :`, no `?.` — use explicit `if/else`.

**Git auto-commit after `-Add`:**

```powershell
if (Get-Command 'Invoke-GitCommit' -ErrorAction SilentlyContinue) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $relPath  = "config/pinky-config.yaml"
    Invoke-GitCommit -Message "config: add source type '$TypeName'" `
                     -Files @($relPath) -RepoPath $repoRoot | Out-Null
}
```

---

### Script modification: `scripts/capture-source.ps1`

**Change:** Replace the static `[ValidateSet('web','book','meeting','video','article','idea')]` attribute with runtime validation against config.

**Before (param block):**
```powershell
[Parameter(Mandatory)]
[ValidateSet('web','book','meeting','video','article','idea')]
[string]$SourceType,
```

**After (param block):**
```powershell
[Parameter(Mandatory)]
[string]$SourceType,
```

**Add runtime validation immediately after `$config = Get-Config`:**

```powershell
# Determine valid source types from config, fallback to MVP defaults
$configuredTypes = @('web','book','meeting','video','article','idea')
if ($config.ContainsKey('source_types') -and $config.source_types -is [hashtable]) {
    $configuredTypes = @($config.source_types.Keys | Sort-Object)
}

if ($configuredTypes -notcontains $SourceType) {
    Write-Log "Invalid SourceType '$SourceType'. Valid types: $($configuredTypes -join ', ')" "ERROR"
    exit 1
}
```

All downstream logic in `capture-source.ps1` is unchanged. The template-loading block already reads from `config.system.template_root` — for custom types with a template file, it will find and use it. For custom types without a template, the inline fallback already handles this.

This is the only change to `capture-source.ps1`. Do not modify any other logic.

---

### Script modification: `scripts/validate-config.ps1`

Add a `source_types` validation block after the existing `Test-ConfigPaths` call, before the summary section:

```powershell
# Validate source_types section (optional section — absence is not an error)
if ($config.ContainsKey('source_types') -and $config.source_types -is [hashtable]) {
    $typeCount = $config.source_types.Count
    Write-Host "✓ source_types section present ($typeCount type(s) configured)" -ForegroundColor Green

    foreach ($typeName in $config.source_types.Keys) {
        $typeEntry = $config.source_types[$typeName]
        if ($typeEntry -isnot [hashtable] -or !$typeEntry.ContainsKey('template')) {
            $allErrors += "source_types.$typeName: missing required 'template' key"
            Write-Host "✗ source_types.$typeName: missing 'template' key" -ForegroundColor Red
        }
        elseif (!(Test-Path $typeEntry['template'])) {
            $warnings += "source_types.$typeName: template file not found: $($typeEntry['template'])"
            Write-Host "⚠ source_types.$typeName: template not found: $($typeEntry['template'])" -ForegroundColor Yellow
        }
        else {
            Write-Host "✓ source_types.$typeName: template exists" -ForegroundColor Green
        }
    }
}
else {
    Write-Host "⚠ source_types section absent — capture-source.ps1 will use built-in defaults" -ForegroundColor Yellow
}
```

No other changes to `validate-config.ps1`.

---

## Testing Requirements

Follow test file conventions from `tests/capture-source.Tests.ps1` and `tests/import-conversation.Tests.ps1`:
- Use `$TestDrive` for isolated config/template roots
- Set `$env:PINKY_VAULT_ROOT` and `$env:PINKY_FORCE_NONINTERACTIVE = "1"`
- Mock `Invoke-GitCommit` via env-guard pattern

New test file: `tests/manage-source-types.Tests.ps1`

**Required test cases:**

| Test | What to verify |
|------|----------------|
| List — 6 MVP types | With default config, lists all 6 types |
| List — template exists column | Shows YES/NO per template; web template exists after this story |
| Add — new type written to config | `podcast` type appears in config YAML after `-Add` |
| Add — TypeName validation | Non-lowercase or invalid chars → exit 1 |
| Add — missing TypeName or TemplatePath | → exit 1 with message |
| Add — WhatIf | No config modification, exits 0 |
| Add — git commit fires | `Invoke-GitCommit` called after successful add |
| Validate — missing template → warning | Missing template file is warning not error, exits 0 |
| Validate — missing template key → error | Entry with no `template` key → exits 1 |
| Validate — all templates present → clean | Exits 0 with no errors or warnings |
| capture-source — config-driven types | After adding `podcast` to config, `-SourceType podcast` succeeds |
| capture-source — invalid type from config | `-SourceType unknown` → exit 1, lists valid types from config |
| capture-source — fallback when no source_types | With no `source_types` in config, 6 defaults still work |
| capture-source — backward compat | All 6 existing types still produce correct output (regression guard) |

Run focused validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\manage-source-types.Tests.ps1"
```

Also run the existing capture-source tests to confirm no regressions:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\capture-source.Tests.ps1"
```

---

## Dev Notes

### Why config-driven, not hardcoded

Story 4.2 used `[ValidateSet(...)]` as a safe MVP — the 6 types were fixed at development time. Story 4.3 introduces the extensibility seam: `config.source_types` is the single source of truth for what's a valid source type. The fallback to 6 hardcoded defaults when `source_types` is absent ensures zero regressions against all prior test state.

### YAML editing approach for `-Add`

The config file is meant to be human-readable and git-diffable. Avoid round-tripping through a YAML parser that would reformat the file. Use string manipulation to append entries under the `source_types:` block. This matches the local-first, inspectable-workflow constraint (NFR-010).

Concrete approach: find the `source_types:` line in the raw text, locate the insertion point (end of the block or end of file), insert the new entry at two-space indentation. Write back with `Set-Content -Encoding UTF8`.

### Scope boundary: project subfolders

The epics.md AC for 4.3 mentions project-tag-based subfolders. This is **not** in scope here — it belongs to Story 5.2 (Project and Domain Separation). The `projects` section already exists in config; Story 4.3 does not add routing logic to any capture script.

### Scope boundary: review cadence UI

Review cadence configuration already exists in `config/review_cadence`. Story 4.3 does not add any new review schedule tooling — that is Story 6.1/7.4 territory.

### template for web type

Story 4.2 built web captures inline (no template file). Story 4.3 adds `templates/source-web.md` to complete the set, making web inspectable and config-consistent. The inline fallback in `capture-source.ps1` is unchanged; once the template file exists, it will be loaded automatically by the existing template-loading logic.

### Architecture compliance

- PowerShell 5.1 — no `??`, no `? :`, no `?.` — explicit `if/else` throughout
- All file writes: `Set-Content -Path ... -Value ... -Encoding UTF8`
- Logging: `Write-Log` from `scripts/lib/common.ps1`
- Exit codes: `0` = success or WhatIf, `1` = user input error, `2` = system error
- `$PSScriptRoot` for all lib path resolution
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` at script top
- Config loaded via `Get-Config` — never bypassed
- Inspectability (NFR-010): all config changes are plain YAML edits, committed to git, human-readable

### References

- Epic 4 Story 4.3 requirements: `_bmad-output/planning-artifacts/epics.md#Story-4.3`
- FR-014: `_bmad-output/planning-artifacts/prd.md`
- Story 4.2 (completed): `_bmad-output/implementation-artifacts/4-2-non-ai-source-capture.md`
- Config structure: `config/pinky-config.yaml`
- Existing validator: `scripts/validate-config.ps1`

---

## Previous Story Intelligence

**From Story 4.2 (Non-AI Source Capture):**
- `capture-source.ps1` uses a hardcoded `ValidateSet` for 6 types — Story 4.3 replaces this with config-driven runtime validation
- Template loading already uses `config.system.template_root` + `source-$($SourceType.ToLower()).md` — custom types with matching template files will be picked up without additional changes
- `review_status: "pending"` and `private: false` defaults remain unchanged
- The inline fallback for missing templates is already implemented — do not remove it

**From Story 0.4 (Configuration Management):**
- Config path is resolved via `$config.system.vault_root` and related keys; the config file path itself is `config/pinky-config.yaml` relative to repo root
- `Read-YamlConfig` in `config-loader.ps1` handles YAML parsing
- `validate-config.ps1` validates required sections and value ranges

**From Story 1.1 / 4.1 (script boilerplate):**
- Same dot-source pattern, same `$ErrorActionPreference`, same git-commit guard
- `$env:PINKY_FORCE_NONINTERACTIVE = "1"` disables interactive prompts in tests

---

## Scope Boundaries

**In scope:**
- `config/pinky-config.yaml` — add `source_types` section with 6 MVP types
- `templates/source-web.md` — new template completing the 6-type set
- `scripts/manage-source-types.ps1` — NEW: `-List`, `-Add`, `-Validate`
- `scripts/validate-config.ps1` — ENHANCED: validates `source_types` section
- `scripts/capture-source.ps1` — SURGICAL: replace static ValidateSet with config-driven runtime validation + fallback
- Pester tests for `manage-source-types.ps1` and regression guard for `capture-source.ps1`

**Explicitly out of scope:**
- Project subfolder routing (Story 5.2) — do not route captures to `inbox/work/` etc.
- Review cadence UI or reminder tooling (Stories 6.1, 7.4)
- Privacy audit commands (Story 5.1)
- Health check strictness UI (Story 6.1)
- Archive behavior configuration
- Field definition metadata per source type (optional future enhancement — the config section supports it but the story does not require it)
- Modifying `capture.ps1` (basic `-Type web` from Story 1.1 — leave untouched)

---

## Definition of Done

- [x] `config/pinky-config.yaml` has a `source_types` section with entries for: web, book, meeting, video, article, idea
- [x] Each `source_types` entry has a `template` key pointing to the correct `templates/source-*.md` path
- [x] `templates/source-web.md` exists with frontmatter scaffold and `## My Notes` section
- [x] `scripts/manage-source-types.ps1` exists and runs on PowerShell 5.1 without errors
- [x] `-List` shows all configured source types and template existence status
- [x] `-Add -TypeName podcast -TemplatePath templates/source-podcast.md` adds entry to config YAML
- [x] `-Add` with invalid TypeName exits code 1
- [x] `-Add -WhatIf` prints intended change without writing
- [x] `-Validate` warns on missing template files, errors on missing `template` key
- [x] `scripts/validate-config.ps1` validates `source_types` section and reports type count
- [x] `scripts/capture-source.ps1` reads valid types from `config.source_types` at runtime
- [x] `capture-source.ps1` falls back to 6 hardcoded defaults when `source_types` is absent from config
- [x] All 6 existing source types continue to work identically (regression: `Invoke-Pester tests\capture-source.Tests.ps1` still passes)
- [x] Custom type added via `-Add` is immediately usable with `capture-source.ps1`
- [x] Git auto-commit fires after `-Add` succeeds
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in new script
- [x] No `??`, no ternary `? :`, no `?.` operators
- [x] `Invoke-Pester tests\manage-source-types.Tests.ps1` passes
- [x] `Invoke-Pester tests\capture-source.Tests.ps1` still passes (no regressions)

---

## Tasks / Subtasks

- [x] Task 1: Extend `config/pinky-config.yaml`
  - [x] 1.1 Add `source_types` section with all 6 MVP types and their template paths

- [x] Task 2: Add `templates/source-web.md`
  - [x] 2.1 Create web source template with frontmatter scaffold and `## My Notes` body

- [x] Task 3: Implement `scripts/manage-source-types.ps1`
  - [x] 3.1 Standard boilerplate: dot-source libs, `Get-Config`
  - [x] 3.2 `-List` mode: read `source_types`, format table with template-existence column
  - [x] 3.3 `-Validate` mode: check each entry for `template` key and file existence
  - [x] 3.4 `-Add` mode: validate TypeName format, append to config YAML, warn if template missing
  - [x] 3.5 `-Add -WhatIf` path: print action, exit 0 without writing
  - [x] 3.6 Git auto-commit after `-Add`

- [x] Task 4: Modify `scripts/capture-source.ps1`
  - [x] 4.1 Remove `[ValidateSet(...)]` from `-SourceType` parameter
  - [x] 4.2 Add post-config-load runtime validation block with fallback to 6 defaults

- [x] Task 5: Enhance `scripts/validate-config.ps1`
  - [x] 5.1 Add `source_types` validation block (template key check + file existence check)

- [x] Task 6: Write `tests/manage-source-types.Tests.ps1`
  - [x] 6.1 All test cases from Testing Requirements table
  - [x] 6.2 Regression run: `Invoke-Pester tests\capture-source.Tests.ps1`

- [x] Task 7: Update sprint status
  - [x] 7.1 Set `4-3-capture-configuration-management` to `ready-for-dev` in `sprint-status.yaml`

---

## File List

- `config/pinky-config.yaml` — MODIFIED (add `source_types` section)
- `templates/source-web.md` — NEW
- `scripts/manage-source-types.ps1` — NEW
- `scripts/validate-config.ps1` — MODIFIED (add `source_types` validation block)
- `scripts/capture-source.ps1` — MODIFIED (replace ValidateSet with config-driven runtime validation)
- `tests/manage-source-types.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/4-3-capture-configuration-management.md` — this file
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED (`4-3-capture-configuration-management` → `ready-for-dev`)

## Dev Agent Record

### Debug Log References

- 2026-04-26: `Invoke-Pester tests\manage-source-types.Tests.ps1` — 14 passed, 0 failed.
- 2026-04-26: `Invoke-Pester tests\capture-source.Tests.ps1` — 15 passed, 0 failed.
- 2026-04-26: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\validate-config.ps1` — configuration valid, `source_types` recognized with 6 templates present.

### Completion Notes List

- Added `source_types` to `config/pinky-config.yaml` so the 6 MVP capture types are config-inspectable and extensible.
- Added `templates/source-web.md` to complete the source template set.
- Added `scripts/manage-source-types.ps1` with `-List`, `-Validate`, and `-Add` modes, including git auto-commit on successful additions.
- Replaced the hardcoded source-type `ValidateSet` in `capture-source.ps1` with runtime validation from config plus a silent fallback to the 6 MVP defaults.
- Enhanced `validate-config.ps1` to validate `source_types` and report template presence without turning missing templates into hard errors.
- BMAD code review did not confirm any remaining defects in the 4.3 change set after validation.

### File List

- `config/pinky-config.yaml` — MODIFIED
- `templates/source-web.md` — NEW
- `scripts/manage-source-types.ps1` — NEW
- `scripts/validate-config.ps1` — MODIFIED
- `scripts/capture-source.ps1` — MODIFIED
- `tests/manage-source-types.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/4-3-capture-configuration-management.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED
