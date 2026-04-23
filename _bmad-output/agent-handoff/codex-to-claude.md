# Claude Handoff: BMAD Create Story

Claude is the story creation executor in a Codex-coordinated BMAD pipeline.

## Task

Run BMAD Create Story for this story only:

- Epic: 1 - Basic Knowledge Lifecycle
- Story: 1.3 - Working Note Creation and Management
- Sprint key: `1-3-working-note-creation-and-management`
- Expected story file: `_bmad-output/implementation-artifacts/1-3-working-note-creation-and-management.md`

## Required Context

Use relevant context from:

- `_bmad-output/implementation-artifacts/sprint-status.yaml`
- `_bmad-output/planning-artifacts/epics.md`
- `_bmad-output/planning-artifacts/prd.md`
- `_bmad-output/planning-artifacts/architecture.md`
- any UX artifact if present
- any `project-context.md` if present
- prior completed Epic 0 story files in `_bmad-output/implementation-artifacts/`
- completed Story 1.1 file `_bmad-output/implementation-artifacts/1-1-quick-knowledge-capture.md`
- completed Story 1.2 file `_bmad-output/implementation-artifacts/1-2-inbox-triage-workflow.md`

Keep the story aligned with the overall product structure:

- local-first, Markdown-first, Obsidian-compatible knowledge operating system
- PowerShell-first MVP automation on Windows
- inspectable repo files, templates, metadata, and scripts
- provenance preservation and explicit promotion/review gates
- optional hooks must not be required for the core workflow
- Epic 1 flow is capture -> triage -> working notes; Story 1.3 should build working-note creation/management only and must not implement Epic 2 wiki-promotion scope early

## Story 1.3 Source Requirements

Create the developer-ready story for working-note creation and management from the Epic 1 requirements:

- `.\scripts\create-working-note.ps1 -Title "My Topic" -Project "research"` creates a new file in `knowledge/working/` using the working-note template
- filename is `my-topic.md` with kebab-case title
- frontmatter includes `status: "draft"`, `confidence: "low"`, `last_updated`, and `project`
- template includes all sections: Current Interpretation, Evidence, Connections, Tensions, Open Questions, Next Moves, Source Pointers
- `.\scripts\promote-to-working.ps1 -SourceFile "knowledge/inbox/my-item.md" -Title "Working Topic"` creates a working note with source content in Evidence, source metadata linked in Source Pointers, source frontmatter marked with `promoted_to`, and working-note frontmatter including `source_list`
- metadata management must update `last_updated`, recalculate `review_trigger`, validate required fields, and warn on invalid values
- Git history should capture working-note evolution, and `.\scripts\working-note-summary.ps1 -File "my-topic.md"` should summarize changes
- overdue review triggers should be visible to health checks
- `.\scripts\list-working-notes.ps1` should list working notes with title, status, confidence, last_updated, and days until review; support `-Status` and `-SortBy`
- overdue notes should be highlighted in red
- duplicate-title handling must prevent overwrite, suggest alternatives, and offer opening the existing note
- source corruption during promotion must still salvage readable content, warn, and log the issue

## Constraints

- Run BMAD Create Story only.
- Do not implement code.
- Do not review code.
- Do not advance beyond Story 1.3.
- Stop after creating the story, or stop if a decision/user-required blocker arises.
- If updating sprint status, preserve its comments and structure.

## Report Back

Report only:

- story file path
- resulting story status
- files changed
- validation performed, if any
- blockers, if any
