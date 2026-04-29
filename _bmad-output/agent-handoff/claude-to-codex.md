# Codex Task: Fix 6.2 Review Findings

## Task Type
BMAD Fix — address 4 confirmed code review findings for story 6.2.

## Findings to Fix

### H1 (High) — Path traversal in resolve-findings.ps1

`resolve-findings.ps1` resolves report-derived file paths with `GetFullPath` but never verifies the result stays within `$VaultRoot` or `$RepoRoot`. A crafted finding like `../../outside.md` could read/write outside the knowledge vault.

Fix: after resolving any path from a report finding, check that it starts with the canonical vault root. If it does not, skip the finding with a warning and continue. Pattern to mirror: `scripts/rollback-import.ps1` uses path-containment checks — apply the same approach.

### H2 (High) — fix-link -Force silently selects first candidate

`resolve-findings.ps1` line ~213: `-Force` is used to both skip confirmation AND auto-select candidate 1 for link repair. These are separate concerns. Auto-selecting a candidate without explicit user input can silently rewrite a link to the wrong file.

Fix: add a `-LinkTarget` parameter (string, optional) for non-interactive link target selection. `-Force` should only skip the apply-confirmation prompt. If no candidates match and no `-LinkTarget` is given, and `-Force` is set, fail with a clear message ("no candidate selected — provide -LinkTarget to proceed non-interactively") and exit 1.

### M1 (Medium) — mark-broken not honored by health-check

`resolve-findings.ps1` records `mark-broken` under a different action key than `health-check.ps1` reads. The broken link finding reappears on subsequent health check runs.

Fix: ensure that when `fix-link` action records a `mark-broken` decision to `.ai/health-deferred.json`, it uses `action: "mark-broken"`. In `health-check.ps1`, update the defer-suppression logic to also suppress findings whose matching defer record has `action` equal to `"mark-broken"` (i.e., suppress indefinitely, not just for 30 days — `deferred_until` null or far future).

### M2 (Medium) — Interactive review shows wrong suggested actions

`resolve-findings.ps1` line ~308-313: the guided action display shows only 4 hardcoded actions regardless of finding type. AC1 requires "2-3 suggested repair actions" relevant to the specific finding.

Fix: build a mapping from `rule` → suggested actions. At minimum:
- `require-metadata` / `require-wiki-sources` / `require-confidence` → suggest `update-metadata`, `archive`, `defer`
- `link-target-exists` → suggest `fix-link`, `mark-broken` (via fix-link mark-broken option), `defer`
- `stale-threshold` / `review-trigger-overdue` → suggest `update-metadata` (update `last_updated`), `archive`, `defer`
- `duplicate-title` / `title-edit-distance` → suggest `merge-duplicate`, `defer`
- `body-sha256-match` / `body-prefix-length-match` → suggest `ignore-fingerprint`, `merge-duplicate`, `defer`
- `incoming-link-required` → suggest `archive`, `defer`
- `index-drift` → suggest `rebuild-index`, `defer`
- Default (unknown rule) → suggest `archive`, `defer`

## Validation
```powershell
Invoke-Pester tests\resolve-findings.Tests.ps1
Invoke-Pester tests\health-check.Tests.ps1
```

Add tests for H1 (path outside vault rejected) and M1 (mark-broken suppresses link finding).
Both suites must pass 0 failures.

## Report Format
- Files changed
- Validation pass/fail counts
- Status: complete or blocked
