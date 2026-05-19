# Expected output: v7 `/ss:init` against `plugins/ss/test-fixtures/rich-corpus/`

This document describes what a successful v7.0.0 `/ss:init --reset` run against this fixture should produce. It serves as a regression target for future maintainers and a sanity check for end-to-end behavior.

This document is **descriptive, not byte-for-byte canonical**. Extractor output will vary in phrasing run-to-run. What MUST hold is the semantic content — the same decisions, principles, and budgets land in the right foundation files with the right structure.

## Discovery output (`.specswarm/.discovery.tmp`)

```
spec-doc       docs/STRATEGY.md   <size>  Framework, language, build, state, styling, testing decisions with [DECIDED] markers and a decision log.
spec-doc       docs/RULES.md      <size>  Four enforceable project rules in must-NEVER / every-X-must-Y form.
spec-doc       docs/BUDGETS.md    <size>  Performance budgets (Core Web Vitals + asset budgets), WCAG AA accessibility baseline, browser support floor.
memory         memory/feedback_no_console_log.md          <size>  Enforceable rule banning console.* in src/**/*.ts.
memory         memory/feedback_audit_required.md          <size>  Enforceable rule requiring auditLog() in route handlers that write to the DB.
memory         memory/project_tech_decisions.md           <size>  Cross-reference to STRATEGY.md decision log.
memory         memory/project_perf_budgets.md             <size>  Cross-reference to BUDGETS.md quick lookup.
memory         memory/user_context.md                     <size>  Personal context (should be default-skipped by extractors).
config         package.json       <size>
config         tsconfig.json      <size>
noise-rollup                      <count>  (any noise files; expected near-zero in this fixture)
```

Discovery acknowledgment line: `Discovered 3 spec-docs, 5 memory files, 2 configs, <small-N> noise.`

## Extractor proposals

### `.specswarm/.proposals.tech-stack.tmp`

Minimum required high-confidence proposals from STRATEGY.md (each tagged `[DECIDED]`):

```
tech-stack|framework|React Router|high|docs/STRATEGY.md:§4.1|...
tech-stack|framework_version|7.2.1|high|package.json|matches dep version
tech-stack|language|TypeScript|high|docs/STRATEGY.md:§4.2|...
tech-stack|language_version|5.4|high|docs/STRATEGY.md:§4.2 or package.json|...
tech-stack|language_strict_flags|strict; noUncheckedIndexedAccess; exactOptionalPropertyTypes|high|tsconfig.json|...
tech-stack|build_tool|Vite|high|docs/STRATEGY.md:§4.3|...
tech-stack|build_tool_version|6|high|docs/STRATEGY.md:§4.3 or package.json|...
tech-stack|state_mgmt|Server-managed via React Router loaders/actions|high|docs/STRATEGY.md:§4.4|...
tech-stack|styling|Tailwind CSS v4|high|docs/STRATEGY.md:§4.5|...
tech-stack|unit_test|Vitest|high|docs/STRATEGY.md:§4.6|...
tech-stack|e2e_test|Playwright|high|docs/STRATEGY.md:§4.6|...
```

Prohibited entries (from §4.4 and §4.8):

```
tech-stack|prohibited.1|Axios|high|docs/STRATEGY.md:§4.8|Use fetch
tech-stack|prohibited.2|Lodash|high|docs/STRATEGY.md:§4.8|Use native methods
tech-stack|prohibited.3|moment.js|high|docs/STRATEGY.md:§4.8|Use date-fns / Intl
tech-stack|prohibited.4|Class components|high|docs/STRATEGY.md:§4.8|Functional only
tech-stack|prohibited.5|Default exports in app code|high|docs/STRATEGY.md:§4.8|Named exports
tech-stack|prohibited.6|Redux|high|docs/STRATEGY.md:§4.4|Server state via loaders
```

Open decisions (from §5):

```
tech-stack|open_decision.1|Image CDN provider|high|docs/STRATEGY.md:§5|Phase 2
tech-stack|open_decision.2|Email transactional provider|high|docs/STRATEGY.md:§5|Phase 2
tech-stack|open_decision.3|Analytics|high|docs/STRATEGY.md:§5|Phase 3
```

### `.specswarm/.proposals.quality-standards.tmp`

```
quality-standards|coverage_threshold|80% statements / 75% branches|high|docs/BUDGETS.md:§coverage|...
quality-standards|perf_budget.lcp|≤ 2.5s|high|docs/BUDGETS.md:§per-page-core-web-vitals|...
quality-standards|perf_budget.tbt|≤ 200ms|high|docs/BUDGETS.md:§per-page-core-web-vitals|...
quality-standards|perf_budget.cls|≤ 0.1|high|docs/BUDGETS.md:§per-page-core-web-vitals|...
quality-standards|perf_budget.bundle|≤ 180 KB gzipped|high|docs/BUDGETS.md:§asset-budgets|...
quality-standards|perf_budget.chunk|≤ 80 KB gzipped|high|docs/BUDGETS.md:§asset-budgets|...
quality-standards|browser_support_floor|latest 2 of Chrome/Edge/Firefox/Safari|high|docs/BUDGETS.md:§browser-support|...
quality-standards|a11y_wcag_level|WCAG 2.2 Level AA|high|docs/BUDGETS.md:§accessibility|...
quality-standards|a11y_axe_required|zero violations in CI|high|docs/BUDGETS.md:§accessibility|...
quality-standards|a11y_contrast|≥ 4.5:1 small text; ≥ 3:1 large|high|docs/BUDGETS.md:§accessibility|...
quality-standards|a11y_focus_visible|every interactive element|high|docs/BUDGETS.md:§accessibility|...
quality-standards|a11y_touch_targets|44×44 px primary; 24×24 inline|high|docs/BUDGETS.md:§accessibility|...
quality-standards|a11y_reduced_motion|respect prefers-reduced-motion|high|docs/BUDGETS.md:§accessibility|...
quality-standards|email_deliverability_target|100% SPF+DKIM+DMARC|high|docs/BUDGETS.md:§email-deliverability|...
```

### `.specswarm/.proposals.constitution.tmp`

At minimum, four principles from `docs/RULES.md` (R1-R4) and the two memory rules (feedback_no_console_log, feedback_audit_required). The constitution extractor folds in the v6.2.0 memory principle import (FR11), so memory rules should NOT also appear as a separate Step-4.5 import.

Expected principles (numbered P1..PN in acceptance order):

- **No PII in application logs** — citation `docs/RULES.md:§r1-no-pii-in-application-logs`. severity=`block`. rule_block=`no-pattern` glob `src/**/*.ts`, bad-pattern matching `log\.(info|warn|error)\(.*\b(email|fullName|cardNumber|address)\b`.
- **Database access only inside loaders and actions** — citation `docs/RULES.md:§r2`. severity=`block`. rule_block=`no-pattern` glob `app/components/**/*.tsx`, bad-pattern matching `from\s+['"].*db/`.
- **Mutations require audit log entries** — citation `docs/RULES.md:§r3`. severity=`block` or `warn`. rule_block=`required-pair` glob `app/routes/**/*.ts`, trigger-pattern `await\s+db\.(insert|update|delete)\(`, pair-pattern `auditLog\(`.
- **No client-side state libraries** — citation `docs/RULES.md:§r4`. severity=`block`. rule_block=`no-pattern` glob `app/**/*.{ts,tsx}`, bad-pattern `from\s+['"](redux|@reduxjs/toolkit|zustand|jotai|recoil|mobx)`.
- **No console.log in production source** — citation `memory/feedback_no_console_log.md`. severity=`warn`. rule_block=`no-pattern` glob `src/**/*.ts` OR `app/**/*.ts`, bad-pattern `console\.(log|warn|error)\(`.
- **Audit log required on writes** — likely DEDUPED with R3 by the aggregator (same rule from spec + memory; highest-confidence source kept).

`user_context.md` MUST NOT contribute any principle proposals (default-skipped per FR12). Running with `--include-user-memory` would change this.

## Aggregation (`.specswarm/.proposals.aggregated.tmp`)

- Tech-stack: ~20+ records, mostly `high`, with `prohibited.*` and `open_decision.*` positional lists
- Quality-standards: ~13+ records, all `high`
- Constitution: 4–5 principle records (R3 + feedback_audit_required dedupe to one)
- Citation verification rate: 100% (every citation in this fixture resolves)
- Conflicts: 0 (no contradictory sources in the fixture)

## User-facing AskUserQuestion prompts during Step 4.2

Expect roughly 4–8 prompts total against this fixture:

- 1 batch-accept for tech-stack high-confidence (~20 items)
- 1 batch-accept for quality-standards (~13 items)
- 1 batch-accept for constitution (~4-5 principles)
- Possibly 1–4 low-confidence per-item prompts if any low-conf items emerge
- 0 conflict prompts (no conflicts expected)

Well under the ≤ 20 cap.

## Generated foundation files

After Step 7 cleanup, `.specswarm/` should contain:

- `constitution.md` — 4-5 principles with `<!-- specswarm-rule: ... -->` blocks; `generate_constitutional_hooks` emits 4-5 hook files under `.specswarm/hooks/generated/`
- `tech-stack.md` — Core Technologies populated with framework/language/build/state/styling/testing; Prohibited section listing Axios/Lodash/moment/class/default-export/Redux; Open Decisions section with the 3 phase-tagged items
- `quality-standards.md` — coverage thresholds, perf budgets, WCAG AA baseline, browser support floor, focus-visible / touch-targets / reduced-motion requirements
- `references.md` — Spec corpus entries pointing to `docs/STRATEGY.md`, `docs/RULES.md`, `docs/BUDGETS.md`; memory dir entry pointing to the fixture's `memory/`
- `conventions.md` — auto-generated from tsconfig + package.json scripts (light content; no eslintrc in fixture)

## How to actually run this

> ⚠️ The brief forbids running `/ss:init` against this fixture from inside the SpecSwarm repo itself (the repo's own `.specswarm/` is the maintainer's working state and must not be regenerated).

To validate, copy the fixture out to a fresh sandbox directory:

```bash
cp -r plugins/ss/test-fixtures/rich-corpus /tmp/v7-acceptance-rich
cd /tmp/v7-acceptance-rich
git init && git add -A && git commit -m "init fixture"
# Then in a Claude Code session opened on /tmp/v7-acceptance-rich:
# /ss:init --reset
```

Diff `.specswarm/*.md` against this document's expectations. ≥ 80% semantic match passes SC1.
