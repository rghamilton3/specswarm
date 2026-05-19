---
name: user-context
description: personal context — preferred timezone, working hours, accent color
metadata:
  type: user
---

## Personal context

This is a synthetic personal-context memory file. Used by SpecSwarm v7 tests
to verify that `user_*.md` files are **default-skipped** by all three
extractors. If the constitution extractor proposes a principle citing this
file, the test fails: the `--include-user-memory` flag was supposed to be off.

- Preferred timezone: America/Denver
- Working hours: 09:00 — 18:00 local
- UI accent color preference: green-700
- IDE: Cursor

This file contains zero enforceable project rules, by construction.
