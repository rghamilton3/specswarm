# Implementation Plan: Subagent-Driven Foundation File Generation

**Branch**: `001-subagent-foundation-extraction`
**Spec**: [spec.md](spec.md)
**Target release**: v7.0.0 (single PR)

## Technical Context

This is a Claude Code plugin written primarily in bash + markdown. The plugin's "source files" are:

- **Slash-command prompts** under `plugins/ss/commands/*.md` — markdown documents that double as LLM instructions when invoked by the user
- **Skill files** under `plugins/ss/skills/*/SKILL.md` — invokable workflows
- **Shell helper libraries** under `plugins/ss/lib/*.sh` — sourced by commands and hooks for parsing, validation, audit, etc.
- **Hook scripts** under `plugins/ss/hooks/*.sh` — event-driven shell scripts the harness runs
- **Templates** under `plugins/ss/templates/*` — canonical output forms (constitution skeleton, tech-stack/quality-standards templates, hook templates)
- **Manifests** at `plugins/ss/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`

The feature touches the orchestration layer (the `/ss:init` command, which is one of the larger command files at ~1777 lines), introduces new shell helpers, adds a single LLM-level subagent dispatch step (Step 3.0), and adds a fan-out parallel dispatch step (Step 4.0) implemented as a single assistant message with three `Agent` tool calls.

There is no traditional application runtime, database, or HTTP API. The "data model" is a flat-file proposal record format. The "contracts" are subagent prompt specifications.

## Constitution Check

The SpecSwarm repo itself does NOT have `.specswarm/constitution.md` populated. The brief explicitly forbids running `/ss:init` against this repo during v7 dev (it would overwrite the maintainer's working state). Constitution check is therefore skipped by design for this feature.

Equivalent maintainer-level principles that apply here, captured implicitly by the spec:

- Pure bash + grep/sed/awk in shell helpers — no `jq`, Python, or npm dependencies (matches existing `lib/` style)
- `set -e` is NOT enabled in `lib/` parsers that return non-zero as signal (matches `guide-parsers.sh` convention)
- Idempotency: re-running `/ss:init` MUST be safe (matches v6.4.0 reconciliation guarantee — FR14)
- Read-only against the project tree (FR18 in spec)
- Backwards compat with v6.x thin-project behavior (FR16, SC4)

## Tech-stack initialization (skipped by design)

The `/ss:plan` skill normally creates `.specswarm/tech-stack.md` on first-feature setup. This is skipped for this feature because:

1. The brief explicitly forbids generating foundation files inside the SpecSwarm repo during v7 development (would clobber the maintainer's working state)
2. The feature targets the plugin itself (markdown + bash), not the project's app-runtime tech stack
3. There are no plan-time tech choices that need stack validation — implementation language is fixed (bash + markdown)

Any future SpecSwarm-on-SpecSwarm meta-work that legitimately needs a tech-stack.md will create one in a dedicated session, not as a side-effect of v7 planning.

## File-by-file change map

### Modified files

| File | Phase | Change |
|------|-------|--------|
| `plugins/ss/commands/init.md` | 1A, 1B, 1C, 2 | Insert Steps 3.0, 4.0, 4.1, 4.2. Rework Steps 3.5, 4, 5, 6, 7. Remove Step 4.5. Add `--full-scan` and `--include-user-memory` to arg parsing. New summary metrics in Step 7. |
| `plugins/ss/.claude-plugin/plugin.json` | 2 | Version `6.4.0` → `7.0.0`. |
| `plugins/specswarm/.claude-plugin/plugin.json` | 2 | Version `6.4.0` → `7.0.0` (kept in sync with `ss` stub). |
| `.claude-plugin/marketplace.json` | 2 | Both `plugins[].version` entries bumped to `7.0.0`. |
| `CHANGELOG.md` | 2 | New `## [7.0.0]` entry above v6.4.0. |
| `plugins/ss/README.md` (if present) | 2 | Add "Spec corpus extraction" section. |
| `plugins/ss/CLAUDE.md` | 2 | Touch only if the file lists v6 step numbering — keep current. |

### New library files

| File | Phase | Purpose |
|------|-------|---------|
| `plugins/ss/lib/extraction-schema.sh` | 1B | Document and validate the pipe-delimited proposal record format. Public functions: `ss_proposal_emit`, `ss_proposal_read_each` (calls callback per record, handles `<<<BLOCK ... BLOCK` markers), `ss_proposal_validate_record`. Used by extractors (indirectly — they emit text) and by the aggregator (directly — to parse). |
| `plugins/ss/lib/proposal-aggregator.sh` | 1C | Dedupe, conflict detect, sort. Public functions: `ss_proposals_dedupe`, `ss_proposals_detect_conflicts`, `ss_proposals_sort_by_authority`, `ss_proposals_coverage_gaps`. Reads from `.specswarm/.proposals.<destination>.tmp` files; writes resolved-set to `.specswarm/.proposals.aggregated.tmp`. |
| `plugins/ss/lib/citation-verifier.sh` | 2 | grep-verify that each citation resolves to a real file:section. Public function: `ss_citation_verify <path-or-anchor>` → exit 0 if resolvable, 1 if not. Used by Step 4.1 post-aggregation. |

### New template files

| File | Phase | Purpose |
|------|-------|---------|
| `plugins/ss/templates/agents/ss-source-discoverer.md.template` | 2 (optional) | Externalized form of the discovery prompt. Phase 1A ships the prompt inline in `init.md`; Phase 2 extracts it here if length warrants. |
| `plugins/ss/templates/agents/ss-tech-stack-extractor.md.template` | 2 (optional) | Same pattern for tech-stack extractor. |
| `plugins/ss/templates/agents/ss-quality-standards-extractor.md.template` | 2 (optional) | Same pattern. |
| `plugins/ss/templates/agents/ss-constitution-extractor.md.template` | 2 (optional) | Same pattern. |

### New test fixtures

| File | Phase | Purpose |
|------|-------|---------|
| `plugins/ss/test-fixtures/rich-corpus/docs/STRATEGY.md` | 1A | ~200 lines: 6 `[DECIDED]` tech entries with rationale, 3 `[OPEN]` phase-tagged. |
| `plugins/ss/test-fixtures/rich-corpus/docs/RULES.md` | 1A | ~80 lines: 4 enforceable principles in "must NEVER" / "every X must Y" form. |
| `plugins/ss/test-fixtures/rich-corpus/docs/BUDGETS.md` | 1A | ~60 lines: perf budgets in tables, a11y baseline, browser support floor. |
| `plugins/ss/test-fixtures/rich-corpus/memory/feedback_no_console_log.md` | 1A | Enforceable rule with rationale. |
| `plugins/ss/test-fixtures/rich-corpus/memory/feedback_audit_required.md` | 1A | Enforceable rule with rationale. |
| `plugins/ss/test-fixtures/rich-corpus/memory/project_perf_budgets.md` | 1A | Quality content (perf budget restatement). |
| `plugins/ss/test-fixtures/rich-corpus/memory/project_tech_decisions.md` | 1A | Tech content (decision log). |
| `plugins/ss/test-fixtures/rich-corpus/memory/user_context.md` | 1A | Personal context — used to verify default-skip. |
| `plugins/ss/test-fixtures/rich-corpus/package.json` | 1A | Framework + testing deps declared. |
| `plugins/ss/test-fixtures/rich-corpus/tsconfig.json` | 1A | strict mode config. |
| `plugins/ss/test-fixtures/thin/README.md` | 1A | Smoke-test fixture for FR16 / SC4 (thin-project parity). |
| `plugins/ss/test-fixtures/thin/package.json` | 1A | Minimal package metadata. |
| `plugins/ss/test-fixtures/rich-corpus/EXPECTED-OUTPUT.md` | 2 | Hand-curated reference output for v7 acceptance demo. |

Fixtures ship with the plugin (useful as regression-test assets for future maintainers).

### Files unchanged but contracts must be honored

| File | Why mentioned |
|------|---------------|
| `plugins/ss/lib/guide-parsers.sh` | `ss_preserve_user_sections` ordinal-matching behavior is part of FR14. Do not touch. |
| `plugins/ss/lib/references-loader.sh` | Public API consumed by Step 3.5; remains stable. |
| `plugins/ss/lib/constitution-parser.sh` | `generate_constitutional_hooks` and rule-block format remain stable (FR15). |
| `plugins/ss/templates/constitution.skeleton.md` | Unchanged. |
| `plugins/ss/templates/tech-stack.template.md` | Unchanged at the placeholder level — extracted values fill existing `[PLACEHOLDER]` slots. If extraction surfaces a value that has no existing placeholder, the extra goes in a `<!-- ss:user-additions -->` block (per the existing v6.4.0 pattern). |
| `plugins/ss/templates/quality-standards.template.md` | Same. |
| `plugins/ss/templates/references.md.template` | Same. |

## Dependency order across phases

```
Phase 1A:  Fixtures ─┬──────────────────────────────────────────────────────────┐
           Step 3.0  ─┤                                                          │
           Step 3.5/6.5 consumer updates  ─┘                                     │
                                                                                  │
Phase 1B:  extraction-schema.sh ──────► Step 4.0 (3 extractors, parallel)         │
                                          │                                       │
Phase 1C:  proposal-aggregator.sh  ─────► Step 4.1 ──► Step 4.2 ──► Step 4/5/6   │
                                                                       rewrite    │
                                                                                  │
Phase 2:   citation-verifier.sh ──► hook into Step 4.1                            │
           agent template extraction (optional)                                   │
           CHANGELOG.md, README.md, version bumps ───────────────────────────────┘
                                                                                  │
                                                                          single PR
```

Within a phase, files marked Phase 1A in the table above are independent and can be created in parallel. The fixture set is independent of the `init.md` changes; both can land before extractor design (1B) begins.

## Phase 0: Outline & Research

The spec lists 7 assumptions. The two needing research-style validation are baked into the implementation phases themselves, since both answers depend on empirical behavior of Claude Code rather than external documentation:

- **A1. Parallel `Agent` dispatch**: verified at the start of Phase 1B by writing two probe `Agent` calls in a single message and observing whether they execute concurrently. If they do not, the design falls back to sequential dispatch (still saves parent context, loses wall-clock parallelism only).
- **A4. Subagent timeout**: confirmed at the start of Phase 1B that no timeout knob exists on the `Agent` tool. Mitigation is in FR13 (partial-output handling). No further research needed.

Other assumptions (A2–A3, A5–A7) are accepted as designed; they get validated implicitly by the rich-corpus fixture smoke test in Phase 1C.

Output: [research.md](research.md)

## Phase 1: Design

### Data model

The proposal record format. See [data-model.md](data-model.md).

### Contracts

Four subagent prompt contracts — one per subagent. See [contracts/](contracts/) directory:

- `contracts/ss-source-discoverer.md` — discovery prompt + output schema
- `contracts/ss-tech-stack-extractor.md` — tech extraction prompt + output schema
- `contracts/ss-quality-standards-extractor.md` — quality extraction prompt + output schema
- `contracts/ss-constitution-extractor.md` — constitution extraction prompt + output schema

### Quickstart

User-facing demo of what v7 looks like in practice. See [quickstart.md](quickstart.md).

## Phase 2 (deferred until Phase 1 complete)

- Citation verification wired into Step 4.1
- Optional agent prompt externalization to `plugins/ss/templates/agents/`
- README "Spec corpus extraction" section
- CHANGELOG `[7.0.0]` entry
- Version bumps in all three manifest files
- `EXPECTED-OUTPUT.md` reference transcript for the rich-corpus fixture

## Validation gates (must pass before tagging v7.0.0)

1. `claude plugin validate plugins/ss/` exits 0
2. `claude plugin validate plugins/specswarm/` exits 0
3. Existing `/ss:init` behavior unchanged on the thin fixture (no extraction prompts, file output diff vs. v6.4.0 should be empty modulo timestamps)
4. Rich-corpus fixture produces a `.specswarm/*.md` set that matches the hand-curated `EXPECTED-OUTPUT.md` for the documented decisions
5. All four `ss_check_*_sufficient` functions continue to pass on a freshly-generated foundation file set
6. `generate_constitutional_hooks` produces hooks from a constitution.md authored by the constitution-extractor (FR15 end-to-end)
7. Maintainer (Marty) runs `/ss:init --reset` against customcult-v3 himself and confirms output quality before v7.0.0 is tagged
