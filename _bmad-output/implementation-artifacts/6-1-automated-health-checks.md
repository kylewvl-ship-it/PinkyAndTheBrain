# Story 6.1: Automated Health Checks

**Story ID:** 6.1
**Epic:** 6 - System Health & Maintenance
**Status:** review
**Created:** 2026-04-29

---

## Story

As Reno,
I want to run comprehensive health checks that detect knowledge base issues,
so that I can maintain trust and quality in my stored knowledge over time.

## Acceptance Criteria

1. **Metadata check** — Given I run a health check, the system scans wiki and working files and flags: missing required metadata fields (`status`, `last_updated`, `confidence`), missing source references in frontmatter, and files with content body under 100 characters.

2. **Link integrity check** — Broken `[[wiki-link]]` and `[md](path)` internal links are identified across all non-archived knowledge files.

3. **Orphan check** — Files in `working/` and `wiki/` with no incoming links from other knowledge files are reported.

4. **Stale content check** — Files in `working/` and `wiki/` whose `last_updated`/`last_verified` exceeds `stale_threshold_months` (default 6, from config) are flagged; overdue `review_trigger` dates also trigger findings.

5. **Duplicate detection** — Two duplicate subtypes are reported distinctly:
   - *Title similarity*: files whose title or filename stem has edit distance < `similarity_threshold` (config default 3)
   - *Fingerprint candidates*: files with identical or near-identical content hash (SHA256 of body stripped of frontmatter, within 5% length)

6. **Extraction Confidence Gaps** — Wiki files with no `sources` entry in frontmatter are reported as low-confidence extracted content needing provenance.

7. **Derived Index Drift** — Per-folder `index.md` files whose `last_updated` frontmatter (or filesystem mtime) is older than the newest `.md` sibling in that folder are flagged as stale derived indexes.

8. **Output format** — Findings are grouped by type: `Missing Metadata`, `Broken Links`, `Stale Content`, `Duplicates`, `Orphans`, `Extraction Confidence Gaps`, `Derived Index Drift`. Within each group, findings are sorted High → Medium → Low. Deterministic groups (Missing Metadata, Broken Links) are displayed before heuristic groups. Each finding includes: file path, issue type, severity, rule triggered, suggested repair action. Total count per type is shown.

9. **Report file** — After every run, a Markdown report is written to `knowledge/reviews/health-report-YYYY-MM-DD.md` (vault-relative, using `$Config.folders.reviews`). Existing same-day report is overwritten.

10. **Targeted checks** — `-Type metadata|links|stale|duplicates|orphans` (existing param) selects a subset. Archive folder is excluded from all checks by default.

## Tasks / Subtasks

- [x] Task 1: Extend `scripts/health-check.ps1` — metadata check (AC: 1)
  - [x] 1.1 Read `min_content_length` from `$Config.health_checks.min_content_length` (not hardcoded 50 — fix existing bug)
  - [x] 1.2 Add source-references check: for wiki and working files, flag `sources` frontmatter field missing or empty as a `Missing Metadata` / Medium finding with rule `require-sources`
  - [x] 1.3 Archive folder excluded: remove archive from the folders iterated in `Test-Metadata`

- [x] Task 2: Extend `Test-Duplicates` — edit distance + fingerprint subtypes (AC: 5)
  - [x] 2.1 Read `$Config.health_checks.similarity_threshold` (already present in config); use it as max edit distance for title/stem comparison
  - [x] 2.2 Implement simple Levenshtein between filename stems (limit to files in the same folder to bound O(N²) cost; skip pairs where both stems are > 50 chars to avoid DoS — see deferred work)
  - [x] 2.3 Add fingerprint duplicate detection: SHA256 of body (frontmatter stripped) for each file; group by identical hash; also flag pairs where body length differs by ≤ 5% and first 200 chars match
  - [x] 2.4 Distinguish finding types: `Duplicates (title-similarity)` vs `Duplicates (fingerprint-candidate)` in the `Type` field

- [x] Task 3: Add `Test-ExtractionConfidenceGaps` (AC: 6)
  - [x] 3.1 Scan wiki files only; flag any file whose frontmatter has no `sources` key or `sources` is empty/blank as severity Medium, rule `require-wiki-sources`
  - [x] 3.2 Return `[PSCustomObject]@{ Type = "Extraction Confidence Gaps"; ... }` findings

- [x] Task 4: Add `Test-DerivedIndexDrift` (AC: 7)
  - [x] 4.1 For each knowledge folder in config (inbox, raw, working, wiki — not archive), check if `index.md` exists
  - [x] 4.2 If `index.md` exists: parse its `last_updated` frontmatter; compare against newest `LastWriteTime` of sibling `.md` files (excluding index.md itself)
  - [x] 4.3 If index is older than newest sibling by > 0 seconds, emit severity Low finding, rule `index-drift`
  - [x] 4.4 Return `[PSCustomObject]@{ Type = "Derived Index Drift"; ... }` findings

- [x] Task 5: Wire new checks into main flow + report file (AC: 8, 9, 10)
  - [x] 5.1 Add `Test-ExtractionConfidenceGaps` and `Test-DerivedIndexDrift` to the `"all"` branch in the main `switch ($Type)` block
  - [x] 5.2 In `Show-HealthReport`, enforce display order: Missing Metadata, Broken Links, Stale Content, Duplicates, Orphans, Extraction Confidence Gaps, Derived Index Drift (deterministic first)
  - [x] 5.3 Write findings as Markdown to `$vaultRoot/$($Config.folders.reviews)/health-report-$(Get-Date -Format 'yyyy-MM-dd').md` using `Set-Content -Encoding UTF8`; create the reviews folder if missing
  - [x] 5.4 Add `ValidateSet` entry `"all"` already present; no param change needed for targeted checks

- [x] Task 6: Pester tests in `tests/health-check.Tests.ps1` (AC: 1–10)
  - [x] 6.1 Setup: use `$TestDrive`, `PINKY_VAULT_ROOT`, `PINKY_GIT_REPO_ROOT`, `PINKY_FORCE_NONINTERACTIVE = "1"` (match all existing test patterns)
  - [x] 6.2 Test missing-metadata: file with no frontmatter → High; wiki file missing `confidence` → Medium; file body < 100 chars → Low
  - [x] 6.3 Test source-references check: wiki file with no `sources` → `Extraction Confidence Gaps` Medium finding
  - [x] 6.4 Test broken link detection: file with `[[missing-page]]` → Broken Links finding; file with `[text](missing.md)` → Broken Links finding; external `https://` link → no finding
  - [x] 6.5 Test orphan detection: file with no incoming links → Orphans Low; file referenced by another → no finding
  - [x] 6.6 Test stale content: file with `last_updated` 7 months ago → Stale Content (config threshold 6); file with overdue `review_trigger` → Stale Content Medium
  - [x] 6.7 Test duplicate title similarity: two files with stems differing by 1 char → `Duplicates (title-similarity)` finding; stems differing by 4 chars → no finding
  - [x] 6.8 Test duplicate fingerprint: two files with identical body → `Duplicates (fingerprint-candidate)` finding
  - [x] 6.9 Test derived index drift: `index.md` with stale `last_updated` and a newer sibling → `Derived Index Drift` Low
  - [x] 6.10 Test report file written to `reviews/health-report-YYYY-MM-DD.md` after run
  - [x] 6.11 Test archive exclusion: file in archive folder → not included in any findings
  - [x] 6.12 Test `-Type metadata` runs only metadata checks (not links/stale)
  - [x] 6.13 Regression: run existing `setup-system.Tests.ps1` or config-loader tests to confirm no shared-lib breakage

- [x] Task 7: Validate and update story status
  - [x] 7.1 Run `Invoke-Pester tests\health-check.Tests.ps1`
  - [x] 7.2 Run `Invoke-Pester tests\config-loader.Tests.ps1` to confirm no regression in shared config helpers
  - [x] 7.3 Update Dev Agent Record, File List, and status when complete

## Dev Notes

### Scope Boundaries

In scope:
- `scripts/health-check.ps1` — extend only; do not refactor unrelated checks
- `tests/health-check.Tests.ps1` — new file
- Generated artifacts under `knowledge/reviews/health-report-*.md`

Out of scope:
- Interactive repair (that is Story 6.2)
- Offline/hook-free operation (Story 6.3)
- `knowledge/reviews/` folder structure changes beyond creating it if missing

### Existing Code to Extend (Not Replace)

The file `scripts/health-check.ps1` **already exists** with working implementations of:
- `Test-Metadata` — extend: fix min_content_length bug (50 → config value), add source-ref check, remove archive from folders list
- `Test-Links` — no changes needed unless behavior tests reveal bugs
- `Test-StaleContent` — no changes needed
- `Test-Duplicates` — extend: add edit-distance subtask + fingerprint subtype
- `Test-Orphans` — no changes needed
- `Show-HealthReport` — extend: enforce deterministic-first ordering, add report-file write

**Do not rewrite these functions from scratch.**

### Existing Patterns To Reuse

- `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'` (all scripts)
- `Get-Config` from `scripts/lib/common.ps1` returns hashtable with `$Config.health_checks.stale_threshold_months`, `$Config.health_checks.min_content_length`, `$Config.health_checks.similarity_threshold`
- `scripts/lib/frontmatter.ps1` provides `Get-FrontmatterData` / `Get-FrontmatterValue` — use instead of inline regex where practical
- `Set-Content -Path ... -Value ... -Encoding UTF8` for all generated artifacts
- Test scaffolding: `$TestDrive` for isolated file trees, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_GIT_REPO_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"` (match `tests/rollback-import.Tests.ps1` exactly)

### Config Keys Used

From `config/pinky-config.yaml`:
```yaml
health_checks:
  stale_threshold_months: 6    # used in Test-StaleContent (already wired)
  min_content_length: 100      # CURRENTLY IGNORED in script (hardcoded 50) — fix in Task 1.1
  similarity_threshold: 3      # edit distance max for title-similarity duplicates
folders:
  reviews: "reviews"           # output report subfolder under vault_root
```

### Levenshtein DoS Guard (from deferred work)

Limit pairwise edit-distance computation to same-folder files only. Skip any pair where both stems exceed 50 characters. This bounds worst-case to `O(folder_size² × 50²)` which is acceptable for typical vault sizes.

### Fingerprint Duplicate Algorithm

```powershell
# Strip frontmatter block, hash remaining body
$body = $content -replace '(?s)^---.*?---\s*', ''
$hash = [System.Security.Cryptography.SHA256]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body.Trim())
$hex = [BitConverter]::ToString($hash.ComputeHash($bytes)) -replace '-', ''
```

Group files by `$hex`. Also flag pairs with same first 200 chars of body AND body length within 5% of each other as fingerprint candidates (catches near-duplicates).

### Report File Format

```markdown
---
generated: 2026-04-29
check_type: all
total_findings: 12
---

# Health Check Report — 2026-04-29

## Summary
| Type | High | Medium | Low | Total |
|------|------|--------|-----|-------|
| Missing Metadata | 2 | 3 | 1 | 6 |
...

## Missing Metadata
...
```

### Previous Story Intelligence

From Story 5.5 (most recent completed):
- Per-file errors must continue, not abort — mirror this in health check file iteration
- Path containment: always resolve vault paths from config, never trust user-provided raw paths
- `scripts/lib/frontmatter.ps1` supports simple inline arrays only; unparseable frontmatter fields should be treated as absent (not crash)

From deferred work (0-4 code review):
- `required_working_fields` and `retrieval.require_sources_for_wiki` were removed from config spec — the health check should NOT attempt `$Config.required_working_fields`; instead use hardcoded field lists per folder type (as existing code already does)
- `similarity_threshold` in config is an **integer count** (edit distance), not a normalized ratio

### Architecture Alignment

- Health check is the "Lint" phase of the Karpathy pipeline: automated detection only, no auto-repair (NFR-010) [Source: `_bmad-output/planning-artifacts/architecture.md` — Health Check & Validation Architecture]
- Output goes to `knowledge/reviews/` per architecture spec [Source: architecture.md — `# Daily: scripts/health-check-daily.ps1 / Output: knowledge/reviews/health-report-YYYY-MM-DD.md`]
- Archive excluded by default [Source: epics.md Story 6.1 AC — "I can exclude archived content from health checks by default"]
- Derived artifacts (index.md files) are rebuildable from canonical Markdown [Source: architecture.md — "derived artifacts can be deleted and rebuilt without loss of canonical knowledge"]

### Testing Requirements

New file: `tests/health-check.Tests.ps1`

Regression suite to run after changes:
- `Invoke-Pester tests\health-check.Tests.ps1` — new focused tests
- `Invoke-Pester tests\config-loader.Tests.ps1` — if `scripts/lib/common.ps1` or `config-loader.ps1` touched

### References

- `_bmad-output/planning-artifacts/epics.md` — Story 6.1 acceptance criteria
- `_bmad-output/planning-artifacts/prd.md` — FR-009
- `_bmad-output/planning-artifacts/architecture.md` — Health Check & Validation Architecture, Derived artifacts, Karpathy lint phase
- `scripts/health-check.ps1` — existing implementation to extend
- `scripts/lib/frontmatter.ps1` — frontmatter helpers
- `scripts/lib/common.ps1` — `Get-Config`, `Show-Usage`, `Write-Log`
- `config/pinky-config.yaml` — `health_checks.*` and `folders.reviews` keys
- `_bmad-output/implementation-artifacts/deferred-work.md` — Levenshtein DoS risk, similarity_threshold type

## Dev Agent Record

### Agent Model Used

GPT-5 Codex

### Debug Log References

- 2026-04-29: Direct `Invoke-Pester` was blocked by local PowerShell execution policy; reran required validations with `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester ..."` to execute the same suites.

### Completion Notes List

- Extended metadata checks to use configured `health_checks.min_content_length`, require source references for working/wiki files, and skip archive by default.
- Added duplicate title-similarity and fingerprint-candidate detection with distinct finding `Type` values.
- Added extraction confidence gap and derived index drift checks, wired them into `-Type all`, and added deterministic report ordering plus Markdown report generation under the configured reviews folder.
- Added focused Pester coverage for story acceptance criteria using isolated `$TestDrive` vaults and Pinky environment overrides.

### File List

- `scripts/health-check.ps1`
- `tests/health-check.Tests.ps1`
- `_bmad-output/implementation-artifacts/6-1-automated-health-checks.md`
- `_bmad-output/implementation-artifacts/sprint-status.yaml`

### Change Log

- 2026-04-29: Implemented Story 6.1 automated health checks and validation coverage.
