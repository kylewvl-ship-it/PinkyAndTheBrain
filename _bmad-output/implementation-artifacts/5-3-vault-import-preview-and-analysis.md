# Story 5.3: Vault Import Preview and Analysis

**Story ID:** 5.3
**Epic:** 5 - Privacy & Project Management
**Status:** done
**Created:** 2026-04-28

---

## Story

As Reno,
I want to preview how my existing Obsidian vault would be imported before making any changes,
so that I can understand the impact and make informed decisions.

## Acceptance Criteria

1. **Source vault scanning**
   - Given I have an existing Obsidian vault to import
   - When I run `.\scripts\import-preview.ps1 -SourceVault "C:\MyVault"`
   - Then the system scans all markdown files in the source vault recursively
   - And it never writes to or modifies the source vault or PinkyAndTheBrain knowledge folders

2. **Classification analysis**
   - Given markdown files are discovered
   - When the preview analyzes them
   - Then it proposes classification into `inbox`, `raw`, `working`, `wiki`, `archive`, or `skip`
   - And classification uses folder names, filename patterns, frontmatter, content length, and link density
   - And files that cannot be classified are listed separately with reasons

3. **Preview report output**
   - Given analysis completes
   - When no fatal errors occur
   - Then the script writes a timestamped JSON preview file under `.ai/import-previews/`
   - And it writes a Markdown report beside it for human review
   - And the report shows file counts per proposed category, unclassified files, estimated disk space, and estimated import time
   - And console output prints the generated preview/report paths

4. **Duplicate detection**
   - Given source files may overlap existing PinkyAndTheBrain content
   - When the preview compares source files to current knowledge files
   - Then the report includes a `Potential Duplicates` section
   - And each duplicate candidate includes at least one reason: exact title match, similar filename, or content overlap estimate
   - And each duplicate lists available future resolution strategies: `skip`, `rename-with-suffix`, `merge-content`, `import-separate`

5. **Mapping rules and profiles**
   - Given I want to customize classification
   - When I run with mapping rules or a profile
   - Then folder rules can map source folders to categories, e.g. `Daily Notes=raw`, `MOCs=wiki`, `Templates=skip`
   - And rules override heuristic classification
   - And I can save the effective mapping rules as a profile for future preview runs
   - And saved profiles are reviewable local files, not hidden state

6. **Safe failure behavior**
   - Given the source vault is missing, unreadable, or contains unreadable files
   - When the preview runs
   - Then invalid source vault input exits `1` with a clear message
   - And unreadable individual files are recorded in the report without stopping the whole scan
   - And unexpected system failures exit `2`

## Tasks / Subtasks

- [x] Task 1: Add non-destructive import preview script (AC: 1, 2, 3, 6)
  - [x] 1.1 Create `scripts/import-preview.ps1` with `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `Get-Config`, and `$PSScriptRoot` lib resolution
  - [x] 1.2 Add `-SourceVault`, `-MappingRules`, `-Profile`, `-SaveProfile`, and `-Help` parameters
  - [x] 1.3 Validate `-SourceVault` exists and is a directory; exit `1` for user input errors
  - [x] 1.4 Recursively collect source `*.md` files without writing to source or target knowledge folders
  - [x] 1.5 Write generated preview artifacts under `.ai/import-previews/`

- [x] Task 2: Implement classification heuristics (AC: 2, 5)
  - [x] 2.1 Classify by source folder names first: templates -> `skip`, archive/old -> `archive`, daily/journal/log -> `raw`, moc/map/index -> `wiki`
  - [x] 2.2 Classify by frontmatter/status/title hints where present
  - [x] 2.3 Use content length and link density as fallback signals: short/unclear -> `inbox`, source-like/captured material -> `raw`, many links/index-like -> `wiki`, developed notes -> `working`
  - [x] 2.4 Return `unclassified` with explicit reasons when confidence is too low
  - [x] 2.5 Apply mapping rules after scanning and before report generation so overrides are visible in outputs

- [x] Task 3: Implement duplicate analysis (AC: 4)
  - [x] 3.1 Compare source files against existing files in configured `inbox`, `raw`, `working`, `wiki`, and `archive`
  - [x] 3.2 Detect exact title matches using frontmatter `title` when present, otherwise filename stem
  - [x] 3.3 Detect similar filenames using the existing Levenshtein approach from `scripts/search.ps1` rather than introducing a dependency
  - [x] 3.4 Estimate content overlap with simple token/set overlap; keep it deterministic and bounded
  - [x] 3.5 Include duplicate reasons and future resolution strategy options in JSON and Markdown

- [x] Task 4: Generate preview JSON and Markdown report (AC: 3, 4, 5, 6)
  - [x] 4.1 JSON includes source vault, generated timestamp, summary counts, category counts, file entries, duplicate candidates, unclassified files, errors, mapping rules, and estimates
  - [x] 4.2 Markdown includes summary, proposed category counts, unclassified files, potential duplicates, mapping profile/rules, estimates, and next-step note for Story 5.4
  - [x] 4.3 Estimate disk space from total source file bytes
  - [x] 4.4 Estimate import time with a simple documented local heuristic, e.g. file count based; do not call external services
  - [x] 4.5 Preserve source file paths in outputs for traceability

- [x] Task 5: Add Pester coverage (AC: 1-6)
  - [x] 5.1 Create `tests/import-preview.Tests.ps1`
  - [x] 5.2 Test recursive markdown discovery and non-destructive behavior
  - [x] 5.3 Test folder/frontmatter/content/link-density classification cases
  - [x] 5.4 Test unclassified reporting
  - [x] 5.5 Test duplicate reasons: exact title, similar filename, content overlap
  - [x] 5.6 Test mapping rules/profile behavior
  - [x] 5.7 Test invalid source vault exit `1` and unreadable-file reporting where feasible

- [x] Task 6: Validate and update story status (AC: 1-6)
  - [x] 6.1 Run `Invoke-Pester tests\import-preview.Tests.ps1`
  - [x] 6.2 Run directly affected import/config/frontmatter regression tests if changes touch shared helpers
  - [x] 6.3 Update this story file Dev Agent Record, File List, and status when implementation is complete

## Dev Notes

### Scope Boundaries

In scope:
- New preview-only script: `scripts/import-preview.ps1`
- New tests: `tests/import-preview.Tests.ps1`
- Optional local profile output under `.ai/import-previews/` or a clearly named reviewable profile file
- Read-only scanning of source vault and current PinkyAndTheBrain knowledge folders

Out of scope:
- Copying, moving, renaming, deleting, or modifying imported files. That is Story 5.4.
- Rollback mechanics. That is Story 5.5.
- Interactive UI or real-time GUI updates. For MVP, “preview updates” means rerunning the script with new mapping rules/profile regenerates updated preview artifacts.
- Obsidian plugin integration.
- Semantic embeddings or hosted duplicate detection.

### Existing Patterns To Reuse

- Use PowerShell scripts with `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`, `Get-Config`, and `$PSScriptRoot`-relative lib loading, matching `scripts/import-conversation.ps1`, `scripts/manage-project-tags.ps1`, and `scripts/manage-source-types.ps1`.
- Use `scripts/lib/frontmatter.ps1` for `Get-FrontmatterData`, `Get-FrontmatterValue`, and relative repo path helpers. Do not add a YAML parser dependency.
- Use `scripts/search.ps1` as the local source for Levenshtein-style filename similarity logic. Copy a small local helper if needed; do not dot-source `search.ps1`.
- Use `Set-Content -Path ... -Value ... -Encoding UTF8` for generated preview artifacts.
- Use `$TestDrive`, `PINKY_VAULT_ROOT`, `PINKY_GIT_REPO_ROOT`, and `PINKY_FORCE_NONINTERACTIVE = "1"` in tests, following existing Pester test setup.

### Architecture Requirements

- Local-first and Markdown-compatible: source notes remain plain Markdown and preview artifacts are local files. [Source: `_bmad-output/planning-artifacts/prd.md` FR-015, NFR-001, NFR-002, NFR-011]
- Preview-first migration: this story must produce impact analysis before any restructuring. [Source: `_bmad-output/planning-artifacts/prd.md` Existing Obsidian Vault Import; `_bmad-output/planning-artifacts/architecture.md` NFR-010/NFR-011]
- Inspectable automation: all recommendations must be visible in JSON/Markdown; no hidden state. [Source: `_bmad-output/planning-artifacts/prd.md` NFR-010]
- Provenance: every proposed import entry must preserve the original source path in report data. [Source: `_bmad-output/planning-artifacts/architecture.md` Provenance Tracking]
- Error handling: continue past per-file read/parse issues, but fail invalid top-level inputs clearly. [Source: `_bmad-output/planning-artifacts/architecture.md` Error Handling]

### Suggested Data Shape

The preview JSON should be stable enough for Story 5.4 to consume later:

```json
{
  "generated_at": "2026-04-28T00:00:00Z",
  "source_vault": "C:/MyVault",
  "summary": {
    "total_files": 0,
    "total_bytes": 0,
    "estimated_import_seconds": 0
  },
  "category_counts": {
    "inbox": 0,
    "raw": 0,
    "working": 0,
    "wiki": 0,
    "archive": 0,
    "skip": 0,
    "unclassified": 0
  },
  "files": [
    {
      "source_path": "C:/MyVault/Note.md",
      "relative_path": "Note.md",
      "title": "Note",
      "proposed_category": "working",
      "classification_reasons": ["frontmatter status active"],
      "size_bytes": 1234,
      "link_count": 2,
      "word_count": 240
    }
  ],
  "duplicates": [
    {
      "source_path": "C:/MyVault/Note.md",
      "existing_path": "knowledge/wiki/note.md",
      "reasons": ["exact title match"],
      "resolution_options": ["skip", "rename-with-suffix", "merge-content", "import-separate"]
    }
  ],
  "unclassified": [],
  "errors": [],
  "mapping_rules": []
}
```

### Classification Guidance

Keep heuristics deterministic and explainable:
- `skip`: folders named `templates`, `.obsidian`, `.trash`, attachments/media-only folders, or mapping rule says skip
- `archive`: path contains `archive`, `old`, or `deprecated`
- `raw`: path contains `daily`, `journal`, `log`, `clippings`, `sources`, or file has capture/source-like metadata
- `wiki`: path/title suggests `moc`, `map of content`, `index`, or link density is high
- `working`: substantial notes with developed content but not clearly wiki
- `inbox`: short notes, missing metadata, or unclear one-off notes
- `unclassified`: unreadable/ambiguous files where the script cannot responsibly recommend a category

### Mapping Rule/Profile Requirements

Use a simple local format to avoid new dependencies:
- `-MappingRules "Daily Notes=raw;MOCs=wiki;Templates=skip"`
- `-Profile ".ai/import-previews/profile-work.json"` loads saved rules
- `-SaveProfile ".ai/import-previews/profile-work.json"` writes the effective rules

If both `-Profile` and `-MappingRules` are provided, explicit `-MappingRules` should override matching profile entries. Document this in `-Help` output and test it.

### Previous Story Intelligence

From Story 5.2:
- Path containment matters for bulk operations. Any path that could affect files must be resolved deliberately and constrained to the intended read/write scope.
- Frontmatter arrays may be scalar inline values such as `["work","research"]`; existing parser helpers only support simple inline arrays, not full YAML block arrays.
- Malformed frontmatter should be reported rather than silently rewritten.
- Story 5.2 added project/domain/shared metadata; import preview should preserve and display discovered `project`, `domain`, and `shared` fields when present, but must not require them.
- The repo still has unrelated pre-existing full-suite test failures; validate this story with focused tests and report unrelated suite failures separately if full suite is run.

### Testing Requirements

Required focused tests in `tests/import-preview.Tests.ps1`:
- Invalid `-SourceVault` exits `1`
- Recursive scan includes nested markdown files and excludes non-markdown files
- Script does not modify source files or configured knowledge folders
- Category counts match created fixtures
- Folder mapping rules override heuristics
- Saved profile can be loaded by a later run
- Exact title duplicate is reported
- Similar filename duplicate is reported
- Content overlap duplicate is reported
- Unclassified files are listed with reasons
- JSON and Markdown preview artifacts are created under `.ai/import-previews/`

Regression guidance:
- Run `Invoke-Pester tests\import-preview.Tests.ps1`
- If shared helpers are edited, also run affected tests for `frontmatter`, `config-loader`, `import-conversation`, and `search`.

### References

- `_bmad-output/planning-artifacts/epics.md` — Story 5.3 acceptance criteria
- `_bmad-output/planning-artifacts/prd.md` — FR-015, NFR-001, NFR-002, NFR-010, NFR-011
- `_bmad-output/planning-artifacts/architecture.md` — local-first Markdown/frontmatter, provenance, inspectable automation, rollback-safe architecture
- `_bmad-output/implementation-artifacts/5-2-project-and-domain-separation.md` — prior story learnings and path/frontmatter review outcomes
- `scripts/import-conversation.ps1` — script boilerplate, read/convert/report style
- `scripts/health-check.ps1` — existing deterministic duplicate/title/link scanning patterns
- `scripts/search.ps1` — Levenshtein filename similarity helper pattern

## Dev Agent Record

### Agent Model Used

GPT-5

### Debug Log References

### Completion Notes List

- Added `scripts/import-preview.ps1` as a preview-only vault scanner that classifies notes, reports unclassified files, detects potential duplicates, and writes JSON/Markdown artifacts under `.ai/import-previews/`.
- Reused the repo's frontmatter parsing and local Levenshtein approach instead of introducing new dependencies, because the story explicitly required deterministic, inspectable local behavior.
- Added focused Pester coverage for source validation, recursive markdown discovery, non-destructive behavior, category heuristics, mapping rule/profile precedence, duplicate reasons, and artifact generation.
- Shared helpers were not modified, so no additional regression suites were required beyond the focused story test file.

### File List

- `scripts/import-preview.ps1`
- `tests/import-preview.Tests.ps1`
- `_bmad-output/implementation-artifacts/5-3-vault-import-preview-and-analysis.md`

### Review Findings

Code review of 2026-04-28 (3 layers: Blind Hunter, Edge Case Hunter, Acceptance Auditor). All 6 ACs satisfied per Acceptance Auditor. The findings below are quality/robustness issues raised by Blind/Edge layers and verified against the actual code.

- [x] [Review][Patch] StrictMode null-deref on `.ToLowerInvariant()` of optional frontmatter keys [scripts/import-preview.ps1:295-297] — `Get-FrontmatterValue` may return `$null` when `status`/`source_type`/`review_status` are absent; `.ToLowerInvariant()` then throws and the per-file try/catch reports a misleading "file could not be read" for any vault file with frontmatter that does not contain those keys.
- [x] [Review][Patch] StrictMode PropertyNotFound on missing `mapping_rules` in profile JSON [scripts/import-preview.ps1:206] — `$profileData.mapping_rules` access throws under `Set-StrictMode -Version Latest` when the profile JSON omits that property, falling to outer catch with exit 2 instead of treating it as "no rules".
- [x] [Review][Patch] `Get-ProfileRules` does not validate `category` against the allowed set [scripts/import-preview.ps1:207-213] — `Parse-MappingRulesString` validates categories but profile-loaded rules with typos like `wikkii` or `todo` flow straight to `$categoryCounts[$category]++`, which throws on unknown ordered-dict key under StrictMode.
- [x] [Review][Patch] `Get-WordCount` clobbers automatic `$matches` variable [scripts/import-preview.ps1:142] — assigning to `$matches` overwrites PowerShell's regex automatic; rename to `$wordMatches` (other scripts in repo follow this convention).
- [x] [Review][Patch] `Get-MatchingRule` uses unanchored substring match [scripts/import-preview.ps1:247-252] — pattern `raw` matches `drawings/note.md`; mapping rules should match on path-segment boundaries to avoid silent miscategorization.
- [x] [Review][Patch] `$sourceEntry.title.Equals(...)` may throw NullReferenceException [scripts/import-preview.ps1:442] — if a source or existing document has `$null` title, duplicate detection crashes the whole loop. Guard with null check or use `[string]::Equals` with safe args.
- [x] [Review][Patch] No guard when `-SourceVault` overlaps configured knowledge folders [scripts/import-preview.ps1:565-583] — pointing at repo root or `<vault>/knowledge` produces self-duplicates with 100% content overlap and false "exact title match" findings; reject the input or skip overlapping paths.
- [x] [Review][Patch] Mapping-rule parse errors exit `2` instead of `1` [scripts/import-preview.ps1:580] — `Parse-MappingRulesString` is called inside `try` so bad-arg failures exit `2` per the outer catch, contrary to AC6 (`exit 1` for invalid user input).
- [x] [Review][Defer] Levenshtein O(N×M) DoS risk on large vaults [scripts/import-preview.ps1:103-129, 438-465] — deferred, performance hardening to be addressed alongside Story 5.4 import execution where larger vault sizes are exercised.
- [x] [Review][Defer] BOM/CRLF source files may bypass frontmatter parsing in PS7 [scripts/import-preview.ps1:602] — deferred, project-wide concern with shared `lib/frontmatter.ps1` parser; out of scope for 5.3.
- [x] [Review][Defer] `MakeRelativeUri` returns absolute URI for cross-volume/symlinked vaults [scripts/import-preview.ps1:60-71] — deferred, rare in practice and only affects exotic vault layouts.
- [x] [Review][Defer] `Get-CleanFilenameStem` only normalizes two date-prefix shapes [scripts/import-preview.ps1:94-101] — deferred, reduces duplicate-detection accuracy for Obsidian default daily-note formats but not a correctness defect.
- [x] [Review][Defer] Concurrent runs collide on identical `yyyyMMdd-HHmmss` timestamp [scripts/import-preview.ps1:662] — deferred, repo-wide convention shared with `import-conversation.ps1`.
