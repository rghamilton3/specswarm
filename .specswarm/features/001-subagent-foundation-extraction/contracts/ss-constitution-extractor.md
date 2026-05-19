# Contract: ss-constitution-extractor

## Role

Read project sources and propose content for `.specswarm/constitution.md`. One of three extractors dispatched in parallel from Step 4.0. Absorbs the v6.2.0 memory-driven principle import (Step 4.5) entirely — there is no longer a separate principles pass.

## Dispatch

Concurrent with tech-stack and quality-standards extractors. Single assistant message in Step 4.0.

## Inputs

- Filtered reading list:
  - All `spec-doc` records whose summary suggests rules/decisions/principles (heuristics: contain `rule`, `principle`, `must`, `forbidden`, `policy`, `constitution`)
  - **ALL** memory `feedback_*.md` files (high yield by convention)
  - Memory `project_*.md` files **only** when their content shows enforceable rule shape (the subagent must read the file briefly to decide). Skip pure-context project files like activity logs, current-state trackers, contact info.
- Excluded: `user_*.md` (unless `--include-user-memory`)

## Process

1. For each candidate file, identify imperative-language rules: `must NEVER`, `always`, `required to`, `forbidden`, `only`, `every X must Y`, `we do not …`, `the system rejects …`.
2. For each candidate rule:
   - Draft a declarative principle (see Principle Format below)
   - Propose a constitutional-hook `rule_block` ONLY if mechanically enforceable (use one of the three v6.3.0 formats; let the actual file content inform regex/glob — don't invent)
   - Tag severity (`warn` for routine rules; `block` for compliance, trade-secret, security)
   - Cite source: file + section + 1-line quote
3. Emit pipe-delimited records to `.specswarm/.proposals.constitution.tmp`.
4. **Skip vague rules** — anything resembling "write good code", "be consistent", "be careful". The bar is: does the rule name a specific pattern, file glob, or data invariant?

## Principle format

The `value` field carries the full principle body, wrapped in `<<<BLOCK ... BLOCK`:

```
### P<n>. <Short name>

<Body — declarative form, 1-3 sentences>

**Why:** <Rationale extracted from the source>
```

`P<n>` numbering is the extractor's responsibility — assign sequentially starting at 1.

## Rule block formats (from constitution-parser.sh)

When the proposal includes a rule_block, use one of:

```
<!-- specswarm-rule: no-pattern -->
<!-- path-glob: <glob> -->
<!-- bad-pattern: <regex> -->
<!-- summary: <text> -->
<!-- severity: warn|block -->
```

```
<!-- specswarm-rule: required-pattern -->
<!-- path-glob: <glob> -->
<!-- required-pattern: <regex> -->
<!-- summary: <text> -->
<!-- severity: warn|block -->
```

```
<!-- specswarm-rule: required-pair -->
<!-- path-glob: <glob> -->
<!-- trigger-pattern: <regex> -->
<!-- pair-pattern: <regex> -->
<!-- summary: <text> -->
<!-- severity: warn|block -->
```

If the rule is real but not mechanically enforceable (e.g. "design decisions belong in the decision log"), emit the principle WITHOUT a rule_block — leave the `rule_block` field empty.

## Output format

See [data-model.md §Format 2](../data-model.md). Constitution records have two extra trailing fields:

```
constitution|<key>|<value>|<confidence>|<citation>|<rationale>|<severity>|<rule_block>
```

`<key>` is `P<n>.<short-name>` (kebab-case slug, e.g. `P3.no-pii-in-logs`).
`<value>` is the principle body wrapped in `<<<BLOCK ... BLOCK`.
`<rule_block>` is empty OR wrapped in `<<<BLOCK ... BLOCK` (multi-line by definition).
`<severity>` is `warn` or `block`.

## Constraints

- Cap 15 principles
- Report under 1500 lines back to parent

## Prompt body (verbatim)

> You are SpecSwarm's constitution extractor. Propose content for `.specswarm/constitution.md`.
>
> Read in full (or via grep where files exceed 2000 lines):
> <INTERPOLATED_READING_LIST>
>
> Identify project-specific ENFORCEABLE rules. Look for imperative language:
> - "must NEVER"
> - "always"
> - "required to"
> - "forbidden"
> - "only"
> - "every X must Y"
> - "we do not …"
> - "the system rejects …"
>
> For each candidate principle:
>
> 1. Draft a declarative principle body in this exact shape:
>
>    ```
>    ### P<n>. <Short name>
>
>    <Body — declarative form, 1-3 sentences>
>
>    **Why:** <Rationale from source>
>    ```
>
>    Number P1, P2, … sequentially.
>
> 2. Propose a constitutional-hook rule block ONLY if mechanically enforceable. Use one of three formats:
>
>    ```
>    <!-- specswarm-rule: no-pattern -->
>    <!-- path-glob: <glob> -->
>    <!-- bad-pattern: <regex> -->
>    <!-- summary: <text> -->
>    <!-- severity: warn|block -->
>    ```
>
>    ```
>    <!-- specswarm-rule: required-pattern -->
>    <!-- path-glob: <glob> -->
>    <!-- required-pattern: <regex> -->
>    <!-- summary: <text> -->
>    <!-- severity: warn|block -->
>    ```
>
>    ```
>    <!-- specswarm-rule: required-pair -->
>    <!-- path-glob: <glob> -->
>    <!-- trigger-pattern: <regex> -->
>    <!-- pair-pattern: <regex> -->
>    <!-- summary: <text> -->
>    <!-- severity: warn|block -->
>    ```
>
>    Use the source file's actual content to inform the regex/glob — do not invent values. If the rule is real but not mechanically enforceable, omit the rule_block (emit empty value for that field).
>
> 3. Tag severity:
>    - `block` for non-recoverable rules (compliance, trade-secret, security)
>    - `warn` for everything else
>
> 4. Cite source: `<file>:<§section-or-line>` and a 1-line quote in the rationale field.
>
> Output your proposals to `.specswarm/.proposals.constitution.tmp` as pipe-delimited records WITH two trailing fields:
>
> ```
> constitution|P<n>.<slug>|<<<BLOCK
> ### P<n>. <Short name>
>
> <Body>
>
> **Why:** <Rationale>
> BLOCK
> |<confidence>|<citation>|<rationale>|<severity>|<<<BLOCK
> <!-- specswarm-rule: ... -->
> ...
> BLOCK
> ```
>
> Or with empty rule_block:
>
> ```
> constitution|P<n>.<slug>|<<<BLOCK
> ...principle body...
> BLOCK
> |<confidence>|<citation>|<rationale>|<severity>|
> ```
>
> Skip vague rules ("write good code", "be consistent"). Focus on rules naming specific patterns, file globs, or data invariants.
>
> Cap 15 principles. When done, return a brief acknowledgment: `Constitution: <N> principles (<RB> with rule blocks, <WB> warn / <BL> block).`

## Failure modes

- **Empty output**: parent falls back to today's interactive principle entry + memory-driven import for constitution only.
- **Rule block missing required fields**: aggregator's `principle_unhandled` flow (per constitution-parser.sh) catches it; principle still lands in the constitution but no hook generated.
- **Severity not `warn|block`**: aggregator coerces to `warn` silently (matches existing `constitution-parser.sh` behavior).
