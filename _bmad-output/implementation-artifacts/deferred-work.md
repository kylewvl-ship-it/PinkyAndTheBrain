# Deferred Work Items

## Deferred from: code review of 5-3-vault-import-preview-and-analysis (2026-04-28)

- Levenshtein O(N×M) DoS risk on large vaults — performance hardening to address alongside Story 5.4 import execution
- BOM/CRLF source files may bypass frontmatter parsing in PS7 — project-wide concern with shared `lib/frontmatter.ps1` parser
- `MakeRelativeUri` returns absolute URI for cross-volume/symlinked vaults — rare in practice, only affects exotic vault layouts
- `Get-CleanFilenameStem` only normalizes two date-prefix shapes — reduces duplicate-detection accuracy for Obsidian default daily-note formats
- Concurrent runs collide on identical `yyyyMMdd-HHmmss` timestamp — repo-wide convention shared with `import-conversation.ps1`

## Deferred from: code review of 0-3-powershell-script-implementation (2026-04-17)

- Search result format styling — cosmetic difference from AC format, low priority visual enhancement
- Triage selection enhancement — range support beyond basic AC, user experience improvement
- Parameter naming consistency — existing design choice across scripts, architectural decision
- Logging location flexibility — implementation choice within reason, configuration flexibility
- Batch mode support — future enhancement beyond current scope, requires significant architecture changes
- Health check grouping display — presentation enhancement for better user experience
- WhatIf return values — edge case in testing mode, minimal impact on functionality
- Network timeout scenarios — external dependency issue, requires broader error handling strategy

## Deferred from: code review of 0-4-configuration-management-system (2026-04-22)

- Unknown keys in user config silently accepted by loader — pre-existing loader architecture; would require schema-driven key allowlist
- `projects.overrides` can recursively merge itself — no depth guard in Merge-Config; pre-existing loader edge case
- Integer values >2,147,483,647 throw in `Convert-YamlValue` (32-bit `[int]` cast) — pre-existing; consider `[long]` or range cap in schema
- YAML key regex rejects keys containing dots — breaks project names like `my.project` in overrides; pre-existing parser limitation
- `privacy` and `limits` config sections not in spec's 8-section schema — sensible additions; spec should be updated to document them
- `inbox_pattern` timestamp tokens (`YYYY-MM-DD-HHMMSS`) unvalidated — user can omit them causing non-unique filenames; needs pattern enforcement
- `max_content_size` has no upper bound in schema — very large values pass unchallenged; add reasonable max (e.g. 100MB)
- `required_working_fields` / `retrieval.require_sources_for_wiki` removed from config with no replacement — check Group C (health-check.ps1) to confirm whether consuming code still references these keys; if so, add schema equivalent
- `similarity_threshold` integer type ambiguity — check Group C (health-check.ps1) to confirm whether consuming code treats this as a count or a normalized ratio

## Deferred from: code review of 0-4-configuration-management-system Group B (2026-04-22)

- `Read-YamlConfig` enforces 2-space indentation as hard rule — YAML spec allows any consistent indent; consider relaxing or documenting the constraint
- `Initialize-Config` prints "Created default configuration" even when no file was written (both source paths missing)
- `Test-ConfigPaths` checks only vault_root, script_root, template_root — other path-like config keys unvalidated
- `Get-Template`: if `system` key is absent from config, template root silently resolves relative to process cwd
- `Get-Template`: "Template not found" error when template root *directory* is missing is misleading — root dir vs file distinction lost
- `Load-Config` uses relative `ConfigPath` default — creates config file relative to process cwd, which diverges across invocations from different directories