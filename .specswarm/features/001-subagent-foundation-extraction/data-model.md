# Data Model: Subagent-Driven Foundation File Generation

This feature has no database. The "data model" is a set of flat-file formats produced and consumed across the `/ss:init` flow.

## Files written/read

| File | Producer | Consumer | Lifecycle |
|------|----------|----------|-----------|
| `.specswarm/.discovery.tmp` | Step 3.0 discovery subagent | Step 3.5 references, Step 4.0 extractors, Step 6.5 conventions | Created at /ss:init start; removed by Step 7 cleanup |
| `.specswarm/.proposals.tech-stack.tmp` | tech-stack-extractor | Step 4.1 aggregator | Same |
| `.specswarm/.proposals.quality-standards.tmp` | quality-standards-extractor | Step 4.1 aggregator | Same |
| `.specswarm/.proposals.constitution.tmp` | constitution-extractor | Step 4.1 aggregator | Same |
| `.specswarm/.proposals.aggregated.tmp` | Step 4.1 aggregator | Step 4.2 acceptance UI, Step 4/5/6 generation | Same |
| `.specswarm/.acceptance-log.tmp` | Step 4.2 acceptance UI | Step 4/5/6 generation, audit_log dispatch | Same |

All tmp files live under `.specswarm/`, are prefixed `.` (hidden), and are removed on success by Step 7. On failure they remain for debugging.

## Format 1: Discovery output (`.discovery.tmp`)

Newline-delimited records. Each record is a TSV row with a leading category tag:

```
<category>\t<path>\t<size-bytes>\t<one-sentence-summary-or-empty>
```

Categories: `spec-doc`, `documentation`, `config`, `memory`, `reference-codebase`, `source-code`, `noise`.

Spec-doc records carry a non-empty summary (one sentence, no embedded tabs/newlines). All other categories may have empty summaries.

A trailing `noise-rollup` record summarizes aggregated noise:
```
noise-rollup\t\t<total-files>\t<dominant-extensions-and-counts>
```

Example:
```
spec-doc	docs/STRATEGY.md	28341	Framework decisions, decision log, tech-stack rationale
spec-doc	docs/RULES.md	12055	Project-enforceable rules in must-NEVER / always form
documentation	README.md	4221	
config	package.json	2117	
memory	~/.claude/.../memory/feedback_no_console_log.md	482	
source-code	src/app/page.tsx	1820	
noise-rollup		1247	tsx:411 ts:298 svg:188 png:127 lockfile:11
```

Total record count is capped at 200 plus the noise-rollup row.

## Format 2: Proposal record (in `.proposals.<destination>.tmp` and `.proposals.aggregated.tmp`)

Pipe-delimited, one record per line OR one record across multiple lines when any field uses a `<<<BLOCK ... BLOCK` marker.

### Field order

```
destination|key|value|confidence|citation|rationale
```

Plus, for `destination=constitution` records only, two additional trailing fields:

```
destination|key|value|confidence|citation|rationale|severity|rule_block
```

`severity` is `warn` or `block`. `rule_block` is empty OR uses the `<<<BLOCK ... BLOCK` form because it spans multiple lines.

### Multi-line / pipe-containing values

When `value` or `rule_block` contains a newline, a literal `|`, or the markers themselves, the field is wrapped:

```
<<<BLOCK
arbitrary content
including | newlines | and
>>>-style sequences are fine
BLOCK
```

The `BLOCK` closer sits alone on its line. After the closer, parsing resumes mid-record: the next character is the field delimiter `|` followed by the next field.

Example single-line:
```
tech-stack|framework|React Router|high|docs/STRATEGY.md:42|Decided 2026-03-01 per decision log
```

Example multi-line with block (constitution principle with rule_block):
```
constitution|P1.no-pii-in-logs|<<<BLOCK
### P1. No PII in logs

PII (email addresses, full names, payment details) MUST NOT appear in
application log output, including stack traces and structured fields.

**Why:** GDPR Art. 5(1)(c) data minimization; redaction is hard to retrofit.
BLOCK
|high|docs/RULES.md:§no-pii-in-logs|GDPR-derived rule|block|<<<BLOCK
<!-- specswarm-rule: no-pattern -->
<!-- path-glob: src/**/*.ts -->
<!-- bad-pattern: log\.(info|warn|error)\(.*\b(email|fullName|cardNumber)\b -->
<!-- summary: PII fields must not appear in log payloads -->
<!-- severity: block -->
BLOCK
```

### Allowed keys per destination

Extractors are not strictly schema-locked, but the canonical keys per destination are:

#### `destination=tech-stack`
- `framework`, `framework_version`
- `language`, `language_version`, `language_strict_flags`
- `build_tool`, `build_tool_version`
- `state_mgmt`
- `styling`
- `unit_test`, `integration_test`, `e2e_test`
- `approved_lib.<n>` — positional list (n=1..k)
- `prohibited.<n>` — positional list
- `open_decision.<n>` — items tagged `[OPEN]` with phase deadlines

#### `destination=quality-standards`
- `coverage_threshold`
- `perf_budget.<page-or-asset>` — keyed by what's budgeted (e.g. `perf_budget.lcp`)
- `browser_support_floor`
- `a11y_wcag_level`, `a11y_axe_required`, `a11y_screen_reader_gate`, `a11y_contrast`, `a11y_focus_visible`, `a11y_touch_targets`, `a11y_reduced_motion`
- `error_handling_pattern`
- `email_deliverability_target`
- `audit_required.<action>` — positional list of required-audited actions
- `build_guardrail.<n>` — TS strict flags, ESLint rules, migration linting
- `pre_merge_check.<n>` — positional checklist items

#### `destination=constitution`
- `P<n>.<short-name>` — principle key (n starts at 1). The `value` field carries the full principle body; the `rule_block` field carries the optional structured comment.

#### `destination=references`
- The references extractor is not part of v7. Step 3.5 continues to handle references discovery; v7's contribution to references is consuming the discovery output for better candidate filtering. So the `references` destination is not used in proposals; this slot is reserved for a future v7.x.

### Confidence

- `high`: explicit + version + `[DECIDED]` marker or equivalent
- `medium`: explicit but no decision marker
- `low`: inferred from indirect evidence (a `dependencies` entry without prose; a single mention in a non-canonical file)

### Citation

`<repo-relative-path>` or `<repo-relative-path>:<anchor>`. Anchor formats: `<line>`, `<line-start>-<line-end>`, `§<section-slug>`, `<line>:§<section-slug>`. See research.md R4.

### Rationale

Free text, must fit on one logical line (no newline) UNLESS wrapped in a `<<<BLOCK ... BLOCK`. Typical length ≤ 120 chars. Used as the comment that lands beside the value in the generated foundation file when the user accepts the proposal.

## Format 3: Aggregated set (`.proposals.aggregated.tmp`)

Same record format as proposals, with three additions:

1. **`conflict-group:` prefix lines** group records that fight over the same `destination|key`:
   ```
   conflict-group: tech-stack|framework
   tech-stack|framework|React Router|high|docs/STRATEGY.md:42|Decided 2026-03-01
   tech-stack|framework|Next.js|low|CONTRIBUTING.md:14|Mentioned in passing
   ```
2. **Records are pre-sorted** within each destination block: high before medium before low; within a confidence tier, sorted by citation authority (Strategy docs > memory > general docs > config files).
3. **Annotation comments** beginning with `# ` may interleave (skipped by parsers, useful for debug). Example: `# 17 high-confidence proposals merged from 2 sources for tech-stack`.

## Format 4: Acceptance log (`.acceptance-log.tmp`)

Append-only, one decision per line. TSV:

```
<timestamp-iso8601>\t<destination>\t<key>\t<decision>\t<accepted-value-or-empty>\t<source-citation-or-empty>
```

`decision` ∈ `accept`, `accept-batch`, `reject`, `defer`, `custom`, `drift-use-corpus`, `drift-keep-declared`.

This log is also fed into `audit_log` so that future `/ss:audit` can trace foundation-file content back to its corpus origin. The tmp file is removed by Step 7; the audit log entries persist.

## Schema validation

`extraction-schema.sh` provides:

- `ss_proposal_validate_record <line>` → exit 0 if parseable, 1 + reason on stderr
- `ss_proposal_read_each <file> <callback>` → invoke `<callback>` once per record with parsed fields as positional args; transparently joins multi-line block-wrapped values
- `ss_proposal_emit <destination> <key> <value> <confidence> <citation> <rationale> [<severity> <rule_block>]` → write a well-formed record (wraps in BLOCK form automatically if any field needs it)

Extractors do NOT call `ss_proposal_emit` (they're LLM-level subagents, not shell). They emit text that conforms to the format because their prompt teaches them the format. The aggregator validates incoming records and rejects malformed ones with a non-fatal warning in the audit log.
