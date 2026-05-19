---
parent_branch: main
feature_number: "001"
status: In Progress
created_at: 2026-05-18T00:00:00Z
---

# Feature: Subagent-Driven Foundation File Generation

## Overview

`/ss:init` today generates the four `.specswarm/*.md` foundation files (constitution, tech-stack, quality-standards, references) from `package.json` auto-detection, interactive prompts, and — since v6.2.0 — memory-file principle import. It does **not** read the project's existing spec corpus (Strategy docs, decision logs, design briefs), even when that corpus contains the canonical, already-decided answers to the very questions `/ss:init` asks. Users who have invested in a rich spec corpus must either re-state each decision through interactive prompts or hand-author the foundation files before running `/ss:init`.

This feature extends `/ss:init` to read the spec corpus and propose foundation-file content automatically. A source-discovery subagent classifies the project's documentation surface; three extractor subagents (tech-stack, quality-standards, constitution) run in parallel against the classified sources and return structured proposals with citations and confidence ratings. The parent flow aggregates, deduplicates, conflict-detects, and surfaces proposals to the user via batched acceptance prompts — capped at a small number of interactions even on rich corpora. The user accepts, edits, or defers each batch; foundation files are then written using existing canonical templates with extracted values plugged in.

The architecture relies on subagents specifically because rich spec corpora can exceed 20K lines — far too much to fit in the parent context alongside the rest of the `/ss:init` workflow. Subagents have isolated contexts; each one reads only what its narrow extraction job needs and returns a compact structured summary (~3K lines total across four subagents vs. ~500K+ if the parent read everything).

## User Scenarios

### Scenario 1: Rich-corpus project — first init

A developer has been planning a new project for weeks. They've written `docs/STRATEGY.md` (200+ lines documenting framework, language, state management, testing tools — each tagged `[DECIDED]` with rationale), `docs/RULES.md` (enforceable principles in "must NEVER" / "every X must Y" form), and `docs/BUDGETS.md` (perf budgets, accessibility floor, browser support). They have a Claude Code memory directory with `feedback_*.md` rules and `project_*.md` context notes. They've never used SpecSwarm in this project.

They run `/ss:init`. SpecSwarm dispatches the discovery subagent, then three extractors in parallel. After ~1–2 minutes, the user sees grouped acceptance prompts:

> "17 high-confidence tech decisions extracted from STRATEGY.md §4. Accept the batch?"
> 1. Accept all (Recommended) · 2. Review one by one · 3. Skip — fill in later

After roughly 5–10 acceptance prompts (some batched, some per-item for conflicts), `.specswarm/constitution.md`, `tech-stack.md`, `quality-standards.md`, and `references.md` are written with their decisions intact, citations preserved as comments where useful, and `<!-- ss:user-additions -->` blocks ready for further hand-editing.

### Scenario 2: Thin project — README and `package.json` only

A developer is starting fresh. They have a `README.md`, a `package.json`, and a `tsconfig.json`. They have no `docs/`, no `feedback_*.md` files, and no prior `.specswarm/` directory.

They run `/ss:init`. The discovery subagent classifies the README as `documentation` (not `spec-doc`) and finds nothing under `docs/`. The extractor subagents return thin proposals — framework + language from `package.json`, nothing for constitution principles, nothing for quality budgets. The user sees the same interactive flow they would see on v6.x today, with no spec-extraction prompts. The four foundation files are generated from auto-detection + interactive answers, identical to v6.x behavior.

### Scenario 3: Sources disagree

The discovery + extraction surfaces a conflict: `docs/STRATEGY.md §4.2` says the framework is "React Router v7 [DECIDED]"; `CONTRIBUTING.md` line 14 says the framework is "Next.js". Both are cited; both are present.

The user sees a per-item prompt:

> "tech-stack.md — framework: Two sources disagree
>   1. React Router v7 (STRATEGY.md §4.2 [DECIDED])
>   2. Next.js (CONTRIBUTING.md:14)
>   3. Skip — resolve manually later
>   4. Custom value"

The user picks; the choice is written to `.specswarm/tech-stack.md`; the unselected option is dropped without modifying the source spec docs.

### Scenario 4: Re-run on populated project

A developer has previously run `/ss:init`. The foundation files exist and have hand-edited `<!-- ss:user-additions -->` blocks. The user updates their `docs/STRATEGY.md` to change the chosen testing framework, then re-runs `/ss:init`.

Discovery + extraction runs against the updated corpus. The new extracted value differs from the declared value in `.specswarm/tech-stack.md`. The user sees a drift-detection prompt:

> "tech-stack.md — unit_test: declared value differs from corpus
>   declared: vitest
>   corpus:   playwright-component (STRATEGY.md §4.6 [DECIDED 2026-05-15])
>   1. Use corpus value (Recommended)
>   2. Keep declared value
>   3. Skip — review later"

After acceptance, the regenerated `.specswarm/tech-stack.md` carries the new value; `<!-- ss:user-additions -->` blocks are preserved verbatim via the v6.4.0 reconciliation machinery.

### Scenario 5: Subagent partial output

A subagent crashes or times out partway through. Its proposals file is empty or truncated. The parent flow detects the missing destination and falls back to today's interactive prompts for that one destination only. The other two extractors' output is consumed normally. The user is informed: "constitution-extractor returned no output; falling back to interactive principles import."

## Functional Requirements

### FR1. Source classification

The system MUST classify every relevant file in the project into exactly one category (`spec-doc`, `documentation`, `config`, `memory`, `reference-codebase`, `source-code`, `noise`) using a single source-discovery subagent. The classification MUST be persisted at `.specswarm/.discovery.tmp` for downstream steps to consume. The scan MUST respect `.gitignore`, skip standard build-output directories (`node_modules`, `.git`, `dist`, `build`, `vendor`), and skip files over 1 MB.

### FR2. Bounded scan

By default the system MUST cap classification at 200 entries and limit recursion to `docs/`, `specs/`, `documentation/`, and root-depth-1 markdown files. A `--full-scan` flag MUST override the bound for projects whose spec content lives outside those default roots.

### FR3. Parallel extraction

The system MUST dispatch three extractor subagents — tech-stack, quality-standards, constitution — in a single batch (all three subagent calls in one message) so they execute in parallel. Each extractor MUST receive the discovery output and a targeted reading list filtered from it.

### FR4. Structured proposal output

Each extractor subagent MUST return its proposals as pipe-delimited records with this shape:
`destination|key|value|confidence|citation|rationale`
where multi-line values use `<<<BLOCK ... BLOCK` markers, confidence is one of `high|medium|low`, and citation is a path:line-or-section anchor. Proposals MUST be persisted at `.specswarm/.proposals.<destination>.tmp`.

### FR5. Aggregation

The parent flow MUST deduplicate proposals (same destination + key across or within subagents — keep highest confidence; preserve citations), detect conflicts (same destination + key but different values), and sort within each destination by confidence first, citation authority second.

### FR6. Conflict surfacing

Conflicts MUST be surfaced one at a time to the user via `AskUserQuestion`, listing each candidate value with its citation and offering a "Skip — resolve manually later" option plus a custom-value option.

### FR7. Batched acceptance

For each destination, high-confidence non-conflicting proposals MUST be presented as a single batch-accept prompt (default option: accept all). The user MUST be able to choose review-one-by-one or skip-batch.

### FR8. Interactive prompt cap

The total number of `AskUserQuestion` interactions added by extraction MUST NOT exceed approximately 20 per `/ss:init` invocation. Low-confidence items that would push past the cap MUST be deferred with a TODO comment in the generated file rather than surfaced individually.

### FR9. Citation verification

After aggregation, the system MUST grep-verify that each citation resolves to a real path and (when a line or section anchor is supplied) that the referenced location exists. Proposals with unverifiable citations MUST be downgraded to "uncited — review required" and surfaced in the interactive prompt for that destination.

### FR10. Drift detection on re-run

When `/ss:init` is run on a project that already has a `.specswarm/<file>.md` and the extractor proposes a different canonical value for a declared field, the system MUST surface a drift-detection prompt with the declared value, the corpus-derived value, and the citation. The user picks; the chosen value is written.

### FR11. Memory principle import folded into extraction

The constitution-extractor MUST incorporate the memory-driven principle import previously handled by Step 4.5: reading all `feedback_*.md` files (high yield) and `project_*.md` files (only when they describe enforceable rules — skipping pure-context project files like activity logs or contact info). The Step 4.5 standalone pass MUST be removed; the system MUST NOT extract principles twice.

### FR12. User-context memory default-skip

The extractors MUST default to skipping `user_*.md` memory files (personal context, not project rules). An `--include-user-memory` flag MUST opt them in.

### FR13. Subagent partial-output handling

When an extractor subagent returns no output, truncated output, or fails to write its proposals file, the system MUST detect this, log it, and fall back to today's interactive prompts for that destination only. The other extractors' proposals MUST be consumed normally.

### FR14. Reconciliation preservation

When the existing foundation file has `<!-- ss:user-additions -->` blocks, the `ss_preserve_user_sections` helper MUST run unchanged. Extracted proposals fill template placeholders and the canonical structure; user blocks survive the re-run verbatim.

### FR15. Constitutional hook generation preserved

When the constitution-extractor proposes a principle with a `rule_block` (one of `no-pattern`, `required-pattern`, `required-pair`) and the user accepts it, the rule block MUST land in `.specswarm/constitution.md` in the existing v6.3.0 `<!-- specswarm-rule: ... -->` comment format. `generate_constitutional_hooks` MUST continue to emit hooks from the resulting file unchanged.

### FR16. Backward compatibility for thin projects

A project with no spec corpus, no `docs/` directory, no Claude Code memory directory, and no `.specswarm/` history MUST run `/ss:init` to completion with output substantively equivalent to v6.x — auto-detect + interactive prompts only, no extraction prompts, no extraction-related output noise beyond a single status line acknowledging that no spec sources were found.

### FR17. Flag compatibility

The existing `--reset` and `--minimal` flags MUST retain their v6.4.0 semantics. `--minimal` MUST skip discovery and extractor dispatch entirely (matches its "no interactive prompts" promise). `--reset` MUST cause extractors to propose values without filtering against an existing declared value.

### FR18. Read-only on the project tree

Extractor subagents MUST NOT write to any file outside `.specswarm/`. Discovery and extraction MUST be read-only against `docs/`, `memory/`, `package.json`, etc.

## Success Criteria

### SC1. Rich-corpus extraction completeness

A project with a spec corpus that explicitly decides the framework, language, build tool, primary testing tool, and at least three enforceable principles MUST emerge from `/ss:init` with all of those decisions captured in the appropriate foundation files. Measurement: count of canonical sections populated by extraction versus left as `[NEEDS CLARIFICATION]` / template default. Target: ≥ 80% of explicitly-decided corpus content lands in the right foundation file.

### SC2. Interactive prompt budget

For a rich-corpus first-init (200 spec-doc lines, 50 memory files), total user interactions added by extraction MUST be ≤ 20 prompts. Measurement: count of `AskUserQuestion` calls during a single end-to-end run.

### SC3. Parent context budget

The parent `/ss:init` context MUST stay under 100K tokens for a rich-corpus init, with subagent extraction responsible for the heavy reading. Measurement: token-usage logging across the parent + subagent calls; subagent extraction MUST account for the majority of consumed reading-token budget.

### SC4. Backward-compat parity for thin projects

A thin project (only `README.md` and `package.json`) MUST complete `/ss:init` in roughly the same wall-clock time as v6.4.0 — extraction overhead MUST be bounded by the discovery subagent only (no extractor fan-out when there's nothing to extract from). Measurement: smoke-test against the synthetic thin fixture; extraction adds ≤ 30s vs. baseline.

### SC5. Reconciliation continuity

A re-run of `/ss:init` on a populated project MUST preserve every `<!-- ss:user-additions -->` block byte-for-byte. Measurement: diff `.specswarm/*.md` user-additions blocks before and after re-run; must be empty.

### SC6. Conflict resolution observability

Every conflict surfaced to the user MUST cite both sources by file:line. Every accepted resolution MUST be persisted to the audit log so a future `/ss:audit` can trace foundation-file content back to its corpus origin. Measurement: every conflict-resolution decision has a corresponding audit log entry.

### SC7. Subagent failure resilience

When any single extractor subagent fails or returns empty output, `/ss:init` MUST still complete successfully for the other destinations and gracefully fall back for the affected destination. Measurement: forced-failure smoke test (synthetic fixture with a subagent prompt that intentionally returns nothing).

### SC8. Citation veracity

For accepted proposals, ≥ 95% of citations MUST resolve to real paths and locations when grep-verified. Measurement: post-aggregation citation verification rate.

## Key Entities

- **Source classification map** (`.specswarm/.discovery.tmp`) — output of the discovery subagent; maps every relevant project file to a category and, for spec-docs, a one-sentence coverage tag. Consumed by Step 3.5 references discovery, the three extractors, and Step 6.5 conventions analysis.
- **Proposal record** — a single extracted decision/value/principle. Pipe-delimited fields: destination, key, value, confidence, citation, rationale. Multi-line values use `<<<BLOCK ... BLOCK` markers. Persisted at `.specswarm/.proposals.<destination>.tmp`.
- **Aggregated proposal set** — the deduplicated, conflict-marked, sorted union of proposals across all extractors, organized by destination. Used to drive Step 4.2 acceptance prompts.
- **Acceptance decision** — the user's response to a batch or per-item prompt: accept, reject, defer, customize. Drives what content lands in the foundation files.
- **Constitutional principle proposal** — a constitution-extractor proposal whose value field carries a multi-line principle body, an optional `rule_block` in one of three v6.3.0 formats (`no-pattern`, `required-pattern`, `required-pair`), and a severity (`warn`|`block`).

## Assumptions

- A1. Claude Code's `Agent` tool supports parallel dispatch when multiple `Agent` calls appear in a single assistant message. (To be verified empirically during Phase 1B before committing the parallel design.)
- A2. Spec corpora that declare canonical decisions use recognizable markers like `[DECIDED]`, `[OPEN]`, or imperative phrasing (`must NEVER`, `always`, `forbidden`). Extractors rely on these to assign high vs. medium confidence.
- A3. The default scan roots (`docs/`, `specs/`, `documentation/`, root-depth-1 `*.md`) cover where spec content lives in practice. Projects with non-standard spec locations use `--full-scan`.
- A4. Subagent per-call wall-clock latency is bounded enough that three extractors plus discovery complete within a few minutes on typical hardware. (No timeout enforcement is available; resilience comes from partial-output handling, not from kill-after-N-seconds.)
- A5. The pipe character (`|`) does not appear in extracted values often enough to require escaping in the proposal format. If it does, extractors are instructed to wrap such values in `<<<BLOCK ... BLOCK` markers.
- A6. The existing canonical templates (`tech-stack.template.md`, `quality-standards.template.md`, `constitution.skeleton.md`) carry enough placeholder structure to receive extracted values without further template-shape changes. (Verified during template review; if a destination needs new placeholders, those are added as a minor adjustment to the template.)
- A7. Synthetic fixtures at `plugins/ss/test-fixtures/rich-corpus/` provide sufficient coverage to validate extraction logic without requiring access to the customcult-v3 reference project. Final end-to-end validation against customcult-v3 is performed by the user (Marty) before v7.0.0 is tagged.
