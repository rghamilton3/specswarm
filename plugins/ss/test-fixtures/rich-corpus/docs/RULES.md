# RULES — Rich-Corpus Fixture

> Project-enforceable rules in declarative + imperative form. Used by SpecSwarm
> v7's `ss-constitution-extractor` subagent to test principle + rule-block
> generation.

## R1. No PII in application logs

PII (email addresses, full names, payment card numbers, postal addresses) MUST
NEVER appear in application log output, including stack traces and structured
log fields.

**Why:** GDPR Art. 5(1)(c) data minimization. Redaction after the fact is hard
and error-prone; not logging in the first place is the only reliable mitigation.

**How it's enforced:** any log call inside `src/**/*.ts` that names one of the
known PII fields fails review.

## R2. Database access only inside loaders and actions

Every database read or write MUST happen inside a React Router loader or
action. Components and hooks MUST NEVER call the database directly.

**Why:** loaders/actions are the single boundary where authentication,
authorization, and audit logging are applied. Breaking the boundary breaks
auditability.

**How it's enforced:** any file matching `app/components/**/*.tsx` that
imports from `db/` is rejected.

## R3. Mutations require audit log entries

Every server action that writes to the database MUST emit an audit-log entry
naming the actor, the action, the table, and the primary key. Read-only loaders
are exempt.

**Why:** SOX-style traceability for regulated business processes (orders,
refunds, account changes).

**How it's enforced:** any function under `app/routes/**/*.ts` whose body
matches `await db\.(insert|update|delete)\(` must also contain a call to
`auditLog(`.

## R4. No client-side state libraries

The application MUST NEVER import from `redux`, `@reduxjs/toolkit`,
`zustand`, `jotai`, `recoil`, or `mobx`. Server-managed state via React
Router loaders/actions is the only sanctioned mechanism.

**Why:** decided 2026-03-05 (see STRATEGY.md §4.4) to avoid duplicate
state-management mental models and to keep server as source of truth.

**How it's enforced:** any matching import in `app/**/*.{ts,tsx}` is a
constitution violation.

---

_Fixture file. Not a real project policy. Used by SpecSwarm v7 tests._
