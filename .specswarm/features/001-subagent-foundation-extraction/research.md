# Research: Subagent-Driven Foundation File Generation

## R1. Parallel `Agent` dispatch (Spec A1)

**Question**: Does Claude Code execute multiple `Agent` tool calls concurrently when they appear in a single assistant message?

**Decision**: Design for parallel; verify empirically at the start of Phase 1B with a throwaway probe (two trivial `Agent` calls in one message, timed). If parallel works, proceed. If sequential, switch to sequential dispatch (still saves parent-context tokens, loses only wall-clock parallelism).

**Rationale**: Tool documentation states multiple tool calls in a single message run in parallel when there are no dependencies. The `Agent` tool is a regular tool from the harness's perspective; nothing in its documentation excludes it. The probe is cheap (sub-30s test).

**Alternatives considered**:
- Three sequential `Agent` calls — costs ~3x wall-clock for what could be one batch
- A single "do all three" subagent — defeats the context-isolation property (one subagent's context grows to hold all three extraction jobs)
- A background subagent + Monitor polling — adds plumbing; partial output handling already gives us fault tolerance without the polling complexity

**Phase 1B kickoff probe**: send a message with two `Agent` calls each instructed to wait briefly and report a timestamp. If both timestamps are within ~5s, parallel dispatch is confirmed.

## R2. Subagent timeout (Spec A4)

**Question**: Can the parent abort a subagent that exceeds a wall-clock budget?

**Decision**: No timeout enforcement. The `Agent` tool does not expose a kill or wall-clock cap. The parent waits until the subagent returns, then handles whatever it got (FR13 partial-output handling).

**Rationale**: This is a harness-level constraint, not a design choice. Aborting a stuck subagent would require harness-level support that doesn't exist. Resilience comes from the parent's tolerance for partial/empty output, not from preemption.

**User-facing implication**: Worst case, one stuck extractor delays `/ss:init` by minutes. Acceptable for a tool that runs once per project setup (or once per major corpus revision).

**Alternatives considered**:
- Background dispatch with Monitor + a poll/cancel — Monitor exists but would require driving lifecycle from the parent prompt, increasing complexity without a clear mitigation path for a stuck subagent
- Don't dispatch parallel — sequential surfaces stuckness slower (3x cumulative wait), same end state

## R3. Pipe-delimited multi-line value safety (Spec A5)

**Question**: Can the pipe character (`|`) appear in extracted values often enough to break the record format?

**Decision**: Default to pipe delimiter; wrap any multi-line or pipe-containing value in a `<<<BLOCK ... BLOCK` marker. The extractor prompt explicitly instructs subagents to use the block form for any value containing `|`, newlines, or `<<<`/`>>>`.

**Rationale**: Real-world tech-stack and quality-standards values rarely contain literal pipes (counter-examples: regex patterns like `(get|post|put|delete)` from constitutional rule blocks; bash command snippets). Those cases ARE the multi-line / structured-value case anyway, so the block-marker fallback covers them naturally.

**Record format**:
```
destination|key|value|confidence|citation|rationale
```

Multi-line / pipe-containing form:
```
destination|key|<<<BLOCK
multi-line content
can contain | freely
BLOCK
|confidence|citation|rationale
```

The `BLOCK` close marker sits alone on its line, followed by the remaining fields. `extraction-schema.sh` provides the parser.

**Alternatives considered**:
- JSON / JSON Lines — cleaner for nested data but introduces `jq` or fragile bash JSON parsing (brief forbids `jq`)
- Block-delimited proposals (every record fenced) — verbose for the common single-line case
- Tab-separated — TAB appears in code-block fixtures and is harder to type-check in extractor outputs

Pipe + block-marker fallback is the lightest design that handles all observed cases.

## R4. Citation anchor format

**Question**: How should citations identify a location within a file?

**Decision**: `<repo-relative-path>:<anchor>` where anchor is one of:
- `<line-number>` — a specific line (e.g. `docs/STRATEGY.md:42`)
- `<line-start>-<line-end>` — a span
- `§<section-anchor>` — a section heading, slug-style (e.g. `docs/STRATEGY.md:§framework-selection`)
- `<line>:§<section>` — combined (e.g. `docs/STRATEGY.md:42:§framework-selection`)

Plain path with no anchor is allowed for short files (e.g. `package.json`) where the whole file is the citation.

**Rationale**: Mirrors how humans cite — by line OR by section. Section anchors survive line-number drift better; line numbers are precise when the section is stable.

**Verifier behavior** (`citation-verifier.sh`):
- Path resolves → exit 0 if no anchor or anchor matches
- Line anchor → file has at least that many lines
- Section anchor → grep for `^##* .*<section-slug>` against the file
- Verifier is intentionally permissive — false positives on verification are worse than false negatives (a slightly-wrong line number that points to the right neighborhood is better than dropping a real citation)

## R5. Discovery scan boundaries

**Question**: What's the default scan footprint? When does the `--full-scan` flag fire?

**Decision**: Default roots:
- `docs/`, `specs/`, `documentation/`, `.specswarm/specs/` (recursive)
- Repo root, `*.md` and `*.mdx` only, depth 1
- Standard config files at repo root: `package.json`, `tsconfig.json`, `composer.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `Gemfile`, `Cargo.toml`, `vite.config.*`, `vitest.config.*`, `drizzle.config.*`, `playwright.config.*`
- Canonical Claude Code memory at `$HOME/.claude/projects/$(pwd | tr / -)/memory/`
- Sibling repos one level up via stem-filtered scan (existing Step 3.5 logic)

Default file cap: 200 classified entries; everything beyond aggregates into a `noise` rollup.

`--full-scan`: lifts the depth and root constraints (still respects `.gitignore` and the size cap). Use case: project with spec docs under non-standard paths.

**Rationale**: Empirical from rich-corpus precedents (customcult-v3) — spec docs live under `docs/`. Defaults trade a little recall for big bounds on context spend.

## R6. Memory file inclusion policy

**Question**: Which memory files do extractors read?

**Decision**:
- **Constitution extractor**: ALL `feedback_*.md` (rules-as-data, high yield) + `project_*.md` only when the body shows enforceable rule shape (imperative verbs, file globs, data invariants). Skip pure-context project files (activity logs, contact info, deadline trackers).
- **Tech-stack extractor**: `project_tech*.md`, `project_*stack*.md`, `project_*framework*.md`, `project_*decisions*.md`.
- **Quality-standards extractor**: `project_perf*.md`, `project_a11y*.md`, `project_quality*.md`, `project_*budget*.md`.
- **All extractors**: skip `user_*.md` by default (personal context); `--include-user-memory` flag opts in.

Each extractor performs its own filename matching against the discovery output, so the parent doesn't need a routing table.

**Rationale**: Aligns with the existing `feedback`/`project`/`reference`/`user` taxonomy in `references-loader.sh`. Naming conventions are already common in mature SpecSwarm projects.

## R7. Acceptance UX cap mechanics

**Question**: How does the ≤20 prompt cap (FR8) work in practice?

**Decision**:
- Each destination earns 1 batch-accept prompt for its high-confidence non-conflicting proposals → 4 prompts.
- Plus 1 prompt per conflict, allocated round-robin across destinations until ~10 prompts are consumed.
- Plus 1 prompt per low-confidence proposal, allocated round-robin until the remaining budget is exhausted (~6 prompts).
- Leftover low-confidence items get a TODO comment in the generated file, surfaced in Step 7's summary.

Pseudo-budget: 4 batch + 10 conflict + 6 low-conf = 20. Cap is a target, not a hard cutoff — implementation may emit 18 or 22, never aiming for 50.

**Rationale**: The cap exists to keep first-init painless. A maintainer running `/ss:init` once shouldn't sit through 80 prompts; review-everything-by-hand is a separate (future) flag.

## R8. Backward compatibility surface

**Question**: What must look identical to v6.4.0 for a thin project?

**Decision**: Bit-for-bit content equality is NOT required. Substantive equivalence is:
- Same set of foundation files generated
- Same arg-parsing behavior on `--reset` and `--minimal`
- Same reconciliation behavior when a previous run's files exist
- Same set of `ss_check_*_sufficient` passes after generation
- Same set of `generate_constitutional_hooks` outputs given a v6-shape constitution

Discovery subagent always runs (cheap on thin projects) — its output is the input to Step 3.5's references discovery and Step 6.5's conventions analysis, both of which already exist and just gain a better-classified input. The three extractors short-circuit when discovery finds no spec-docs and no relevant memory files; the parent skips Steps 4.0/4.1/4.2 entirely.

**Rationale**: Bit-for-bit parity would require generating identical timestamps and identical comment ordering, which adds maintenance burden for no user benefit. The user-observable behavior is what matters.
