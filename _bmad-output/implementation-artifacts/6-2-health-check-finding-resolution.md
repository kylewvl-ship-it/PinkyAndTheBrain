# Story 6.2: Health Check Finding Resolution

**Story ID:** 6.2
**Epic:** 6 - System Health & Maintenance
**Status:** ready-for-dev
**Created:** 2026-04-29

---

## Story

As Reno,
I want to review and resolve health check findings with guided repair actions,
so that I can systematically improve my knowledge base quality.

## Acceptance Criteria

1. **Interactive finding review** — Given I have health check findings, when I review a specific finding I see: affected file, issue description, severity, rule triggered, and 2–3 suggested repair actions. I can choose from: `update-metadata`, `accept-extracted`, `reject-extracted`, `fix-link`, `merge-duplicate`, `ignore-fingerprint`, `rebuild-index`, `archive`, `defer`. Each action shows what will be changed before I confirm.

2. **Broken link repair** — Given I choose to fix a broken link, the system shows potential link targets by filename similarity, I can pick the correct target or mark the link as intentionally broken, and the fix is applied with confirmation.

3. **Batch operations** — I can batch-apply the same fix to all files missing the same metadata field, bulk-archive all files not updated in over a year, and batch-update `review_trigger` dates for files in the same project or domain.

4. **Defer with expiry** — When I defer a finding, it is excluded from future health check reports for 30 days, I can add a note, and deferred findings appear in a separate "Deferred Issues" section of the health report.

## Tasks / Subtasks

- [ ] Task 1: Create `scripts/resolve-findings.ps1` (AC: 1, 2)
  - [ ] 1.1 Parameters: `-ReportFile` (path to `knowledge/reviews/health-report-YYYY-MM-DD.md`), `-FindingIndex` (1-based integer to target a specific finding), `-Action` (ValidateSet: `update-metadata`, `accept-extracted`, `reject-extracted`, `fix-link`, `merge-duplicate`, `ignore-fingerprint`, `rebuild-index`, `archive`, `defer`), `-DeferNote` (string, used with `defer`), `-Force` (switch, skip confirmation prompt), `-WhatIf` (switch), `-Help` (switch)
  - [ ] 1.2 Parse the report Markdown file to extract the ordered findings list; fail clearly if file not found or malformed
  - [ ] 1.3 For `fix-link`: read the affected file, find the broken link, compute Levenshtein distance against all `.md` stems in all non-archived knowledge folders, present top-3 candidates (or none if no close match), prompt for selection or `mark-broken`; apply chosen fix with `Set-Content -Encoding UTF8`
  - [ ] 1.4 For `update-metadata`: prompt for the new field value (or accept via `-Value` param), write updated frontmatter using `scripts/lib/frontmatter.ps1` helpers, print before/after diff
  - [ ] 1.5 For `archive`: delegate to `scripts/archive-content.ps1 -File <path> -Reason "health-check-resolution"` (do not re-implement archive logic)
  - [ ] 1.6 For `rebuild-index`: emit a clear "index.md rebuild is a manual step — edit `<folder>/index.md` to reflect current content" message; this action is informational only
  - [ ] 1.7 For `defer`: write a defer record to `.ai/health-deferred.json` (create if absent); record: `{ "file": "...", "rule": "...", "deferred_until": "<ISO-8601 +30 days>", "note": "...", "deferred_at": "<now>" }`; print confirmation
  - [ ] 1.8 For `ignore-fingerprint`, `accept-extracted`, `reject-extracted`, `merge-duplicate`: record the decision in `.ai/health-deferred.json` with a special `action` field so the decision persists; emit a clear "recorded — re-run health-check to see updated report" message. Full automated merge is out of scope.
  - [ ] 1.9 Confirmation gate: unless `-Force` is set, print the planned change and prompt `Y/N` before applying; in `PINKY_FORCE_NONINTERACTIVE = "1"` mode treat absence of `-Force` as abort with exit `0`

- [ ] Task 2: Integrate deferred findings into `scripts/health-check.ps1` (AC: 4)
  - [ ] 2.1 At the end of each health check run, load `.ai/health-deferred.json` if present; filter out findings whose `file` + `rule` match an active defer record (where `deferred_until` is in the future)
  - [ ] 2.2 Collect all active defer records that match suppressed findings; append them as a "Deferred Issues" section in the console output and in the report file, showing: file, rule, deferred_until, note
  - [ ] 2.3 Expired defer records (where `deferred_until` is in the past) are treated as if absent — the finding reappears normally
  - [ ] 2.4 Do not modify the `.ai/health-deferred.json` file during a health check run (read-only consumption)

- [ ] Task 3: Batch operations via `scripts/resolve-findings.ps1` (AC: 3)
  - [ ] 3.1 Add `-Batch` switch: when set with `-Action update-metadata -Field <name> -Value <val>`, apply the metadata update to all findings in the report that have the same `rule` and missing field
  - [ ] 3.2 Add `-BulkArchiveStale` switch: archive all files in the report with `Stale Content` severity `High` (>12 months) that haven't been updated in over a year; delegate each to `archive-content.ps1`; prompt once for batch confirmation unless `-Force`
  - [ ] 3.3 Add `-BatchExtendReview -Days <n> -Project <tag>`: for all `Stale Content` findings in files whose frontmatter `project` matches `<tag>`, call `update-wiki-metadata.ps1 -File <path> -ReviewTrigger <now+days>`. Emit a summary of files updated.

- [ ] Task 4: Pester tests in `tests/resolve-findings.Tests.ps1` (AC: 1–4)
  - [ ] 4.1 Setup: `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_GIT_REPO_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"` — match all existing test patterns
  - [ ] 4.2 Test fix-link: file with `[[missing-page]]` → script presents candidates, selects first, link is rewritten and confirmed
  - [ ] 4.3 Test update-metadata: file missing `confidence` → script writes `confidence: medium` to frontmatter, before/after printed
  - [ ] 4.4 Test archive action: delegates to `archive-content.ps1` with expected args; original file moved/archived
  - [ ] 4.5 Test defer: creates `.ai/health-deferred.json` with correct `deferred_until` (+30 days); deferred finding absent from next `health-check.ps1` run
  - [ ] 4.6 Test defer expiry: expired defer record causes finding to reappear in health check output
  - [ ] 4.7 Test batch update-metadata: all findings with same missing field updated in one run
  - [ ] 4.8 Test bulk-archive-stale: High-severity stale files archived; Medium-severity files untouched
  - [ ] 4.9 Test confirmation gate: `-Force` skips prompt; absent `-Force` in NONINTERACTIVE mode aborts with exit 0
  - [ ] 4.10 Test deferred section in health report: deferred findings appear under "Deferred Issues" in both console and report file

- [ ] Task 5: Validate and update story status
  - [ ] 5.1 Run `Invoke-Pester tests\resolve-findings.Tests.ps1`
  - [ ] 5.2 Run `Invoke-Pester tests\health-check.Tests.ps1` (regression — story 6.1)
  - [ ] 5.3 Update Dev Agent Record, File List, and status when complete

## Dev Notes

### Scope Boundaries

In scope:
- New script: `scripts/resolve-findings.ps1`
- Modified: `scripts/health-check.ps1` (defer integration only — Tasks 2.1–2.4)
- New tests: `tests/resolve-findings.Tests.ps1`
- Generated artifacts: `.ai/health-deferred.json`

Out of scope:
- Obsidian-specific link repair (Story 6.3 covers offline/hook-free operation)
- Full automated content merge for duplicate findings (AC says "merge duplicate" is an action choice, not an automated merge; recording the decision is sufficient)
- Creating or modifying `scripts/archive-content.ps1` — delegate only
- Modifying `scripts/update-wiki-metadata.ps1` — call it as-is

### Existing Scripts to Delegate To (Do Not Reimplement)

- `scripts/archive-content.ps1` — accepts `-File`, `-Reason`, `-ReplacedBy`, `-WhatIf`. Use for `archive` action and `BulkArchiveStale`.
- `scripts/update-wiki-metadata.ps1` — accepts `-File`, `-ReviewTrigger`, `-Status`, `-Confidence`, `-MarkVerified`, `-WhatIf`. Use for `BatchExtendReview`.
- `scripts/lib/frontmatter.ps1` — `Get-FrontmatterData`, `Set-FrontmatterValue` (or equivalent). Use for `update-metadata` action.

### Existing Patterns To Reuse

- `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`
- `Get-Config` from `scripts/lib/common.ps1`
- Confirmation gate pattern (print planned change → prompt `YES` or `Y/N` → check `PINKY_FORCE_NONINTERACTIVE`): mirror `scripts/rollback-import.ps1`
- `Set-Content -Path ... -Value ... -Encoding UTF8` for all file writes
- Test scaffolding: `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_GIT_REPO_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"` (see `tests/rollback-import.Tests.ps1`, `tests/health-check.Tests.ps1`)
- Per-file errors continue (don't abort batch runs); aggregate and report at end

### Defer Record Format (`.ai/health-deferred.json`)

```json
[
  {
    "file": "wiki/my-page.md",
    "rule": "require-wiki-sources",
    "action": "defer",
    "deferred_at": "2026-04-29T10:00:00Z",
    "deferred_until": "2026-05-29T10:00:00Z",
    "note": "sources being gathered"
  }
]
```

For non-defer decision actions (`ignore-fingerprint`, `accept-extracted`, `reject-extracted`, `merge-duplicate`), use the same shape but `action` = the chosen action name and omit or null `deferred_until`. These records are permanent until manually removed.

### Health Report File Parsing

The health report Markdown (`knowledge/reviews/health-report-YYYY-MM-DD.md`) produced by `health-check.ps1` (Story 6.1) has this structure:

```markdown
---
generated: YYYY-MM-DD
check_type: all
total_findings: N
---

# Health Check Report - YYYY-MM-DD

## Summary
| Type | High | Medium | Low | Total |

## Missing Metadata
- **High** wiki/page.md
  - Rule: require-metadata
  - Issue: ...
  - Suggested repair: ...

## Broken Links
...
```

Parse by scanning section headers (`^## `) for finding groups, then per-finding blocks (`^- \*\*(High|Medium|Low)\*\*`). Extract `File`, `Severity`, `Rule`, `Issue`, `Suggested repair` from the indented lines.

### Architecture Alignment

- Interactive repair with human confirmation before changes — NFR-010 inspectable automation [Source: `_bmad-output/planning-artifacts/architecture.md`]
- All file operations must be reversible or at least logged [Source: architecture.md — Error Handling, idempotent operations with rollback support]
- Local-first: `.ai/health-deferred.json` is a plain JSON file in the repo [Source: prd.md NFR-001]
- Archive delegation preserves provenance metadata (archive-content.ps1 already handles this from Story 2.3)

### Previous Story Intelligence

From Story 6.1:
- `health-check.ps1` output format: findings have `Type`, `Severity`, `File`, `Rule`, `Issue`, `Suggestion` fields — use `Rule` as the matching key for defer suppression
- `Config.folders.reviews` = `"reviews"` — report files live at `knowledge/reviews/health-report-YYYY-MM-DD.md`
- Archive folder excluded from all health checks

From Story 5.5 (rollback):
- Confirmation gate: `YES` (case-sensitive) for destructive ops; `-Force` together with `-Confirm:$false` for automation. For this story use simpler `Y/N` prompt (less destructive than rollback), but still check `PINKY_FORCE_NONINTERACTIVE`
- Per-file errors continue, are logged, and aggregate to non-zero exit only if any error occurred

From Story 2.3 (archival):
- `archive-content.ps1` moves files and updates frontmatter with `archive_reason`, `archived_date`, `replaced_by`
- Do not duplicate this logic

### Testing Requirements

New file: `tests/resolve-findings.Tests.ps1`

Regression to run:
- `Invoke-Pester tests\health-check.Tests.ps1` — confirm defer integration in health-check.ps1 doesn't break existing 11 tests

### References

- `_bmad-output/planning-artifacts/epics.md` — Story 6.2 acceptance criteria
- `_bmad-output/planning-artifacts/prd.md` — FR-010
- `_bmad-output/planning-artifacts/architecture.md` — inspectable automation, idempotent ops
- `_bmad-output/implementation-artifacts/6-1-automated-health-checks.md` — report file format and finding shape
- `scripts/health-check.ps1` — report output format, defer integration target
- `scripts/archive-content.ps1` — archive delegation
- `scripts/update-wiki-metadata.ps1` — metadata update delegation
- `scripts/lib/frontmatter.ps1` — frontmatter helpers
- `scripts/rollback-import.ps1` — confirmation gate pattern

## Dev Agent Record

### Agent Model Used

_to be filled_

### Debug Log References

### Completion Notes List

### File List
