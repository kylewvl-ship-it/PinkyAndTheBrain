# Codex Task: Dev Story 6-1-automated-health-checks

## Task Type
BMAD Dev Story — implement story 6.1 only.

## Story File
`_bmad-output/implementation-artifacts/6-1-automated-health-checks.md`

## Instructions

Run BMAD Dev Story for story 6.1 only. The story file is the source of truth. Implement exactly what the story specifies — no more, no less.

Key implementation points:
1. **Extend `scripts/health-check.ps1`** — do NOT rewrite it. Existing functions Test-Metadata, Test-Links, Test-StaleContent, Test-Duplicates, Test-Orphans, Show-HealthReport are already present and working. Only change what is specified in the story tasks.
2. Fix the `min_content_length` bug: the existing script hardcodes 50, but config has `health_checks.min_content_length: 100`. Use config value.
3. Add source-references check (new check in Test-Metadata for wiki/working files lacking `sources` frontmatter).
4. Remove archive folder from `Test-Metadata` iteration (exclude archive by default).
5. Extend `Test-Duplicates` with edit-distance similarity (use `health_checks.similarity_threshold: 3` from config) and fingerprint-based duplicate detection. Distinguish these as separate finding subtypes in the `Type` field.
6. Add new function `Test-ExtractionConfidenceGaps` — wiki files with no sources frontmatter → `Extraction Confidence Gaps` findings.
7. Add new function `Test-DerivedIndexDrift` — per-folder index.md staleness check.
8. Wire both new functions into the main `switch ($Type)` `"all"` branch.
9. Enforce deterministic-first display order in `Show-HealthReport`.
10. Write report Markdown file to `knowledge/reviews/health-report-YYYY-MM-DD.md` after every run.
11. Create `tests/health-check.Tests.ps1` using `$TestDrive`, `$env:PINKY_VAULT_ROOT`, `$env:PINKY_GIT_REPO_ROOT`, `$env:PINKY_FORCE_NONINTERACTIVE = "1"` — match existing test patterns from `tests/rollback-import.Tests.ps1`.

## Validation to Run

```powershell
Invoke-Pester tests\health-check.Tests.ps1
Invoke-Pester tests\config-loader.Tests.ps1
```

## Stop Conditions

Stop and report if:
- A real blocker is encountered that requires a user decision
- Required config keys are missing from `config/pinky-config.yaml`
- Any test in `tests\rollback-import.Tests.ps1` or `tests\execute-import.Tests.ps1` regresses (run these if shared libs are touched)

## Report Format

Respond with:
- Files changed (list)
- Validation results (pass/fail counts)
- Status: complete or blocked
- Blockers: describe if any
