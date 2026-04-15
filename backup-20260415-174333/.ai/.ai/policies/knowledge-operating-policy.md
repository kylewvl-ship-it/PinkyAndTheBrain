# Knowledge Operating Policy

## Authority Hierarchy
1. Code + passing tests = runtime truth
2. Migrations / schemas / contracts / APIs = data truth
3. ADRs = architectural intent
4. Accepted task files / change records = scoped implementation truth
5. Wiki = derived reference
6. Working notes = exploratory reasoning
7. Raw notes = unverified capture

## Core Rules
- No derived layer overrides a higher layer.
- Wiki pages require sources and metadata.
- Working notes may contain uncertainty and contradictions.
- Archive is excluded from default retrieval.
- One canonical wiki page per stable concept.

## Cadence
- Daily: empty inbox and scan active working notes.
- Weekly: review changed wiki pages and open contradictions.
- Monthly: stale sweep, duplication sweep, and archive dead notes.
- Per release: verify pages tied to changed code, contracts, or schemas.