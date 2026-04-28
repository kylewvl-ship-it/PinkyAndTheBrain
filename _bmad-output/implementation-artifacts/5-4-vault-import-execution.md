# Story 5.4: Vault Import Execution

**Story ID:** 5.4
**Epic:** 5 - Privacy & Project Management
**Status:** done
**Created:** 2026-04-28

---

## Story

As Reno,
I want to execute the vault import with my chosen settings and safeguards,
so that I can safely bring my existing knowledge into PinkyAndTheBrain without risking the source vault.

## Acceptance Criteria

1. **Non-destructive execution from preview**
   - Given I have a preview JSON produced by Story 5.3 (`scripts/import-preview.ps1`)
   - When I run `.\scripts\execute-import.ps1 -PreviewFile ".ai/import-previews/import-preview-<timestamp>.json"`
   - Then files are **copied** (not moved) from the source vault to the appropriate PinkyAndTheBrain knowledge folders based on each entry's `proposed_category`
   - And the original source vault remains completely unchanged (verified by file-existence + size assertions)
   - And files classified `skip` or `unclassified` are not copied
   - And files classified `archive` go to the configured `archive` folder

2. **Provenance and merge metadata**
   - Given imported files have existing frontmatter or metadata
   - When files are processed during import
   - Then each imported file's frontmatter is augmented with `imported_from: <original source path>` and `import_date: <ISO-8601 timestamp>` and `import_id: <import run id>`
   - And existing frontmatter fields are preserved; PinkyAndTheBrain required defaults are added only when missing: default `confidence: medium`, default `project: imported`, default `status` appropriate for the target category
   - And conflicts between existing frontmatter and required fields are recorded as warnings in the import log (existing values are not overwritten)
   - And invalid or unparseable frontmatter is flagged in the log and the file is still imported (raw content preserved)

3. **Folder mapping and naming**
   - Given the preview supplied folder mappings or unmapped folders
   - When the import processes files into target folders
   - Then folder mappings from the preview are applied consistently
   - And unmapped source folders cause the imported file to receive a `project: <sanitized-folder-name>` frontmatter tag (e.g., source `Work/` → `project: work`) instead of creating ad-hoc target subfolders outside the configured knowledge folders
   - And destination filenames are sanitized for safe filesystem use (lowercase, spaces → `-`, strip characters disallowed by the existing capture/promotion conventions)
   - And destination filename collisions are resolved deterministically by appending `-1`, `-2`, … and the rename is recorded in the import log

4. **Resilient error handling and resumability**
   - Given the import encounters errors or per-file conflicts
   - When issues arise during execution
   - Then the import continues processing remaining files instead of aborting (top-level fatal input errors still exit `1`/`2` per existing repo conventions)
   - And every per-file error is logged with the source path, target path, and error message
   - And a run-state file is written incrementally so the import can be resumed via `-Resume` from where it left off (already-processed source paths are skipped on resume)
   - And the import id, run-state file path, and log file path are printed to console at start and end

5. **Detailed import log artifact**
   - Given the import completes (successfully, partially, or with errors)
   - When the run finishes
   - Then a JSON import log is written under `.ai/import-logs/import-<id>.json` containing: `import_id`, `started_at`, `finished_at`, source vault path, preview file path, per-file records (`source_path`, `target_path`, `category`, `action` (`copied`|`skipped`|`renamed`|`error`), `warnings`, `error`), totals, and a status summary
   - And a Markdown report is written beside it for human review
   - And the artifacts paths are stable and discoverable for Story 5.5 rollback

6. **Safe failure behavior**
   - Given the preview file is missing, malformed, or references a non-existent source vault, or the source vault is unreadable
   - When the import runs
   - Then invalid user input (missing/malformed `-PreviewFile`, missing source vault) exits `1` with a clear message and does not write to any knowledge folder
   - And per-file unreadable errors are recorded in the log without stopping the whole run
   - And unexpected system failures exit `2`

## Tasks / Subtasks

- [x] Task 1: Add `scripts/execute-import.ps1` skeleton (AC: 1, 6)
  - [x] 1.1 Create `scripts/execute-import.ps1` with `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `Get-Config`, and `$PSScriptRoot`-relative lib resolution, matching `scripts/import-preview.ps1` and `scripts/import-conversation.ps1`
  - [x] 1.2 Add parameters: `-PreviewFile` (required), `-Resume` (switch), `-DryRun` (switch), `-Help` (switch). `-DryRun` performs all classification/path resolution but does not copy files
  - [x] 1.3 Validate `-PreviewFile` exists and parses as JSON with the expected Story 5.3 shape; exit `1` for user input errors, `2` for unexpected failures
  - [x] 1.4 Resolve target knowledge folders from `Get-Config` (inbox, raw, working, wiki, archive). Do not write outside these folders.

- [x] Task 2: Implement copy + provenance pipeline (AC: 1, 2, 3)
  - [x] 2.1 For each preview entry whose `proposed_category` is one of `inbox|raw|working|wiki|archive`, copy the source file into the corresponding target folder
  - [x] 2.2 Use `Copy-Item -LiteralPath` (never move) and verify destination size matches source size
  - [x] 2.3 Skip entries with `proposed_category` of `skip` or `unclassified`
  - [x] 2.4 Sanitize destination filenames (lowercase, spaces → `-`, strip disallowed characters), reusing helpers from existing capture/promotion scripts where available; copy a small local helper rather than dot-sourcing
  - [x] 2.5 Resolve filename collisions deterministically (`-1`, `-2`, …) and record the rename in the per-file log record
  - [x] 2.6 Merge frontmatter using `scripts/lib/frontmatter.ps1`: preserve existing fields; add `imported_from`, `import_date`, `import_id`; fill missing required defaults (`confidence: medium`, `project: imported`, category-appropriate `status`); record conflicts as warnings without overwriting

- [x] Task 3: Folder mapping + project tagging (AC: 3)
  - [x] 3.1 Honor mapping rules already encoded in the preview JSON (`mapping_rules` and per-file `proposed_category`); do not re-classify
  - [x] 3.2 For unmapped source folders, derive a project tag from the immediate source folder name (sanitized) and add `project: <name>` to imported frontmatter when no `project` field already exists
  - [x] 3.3 Do not create new top-level folders outside configured knowledge folders

- [x] Task 4: Resumability + run-state (AC: 4)
  - [x] 4.1 Generate an `import_id` of `import-yyyyMMdd-HHmmss` and a run-state file path under `.ai/import-runs/<import_id>.json`
  - [x] 4.2 After each file is processed, append/update the run-state with the source path and final action so a partial run is resumable
  - [x] 4.3 When `-Resume` is supplied, locate the most recent in-progress run-state for the same preview file and skip already-processed source paths
  - [x] 4.4 If no matching run-state exists with `-Resume`, exit `1` with a clear message

- [x] Task 5: Logs and Markdown report (AC: 5)
  - [x] 5.1 Write `.ai/import-logs/import-<id>.json` with the full per-file ledger, totals, started/finished timestamps, preview file path, and status summary
  - [x] 5.2 Write `.ai/import-logs/import-<id>.md` summarizing counts per category, renames, warnings, errors, and a next-step note for Story 5.5 rollback
  - [x] 5.3 Print the import id, run-state file, JSON log path, and Markdown report path to console at start and end

- [x] Task 6: Pester coverage (AC: 1-6)
  - [x] 6.1 Create `tests/execute-import.Tests.ps1` using `$TestDrive`, `PINKY_VAULT_ROOT`, `PINKY_GIT_REPO_ROOT`, and `PINKY_FORCE_NONINTERACTIVE = "1"` per existing test conventions
  - [x] 6.2 Test that source vault files are not modified (compare hashes/sizes before/after)
  - [x] 6.3 Test that files in each `proposed_category` are copied into the corresponding configured target folder
  - [x] 6.4 Test that `skip`/`unclassified` entries are not copied
  - [x] 6.5 Test that frontmatter is augmented with `imported_from`, `import_date`, `import_id`, defaults applied only when missing, and existing values preserved (conflicts logged)
  - [x] 6.6 Test deterministic filename collision suffixes
  - [x] 6.7 Test resume behavior: simulate partial run, then `-Resume` and assert previously-copied files are skipped
  - [x] 6.8 Test invalid preview file exits `1` and that JSON/Markdown log artifacts are created on success and on partial-error runs
  - [x] 6.9 Test `-DryRun` writes no files into knowledge folders

- [x] Task 7: Validate and update story status (AC: 1-6)
  - [x] 7.1 Run `Invoke-Pester tests\execute-import.Tests.ps1`
  - [x] 7.2 Run regression tests for any directly affected shared helpers (`tests\import-preview.Tests.ps1` and any `frontmatter` tests if helpers are touched)
  - [x] 7.3 Update Dev Agent Record, File List, and status when implementation is complete

## Dev Notes

### Scope Boundaries

In scope:
- New script: `scripts/execute-import.ps1`
- New tests: `tests/execute-import.Tests.ps1`
- Generated artifacts under `.ai/import-logs/` and `.ai/import-runs/`
- Reading the preview JSON written by Story 5.3 and copying source files into configured knowledge folders

Out of scope:
- Rollback or recovery — Story 5.5
- Re-classifying files (the preview is the source of truth)
- Editing source vault files
- Interactive UI; `-DryRun` and re-running the script with new preview files is the iteration model
- Embeddings, semantic dedup, or hosted services
- Replacing or modifying the existing generic `scripts/rollback.ps1` (Git-history selective recovery), which is unrelated to import-specific rollback in 5.5

### Existing Patterns To Reuse

- PowerShell scripts with `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `Get-Config`, and `$PSScriptRoot`-relative lib loading, matching `scripts/import-preview.ps1`, `scripts/import-conversation.ps1`, `scripts/manage-project-tags.ps1`
- Use `scripts/lib/frontmatter.ps1` for `Get-FrontmatterData`, `Get-FrontmatterValue`, and frontmatter merging. Do not add a YAML parser dependency
- Use `Set-Content -Path ... -Value ... -Encoding UTF8` for generated artifacts and merged Markdown files
- Use `Copy-Item -LiteralPath` for safe path-literal copying; never `Move-Item`
- Test setup uses `$TestDrive`, `PINKY_VAULT_ROOT`, `PINKY_GIT_REPO_ROOT`, and `PINKY_FORCE_NONINTERACTIVE = "1"` (see `tests/import-preview.Tests.ps1` and `tests/import-conversation.Tests.ps1`)

### Architecture Requirements

- Local-first and Markdown-compatible: imported files remain plain Markdown with merged frontmatter [Source: `_bmad-output/planning-artifacts/prd.md` FR-015, NFR-001, NFR-002, NFR-011]
- Non-destructive migration: copy, never move; original vault untouched [Source: `_bmad-output/planning-artifacts/architecture.md` Error Handling, NFR-010/NFR-011]
- Inspectable automation: every action recorded in JSON/Markdown logs; no hidden state [Source: `_bmad-output/planning-artifacts/prd.md` NFR-010]
- Provenance: `imported_from` and `import_date` are mandatory on every imported file [Source: `_bmad-output/planning-artifacts/architecture.md` Provenance Tracking]
- Idempotent + rollback-friendly: `import_id` on imported files is the rollback handle for Story 5.5 [Source: `_bmad-output/planning-artifacts/architecture.md` Error Handling — Idempotent operations with rollback support, NFR-011]

### Required Frontmatter on Imported Files

Every successfully copied file must have at minimum:

```yaml
---
imported_from: "<absolute or vault-relative source path>"
import_date: "2026-04-28T12:00:00Z"
import_id: "import-20260428-120000"
project: "<existing or sanitized-folder-name or 'imported'>"
confidence: "<existing or 'medium'>"
status: "<existing or category-appropriate default>"
---
```

Conflicts between existing values and PinkyAndTheBrain defaults must be logged as warnings; existing values must be preserved.

### Suggested Run-State Shape

```json
{
  "import_id": "import-20260428-120000",
  "preview_file": ".ai/import-previews/import-preview-20260427-110000.json",
  "started_at": "2026-04-28T12:00:00Z",
  "last_updated_at": "2026-04-28T12:00:42Z",
  "processed": [
    {"source_path": "C:/MyVault/Note.md", "action": "copied", "target_path": "knowledge/working/note.md"}
  ]
}
```

### Suggested Import Log Shape

```json
{
  "import_id": "import-20260428-120000",
  "preview_file": ".ai/import-previews/import-preview-20260427-110000.json",
  "source_vault": "C:/MyVault",
  "started_at": "2026-04-28T12:00:00Z",
  "finished_at": "2026-04-28T12:01:30Z",
  "totals": {"copied": 0, "skipped": 0, "renamed": 0, "errors": 0, "warnings": 0},
  "files": [
    {
      "source_path": "C:/MyVault/Note.md",
      "target_path": "knowledge/working/note.md",
      "category": "working",
      "action": "copied",
      "warnings": [],
      "error": null
    }
  ],
  "status": "completed"
}
```

### Previous Story Intelligence

From Story 5.3:
- Mapping rules and per-file classification are already in the preview JSON; do not re-implement classification heuristics here
- Path containment matters: only ever write under configured knowledge folders; resolve paths deliberately
- Frontmatter parser supports simple inline arrays only; preserve unparseable frontmatter as-is rather than rewriting silently
- Use the deterministic `yyyyMMdd-HHmmss` ID convention shared with `import-conversation.ps1` and `import-preview.ps1`
- The repo has unrelated pre-existing full-suite test failures; validate with focused tests and report unrelated suite failures separately if a full run is performed

From Story 5.2:
- Frontmatter arrays may be scalar inline values such as `["work","research"]`; existing parser helpers only support simple inline arrays
- Malformed frontmatter should be reported, not silently rewritten

### Testing Requirements

Required focused tests in `tests/execute-import.Tests.ps1`:
- Invalid `-PreviewFile` exits `1`
- Source vault files are not modified by the import (hash/size compared)
- Each `proposed_category` ends up in its configured target folder
- `skip` and `unclassified` entries are not copied
- Imported files contain `imported_from`, `import_date`, `import_id`
- Existing frontmatter values are preserved; defaults applied only when missing; conflicts produce log warnings
- Filename collisions resolved deterministically (`-1`, `-2`)
- `-Resume` skips already-processed entries from a partial run-state
- `-DryRun` writes no files into knowledge folders
- JSON and Markdown log artifacts are created under `.ai/import-logs/`

Regression guidance:
- Run `Invoke-Pester tests\execute-import.Tests.ps1`
- If `scripts/lib/frontmatter.ps1` is touched, also run affected tests for `frontmatter`/`config-loader`/`import-conversation`/`import-preview`

### References

- `_bmad-output/planning-artifacts/epics.md` — Story 5.4 acceptance criteria
- `_bmad-output/planning-artifacts/prd.md` — FR-015, NFR-001, NFR-002, NFR-010, NFR-011
- `_bmad-output/planning-artifacts/architecture.md` — local-first Markdown/frontmatter, provenance, inspectable automation, idempotent + rollback-friendly
- `_bmad-output/implementation-artifacts/5-3-vault-import-preview-and-analysis.md` — preview JSON shape, mapping/profile model, prior-story learnings
- `scripts/import-preview.ps1` — preview JSON producer (input contract)
- `scripts/import-conversation.ps1` — script boilerplate, frontmatter merge style, ID convention
- `scripts/lib/frontmatter.ps1` — frontmatter helpers (do not introduce a new YAML parser)

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

### Completion Notes List

- Implemented `scripts/execute-import.ps1` as a preview-driven importer that only writes to configured knowledge folders plus `.ai/import-logs/` and `.ai/import-runs/`, because the story required strict path containment and rollback-friendly artifacts.
- Kept filename sanitization and folder-project derivation local to the script instead of adding new shared helpers, because the story explicitly scoped the work to Story 5.4 and the repo already uses small script-local helpers for task-specific behavior.
- Reused `scripts/lib/frontmatter.ps1` for frontmatter detection and updates, preserving existing fields and logging conflicts rather than overwriting them to satisfy the provenance and non-destructive metadata requirements.
- Added focused Pester coverage for invalid preview handling, category routing, source preservation, frontmatter merging, deterministic collision handling, resumability, partial-error logging, and `-DryRun` behavior.
- Shared helpers were not modified, so no additional regression suites were required beyond `Invoke-Pester tests\execute-import.Tests.ps1`.
- Fixed review findings by enforcing source-vault containment, preventing errored rows from becoming resume-skippable, validating resume fingerprints, suffixing colliding import IDs, guarding Windows reserved filenames, surfacing unknown categories, and adding focused negative-path tests.
- Fixed re-review findings by reserving new run-state files atomically, validating source stability before destination promotion, and adding focused coverage for suffixed ID allocation plus source-change cleanup/resume behavior.

### File List

- `scripts/execute-import.ps1`
- `tests/execute-import.Tests.ps1`
- `_bmad-output/implementation-artifacts/5-4-vault-import-execution.md`
- `_bmad-output/agent-handoff/codex-result.md`

### Review Findings

Code review of 2026-04-28 (Codex BMAD Code Review). 7 issues raised: 2 high, 3 medium, 2 low.

- [x] [Review][Patch] **HIGH** Source-path containment not enforced [scripts/execute-import.ps1:565-608] — preview entries with `source_path` outside the resolved `source_vault` are accepted, allowing any readable local file to be copied into knowledge folders. Reject entries whose resolved path is not under `source_vault`.
- [x] [Review][Patch] **HIGH** Errored entries are marked resume-skippable [scripts/execute-import.ps1:607-637] — a per-file failure after `Copy-Item` can leave a partially imported file behind while the run-state records the source as processed (`action = error`). Subsequent `-Resume` skips it. Either copy to a temp path and atomically promote after frontmatter merge succeeds, or remove the partial destination and exclude `error` rows from the resume-skip set.
- [x] [Review][Patch] **MEDIUM** Stale/mismatched run-state silently accepted by `-Resume` [scripts/execute-import.ps1:512-531] — `-Resume` only matches on `preview_file` path; the same path with rewritten content, a different source vault, or a different config is accepted. Persist a preview-content hash plus source-vault/config metadata in the run-state and fail clearly when it no longer matches the current execution.
- [x] [Review][Patch] **MEDIUM** `import_id` collision on concurrent runs [scripts/execute-import.ps1:533-537] — second-precision timestamp can produce identical run-state and log paths for two runs in the same second, causing overwrites. Add a collision-resistant suffix or retry on existing path.
- [x] [Review][Patch] **MEDIUM** Windows reserved device names not handled [scripts/execute-import.ps1:173-184] — sanitizer permits `CON.md`, `PRN.md`, `AUX.md`, `NUL.md`, `COM1.md`, `LPT1.md`. Detect reserved stems case-insensitively and prefix/suffix before path generation.
- [x] [Review][Patch] **LOW** Unknown `proposed_category` silently skipped [scripts/execute-import.ps1:574-585] — only `skip` and `unclassified` should be clean skips; typos or unexpected enum values must be recorded as warnings or per-file errors so they are visible in the import log.
- [x] [Review][Patch] **LOW** Test coverage missing for negative paths [tests/execute-import.Tests.ps1:132-310] — add focused tests for source path outside `source_vault`, malformed preview JSON, missing source vault, unreadable source file, invalid frontmatter preserved/logged, reserved names, import-id collision, and stale/mismatched `-Resume`.

#### Re-review cycle 1 (2026-04-28)

- [x] [Re-Review][Patch] **HIGH** Post-promotion source-stability check leaves orphan destination [scripts/execute-import.ps1:747-768] — after `Move-Item` promotes the temp file to the final destination, the source-size stability check can still throw; the catch records `error` but the destination remains and the row is not added to processed state, so `-Resume` produces a duplicate suffixed import. Perform all source-stability checks before promoting the temp file, or track creation of `$targetPath` and delete it in the outer catch before recording the per-file error.
- [x] [Re-Review][Patch] **MEDIUM** `import_id` allocation is not atomic for concurrent runs [scripts/execute-import.ps1:141-163] — two imports started in the same second can both observe no existing artifacts, choose identical `import_id`, then overwrite each other's run/log files. Reserve the run-state path atomically (exclusive `FileMode.CreateNew` or equivalent) before returning the ID, or always append a sufficiently random suffix and still create the state file with exclusive semantics.
- [x] [Re-Review][Patch] **LOW** Missing tests for concurrent ID allocation and post-promotion source-change cleanup [tests/execute-import.Tests.ps1] — add focused tests covering both new fix paths.
