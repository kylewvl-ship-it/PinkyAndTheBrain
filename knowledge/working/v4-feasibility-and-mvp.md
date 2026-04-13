# v4 Feasibility and MVP Path

## Status
active

## Prompt / Trigger
Evaluate whether `bulletproof_2nd_brain_system_v4.md` is feasible after `llm_wiki_2nd_brain_system_v_3.md`, and define how to start creating it.

## What I think
The system is feasible if treated as a repo-native operating model first and software automation second. v4 is a practical hardening of v3: it keeps the core raw/working/wiki model, adds intake and lifecycle management, and tightens validation/provenance rules.

The build should start with low-friction Markdown scaffolding, then add validation scripts only after the workflow is being used.

## Evidence
- v3 defines the core model: raw capture, working thinking, wiki stable knowledge, task files, and role-based agents.
- v4 adds missing lifecycle layers: inbox, reviews, archive, metadata policy, staleness control, duplication policy, and stricter agent contracts.
- Current repo is greenfield enough to adopt the structure without migration risk.

## Connections
[[build-v4-second-brain-mvp]]
[[knowledge-operating-policy]]

## Tensions / Contradictions
- The design says the system must stay lightweight, but v4 adds more folders and rituals.
- Agent separation improves quality, but can add friction for small solo tasks.
- Wiki verification is valuable, but too much provenance ceremony can stop capture.

## Open Questions
- Should validation become a script-based lint step for Markdown metadata?
- Should inbox triage be daily or simply before each work session?
- Which docs deserve first promotion into wiki pages?

## Next Moves
- Use the scaffold for one real task before adding automation.
- Create one wiki page from the v4 design once provenance expectations are clear.
- Add a small validation script only for checks that are repeated manually.

## Source Pointers
- bulletproof_2nd_brain_system_v4.md
- llm_wiki_2nd_brain_system_v_3.md
- .ai/handoffs/build-v4-second-brain-mvp.md