# Codex Task: Implement Story 5.3 — Vault Import Preview and Analysis

## Task Type
BMAD Dev Story

## Story File
`_bmad-output/implementation-artifacts/5-3-vault-import-preview-and-analysis.md`

## Scope
Implement story 5.3 only. Do not implement any future stories (5.4, 5.5, etc.).

## What to implement

Run the BMAD Dev Story workflow for story 5.3 using the story file above as your specification.

Key deliverables:
1. `scripts/import-preview.ps1` — non-destructive vault preview script
2. `tests/import-preview.Tests.ps1` — focused Pester tests

Follow all Dev Notes, existing patterns, and scope boundaries in the story file exactly.

## Validation
- Run `Invoke-Pester tests\import-preview.Tests.ps1` and report results
- If shared helpers were modified, also run affected tests for frontmatter, config-loader, import-conversation, search
- Do not run the full suite; if you do, report unrelated pre-existing failures separately

## Stop conditions
Stop and report if:
- A real blocker or user decision is required
- Any test exposes a blocking unrelated failure
- Implementation would require changing scope or acceptance criteria

## Report back
When done, report:
- Files changed (list)
- Validation run and results (pass/fail counts)
- Status (complete / blocked)
- Any blockers with details
