# CLAUDE.md — SpecSwarm

## Overview

SpecSwarm is a Claude Code plugin providing spec-driven development workflows: Build, Modify, Fix, Ship. As of v6.0.0, all functionality lives in the `ss` plugin and is invoked via `/ss:*` commands (13 visible + 11 internal/hidden = 24 total — v7.1.0 `/ss:preflight`, v7.2.0 `/ss:notify`, v7.3.0 `/ss:intervention`). Includes 10 natural-language skills, 2 multi-agent orchestration agents, and the `.specswarm/` per-project state directory (directory name preserves the SpecSwarm brand).

The legacy `specswarm` plugin remains as a deprecation stub (no commands/skills/hooks) so users who installed it see a clear migration message. Slated for full removal in v7.0.0.

## Development

### Plugin Validation (required before commits)

```bash
claude plugin validate plugins/ss/
claude plugin validate plugins/specswarm/   # deprecation stub
```

Run this after any change to command/skill/agent frontmatter or plugin.json. It catches YAML typos that would silently fail at runtime.

### Version Bumping

Three files must be bumped in sync:
1. `plugins/ss/.claude-plugin/plugin.json` — `version`
2. `plugins/specswarm/.claude-plugin/plugin.json` — `version` (kept in sync even though it's a stub)
3. `.claude-plugin/marketplace.json` — both `plugins[].version` entries

### Testing After Changes

1. Restart Claude Code (skill prompts are cached per session)
2. Run `/skills` to verify all 10 `ss-*` skills appear
3. Test a low-effort command (`/ss:status`) vs high-effort (`/ss:build`)

## Project Structure

```
plugins/ss/
├── commands/        # 24 slash commands (13 visible + 11 internal/hidden)
│                    # v7.1.0: /ss:preflight   v7.2.0: /ss:notify   v7.3.0: /ss:intervention
├── skills/          # 10 ss-* skills (ss-build, ss-fix, ss-init, ss-metrics, ss-modify, ss-release, ss-rollback, ss-ship, ss-status, ss-upgrade)
├── agents/          # 2 agents (orchestrator, task-router)
├── hooks/           # SessionStart orientation, Setup auto-init, PostToolUse (quality + constitution dispatcher), Stop loop control
├── lib/             # Shared shell helpers (audit-logger, agent-generator, constitution-parser, orchestrator-utils, …)
│   ├── notify.sh        # v7.2.0: ss_notify with notifier-plugin → notify-send → osascript → bell fallbacks
│   ├── intervention.sh  # v7.3.0: ss_intervention_* helpers for capture/list/index
│   └── preflight/       # v7.1.0: deterministic checks (run.sh + checks/*.sh + package-manager-detector.sh)
├── rules/           # Project-level rule references (specswarm-active-build, specswarm-feature-branch)
├── templates/       # Spec/plan/task templates, agent template, constitutional-hook templates
│                    # v7.3.0 adds intervention.template.md
└── .claude-plugin/  # plugin.json (name: "ss", version: "7.3.0")

plugins/specswarm/
└── .claude-plugin/
    └── plugin.json  # DEPRECATION STUB — points users to ss@specswarm-marketplace
```

## Recommended Project-Level Rules

When using SpecSwarm in a project, consider adding these rules to `.claude/rules/`:

**`.claude/rules/specswarm-active-build.md`** (glob: `.specswarm/build-loop.state`):
- Check build state before starting new builds
- Don't create new feature branches during active builds

**`.claude/rules/specswarm-feature-branch.md`** (glob: `.specswarm/features/**`):
- Reference spec.md and plan.md when editing feature files
- Follow tasks.md task breakdown, mark tasks complete when done

(The rule template files now live in `plugins/ss/rules/` and can be copied into a user repo's `.claude/rules/` to enable.)
