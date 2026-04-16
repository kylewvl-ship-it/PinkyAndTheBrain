# Deferred Work

## Deferred from: code review of 0-2-template-system-creation (2026-04-16)

- `$InboxDir` never created when Type="conversation" — only $RawDir is created; if setup-system was not run, inbox won't exist [scripts/capture.ps1]. Pre-existing setup dependency.
- `Escape-YamlValue` only escapes double-quotes — titles or values containing newlines, colons, or YAML special chars could corrupt frontmatter. Pre-existing function, not introduced by story 0-2.

## Deferred from: code review of story-0.1 (2026-04-16)

- Retry-without-recreating logic is pre-existing — script is idempotent via `Ensure-Directory`/`Ensure-File`, not introduced by the story 0.1 diff
- `$Root` fragility when script is moved/symlinked — `$Root = $PSScriptRoot/..` is pre-existing for all script operations, not specific to rollback
