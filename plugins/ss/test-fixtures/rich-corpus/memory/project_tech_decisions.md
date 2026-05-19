---
name: project-tech-decisions
description: cross-reference to canonical tech decisions in docs/STRATEGY.md decision log
metadata:
  type: project
---

## Tech decisions: where they live

Authoritative tech decisions are in `docs/STRATEGY.md` §3 (decision log) and §4
(tech stack). Memory entries here cross-reference but do not override.

**Why:** single source of truth. The Strategy doc is the artifact reviewers and
new hires read; if memory diverges from it, memory is stale.

**How to apply:** when a new tech decision is made, update STRATEGY.md and only
then add a memory entry pointing at the new entry.

Current state as of 2026-03-15:
- Framework: React Router v7 (see STRATEGY.md §4.1)
- Language: TypeScript 5.4 strict (see STRATEGY.md §4.2)
- Build: Vite 6 (see STRATEGY.md §4.3)
- DB: PostgreSQL 17 (see STRATEGY.md §6)
