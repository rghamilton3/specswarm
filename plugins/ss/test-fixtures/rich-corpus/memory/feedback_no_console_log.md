---
name: feedback-no-console-log
description: console.log must never ship to production source — replaced with structured logger
metadata:
  type: feedback
---

## No `console.log` in production source files

Any file under `src/**/*.ts` or `app/**/*.ts` MUST NEVER contain a call to
`console.log(`, `console.warn(`, or `console.error(`.

**Why:** `console.*` calls are not redacted by our log scrubber and have
historically leaked PII into the browser console in production. The structured
logger at `app/lib/logger.ts` is the only sanctioned mechanism.

**How to apply:** in dev, use `logger.debug(...)`. Console calls are fine in
tests (`**/*.test.ts`) and in build scripts (`scripts/**/*.ts`).
