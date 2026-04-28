---

**Story file path:** `_bmad-output/implementation-artifacts/5-2-project-and-domain-separation.md`

**Status:** `ready-for-dev` (sprint-status.yaml already updated)

**Files changed:** Story file updated in place (was untracked); sprint-status was already correct.

**Validation applied:**
- Fixed confusing dead-code line in generate-handoff.ps1 Change 2 (`$isShared` variable renamed to `$isSharedForDomain` to avoid shadowing)
- Fixed fragile untagged-count logic in list-projects.ps1 (now tracks per-file boolean rather than subtracting from inflated sum)
- Added missing regression test cases for search.ps1 domain/array-project filtering and generate-handoff.ps1 domain + `shared: true` bypass
- Added explicit note to update `Search-Files` function signature and call site for `-Domain` param

**Blockers:** None.
