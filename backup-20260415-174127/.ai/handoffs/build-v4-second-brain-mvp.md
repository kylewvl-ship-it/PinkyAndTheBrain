# Task: Build v4 2nd Brain MVP

## Goal
Create the smallest usable implementation of the v4 second-brain operating system in this repo.

## Why
The v4 design is feasible, but it will fail if implemented as a heavy process before daily capture, retrieval, and validation are useful.

## Context
Primary design docs:
- bulletproof_2nd_brain_system_v4.md
- llm_wiki_2nd_brain_system_v_3.md

v3 establishes the core RAW -> WORKING -> WIKI model. v4 hardens it with inbox, archive, reviews, stronger metadata, retrieval safeguards, and explicit agent contracts.

## Constraints
- Local-first and tool-agnostic.
- Markdown-first until automation is justified.
- Do not treat wiki pages as ground truth.
- Keep maintenance cheaper than ignoring the system.
- Avoid duplicate stable concept pages.

## Assumptions
- This repo is the home for the operating system itself.
- Initial implementation should be filesystem-based, not a database or app.
- Automation should start as scripts/checks after the manual workflow is proven.

## Deliverables
- Knowledge folder structure.
- Working-note and wiki-page templates.
- Agent and knowledge operating policies.
- Starter task file for implementation control.
- README guidance for daily usage.

## Done When
- A new note can be captured in `knowledge/inbox/`.
- A useful thought can be developed in `knowledge/working/` from the template.
- A durable page can be compiled in `knowledge/wiki/` from the template.
- The repo explains the authority hierarchy and daily/weekly operating loop.
- Future implementation tasks have a reusable task template.

## Dependencies
- Existing design docs remain the source for system intent.

## Touched Paths
- README.md
- knowledge/**
- .ai/**
- scripts/

## Validation Commands
- `Get-ChildItem -Recurse knowledge,.ai | Select-Object FullName`
- `git status --short`

## Risks
- Overbuilding before the workflow is used.
- Allowing inbox to become permanent storage.
- Creating wiki pages without provenance.
- Treating agent role names as a substitute for validation.

## Rollback Plan
Delete the scaffolded `knowledge/`, `.ai/`, and `scripts/` additions if the repo should remain docs-only.

## Decision Log
- Start with Markdown and folders because the design is primarily an operating model, not yet an app requirement.
- Add `inbox`, `reviews`, and `archive` from v4 because they solve clear failure modes in v3.
- Defer automation until the templates are used enough to reveal real checks.

## Open Questions
- Should this evolve into scripts/CLI automation, a local app, or remain Markdown-only?
- What cadence is realistic for daily/weekly review?
- Which agent runtime should be treated as the default, if any?

## Owner
Kyle

## Reviewer
TBD

## Status
active