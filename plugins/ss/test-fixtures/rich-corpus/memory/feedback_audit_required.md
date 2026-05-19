---
name: feedback-audit-required
description: every server action that writes must call auditLog in the same handler
metadata:
  type: feedback
---

## Mutations require audit log entries

Every server action under `app/routes/**/*.ts` that calls `db.insert`,
`db.update`, or `db.delete` MUST also call `auditLog(` somewhere in the same
function body.

**Why:** SOX-style traceability for regulated business processes. After the
2025-Q4 audit, we were told either we log every write or we fail compliance
review. We chose to log.

**How to apply:** the call site looks like
`auditLog({ actor, action, table, pk })`. It can happen before or after the
mutation; the linter only checks for presence in the same function body.
