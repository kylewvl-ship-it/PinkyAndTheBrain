Status: `complete`

Files changed:
- `scripts/import-preview.ps1`
- `tests/import-preview.Tests.ps1`
- `_bmad-output/implementation-artifacts/5-3-vault-import-preview-and-analysis.md`

What changed:
- Added a preview-only import script that scans source markdown recursively, classifies files into `inbox/raw/working/wiki/archive/skip/unclassified`, records explicit reasons, detects potential duplicates by exact title, Levenshtein-style filename similarity, and bounded token overlap, and writes timestamped JSON plus Markdown reports under `.ai/import-previews/`.
- Added profile support with `-Profile`, `-MappingRules`, and `-SaveProfile`. I kept the profile format as local JSON so rules stay reviewable and inspectable, which matches the story’s “no hidden state” requirement.
- Added focused Pester coverage for the required behaviors. I did not run extra regression suites because no shared helpers were modified.

Validation run and results:
- `Invoke-Pester tests\import-preview.Tests.ps1`
- Result: `Passed: 6 Failed: 0 Skipped: 0 Pending: 0 Inconclusive: 0`

Implementation choices:
- Reused the existing frontmatter helpers and copied the local Levenshtein approach from `scripts/search.ps1` instead of adding dependencies, because the story called for deterministic local analysis and existing repo patterns.
- Used explicit, explainable heuristics in this order: folder/title/frontmatter signals first, then content length and link density, then `unclassified` when confidence is too low. That keeps the preview inspectable and safe before Story 5.4 does any real import work.

Blockers:
- None.