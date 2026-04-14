# PinkyAndTheBrain

Local-first second brain + LLM wiki + multi-agent operating system.

## Design Source
- `llm_wiki_2nd_brain_system_v_3.md`: original raw/working/wiki + task/agent model.
- `bulletproof_2nd_brain_system_v4.md`: hardened target design with inbox, archive, reviews, metadata, staleness, and stricter validation.

## Current MVP
This repo starts as a Markdown-first operating system. Do not build an app or database until the manual workflow proves what needs automation.

## MVP Commands
- `.\scripts\setup-system.ps1`: verify/create the required local folder structure.
- `.\scripts\capture.ps1 -Title "Idea" -Content "..."`: capture a new inbox item.
- `.\scripts\triage.ps1 -List`: list inbox items awaiting disposition.
- `.\scripts\triage.ps1 -File "<file>" -Disposition working`: move an item into a knowledge layer.
- `.\scripts\search.ps1 -Query "term"`: search the knowledge base, excluding archive by default.
- `.\scripts\health-check.ps1 -WriteReport`: check metadata, links, sources, stale reviews, and orphaned notes.
- `.\scripts\obsidian-sync.ps1 -WriteIndexes`: refresh layer indexes for Obsidian-friendly navigation.

## Authority Hierarchy
1. Code + passing tests
2. Migrations / schemas / contracts / APIs
3. ADRs
4. Accepted task files / change records
5. Wiki
6. Working notes
7. Raw notes

No derived note overrides a higher-authority artifact.

## Daily Loop
1. Capture quickly in `knowledge/inbox/`.
2. Move useful source material to `knowledge/raw/`.
3. Develop thinking in `knowledge/working/` using `knowledge/schemas/working-note-template.md`.
4. Promote only reusable, sourced knowledge to `knowledge/wiki/` using `knowledge/schemas/wiki-page-template.md`.
5. Track meaningful work in `.ai/handoffs/` using `.ai/handoffs/task-template.md`.

## Weekly Loop
- Review active working notes.
- Check changed wiki pages for stale claims.
- Archive notes that no longer help retrieval.
- Remove duplicate wiki concepts or replace duplicates with links.

## First Task
Start with `.ai/handoffs/build-v4-second-brain-mvp.md`.
