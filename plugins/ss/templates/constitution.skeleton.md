# Constitution

> Project governance and coding principles. Each `## ` heading is a principle.
> Add an HTML-comment `<!-- specswarm-rule: ... -->` block beneath any principle
> you want SpecSwarm to enforce mechanically via PostToolUse hooks.
>
> Three rule types are supported (full reference: `plugins/ss/lib/constitution-parser.sh`):
>
> - **no-pattern** — pattern must NOT appear in files matching the glob
> - **required-pattern** — pattern MUST appear in files matching the glob
> - **required-pair** — when trigger-pattern appears, pair-pattern must also appear in the same file
>
> Each rule block accepts an optional `severity: warn | block` field (default `warn`).
> `block` returns `{decision: "block", reason: ...}` from the PostToolUse hook;
> `warn` returns `{decision: "approve", systemMessage: ...}`.

---

## Example principle — delete or replace with your own

We require TypeScript for all new source code.

<!-- specswarm-rule: no-pattern -->
<!-- path-glob: src/**/*.js -->
<!-- bad-pattern: . -->
<!-- summary: New code must be TypeScript, not JavaScript -->
<!-- severity: warn -->

---

## Example principle 2 — required-pattern

All route handlers must include the requireAuth middleware.

<!-- specswarm-rule: required-pair -->
<!-- path-glob: routes/**/*.ts -->
<!-- trigger-pattern: app\.(get|post|put|delete)\( -->
<!-- pair-pattern: requireAuth -->
<!-- summary: Route handlers must use requireAuth middleware -->
<!-- severity: block -->

---

## Example principle 3 — required-pattern

Migration files must use the shared migrationHelper utility.

<!-- specswarm-rule: required-pattern -->
<!-- path-glob: migrations/**/*.ts -->
<!-- required-pattern: import .* migrationHelper -->
<!-- summary: Migration files must use migrationHelper -->
<!-- severity: warn -->

---

<!-- ss:user-additions -->
<!-- Add your principles below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->
