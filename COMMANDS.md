# SpecSwarm Commands Reference

Complete documentation for all SpecSwarm commands: **10 visible** + **11 internal**.

## Command Overview

| Category | Commands | Count |
|----------|----------|-------|
| [Core Workflows](#core-workflows) | init, build, fix, modify, ship | 5 |
| [Distinct Workflows](#distinct-workflows) | release, upgrade, rollback, status, metrics | 5 |
| [Internal Commands](#internal-commands) | specify, clarify, plan, tasks, implement, validate, analyze-quality, bugfix, hotfix, complete, constitution | 11 |

---

## Core Workflows

These 5 commands handle the vast majority of daily development work. **Start here** if you're new to SpecSwarm.

### `/ss:init`

Initialize SpecSwarm in your project with interactive setup wizard.

**Usage:**
```bash
/ss:init
```

**What it does:**
- Creates `.specswarm/` directory structure
- Generates `tech-stack.md` with your technology choices
- Creates `quality-standards.md` with validation gates
- Sets up `constitution.md` for project governance
- Configures performance budgets
- *(v6.1.0)* Auto-discovers spec corpus, reference codebases, and memory dirs; writes `references.md` for `/ss:specify` and `/ss:clarify` to consult

**When to use:**
- First-time project setup
- Adding SpecSwarm to existing projects (especially those with existing PRDs / decision logs / legacy reference codebases)

---

### `/ss:build`

Complete workflow for building new features from natural language description.

**Usage:**
```bash
/ss:build "feature description"
```

**Natural Language:**
```
"Build user authentication with JWT"
"Create a payment processing system"
"Add dashboard analytics"
```

**What it does:**
1. Creates specification (spec.md)
2. Asks clarifying questions
3. Generates implementation plan (plan.md)
4. Breaks down into tasks (tasks.md)
5. Implements all tasks
6. Validates quality

**Flags:**
| Flag | Description |
|------|-------------|
| `--validate` | Run browser validation with Playwright after implementation |
| `--quality-gate N` | Set minimum quality score (default 80) |
| `--analyze` | Run cross-artifact consistency analysis after task generation |
| `--checklist` | Generate requirements validation checklist after specification |
| `--orchestrate` | Force multi-agent parallel execution |
| `--no-orchestrate` | Force sequential execution |
| `--background` | Run in background mode |

**When to use:**
- Building any new feature
- When you know what you want but not how to implement it
- Starting fresh feature development

**Related internal commands:** `specify`, `clarify`, `plan`, `tasks`, `implement`

---

### `/ss:fix`

Complete workflow for fixing bugs with regression testing.

**Usage:**
```bash
/ss:fix "bug description"
```

**Natural Language:**
```
"Fix the login button on mobile"
"There's a bug in the checkout process"
"Images don't load"
"Tailwind styles not showing up"
```

**What it does:**
1. Creates regression test
2. Analyzes root cause
3. Implements fix
4. Validates fix with tests
5. Auto-retries on failure (max 2 attempts)

**Flags:**
| Flag | Description |
|------|-------------|
| `--regression-test` | Create failing test first (TDD approach) |
| `--hotfix` | Use expedited hotfix workflow for production issues |
| `--max-retries N` | Maximum fix retry attempts (default 2) |
| `--coordinate` | Multi-bug orchestrated debugging with specialist agents |
| `--background` | Run in background mode |

**When to use:**
- Any bug or broken functionality
- Issues that need regression testing
- Problems that keep coming back

**Related internal commands:** `bugfix`, `hotfix`

---

### `/ss:modify`

Change existing feature behavior with impact analysis and backward compatibility assessment.

**Usage:**
```bash
/ss:modify "modification description"
```

**Natural Language:**
```
"Change authentication from session to JWT"
"Add pagination to user list API"
"Update search to use full-text search"
```

**What it does:**
1. Analyzes impact on existing code
2. Identifies breaking changes
3. Creates migration plan if needed
4. Updates specification and plan
5. Implements modifications
6. Validates against regression tests

**Flags:**
| Flag | Description |
|------|-------------|
| `--refactor` | Behavior-preserving quality improvement |
| `--deprecate` | Phased feature sunset with migration guidance |
| `--analyze-only` | Impact analysis without implementation |

**When to use:**
- Features that work but need to work differently
- Changing implementation approach
- Enhancing existing functionality
- NOT for bugs (use `/ss:fix`)
- For code quality improvements, use `--refactor` flag

**Examples:**
- Change data source from REST to GraphQL
- Switch caching strategy
- Update UI framework
- Modify business logic

---

### `/ss:ship`

Validate quality, merge to parent branch, and complete feature.

**Usage:**
```bash
/ss:ship
```

**Natural Language:**
```
"Ship this feature"  (requires confirmation)
"Deploy to production"  (requires confirmation)
"Merge to main"  (requires confirmation)
```

**What it does:**
1. Runs comprehensive quality analysis
2. Checks quality threshold (default 80%)
3. Shows merge plan with confirmation prompt
4. Merges to parent branch
5. Deletes feature branch

**Flags:**
| Flag | Description |
|------|-------------|
| `--force-quality N` | Override quality threshold |
| `--skip-tests` | Skip test validation (not recommended) |
| `--security-audit` | Comprehensive security scan before merge |

**DESTRUCTIVE OPERATION:**
- Always requires explicit "yes" confirmation
- Merges and deletes branches
- Cannot be easily undone

**When to use:**
- Feature is complete and tested
- Quality score meets threshold
- Ready to merge to main/production

**Related internal commands:** `complete`, `analyze-quality`

---

## Distinct Workflows

These 5 commands cover workflows that can't be expressed as flags on the core 5.

### `/ss:release`

Complete release workflow with versioning, changelog, and deployment.

**Usage:**
```bash
/ss:release [--skip-security]
```

**What it does:**
1. Runs quality validation
2. Executes security audit
3. Generates changelog
4. Bumps version
5. Creates git tag
6. Prepares deployment

**When to use:**
- Releasing new versions
- Production deployments
- Publishing packages

---

### `/ss:upgrade`

Systematic dependency/framework upgrade with compatibility analysis.

**Usage:**
```bash
/ss:upgrade "upgrade description"
```

**Natural Language:**
```
"Upgrade to React 19"
"Migrate from Redux to Zustand"
"Update to the latest PostgreSQL"
```

**What it does:**
1. Analyzes breaking changes
2. Creates upgrade plan
3. Updates dependencies
4. Migrates code patterns
5. Runs tests
6. Documents changes

**When to use:**
- Upgrading frameworks
- Updating dependencies
- Technology migrations
- Security patches

---

### `/ss:rollback`

Safe rollback to previous version with validation.

**Usage:**
```bash
/ss:rollback [--skip-confirm]
```

**What it does:**
1. Identifies previous version
2. Validates rollback safety
3. Reverts changes
4. Runs smoke tests
5. Verifies stability

**When to use:**
- Production issues
- Failed deployments
- Critical bugs in release
- Emergency recovery

Use `--skip-confirm` only in emergencies.

---

### `/ss:status`

Check background session progress. Required when using `--background` on build/fix/release.

**Usage:**
```bash
/ss:status
```

---

### `/ss:metrics`

Feature-level orchestration metrics and analytics from completed features.

**Usage:**
```bash
/ss:metrics [--feature=001-feature-name]
```

**Flags:**
| Flag | Description |
|------|-------------|
| `--export` | Export metrics to CSV |
| `--feature N` | Show details for feature N |
| `--sprint NAME` | Sprint aggregate view |

**What it shows:**
- Completion rates
- Test metrics
- Git history
- Quality scores
- Time tracking

**When to use:**
- Sprint retrospectives
- Team performance analysis
- Process improvement
- Workflow optimization

---

## Internal Commands

These commands are used internally by the core workflows. They're hidden from command listings but can be called directly for re-running individual steps.

### `/ss:specify`

Create detailed feature specification from natural language description.

**Usage:**
```bash
/ss:specify "Add user authentication with email/password"
```

**What it creates:**
```
.specswarm/features/001-user-authentication/spec.md
```

**Specification includes:**
- Feature objectives
- User stories
- Acceptance criteria
- Technical constraints
- Dependencies

**v6.1.0 — External Reference Corpus consultation:**

When `.specswarm/references.md` is populated, `/ss:specify` reads every declared spec corpus path and memory directory before generating spec content. Corpus content is treated as canonical — quoted/paraphrased with citations (`per <path> §X`) rather than fabricated. Generated spec.md gains a `## Sources` section and an optional `references_consulted:` YAML frontmatter field. When references.md is absent, behavior is identical to v6.0.0.

Called by: `build` (Step 2)

---

### `/ss:clarify`

Ask up to 5 targeted clarification questions and encode answers into specification.

**v6.1.0 — Corpus-aware question filtering:**

When references.md is populated, each candidate clarification question is cross-checked against the corpus before being asked. Categories: **CORPUS-RESOLVED** (drop and inject corpus answer with citation), **CORPUS-PARTIAL** (keep but pre-load corpus-suggested options), **CORPUS-SILENT** (proceed normally), **CORPUS-CONFLICT** (blocking question — spec disagrees with corpus). Final report surfaces "Auto-resolved from references (N)" sub-list. When references.md is absent, behavior is identical to v6.0.0.

Called by: `build` (Step 3)

---

### `/ss:plan`

Design implementation plan with tech stack validation.

Called by: `build` (Step 4)

---

### `/ss:tasks`

Generate actionable, dependency-ordered task breakdown.

Called by: `build` (Step 5)

---

### `/ss:implement`

Execute implementation plan with comprehensive quality validation.

Called by: `build` (Step 6)

---

### `/ss:validate`

Browser automation validation with Playwright flow testing.

Called by: `build --validate`

---

### `/ss:analyze-quality`

Comprehensive codebase quality analysis with prioritized recommendations.

**Quality Score (0-100):**
- Unit Tests (25 pts)
- Code Coverage (25 pts)
- Integration Tests (15 pts)
- Browser Tests (15 pts)
- Bundle Size (20 pts)

Called by: `build` (Step 8), `ship` (Step 2)

---

### `/ss:bugfix`

Regression-test-first bugfix workflow with auto-retry (max 2 attempts).

Called by: `fix` (internal)

---

### `/ss:hotfix`

Expedited emergency response workflow for critical production issues. Minimal ceremony, fast diagnosis, essential testing only.

Called by: `fix --hotfix` (internal)

---

### `/ss:complete`

Alias for `/ss:ship` - validates quality and merges feature.

Called by: `ship` (internal). Alias for ship.

---

### `/ss:constitution`

Create or update project constitution from interactive inputs. Generates `.specswarm/constitution.md` with project principles, code standards, decision-making guidelines, and technology preferences.

Called by: `init` (internal)

---

## Removed in v4.0.0

The following commands were removed and absorbed as flags:

| Removed Command | Now Use |
|----------------|---------|
| `/ss:orchestrate-feature` | `/ss:build --orchestrate` |
| `/ss:orchestrate` | `/ss:build --orchestrate` |
| `/ss:orchestrate-validate` | `/ss:validate` |
| `/ss:suggest` | Only 10 commands, no longer needed |
| `/ss:session` | `/ss:status` |
| `/ss:checkpoint` | `/ss:rollback` |
| `/ss:analyze` | `/ss:build --analyze` |
| `/ss:checklist` | `/ss:build --checklist` |
| `/ss:coordinate` | `/ss:fix --coordinate` |
| `/ss:impact` | `/ss:modify --analyze-only` |
| `/ss:security-audit` | `/ss:ship --security-audit` |
| `/ss:refactor` | `/ss:modify --refactor` |
| `/ss:deprecate` | `/ss:modify --deprecate` |
| `/ss:metrics-export` | `/ss:metrics --export` |

---

## Command Comparison

### Build vs Fix vs Modify

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/ss:build` | New features | Building something that doesn't exist |
| `/ss:fix` | Bug fixes | Something is broken or not working |
| `/ss:modify` | Change behavior | Working feature needs to work differently |

---

## Workflow Patterns

### Standard Feature Development

```bash
/ss:build "feature description"
# Or manually:
/ss:specify -> /ss:clarify -> /ss:plan ->
/ss:tasks -> /ss:implement -> /ss:ship
```

### Bug Fixing

```bash
/ss:fix "bug description"
# Or for critical issues:
/ss:fix --hotfix "emergency description"
```

### Changing Existing Features

```bash
/ss:modify "change description"
```

### Technology Upgrades

```bash
/ss:upgrade "upgrade description"
```

### Pre-Release Checklist

```bash
/ss:analyze-quality
/ss:ship --security-audit
/ss:release
```

---

## Tips & Best Practices

1. **Use `/ss:init` first** - Sets up proper foundation
2. **Define tech-stack.md early** - Prevents technology drift
3. **Run `/ss:analyze-quality` before shipping** - Catch issues early
4. **Enable quality gates** - Maintain >80% scores
5. **Use `--background` for long builds** - Check progress with `/ss:status`
6. **Use `--orchestrate` for complex features** - Parallel execution speeds up builds
7. **Call internal commands directly** - Re-run individual steps without restarting the whole workflow

---

**See also:**
- [README.md](./README.md) - Quick start and overview
- [docs/SETUP.md](./docs/SETUP.md) - Technical setup
- [docs/FEATURES.md](./docs/FEATURES.md) - Feature deep-dive

---

**SpecSwarm v6.0.0** - Complete software development toolkit
