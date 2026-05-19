# Contract: ss-quality-standards-extractor

## Role

Read project sources and propose content for `.specswarm/quality-standards.md`. One of three extractors dispatched in parallel from Step 4.0.

## Dispatch

Concurrent with the other two extractors. Single assistant message in Step 4.0.

## Inputs

- Filtered reading list:
  - `spec-doc` records flagged quality-related by their one-sentence summary (heuristics: contain `budget`, `performance`, `a11y`, `accessibility`, `quality`, `coverage`, `lint`, `ci`, `pre-merge`, `audit`)
  - Memory files matching `project_perf*`, `project_a11y*`, `project_quality*`, `project_*budget*`
  - All `spec-doc` records with `quality` or `budget` in their path
- Excluded: `user_*.md` (unless `--include-user-memory`)

## Process

Read each file on the reading list; identify the canonical sections listed under Output Keys; emit pipe-delimited records to `.specswarm/.proposals.quality-standards.tmp`.

## Output keys

- `coverage_threshold`
- `perf_budget.<page-or-asset-key>` (one record per budgeted item; key is the budget category — `lcp`, `tbt`, `cls`, `bundle`, `initial_load`, `chunk`, `page.<route>`, etc.)
- `browser_support_floor`
- `a11y_wcag_level`
- `a11y_axe_required`
- `a11y_screen_reader_gate`
- `a11y_contrast`
- `a11y_focus_visible`
- `a11y_touch_targets`
- `a11y_reduced_motion`
- `error_handling_pattern`
- `email_deliverability_target`
- `audit_required.<n>`
- `build_guardrail.<n>`
- `pre_merge_check.<n>`

## Confidence rules

Same as tech-stack-extractor:
- `high`: explicit + numeric/specific + decision marker
- `medium`: explicit but no decision marker
- `low`: inferred / soft-language ("we generally aim for")

## Constraints

- Cap 50 records
- Report under 600 lines back to parent

## Prompt body (verbatim)

> You are SpecSwarm's quality-standards extractor. Propose content for `.specswarm/quality-standards.md`.
>
> Read in full (or via grep where files exceed 2000 lines):
> <INTERPOLATED_READING_LIST>
>
> Identify:
> 1. Coverage thresholds (target %)
> 2. Performance budgets (per-page LCP/TBT/CLS, asset budgets, bundle limits)
> 3. Browser support floor
> 4. Accessibility (WCAG level, axe-core, screen reader gates, contrast, focus visible, touch targets, reduced-motion)
> 5. Error handling pattern (N-layer model, anti-patterns)
> 6. Email deliverability targets
> 7. Audit/logging required behaviors
> 8. Build-time guardrails (TS strict flags, ESLint rules, migration linting)
> 9. Pre-merge checklist items
>
> Output your proposals to `.specswarm/.proposals.quality-standards.tmp` as pipe-delimited records (same format and confidence rules as the tech-stack extractor):
>
> ```
> quality-standards|<key>|<value>|<confidence>|<citation>|<rationale>
> ```
>
> Where `<key>` is one of: `coverage_threshold`, `perf_budget.<category>`, `browser_support_floor`, `a11y_wcag_level`, `a11y_axe_required`, `a11y_screen_reader_gate`, `a11y_contrast`, `a11y_focus_visible`, `a11y_touch_targets`, `a11y_reduced_motion`, `error_handling_pattern`, `email_deliverability_target`, `audit_required.<n>`, `build_guardrail.<n>`, `pre_merge_check.<n>`.
>
> Wrap multi-line or pipe-containing values in `<<<BLOCK ... BLOCK`. The BLOCK closer sits alone on its line.
>
> Cap 50 records. Skip duplicates within your output (prefer highest confidence).
>
> When you've written the file, return a brief acknowledgment: `Quality-standards: <N> proposals (<H> high / <M> medium / <L> low).`

## Failure modes

Same as tech-stack-extractor: empty/truncated → fallback to interactive prompts for this destination only; malformed records logged and skipped; no spec input → may legitimately produce zero proposals.
