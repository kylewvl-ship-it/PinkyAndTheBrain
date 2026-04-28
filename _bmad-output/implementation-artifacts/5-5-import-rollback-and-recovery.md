# Story 5.5: Import Rollback and Recovery

**Story ID:** 5.5
**Epic:** 5 - Privacy & Project Management
**Status:** done
**Created:** 2026-04-28

---

## Story

As Reno,
I want to rollback a vault import that didn't work as expected,
so that I can return to a clean state and try again with different settings without data loss.

## Acceptance Criteria

1. **Discoverable rollback by import id, gated by recency window**
   - Given I want to rollback an import that completed within the last 7 days
   - When I run `.\scripts\rollback-import.ps1 -ImportId "import-<yyyyMMdd-HHmmss>[-<suffix>]"`
   - Then the script discovers the matching import log under `.ai/import-logs/import-<id>.json`, prints a summary (file count per knowledge folder, total size, import date), and lists the files that will be removed
   - And imports older than 7 days are rejected with a clear message and exit `1` unless `-AllowOld` is supplied; `-AllowOld` is documented in `-Help`
   - And missing or malformed import logs exit `1` with a clear message

2. **Confirmation gate**
   - Given the summary is shown
   - When I am prompted for confirmation
   - Then I must type the literal string `YES` (case-sensitive) to proceed; any other input aborts with no changes and exit `0`
   - And `-Confirm:$false` together with `-Force` may be supplied to skip the prompt for non-interactive automation; either alone is not sufficient

3. **Provenance-driven removal**
   - Given I confirm the rollback
   - When the rollback executes
   - Then only files whose frontmatter `import_id` matches the requested id AND whose `imported_from` matches the corresponding ledger entry are removed
   - And files lacking matching `import_id` frontmatter are never removed (no risk to existing PinkyAndTheBrain content)
   - And a confirmation summary is printed: e.g., "Removed 247 files imported on 2026-04-14"
   - And rollback artifacts are written under `.ai/rollback-logs/rollback-<rollback_id>.json` and `.md` with per-file records (`source_path` from import, `target_path`, `action` (`removed`|`kept`|`backed-up`|`error`|`skipped-not-found`|`skipped-not-matching`), `error`)

4. **Modified-since-import handling**
   - Given some imported files have been modified since import
   - When the rollback processes these files
   - Then a file is considered modified if its content hash differs from the value the importer recorded, or, if no content hash is recorded, its filesystem `LastWriteTimeUtc` is later than the recorded `import_date`
   - And by default the rollback prompts per-file, with three options: `remove`, `keep`, `backup-and-remove`. Backups are written under `.ai/rollback-backups/rollback-<rollback_id>/<original-relative-path>` preserving directory structure and a sidecar `.json` recording original path and original frontmatter
   - And the default behavior may be set non-interactively via `-OnModified` accepting `remove|keep|backup`; `-OnModified backup` is the safest preset
   - And every modified-file decision is recorded in the rollback log with the chosen action and reason

5. **Retry-friendly state and idempotency**
   - Given I want to retry import after rollback
   - When I run a new import preview on the same source vault
   - Then rolled-back files are no longer present in the configured knowledge folders so they cannot show as duplicates
   - And the original import log and the rollback log are preserved (not deleted) for audit, and a `rollback_id` and `rolled_back_at` are written into the original import log under a new `rollback` field
   - And re-running the same rollback id is idempotent: already-rolled-back imports exit `0` after printing a clear "already rolled back at <timestamp>" message and do not modify state again

6. **Safe failure behavior**
   - Given inputs are invalid or the run hits unexpected failures
   - When the rollback runs
   - Then unknown import id, missing import log, malformed log, or `-OnModified` with an unrecognized value exit `1` with a clear message and no removals
   - And per-file errors during removal continue to the next file (best-effort), are recorded in the rollback log, and the script ends with non-zero exit only if any per-file error occurred (`exit 3` for "completed with errors", reserving `1` for input errors and `2` for unexpected failures)
   - And paths that resolve outside configured knowledge folders are refused (defense in depth against tampered import logs)

## Tasks / Subtasks

- [x] Task 1: Add `scripts/rollback-import.ps1` skeleton (AC: 1, 6)
  - [x] 1.1 Create `scripts/rollback-import.ps1` with `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `Get-Config`, `$PSScriptRoot` lib resolution, matching `scripts/execute-import.ps1` and `scripts/import-preview.ps1`
  - [x] 1.2 Add parameters: `-ImportId` (required), `-AllowOld` (switch), `-OnModified` (`remove|keep|backup`, default `prompt`), `-Force` (switch), `-Help` (switch)
  - [x] 1.3 Resolve and validate `-ImportId`; locate `.ai/import-logs/import-<id>.json`; exit `1` for missing/malformed log
  - [x] 1.4 Refuse to operate on imports older than 7 days unless `-AllowOld` is set; clear message and exit `1`
  - [x] 1.5 Refuse target paths outside configured knowledge folders; never delete outside them. (Defense in depth.)
  - [x] 1.6 Do NOT modify or rely on the existing generic `scripts/rollback.ps1` (Git-history selective recovery); it is unrelated.

- [x] Task 2: Summary + confirmation gate (AC: 1, 2)
  - [x] 2.1 Print a summary including counts per knowledge folder, total size, import date, and a per-file preview list
  - [x] 2.2 Prompt for the literal string `YES` (case-sensitive); anything else aborts with exit `0` and no changes
  - [x] 2.3 Allow `-Force` together with `-Confirm:$false` to skip the prompt for automation; either alone keeps the prompt
  - [x] 2.4 In `PINKY_FORCE_NONINTERACTIVE = "1"` test mode, treat absence of `-Force -Confirm:$false` as abort (no hanging prompt)

- [x] Task 3: Provenance-driven removal pipeline (AC: 3, 6)
  - [x] 3.1 For each entry in the import log with `action = copied|renamed`, read the destination file's frontmatter via `scripts/lib/frontmatter.ps1`
  - [x] 3.2 Verify `import_id` and `imported_from` frontmatter match the rollback target before removing
  - [x] 3.3 Remove with `Remove-Item -LiteralPath`. On per-file failure, record and continue
  - [x] 3.4 Files missing on disk are recorded as `skipped-not-found`; mismatching frontmatter as `skipped-not-matching`
  - [x] 3.5 Print a confirmation summary at the end (e.g., "Removed N files imported on <date>")

- [x] Task 4: Modified-since-import handling (AC: 4)
  - [x] 4.1 Compare content hash if importer-recorded hash exists; otherwise compare filesystem `LastWriteTimeUtc` against `import_date` from frontmatter
  - [x] 4.2 In prompt mode, prompt per-modified-file with `remove|keep|backup-and-remove`; in non-interactive runs respect `-OnModified`
  - [x] 4.3 For `backup`, copy the file to `.ai/rollback-backups/rollback-<rollback_id>/<original-relative-path>` and write a sidecar `.json` with original path and original frontmatter, then remove the original
  - [x] 4.4 Every modified-file decision is recorded in the rollback log with chosen action and reason

- [x] Task 5: Logs and idempotency (AC: 3, 5)
  - [x] 5.1 Generate `rollback_id = rollback-yyyyMMdd-HHmmss` and write `.ai/rollback-logs/rollback-<rollback_id>.json` and `.md`
  - [x] 5.2 Update the original `.ai/import-logs/import-<id>.json` with a new `rollback` field: `{ "rollback_id": "...", "rolled_back_at": "..." }`
  - [x] 5.3 If the original import log already has a `rollback` field, treat the rollback as already-completed: exit `0`, print the prior `rollback_id` and timestamp, do not touch the filesystem
  - [x] 5.4 Use exclusive create-new file allocation when writing rollback artifacts to avoid collision with concurrent runs (mirror the pattern from `scripts/execute-import.ps1`)

- [x] Task 6: Pester coverage (AC: 1-6)
  - [x] 6.1 Create `tests/rollback-import.Tests.ps1` using `$TestDrive`, `PINKY_VAULT_ROOT`, `PINKY_GIT_REPO_ROOT`, and `PINKY_FORCE_NONINTERACTIVE = "1"`
  - [x] 6.2 Test happy-path rollback: removes only matching files, prints summary, writes rollback log
  - [x] 6.3 Test files lacking matching `import_id` are never removed (place a hand-authored file with no provenance and assert it survives)
  - [x] 6.4 Test recency window: imports older than 7 days exit `1` without `-AllowOld`; succeed with `-AllowOld`
  - [x] 6.5 Test confirmation gate: any input other than literal `YES` aborts; `-Force -Confirm:$false` skips prompt
  - [x] 6.6 Test modified-since-import detection (both hash and timestamp paths) and each `-OnModified` mode (`remove|keep|backup`); assert `backup` writes the file under `.ai/rollback-backups/...` with sidecar JSON
  - [x] 6.7 Test idempotency: a second run of the same rollback id is a no-op exit `0`
  - [x] 6.8 Test invalid `-ImportId`, missing log, malformed log all exit `1`
  - [x] 6.9 Test that paths resolving outside configured knowledge folders are refused (tampered log scenario)
  - [x] 6.10 Test post-rollback re-import preview no longer reports rolled-back files as duplicates (lightweight integration with `scripts/import-preview.ps1` if practical; otherwise assert the absence on disk)

- [x] Task 7: Validate and update story status (AC: 1-6)
  - [x] 7.1 Run `Invoke-Pester tests\rollback-import.Tests.ps1`
  - [x] 7.2 Run `Invoke-Pester tests\execute-import.Tests.ps1` to confirm no regression in 5.4
  - [x] 7.3 Update Dev Agent Record, File List, and status when implementation is complete

## Dev Notes

### Scope Boundaries

In scope:
- New script: `scripts/rollback-import.ps1`
- New tests: `tests/rollback-import.Tests.ps1`
- Generated artifacts under `.ai/rollback-logs/` and `.ai/rollback-backups/`
- Augmenting the original import log JSON with a `rollback` field for audit and idempotency

Out of scope:
- Editing or replacing the existing generic `scripts/rollback.ps1` (Git-history selective recovery); leave untouched
- Re-running classification / re-importing — handled by 5.3 and 5.4
- Cross-import rollback (rolling back multiple import ids in one run); pass them in separate invocations
- Changing the import log JSON shape produced by 5.4 (only adding a `rollback` field on rollback)
- Embeddings or hosted services

### Existing Patterns To Reuse

- PowerShell scripts with `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `Get-Config`, and `$PSScriptRoot`-relative lib loading (see `scripts/execute-import.ps1`, `scripts/import-preview.ps1`)
- `scripts/lib/frontmatter.ps1` for `Get-FrontmatterData` / `Get-FrontmatterValue`. Do not introduce a YAML dependency
- `Set-Content -Path ... -Value ... -Encoding UTF8` for generated artifacts
- Exclusive create-new file allocation pattern from `scripts/execute-import.ps1` for rollback-id uniqueness
- Test setup via `$TestDrive`, `PINKY_VAULT_ROOT`, `PINKY_GIT_REPO_ROOT`, `PINKY_FORCE_NONINTERACTIVE = "1"`

### Architecture Requirements

- Local-first, Markdown-friendly: rollback acts on plain Markdown files and Markdown logs [Source: `_bmad-output/planning-artifacts/prd.md` FR-015, NFR-001, NFR-002, NFR-011]
- Provenance-driven safety: only files with matching `import_id` + `imported_from` are eligible for removal [Source: `_bmad-output/planning-artifacts/architecture.md` Provenance Tracking; Story 5.4 frontmatter contract]
- Inspectable automation: every action (removed, kept, backed-up, error) is recorded in JSON+Markdown [Source: `_bmad-output/planning-artifacts/prd.md` NFR-010]
- Idempotent + rollback-friendly: re-running an already-completed rollback must be a no-op [Source: `_bmad-output/planning-artifacts/architecture.md` Error Handling — Idempotent operations with rollback support, NFR-011]
- Path containment: only ever delete inside configured knowledge folders [Source: Story 5.2 path-containment learning; Story 5.4 fix for source-path containment]

### Story 5.4 Contract Reused

Imported files have at least these frontmatter fields:

```yaml
imported_from: "<source path>"
import_date: "<ISO-8601>"
import_id: "import-yyyyMMdd-HHmmss[-<suffix>]"
```

The import log at `.ai/import-logs/import-<id>.json` contains per-file records with `source_path`, `target_path`, `category`, `action` (`copied|skipped|renamed|error`). Rollback uses `target_path` to locate files and verifies `import_id` + `imported_from` against frontmatter before removing.

If the importer recorded a per-file content hash, prefer it for modified-since detection. If not, fall back to filesystem `LastWriteTimeUtc` vs `import_date`. (5.4 does not strictly require recording per-file hash; rollback must work either way.)

### Rollback Log Shape (suggested)

```json
{
  "rollback_id": "rollback-20260428-150000",
  "import_id": "import-20260428-120000",
  "started_at": "2026-04-28T15:00:00Z",
  "finished_at": "2026-04-28T15:00:42Z",
  "totals": {"removed": 0, "kept": 0, "backed_up": 0, "errors": 0, "skipped": 0},
  "files": [
    {
      "source_path": "C:/MyVault/Note.md",
      "target_path": "knowledge/working/note.md",
      "action": "removed",
      "modified_since_import": false,
      "error": null
    }
  ],
  "status": "completed"
}
```

### Previous Story Intelligence

From Story 5.4:
- Use exclusive `[System.IO.File]::Open(..., FileMode.CreateNew, ...)` allocation for IDs to avoid concurrent collisions; mirror the same retry-with-suffix loop here
- Always validate path containment with the resolved knowledge folders; do not trust paths from JSON logs blindly
- Per-file failures must continue, not abort; record and aggregate
- The repo has unrelated pre-existing full-suite test failures; validate with focused tests and report unrelated suite failures separately if a full run is performed

From Story 5.3:
- Frontmatter parser supports simple inline arrays only; preserve unparseable frontmatter as-is rather than rewriting silently

From Story 5.2:
- Path containment matters for any deletion or write; resolve deliberately and constrain to the intended scope

### Testing Requirements

Required focused tests in `tests/rollback-import.Tests.ps1` (see Task 6 for the exact list).

Regression guidance:
- Run `Invoke-Pester tests\rollback-import.Tests.ps1`
- Run `Invoke-Pester tests\execute-import.Tests.ps1` to ensure 5.4 still passes after any shared-helper changes
- If `scripts/lib/frontmatter.ps1` is touched, also run `frontmatter`/`config-loader`/`import-conversation`/`import-preview` tests

### References

- `_bmad-output/planning-artifacts/epics.md` — Story 5.5 acceptance criteria
- `_bmad-output/planning-artifacts/prd.md` — FR-015, NFR-001, NFR-002, NFR-010, NFR-011
- `_bmad-output/planning-artifacts/architecture.md` — provenance tracking, idempotent + rollback-friendly, inspectable automation
- `_bmad-output/implementation-artifacts/5-4-vault-import-execution.md` — frontmatter contract, log shape, exclusive allocation pattern
- `scripts/execute-import.ps1` — existing patterns (StrictMode, Get-Config, exclusive allocation, path containment)
- `scripts/lib/frontmatter.ps1` — frontmatter helpers

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- `Invoke-Pester tests\rollback-import.Tests.ps1` - 11 passed, 0 failed
- `Invoke-Pester tests\execute-import.Tests.ps1` - 18 passed, 0 failed

### Completion Notes List

- Added a dedicated rollback-import script that loads repo config, validates import logs, enforces a 7-day recency gate, refuses tampered paths outside knowledge folders, and leaves `scripts/rollback.ps1` untouched.
- Implemented provenance-driven deletion using `import_id` and `imported_from` frontmatter from `scripts/lib/frontmatter.ps1`; mismatches and missing files are logged without deletion.
- Added modified-file handling with hash-first detection, timestamp fallback, prompt/default decisions, `-OnModified remove|keep|backup`, backup sidecars, rollback JSON/Markdown logs, original import-log audit updates, and idempotent no-op reruns.
- Added focused Pester coverage for AC1-AC6 and confirmed Story 5.4 execute-import regression remains green.

### File List

- scripts/rollback-import.ps1
- tests/rollback-import.Tests.ps1
- _bmad-output/implementation-artifacts/5-5-import-rollback-and-recovery.md
- _bmad-output/implementation-artifacts/sprint-status.yaml

### Review Findings

- [x] R1 (HIGH): `completed-with-errors` path wrote `rollback` field to import log, blocking retry. Fixed: field only written when `$totals.errors -eq 0`.
- [x] R2 (MEDIUM): confirmation-gate test lacked survival assertions after aborted/Force-only runs. Fixed: `Test-Path $target | Should Be $true` added before confirmed run.
- [x] R3 (MEDIUM): hard-coded `2026-04-28` timestamps would expire after 7-day window. Fixed: script-scope relative timestamps computed at load time.
