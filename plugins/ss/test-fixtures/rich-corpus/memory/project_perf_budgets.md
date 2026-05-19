---
name: project-perf-budgets
description: cross-reference to perf budgets in docs/BUDGETS.md
metadata:
  type: project
---

## Performance budgets — quick reference

Canonical source: `docs/BUDGETS.md`. Quick lookup:

- LCP: ≤ 2.5s all pages; ≤ 1.8s home; ≤ 2.0s PDP
- TBT: ≤ 200ms; CLS: ≤ 0.1
- Initial JS bundle: ≤ 180 KB gzipped
- Route chunk: ≤ 80 KB gzipped each

**Why:** PDP latency is our #1 conversion lever. Budgets are enforced in CI
via Lighthouse + WebPageTest.

**How to apply:** if a new feature adds > 5 KB to the initial bundle, request
a budget review before merge.
