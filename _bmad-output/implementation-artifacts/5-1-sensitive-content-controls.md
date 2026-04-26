# Story 5.1: Sensitive Content Controls

**Story ID:** 5.1
**Epic:** 5 - Privacy & Project Management
**Status:** done
**Created:** 2026-04-26

---

## User Story

As Reno,
I want to mark and control sensitive content with redaction and exclusion metadata,
So that private information doesn't leak into AI sessions or shared contexts.

---

## Acceptance Criteria

### Scenario: Marking a file as private

- **Given** I capture or create content that contains sensitive information
- **When** I edit the content's frontmatter
- **Then** I can set `private: true` to mark the entire file as private
- **And** I can set `exclude_from_ai: true` to prevent AI handoff inclusion independently of `private`
- **And** I can add `redacted_sections: ["Section Heading 1", "Section Heading 2"]` to list specific H2 sections that must be redacted before any inclusion

### Scenario: Private file in search results

- **Given** I have content marked with `private: true`
- **When** the content appears in search results from `search.ps1`
- **Then** it shows a `[PRIVATE]` indicator next to the filename
- **And** the 2-line content preview is suppressed — only the filename and metadata (layer, date) are shown
- **And** there is no change to the file's triage or promotion eligibility

### Scenario: AI handoff excludes private and excluded content

- **Given** I generate AI handoff context with `generate-handoff.ps1`
- **When** the system selects relevant content
- **Then** files with `private: true` are excluded (already enforced — this story must not break that)
- **And** files with `exclude_from_ai: true` are also excluded regardless of `private` value
- **And** if a file is included but has `redacted_sections` populated, each named section's content is replaced with `[REDACTED]` in the output — the section heading itself remains visible

### Scenario: Privacy audit

- **Given** I want to review all sensitive content in my vault
- **When** I run `.\scripts\privacy-audit.ps1`
- **Then** I get a list of all files that have `private: true`, `exclude_from_ai: true`, or a non-empty `redacted_sections` list
- **And** each row shows: file path, layer, `private`, `exclude_from_ai`, and redacted section count
- **And** I can filter to a specific control with flags: `-Private`, `-ExcludeFromAI`, `-Redacted`

### Scenario: Bulk update privacy settings

- **Given** I want to set the same privacy flag on multiple files
- **When** I run `.\scripts\privacy-audit.ps1 -SetPrivate true -Files "path1.md","path2.md"`
- **Then** each named file's `private` frontmatter field is updated to `true`
- **And** existing frontmatter fields are preserved; only the named field changes
- **And** each updated file is git-committed individually using the standard `Invoke-GitCommit` pattern

### Scenario: Redacted section replacement in handoff

- **Given** a wiki page is included in handoff context and has `redacted_sections: ["Salary Details"]`
- **When** `generate-handoff.ps1` builds the context package
- **Then** the `## Salary Details` section body is replaced by `[REDACTED]`
- **And** the section heading line (`## Salary Details`) remains in the output so the reader knows a section was present
- **And** the token count in the handoff footer reflects the post-redaction length

---

## Technical Requirements

### What already exists — do NOT reimplement

- `scripts/search.ps1` — Story 3.1. The `[PRIVATE]` indicator for `private: true` **may already be present** from Story 4.2's AC. Verify before modifying — add only if absent; do not refactor existing search logic.
- `scripts/generate-handoff.ps1` — Story 3.3. Already excludes files with `private: true`. This story adds two surgical changes: (1) also skip `exclude_from_ai: true` files, (2) apply `[REDACTED]` substitution for `redacted_sections`.
- `scripts/lib/common.ps1` — `Get-Config`, `Write-Log`, `Get-TimestampedFilename`
- `scripts/lib/config-loader.ps1` — `Read-YamlConfig`, `Merge-Config`, `Get-DefaultConfig`
- Templates `inbox-item.md`, `working-note.md` — already have `private: false`
- Template `wiki-page.md` — already has `private: false` **and** `exclude_from_ai: false`

### New file

```
scripts/
  privacy-audit.ps1              # NEW — list + bulk-update sensitive content controls
tests/
  privacy-audit.Tests.ps1        # NEW — Pester coverage
```

### Modified files

```
templates/inbox-item.md          # ADD exclude_from_ai: false, redacted_sections: []
templates/working-note.md        # ADD exclude_from_ai: false, redacted_sections: []
templates/wiki-page.md           # ADD redacted_sections: [] (exclude_from_ai already present)
scripts/search.ps1               # SURGICAL: add [PRIVATE] indicator if not already present
scripts/generate-handoff.ps1     # SURGICAL: exclude exclude_from_ai + apply [REDACTED] substitution
```

---

### Template changes

For `templates/inbox-item.md` and `templates/working-note.md`, add after the existing `private: false` line:

```yaml
exclude_from_ai: false
redacted_sections: []
```

For `templates/wiki-page.md`, add after `exclude_from_ai: false`:

```yaml
redacted_sections: []
```

Keep all other frontmatter fields unchanged. Do not reformat, reorder, or rename existing fields.

---

### Script modification: `scripts/search.ps1`

**Check first:** If the output already contains `[PRIVATE]` for files with `private: true`, this change is already done — add a comment and skip.

If absent, add after the line that builds the result display string (before printing):

```powershell
# Suppress content preview for private files
$privacyTag = ""
$showPreview = $true
if ($frontmatter.ContainsKey('private') -and $frontmatter['private'] -eq $true) {
    $privacyTag = " [PRIVATE]"
    $showPreview = $false
}
```

Use `$privacyTag` appended to the filename column and `$showPreview` to gate the 2-line preview. Do not change result ranking, layer filtering, or any other search logic.

---

### Script modification: `scripts/generate-handoff.ps1`

**Change 1 — exclude `exclude_from_ai: true`:**

In the file-inclusion loop (where `private: true` is already excluded), add:

```powershell
if ($frontmatter.ContainsKey('exclude_from_ai') -and $frontmatter['exclude_from_ai'] -eq $true) {
    continue
}
```

Place this immediately after the existing `private: true` check. No other logic changes.

**Change 2 — apply `[REDACTED]` substitution:**

After a file's content is loaded but before it is appended to the context package, apply section redaction:

```powershell
if ($frontmatter.ContainsKey('redacted_sections') -and
    $frontmatter['redacted_sections'] -is [System.Collections.IList] -and
    $frontmatter['redacted_sections'].Count -gt 0) {

    foreach ($sectionName in $frontmatter['redacted_sections']) {
        # Match ## SectionName heading through end of section (next ## or end of string)
        $pattern = "(?m)(^## $([regex]::Escape($sectionName))\s*$\r?\n)([\s\S]*?)(?=^## |\z)"
        $content = [regex]::Replace($content, $pattern, "`$1`n[REDACTED]`n`n")
    }
}
```

Apply this block once per included file. Do not modify the token-count logic — recalculate after substitution using the same method already in place.

This is the only change to the file inclusion path. Do not alter retrieval, prioritization, or output structure.

---

### Script: `scripts/privacy-audit.ps1`

**Boilerplate — follow exactly (same pattern as `manage-source-types.ps1`):**

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Private,
    [switch]$ExcludeFromAI,
    [switch]$Redacted,
    [string[]]$Files,
    [string]$SetPrivate,
    [string]$SetExcludeFromAI,
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

**Audit mode (default — no `-SetPrivate` or `-SetExcludeFromAI`):**

- Scan all `.md` files under `$config.system.vault_root` (inbox, raw, working, wiki, archive subfolders)
- Parse frontmatter for each file (use the same frontmatter-parse pattern from `generate-handoff.ps1`)
- Include a file in results if any of:
  - `private: true`
  - `exclude_from_ai: true`
  - `redacted_sections` is a non-empty list
- If `-Private` flag: only include files where `private: true`
- If `-ExcludeFromAI` flag: only include files where `exclude_from_ai: true`
- If `-Redacted` flag: only include files where `redacted_sections` is non-empty
- Output as a formatted table:

```
File                              Layer   Private  ExcludeFromAI  RedactedSections
----                              -----   -------  -------------  ----------------
knowledge/wiki/salary.md          [WIKI]  true     false          2
knowledge/working/health.md       [WORK]  false    true           0
```

- Exit 0 always in audit mode.
- If no files match, print: `No files with sensitive content controls found.`

**Bulk update mode (`-SetPrivate` or `-SetExcludeFromAI` with `-Files`):**

- Both `-SetPrivate` and `-SetExcludeFromAI` accept `"true"` or `"false"` as string values
- Validate: `-Files` must be provided; each path must exist; exit 1 with message if not
- Validate: value must be `"true"` or `"false"`; exit 1 otherwise
- For each file in `-Files`:
  - Read raw file content
  - If the frontmatter field exists, replace its value using string substitution
  - If the field is absent, insert it after `private:` line (or at end of frontmatter block if `private:` is absent)
  - Write back with `Set-Content -Path ... -Encoding UTF8`
  - If `-WhatIf`, print intended change without writing
  - If git operations available, call `Invoke-GitCommit` per file:
    ```powershell
    Invoke-GitCommit -Message "privacy: set $fieldName=$fieldValue in $relPath" `
                     -Files @($relPath) -RepoPath $repoRoot | Out-Null
    ```
- Print summary: `Updated 3 file(s).`
- Exit 0 on success.

**PowerShell 5.1 constraints:** No `??`, no `? :`, no `?.` — explicit `if/else` throughout. Strings only for YAML field value replacement (same approach as `manage-source-types.ps1` YAML editing).

---

## Testing Requirements

Follow conventions from `tests/manage-source-types.Tests.ps1`:
- Use `$TestDrive` for isolated vault roots
- Set `$env:PINKY_VAULT_ROOT` and `$env:PINKY_FORCE_NONINTERACTIVE = "1"`
- Mock `Invoke-GitCommit` via env-guard pattern

New test file: `tests/privacy-audit.Tests.ps1`

**Required test cases:**

| Test | What to verify |
|------|----------------|
| Audit — finds private:true files | File with `private: true` appears in output |
| Audit — finds exclude_from_ai:true files | File with `exclude_from_ai: true` appears in output |
| Audit — finds non-empty redacted_sections | File with `redacted_sections: ["Foo"]` appears in output |
| Audit — `-Private` filter | Only private:true files shown |
| Audit — `-ExcludeFromAI` filter | Only exclude_from_ai:true files shown |
| Audit — `-Redacted` filter | Only files with non-empty redacted_sections shown |
| Audit — no matches | Prints "No files with sensitive content controls found." exits 0 |
| Bulk update — `-SetPrivate true` | Sets `private: true` in named files, git commit fires |
| Bulk update — missing `-Files` | Exits 1 with message |
| Bulk update — invalid path | Exits 1 identifying bad path |
| Bulk update — invalid value | Exits 1 (not "true" or "false") |
| Bulk update — `-WhatIf` | No file modification, exits 0 |
| generate-handoff — exclude_from_ai | File with `exclude_from_ai: true` not in context output |
| generate-handoff — redacted_sections | Section content replaced by [REDACTED], heading preserved |
| generate-handoff — private still excluded | Regression: `private: true` still excluded (not broken) |
| search — [PRIVATE] indicator | File with `private: true` shows [PRIVATE], no content preview |
| search — non-private unaffected | Files without privacy flags show full preview (regression guard) |

Run focused validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\privacy-audit.Tests.ps1"
```

Also run regression guards:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\search.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests\generate-handoff.Tests.ps1"
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
- **NFR-008**: All sensitivity controls are plain frontmatter fields in the Markdown file — inspectable without running any script
- **NFR-010**: Bulk updates are committed to git; no silent state changes
- **NFR-001/NFR-002**: No hosted service; all controls live in Markdown frontmatter

---

## Scope Boundaries

**In scope:**
- `private: true`, `exclude_from_ai: true`, `redacted_sections: []` frontmatter controls
- Template updates: `inbox-item.md`, `working-note.md`, `wiki-page.md`
- `search.ps1` — add `[PRIVATE]` indicator + preview suppression (surgical)
- `generate-handoff.ps1` — add `exclude_from_ai` exclusion + `[REDACTED]` section substitution (surgical)
- `scripts/privacy-audit.ps1` — NEW: audit listing and bulk field update
- `tests/privacy-audit.Tests.ps1` — NEW: Pester tests
- Regression tests for `search.ps1` and `generate-handoff.ps1`

**Explicitly out of scope:**
- Project/domain separation or `--project` scoping (Story 5.2)
- Vault import preview or execution (Stories 5.3, 5.4)
- Import rollback (Story 5.5)
- Promotion workflow gating based on privacy flags (Stories 7.1 — AI review gates cover that)
- Private subfolders or folder-based privacy isolation
- Modifying `capture.ps1`, `capture-source.ps1`, or `import-conversation.ps1` — they already write `private: false` by default; `-Private` flag on `capture-source.ps1` already works (Story 4.2)

---

## Previous Story Intelligence

**From Story 4.2 (Non-AI Source Capture):**
- `capture-source.ps1` already supports `-Private` flag, setting `private: true` in frontmatter
- `private: true` is already excluded from `generate-handoff.ps1` (Story 3.3) — do NOT remove or duplicate this logic; only add `exclude_from_ai` exclusion alongside it
- The `[PRIVATE]` indicator in search results was mentioned in 4.2 AC but may or may not have been implemented in `search.ps1` — **verify before writing** to avoid duplicate code

**From Story 4.3 (Capture Configuration Management):**
- YAML editing strategy: string manipulation on raw file text, not round-trip through YAML parser — use the same approach for frontmatter field updates in `privacy-audit.ps1 -SetPrivate`
- `manage-source-types.ps1` is the reference implementation for the script boilerplate pattern
- Git auto-commit guard: check `Get-Command 'Invoke-GitCommit'` before calling

**From Story 3.3 (AI Handoff Context Generation):**
- `generate-handoff.ps1` reads frontmatter and already skips `private: true` files — find that check and insert the `exclude_from_ai` check immediately after it
- Token count is computed and written to the handoff footer — recalculate after `[REDACTED]` substitution using the same token-estimation method already in place

**From Story 3.1 (Cross-Layer Knowledge Search):**
- `search.ps1` outputs layer indicators `[WIKI]`, `[WORK]`, `[RAW]`, `[ARCH]`, `[TASK]` — `[PRIVATE]` is an additional tag on the same line, not a replacement for the layer indicator

---

## Definition of Done

- [x] `templates/inbox-item.md` has `exclude_from_ai: false` and `redacted_sections: []` after `private: false`
- [x] `templates/working-note.md` has `exclude_from_ai: false` and `redacted_sections: []` after `private: false`
- [x] `templates/wiki-page.md` has `redacted_sections: []` after `exclude_from_ai: false`
- [x] `search.ps1` shows `[PRIVATE]` for `private: true` files and suppresses content preview
- [x] `generate-handoff.ps1` skips `exclude_from_ai: true` files
- [x] `generate-handoff.ps1` replaces named section bodies with `[REDACTED]` when `redacted_sections` is non-empty
- [x] `scripts/privacy-audit.ps1` exists and runs on PowerShell 5.1 without errors
- [x] Default audit lists all files with any sensitivity control populated
- [x] `-Private`, `-ExcludeFromAI`, `-Redacted` filters work correctly
- [x] `-SetPrivate`/`-SetExcludeFromAI -Files` updates named files and git-commits each
- [x] `-WhatIf` prints intended changes without writing
- [x] `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` in new script
- [x] No `??`, no ternary `? :`, no `?.` operators
- [x] All writes use `Set-Content -Encoding UTF8`
- [x] `Invoke-Pester tests\privacy-audit.Tests.ps1` passes
- [x] `Invoke-Pester tests\search.Tests.ps1` still passes (no regressions)
- [x] `Invoke-Pester tests\generate-handoff.Tests.ps1` still passes (no regressions)

---

## Tasks / Subtasks

- [x] Task 1: Update templates
  - [x] 1.1 Add `exclude_from_ai: false` and `redacted_sections: []` to `templates/inbox-item.md`
  - [x] 1.2 Add `exclude_from_ai: false` and `redacted_sections: []` to `templates/working-note.md`
  - [x] 1.3 Add `redacted_sections: []` to `templates/wiki-page.md`

- [x] Task 2: Update `scripts/search.ps1`
  - [x] 2.1 Check if `[PRIVATE]` indicator already exists; if not, add it with preview suppression

- [x] Task 3: Update `scripts/generate-handoff.ps1`
  - [x] 3.1 Add `exclude_from_ai: true` skip check after existing `private: true` check
  - [x] 3.2 Add `redacted_sections` substitution block per-file, recalculate token count

- [x] Task 4: Implement `scripts/privacy-audit.ps1`
  - [x] 4.1 Standard boilerplate: dot-source libs, `Get-Config`
  - [x] 4.2 Audit mode: scan vault, parse frontmatter, display table with filter support
  - [x] 4.3 Bulk update mode: `-SetPrivate`/`-SetExcludeFromAI -Files` with YAML string editing
  - [x] 4.4 `-WhatIf` path: print action, exit 0 without writing
  - [x] 4.5 Git auto-commit per file after successful update

- [x] Task 5: Write `tests/privacy-audit.Tests.ps1`
  - [x] 5.1 All test cases from Testing Requirements table
  - [x] 5.2 Regression runs for `search.ps1` and `generate-handoff.ps1`

- [x] Task 6: Update sprint status
  - [x] 6.1 Set `5-1-sensitive-content-controls` to `ready-for-dev` in `sprint-status.yaml`

---

## File List

- `templates/inbox-item.md` — MODIFIED (add `exclude_from_ai`, `redacted_sections`)
- `templates/working-note.md` — MODIFIED (add `exclude_from_ai`, `redacted_sections`)
- `templates/wiki-page.md` — MODIFIED (add `redacted_sections`)
- `scripts/search.ps1` — MODIFIED (add `[PRIVATE]` indicator + preview suppression)
- `scripts/generate-handoff.ps1` — MODIFIED (`exclude_from_ai` exclusion + `[REDACTED]` substitution)
- `scripts/privacy-audit.ps1` — NEW
- `tests/privacy-audit.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/5-1-sensitive-content-controls.md` — this file
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED (`5-1-sensitive-content-controls` → `ready-for-dev`, `epic-5` → `in-progress`)

## Dev Agent Record

### Debug Log References

- 2026-04-26: `Invoke-Pester tests\privacy-audit.Tests.ps1` — 17 passed, 0 failed.
- 2026-04-26: `Invoke-Pester tests\search.Tests.ps1` — 8 passed, 0 failed.
- 2026-04-26: `Invoke-Pester tests\generate-handoff.Tests.ps1` — 16 passed, 0 failed.

### Completion Notes List

- Added frontmatter defaults for `exclude_from_ai` and `redacted_sections` to inbox/working/wiki templates so privacy controls are inspectable in Markdown.
- Added `[PRIVATE]` search tagging with preview suppression for private files without changing ranking or filtering behavior.
- Extended handoff generation to preserve private/exclude filtering and redact named H2 sections with `[REDACTED]` while keeping section headings visible.
- Added `scripts/privacy-audit.ps1` for privacy auditing and bulk frontmatter updates with per-file git commits.
- BMAD code review did not confirm any remaining defects in the 5.1 change set after validation.

### File List

- `templates/inbox-item.md` — MODIFIED
- `templates/working-note.md` — MODIFIED
- `templates/wiki-page.md` — MODIFIED
- `scripts/search.ps1` — MODIFIED
- `scripts/generate-handoff.ps1` — MODIFIED
- `scripts/privacy-audit.ps1` — NEW
- `tests/privacy-audit.Tests.ps1` — NEW
- `_bmad-output/implementation-artifacts/5-1-sensitive-content-controls.md` — UPDATED
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — UPDATED
