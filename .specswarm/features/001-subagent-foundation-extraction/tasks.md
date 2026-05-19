# Tasks: Subagent-Driven Foundation File Generation

**Feature**: 001-subagent-foundation-extraction
**Target**: v7.0.0 (single PR)
**Phases**: 1A → 1B → 1C → 2 (sequential)

Tasks within a phase tagged `[P]` may run in parallel; everything else is sequential within the phase.

## Phase 1A — Source Discovery + Fixtures

### T1.A1 Create rich-corpus fixture directory `[P]`

Build the v7 test fixture at `plugins/ss/test-fixtures/rich-corpus/`. Content per [plan.md §New test fixtures](plan.md):

- `docs/STRATEGY.md` — ~200 lines, 6 `[DECIDED]` tech entries with rationale, 3 `[OPEN]` markers
- `docs/RULES.md` — ~80 lines, 4 enforceable principles in `must NEVER` / `every X must Y` form
- `docs/BUDGETS.md` — ~60 lines, perf budgets in tables, a11y baseline, browser support floor
- `memory/feedback_no_console_log.md`, `feedback_audit_required.md` — enforceable rules
- `memory/project_perf_budgets.md`, `project_tech_decisions.md` — quality/tech content
- `memory/user_context.md` — personal-context (must be default-skipped by extractors)
- `package.json`, `tsconfig.json` — minimal but realistic

### T1.A2 Create thin fixture directory `[P]`

`plugins/ss/test-fixtures/thin/` with just `README.md` (5 lines) and `package.json` (minimal). Used to validate FR16 / SC4 (backward compat for thin projects).

### T1.A3 Add `--full-scan` and `--include-user-memory` to init.md arg parsing `[P]`

Edit `plugins/ss/commands/init.md` Step 0 (the existing arg-parsing block near line 64). Add the two new flags with the same pattern as `--reset` / `--minimal`. Variables: `FULL_SCAN_FLAG`, `INCLUDE_USER_MEMORY_FLAG`. Default both to false.

### T1.A4 Insert Step 3.0 (Source Discovery) into init.md

Insert between existing Step 3 (line ~319 in v6.4.0) and Step 3.5 (line ~443). The step:

1. Computes `MEMORY_DIR=$HOME/.claude/projects/$(pwd | tr / -)/memory`
2. Computes the default scan-root set (or empty if `--full-scan`)
3. Dispatches the discovery subagent via a single `Agent` call (prompt body from [contracts/ss-source-discoverer.md](contracts/ss-source-discoverer.md))
4. Waits for subagent to return; verifies `.specswarm/.discovery.tmp` exists and is non-empty
5. On empty/missing: emit warning, set `DISCOVERY_AVAILABLE=false`, continue

### T1.A5 Rework Step 3.5 to consume discovery output

Edit the existing Step 3.5 (lines ~443–828). Where the existing flow scans the filesystem for spec-corpus candidates, replace with: read `.specswarm/.discovery.tmp`, filter for `spec-doc` and `reference-codebase` categories, present those as candidates to the user. The existing sibling-repo + path-pattern scans remain as fallbacks when `DISCOVERY_AVAILABLE=false`.

### T1.A6 Rework Step 6.5 to consume discovery output

Edit Step 6.5 (lines ~1380–1462). Where the existing flow scans source code to infer conventions, replace with: read `.specswarm/.discovery.tmp`, filter for `source-code` records, use those as the source-file inventory (cheaper than a fresh scan; better-classified).

### T1.A7 Probe parallel `Agent` dispatch

Before Phase 1B starts, send a single throwaway message with two `Agent` calls each instructed to record a timestamp. Confirm both timestamps land within ~5s. If sequential, document in research.md R1 and update Step 4.0 design to sequential dispatch. **Blocking** for Phase 1B kickoff.

### T1.A8 Commit Phase 1A

`git commit -m "feat(v7-1a): source discovery subagent + fixtures + Step 3.5/6.5 consumers"`

## Phase 1B — Parallel Extraction

### T1.B1 Create lib/extraction-schema.sh

Write `plugins/ss/lib/extraction-schema.sh` per [data-model.md §Schema validation](data-model.md). Functions:

- `ss_proposal_validate_record <line>` — exit 0 if parseable
- `ss_proposal_read_each <file> <callback>` — multi-line BLOCK-aware reader
- `ss_proposal_emit <destination> <key> <value> <conf> <citation> <rationale> [<severity> <rule_block>]` — well-formed writer (auto-BLOCK-wraps as needed)

No `set -e` (matches lib/ convention for parsers).

### T1.B2 Insert Step 4.0 (Parallel Extraction) into init.md

New step between Step 3.5 and existing Step 4 (constitution). Step:

1. Reads `.specswarm/.discovery.tmp`
2. Builds three filtered reading lists (one per extractor) per the contracts
3. Issues a SINGLE assistant message containing THREE `Agent` tool calls with the three extractor prompts (verbatim from contracts/)
4. Waits for all three; for each, verifies its proposals file exists and is non-empty
5. On per-subagent failure: set destination-specific fallback flag (FR13)
6. Skipped entirely under `--minimal`

### T1.B3 Write tech-stack extractor prompt into Step 4.0

Inline the verbatim prompt from [contracts/ss-tech-stack-extractor.md](contracts/ss-tech-stack-extractor.md). Interpolate the filtered reading list.

### T1.B4 Write quality-standards extractor prompt into Step 4.0

Inline from [contracts/ss-quality-standards-extractor.md](contracts/ss-quality-standards-extractor.md).

### T1.B5 Write constitution extractor prompt into Step 4.0

Inline from [contracts/ss-constitution-extractor.md](contracts/ss-constitution-extractor.md). This prompt folds in the v6.2.0 memory-driven principle import — reading `feedback_*.md` files exhaustively and `project_*.md` files selectively.

### T1.B6 Remove Step 4.5 (memory-driven principle import)

The standalone Step 4.5 (lines ~913–1089) is REMOVED. Its responsibilities transfer to T1.B5's constitution extractor (FR11). Leave a single comment marker in init.md noting Step 4.5 was folded into Step 4.0 in v7.0.0.

### T1.B7 Smoke-test extractor output format on rich-corpus fixture

Dispatch each extractor subagent independently with paths pointed at `plugins/ss/test-fixtures/rich-corpus/`. Verify each produces a valid `.proposals.<destination>.tmp`. Run `ss_proposal_read_each` against each and confirm record counts ≥ expected minimums.

### T1.B8 Commit Phase 1B

`git commit -m "feat(v7-1b): three extractors + extraction-schema.sh + Step 4.0 parallel dispatch"`

## Phase 1C — Aggregation + Interactive Acceptance + Generation Rewrite

### T1.C1 Create lib/proposal-aggregator.sh

Write `plugins/ss/lib/proposal-aggregator.sh`. Functions:

- `ss_proposals_dedupe <file...>` — same-destination/same-key dedupe, keep highest confidence
- `ss_proposals_detect_conflicts <file...>` — emit conflict-group records for same-destination/same-key with differing values
- `ss_proposals_sort_by_authority <file>` — sort within destination: confidence first, citation authority second (Strategy > memory > general docs > config)
- `ss_proposals_coverage_gaps <file>` — emit a TSV of `<destination>\t<canonical-key>\t<status>` for canonical keys not present in proposals (status: `missing`, `low-conf-only`)

Aggregates output to `.specswarm/.proposals.aggregated.tmp` per [data-model.md §Format 3](data-model.md).

### T1.C2 Insert Step 4.1 (Aggregation) into init.md

After Step 4.0. Reads `.specswarm/.proposals.<destination>.tmp`, calls aggregator functions, writes `.specswarm/.proposals.aggregated.tmp`. Emits coverage-gap and conflict summary lines (≤ 5 lines visible to user).

### T1.C3 Insert Step 4.2 (Interactive Acceptance) into init.md

After Step 4.1. For each destination, walk the aggregated proposals:

1. Issue one batch-accept `AskUserQuestion` for high-confidence non-conflicting groups
2. Per-item `AskUserQuestion` for each conflict (cap budget per R7)
3. Per-item `AskUserQuestion` for low-confidence items within budget; deferred items get TODO comments in the generated file
4. Drift detection: if existing `.specswarm/<file>.md` has a declared value and extractor proposes different, surface as a drift prompt (R10)

Write each acceptance decision to `.specswarm/.acceptance-log.tmp` and to `audit_log`.

Total prompts capped at ~20 across all destinations per FR8 / R7.

### T1.C4 Rework Step 4 (Constitution generation)

Edit existing Step 4 (lines ~829–912). Generate `.specswarm/constitution.md` by:

1. Reading accepted constitution proposals from `.proposals.aggregated.tmp`
2. Pulling the `value` body (principle text) and `rule_block` (optional)
3. Writing the principle into the canonical constitution skeleton's principles section, in P1, P2, … order
4. Calling existing `generate_constitutional_hooks` unchanged (FR15)
5. Running `ss_preserve_user_sections` if a prior constitution.md exists (FR14)

### T1.C5 Rework Step 5 (Tech-stack generation)

Edit existing Step 5 (lines ~1090–1241). Generate `.specswarm/tech-stack.md` by:

1. Reading accepted tech-stack proposals from `.proposals.aggregated.tmp`
2. Replacing `[PLACEHOLDER]` slots in `tech-stack.template.md` with accepted values
3. Putting extras (prohibited entries, open decisions, approved libs beyond template) into the existing `<!-- ss:user-additions -->` block region
4. Citing the source as a sibling HTML comment (`<!-- source: docs/STRATEGY.md:42 -->`)
5. Running `ss_preserve_user_sections` against any prior file (FR14)

### T1.C6 Rework Step 6 (Quality-standards generation)

Edit existing Step 6 (lines ~1242–1379). Same pattern as T1.C5 for quality-standards.

### T1.C7 Rework Step 7 (Summary)

Edit existing Step 7 (lines ~1619+). Add extraction-related summary lines: proposals extracted by destination, accepted/deferred/conflicted counts, citation verification rate, time per phase.

### T1.C8 Smoke-test end-to-end against rich-corpus fixture

Run a full mock `/ss:init` flow (LLM-level) against `plugins/ss/test-fixtures/rich-corpus/`. Verify:

- `.specswarm/.discovery.tmp` is correct
- 3 `.proposals.<destination>.tmp` files have expected record counts
- `.proposals.aggregated.tmp` has expected dedupe + conflicts
- Final `.specswarm/*.md` files match expected content for canonical sections (≥ 80% per SC1)

### T1.C9 Smoke-test end-to-end against thin fixture

Run against `plugins/ss/test-fixtures/thin/`. Verify:

- Extraction step short-circuits (FR16)
- Generated `.specswarm/*.md` are functionally identical to v6.4.0 output on the same fixture
- No extraction-related prompts surface to the user

### T1.C10 Commit Phase 1C

`git commit -m "feat(v7-1c): aggregation + interactive acceptance + Step 4/5/6 generation rewrite"`

## Phase 2 — Polish

### T2.1 Create lib/citation-verifier.sh `[P]`

Per [research.md §R4](research.md). Function: `ss_citation_verify <citation>` → exit 0 if resolvable. Permissive matching for line/section anchors.

### T2.2 Wire citation verification into Step 4.1 `[P]`

After aggregation, walk all accepted proposals; verify citations; downgrade unverifiable ones with a `# uncited — review required` comment in the aggregated file.

### T2.3 (Optional) Extract subagent prompts to template files `[P]`

If the inline prompts in init.md exceed ~150 lines each, extract to `plugins/ss/templates/agents/ss-{source-discoverer,tech-stack-extractor,quality-standards-extractor,constitution-extractor}.md.template`. Step 3.0/4.0 reads the template, substitutes interpolation vars. Skip if inline is fine.

### T2.4 Update CHANGELOG.md `[P]`

Add `## [7.0.0]` entry above v6.4.0. Sections: Added (spec corpus extraction, --full-scan, --include-user-memory, citation verification), Changed (Step 4.5 folded into Step 4.0), Removed (none breaking).

### T2.5 Update README.md `[P]`

Add a "Spec corpus extraction" section near the `/ss:init` description. Quickstart-style snippet.

### T2.6 Version bump `[P]`

Three files in sync:
1. `plugins/ss/.claude-plugin/plugin.json`: `6.4.0` → `7.0.0`
2. `plugins/specswarm/.claude-plugin/plugin.json`: `6.4.0` → `7.0.0`
3. `.claude-plugin/marketplace.json`: both `plugins[].version` entries → `7.0.0`

### T2.7 Generate EXPECTED-OUTPUT.md for rich-corpus fixture

Run v7 `/ss:init` against the fixture; capture the generated `.specswarm/*.md` contents and a transcript of the AskUserQuestion prompts; write to `plugins/ss/test-fixtures/rich-corpus/EXPECTED-OUTPUT.md` as the acceptance demo.

### T2.8 Commit Phase 2

`git commit -m "feat(v7-2): citation verification + docs + version bump for v7.0.0"`

## Validation gates

### T3.1 `claude plugin validate plugins/ss/`

Exit 0 required.

### T3.2 `claude plugin validate plugins/specswarm/`

Exit 0 required (stub plugin still validates).

### T3.3 Thin-fixture parity check

Confirm thin fixture's output is functionally identical to v6.4.0 baseline. Time delta ≤ 30s (SC4).

### T3.4 Sufficiency check passthrough

All four `ss_check_*_sufficient` pass on the generated rich-corpus output.

### T3.5 Constitutional-hooks end-to-end

`generate_constitutional_hooks .specswarm/constitution.md` emits hooks under `.specswarm/hooks/generated/` for each `rule_block`-bearing principle.

### T3.6 Open PR

`gh pr create --base main` with the v7.0.0 changeset. PR body links to spec.md / plan.md / quickstart.md. Note in PR description: **do not merge until Marty validates end-to-end against customcult-v3**.
