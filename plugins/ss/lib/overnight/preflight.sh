#!/bin/bash
# SpecSwarm Overnight Preflight (v7.10.0)
#
# Validates that a feature is READY for autonomous overnight execution. This is
# stricter than /ss:preflight (v7.1.0) — autonomous mode has zero tolerance for
# missing artifacts or unanswered decisions.
#
# Checks (project-agnostic):
#   1. Feature dir resolves
#   2. spec.md exists and non-empty
#   3. plan.md exists and non-empty
#   4. tasks.md exists with at least one unchecked task (otherwise nothing to do)
#   5. decision-sheet.md exists with status: locked (otherwise asking would happen)
#   6. Git working tree is clean OR explicitly allowed via --allow-dirty
#   7. Feature branch resolves to an NNN-slug branch
#   8. claude CLI is in PATH (else --exec mode is impossible)
#
# Public API:
#   ss_overnight_preflight <feature_dir> [allow_dirty=false]
#     Echoes a human-readable report.
#     Returns 0 if PASS, 1 if BLOCKED.

set -e

PLUGIN_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

ss_overnight_preflight() {
  local feature_dir="$1"
  local allow_dirty="${2:-false}"

  local errors=0
  local warnings=0
  local repo_root
  repo_root=$(git -C "$feature_dir" rev-parse --show-toplevel 2>/dev/null \
    || dirname "$(dirname "$feature_dir")")

  echo "Overnight preflight for: $(basename "$feature_dir")"
  echo "─────────────────────────────────────────────────────"

  # 1. Feature dir
  if [ ! -d "$feature_dir" ]; then
    echo "  🚫 FAIL feature_dir         — does not exist: $feature_dir"
    return 1
  fi
  echo "  ✅ feature_dir              $feature_dir"

  # 2. spec.md
  if [ ! -s "${feature_dir}/spec.md" ]; then
    echo "  🚫 FAIL spec.md              — missing or empty (run /ss:specify)"
    errors=$((errors + 1))
  else
    echo "  ✅ spec.md                  $(wc -l < "${feature_dir}/spec.md") lines"
  fi

  # 3. plan.md
  if [ ! -s "${feature_dir}/plan.md" ]; then
    echo "  🚫 FAIL plan.md              — missing or empty (run /ss:plan)"
    errors=$((errors + 1))
  else
    echo "  ✅ plan.md                  $(wc -l < "${feature_dir}/plan.md") lines"
  fi

  # 4. tasks.md with at least one unchecked task
  if [ ! -s "${feature_dir}/tasks.md" ]; then
    echo "  🚫 FAIL tasks.md             — missing or empty (run /ss:tasks)"
    errors=$((errors + 1))
  else
    local unchecked
    unchecked=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[[:space:]]\][[:space:]]+T[0-9]+' "${feature_dir}/tasks.md" 2>/dev/null || echo 0)
    local checked
    checked=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+T[0-9]+' "${feature_dir}/tasks.md" 2>/dev/null || echo 0)
    if [ "$unchecked" -eq 0 ]; then
      echo "  ⚠️  WARN tasks.md            — all tasks already checked ($checked done); nothing to run"
      warnings=$((warnings + 1))
    else
      echo "  ✅ tasks.md                 $unchecked unchecked / $checked done"
    fi
  fi

  # 5. decision-sheet.md status: locked
  if [ ! -f "${feature_dir}/decision-sheet.md" ]; then
    echo "  🚫 FAIL decision-sheet.md    — missing (run /ss:decisions first to pre-batch)"
    errors=$((errors + 1))
  else
    local status
    status=$(grep -E '^status:' "${feature_dir}/decision-sheet.md" 2>/dev/null | head -n1 | sed -E 's/^status:[[:space:]]*//')
    if [ "$status" != "locked" ]; then
      echo "  🚫 FAIL decision-sheet.md    — status is '${status:-(unset)}'; must be 'locked' (re-run /ss:decisions)"
      errors=$((errors + 1))
    else
      local dcount
      dcount=$(grep -cE '^## D[0-9]+:' "${feature_dir}/decision-sheet.md" 2>/dev/null || echo 0)
      echo "  ✅ decision-sheet.md        locked ($dcount decision(s))"
    fi
  fi

  # 6. Git working tree
  local dirty
  dirty=$(git -C "$repo_root" status --porcelain 2>/dev/null | head -c 1)
  if [ -n "$dirty" ]; then
    if [ "$allow_dirty" = "true" ]; then
      echo "  ⚠️  WARN git working tree    — has uncommitted changes (--allow-dirty acknowledged)"
      warnings=$((warnings + 1))
    else
      echo "  🚫 FAIL git working tree     — has uncommitted changes (commit or stash; or pass --allow-dirty)"
      errors=$((errors + 1))
    fi
  else
    echo "  ✅ git working tree         clean"
  fi

  # 7. Branch is NNN-slug feature branch
  local branch
  branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if echo "$branch" | grep -qE '^[0-9]{3}-'; then
    echo "  ✅ branch                   $branch"
  else
    echo "  ⚠️  WARN branch              — '${branch:-?}' is not an NNN-slug feature branch (autonomous run will land commits here)"
    warnings=$((warnings + 1))
  fi

  # 8. claude CLI
  if command -v claude >/dev/null 2>&1; then
    local v
    v=$(claude --version 2>/dev/null | head -1 || echo "(version unknown)")
    echo "  ✅ claude CLI               $v"
  else
    echo "  🚫 FAIL claude CLI           — not in PATH; --exec mode requires it"
    errors=$((errors + 1))
  fi

  echo "─────────────────────────────────────────────────────"
  if [ "$errors" -gt 0 ]; then
    echo "  STATUS: 🚫 BLOCKED ($errors error(s), $warnings warning(s))"
    return 1
  elif [ "$warnings" -gt 0 ]; then
    echo "  STATUS: ⚠️  READY with warnings ($warnings)"
    return 0
  else
    echo "  STATUS: ✅ READY"
    return 0
  fi
}

# Allow direct invocation
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  ss_overnight_preflight "$@"
fi
