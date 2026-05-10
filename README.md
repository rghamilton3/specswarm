# SpecSwarm v6.3.0

Spec-driven development for Claude Code. Build → Fix → Modify → Ship, with quality gates, multi-agent orchestration, and version-controlled specs.

---

## Install

```bash
# 1. Add the marketplace
/plugin marketplace add MartyBonacci/specswarm

# 2. Install SpecSwarm
/plugin install ss@specswarm-marketplace
```

Restart Claude Code to activate the plugin. *(Upgrading from v5.x? See [Migrating from v5.x](#migrating-from-v5x) at the bottom.)*

---

## The 5 commands

| Command      | What it does                                                       |
| ------------ | ------------------------------------------------------------------ |
| `/ss:init`   | Set up or refresh project knowledge: tech stack, constitution, quality gates |
| `/ss:build`  | Spec → plan → tasks → implement → quality score                    |
| `/ss:fix`    | Test-driven bug fix with auto-retry and silent-failure audit       |
| `/ss:modify` | Behavior change with impact analysis and backward-compat plan      |
| `/ss:ship`   | Multi-agent review + quality gate + merge to parent branch         |

---

## How to use it

1. Write a clear spec of the feature, sprint, or project that you want.
2. Run `/ss:init` in your project.
3. Run `/ss:build "<your feature description referencing your spec document>"`.
4. Use `/ss:fix "<bug>"` for anything broken, or `/ss:modify "<change>"` for things that work but aren't right. Repeat as needed.
5. Run `/ss:ship` when everything's good.

That's the loop.

*Re-run `/ss:init` any time the project's tech stack, conventions, or constitution changes — it refreshes SpecSwarm's knowledge of the project.*

---

## Example: a useful `/ss:build` prompt

Most of SpecSwarm's value comes from a clear spec document and a prompt that points to it. Keep the spec in your repo (e.g., `docs/specs/...`); the prompt itself stays short and points SpecSwarm at the spec, optionally with scope or exclusions to keep this build focused.

```
/ss:build "Implement the email + password authentication feature
described in docs/specs/auth-v1.md.

Out of scope for this build:
- OAuth and social sign-in
- Password reset flow
- Multi-factor authentication"
```

The clearer the spec document, the less back-and-forth during clarification.

**v6.1.0 makes this even better.** If your project has existing PRDs, design docs, decision logs, or a legacy/prototype reference codebase, declare them in `.specswarm/references.md` (auto-populated by `/ss:init`) and SpecSwarm will read them automatically during `/ss:specify` and `/ss:clarify` — quoting from corpus content with citations instead of fabricating, and skipping clarification questions whose answers are already locked in.

**v6.2.0 closes the loop on Claude Code memory.** If your project has memory directories declared in `references.md`, `/ss:init` now scans your `feedback_*.md` files for imperative rules ("X must NEVER appear in Y") and proposes constitution principles in the mechanical hook format. You wrote the rule once in memory; SpecSwarm proposes the enforcement; you accept or reject each proposal. Accepted principles get PostToolUse hooks generated automatically.

**v6.3.0 gives constitutional principles teeth.** Each rule block now accepts an optional `severity: warn | block` field (default warn). When a `severity: block` rule fires — say, a trade-secret import slipping into the frontend bundle — the PostToolUse hook returns `decision: block` and Claude is told to revert/fix rather than just being warned. v6.3.0 also fixes a pre-existing path-glob bug that had been silently preventing warn hooks from firing in production. See [CHANGELOG.md](./CHANGELOG.md) for details.

---

## Inside the 5 commands

A lot happens automatically inside each command. You don't invoke these phases directly — they run as the command needs them. The list below is descriptive, not a control surface; trust the system to sequence them correctly.

### Inside `/ss:init`

1. **Tech stack detection** — parses package.json, requirements.txt, go.mod, etc.
2. **Constitution creation** — captures project principles and non-negotiable rules
3. **Tech stack documentation** — locks approved technologies into `.specswarm/tech-stack.md` to prevent drift across builds
4. **Quality standards** — sets coverage, score, and performance gates
5. **Convention analysis** — extracts coding patterns from existing code
6. **MCP discovery & registration** — adds Context7, Playwright, Postgres, etc., based on detected stack
7. **Project subagent seeding** — generates project-specific implementer agents matched to your stack
8. **Constitutional hooks** — turns mechanically-checkable principles into PostToolUse hooks; *(v6.3.0)* each principle can declare `severity: warn` or `severity: block` — warn surfaces a system message, block returns `decision: block` so Claude reverts/fixes
9. **References discovery** *(v6.1.0)* — auto-discovers spec corpus markdown docs, sibling reference codebases (stem-similarity filter), and Claude Code memory directories; interactive picker writes `.specswarm/references.md`
10. **Memory-driven principle import** *(v6.2.0, severity-aware in v6.3.0)* — scans declared memory directories for `feedback_*.md` rules, drafts constitution principles in hook-enforceable format, asks user to accept/reject each; gravity signals in the source memory (`trade secret`, `compliance`, `must NEVER`, etc.) propose `severity: block` automatically

### Inside `/ss:build`

1. **Feature branch creation** — branches from your current branch
2. **Specification generation** — turns your prompt into a structured, version-controlled spec; *(v6.1.0)* when `.specswarm/references.md` is populated, reads spec corpus + memory dirs and extracts canonical content with citations instead of fabricating
3. **Clarification** — asks targeted questions on ambiguous areas (skipped in `--quick` mode); *(v6.1.0)* skips questions auto-resolved from corpus and surfaces `CORPUS-CONFLICT` markers when feature description disagrees with corpus
4. **Implementation plan** — architecture, file layout, data flow, technology choices
5. **Task breakdown** — dependency-ordered tasks with parallel-safe markers
6. **Project subagent refresh** — adds agents for any new recurring task types in this build
7. **Orchestration analysis** — detects parallelizable task streams and dispatches multiple agents when safe
8. **Implementation** — executes tasks sequentially or in parallel as appropriate
9. **Per-task verification** — a verifier subagent confirms each task's acceptance criteria before it's marked complete
10. **Quality analysis** — proportional 0-100 scoring across unit tests, coverage, integration tests, and browser tests

### Inside `/ss:fix`

1. **Regression test creation** — captures the bug as a failing test
2. **Root-cause analysis** — investigates the cause, with multi-bug coordination if requested
3. **Fix implementation** — applies the targeted change
4. **Test verification** — runs the full test suite
5. **Silent-failure audit** — scans the diff for swallowed errors, empty catches, and masking fallbacks
6. **Auto-retry** — retries with additional context if tests still fail (up to retry limit)

### Inside `/ss:modify`

1. **Context discovery** — locates the feature's existing spec, plan, and dependents
2. **Impact analysis** — finds every file and feature affected by the change
3. **Change categorization** — breaking, backward-compatible, or phased deprecation
4. **Migration planning** — designs an optional compatibility layer
5. **Spec update** — rewrites the spec to reflect the new intended behavior so it stays canonical
6. **Phased task generation** — validation → compat layer → implementation → testing → migration
7. **Implementation** — executes the modification
8. **Regression validation** — confirms existing tests still pass

### Inside `/ss:ship`

1. **Security audit** *(optional with `--security-audit`)* — dependency CVEs, hardcoded secrets, OWASP pattern scan
2. **Quality analysis** — proportional 0-100 scoring across all test types
3. **Multi-agent review** — parallel dispatch of code reviewer, silent-failure hunter, type-design analyzer, and comment analyzer
4. **Quality threshold gate** — configurable, default 80/100
5. **Merge to parent branch** — clean fast-forward when possible
6. **Feature branch cleanup** — deletes the merged branch

---

## Going deeper

- **[COMMANDS.md](./COMMANDS.md)** — every command, every flag, every internal detail
- **[docs/CHEATSHEET.md](./docs/CHEATSHEET.md)** — fast reference card
- **[docs/WORKFLOW.md](./docs/WORKFLOW.md)** — extended walkthroughs
- **[docs/FEATURES.md](./docs/FEATURES.md)** — what makes SpecSwarm different
- **[docs/SETUP.md](./docs/SETUP.md)** — detailed setup guide
- **[CHANGELOG.md](./CHANGELOG.md)** — version history

---

## Migrating from v5.x

If you have the old `specswarm` plugin installed, install the canonical `ss` plugin first, then uninstall the old one:

```bash
/plugin install ss@specswarm-marketplace
/plugin uninstall specswarm
```

All commands have moved from `/specswarm:*` to `/ss:*`. Skill IDs renamed from `specswarm-*` to `ss-*`. The `.specswarm/` per-project state directory and the SpecSwarm name are unchanged — only the command prefix moved.

The deprecated `specswarm` plugin still appears in the marketplace as a stub through v6.x and will be removed entirely in v7.0.0.
