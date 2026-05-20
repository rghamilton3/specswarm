#!/bin/bash
# SpecSwarm Decision Scanner (v7.6.0)
#
# Deterministic candidate extraction for /ss:decisions. Scans a plan.md (and
# its associated foundation files) for patterns that signal strategic
# decisions the user should pre-batch BEFORE /ss:tasks / /ss:implement.
#
# Output format (TSV, one candidate per line):
#   kind<TAB>line_num<TAB>excerpt<TAB>context
#
# Kinds (in priority order):
#   clarification  — explicit "NEEDS CLARIFICATION" marker
#   conflict       — explicit conflict / adjudication language
#   constitution   — P1/P2/P3 callouts in plan.md
#   version        — version pin in plan.md NOT anchored in tech-stack.md
#   multioption    — OR / vs / preferred-fallback language
#   defer          — defer / include / optional language
#   placeholder    — TBD / TODO / bracketed placeholders
#
# Public API (when sourced):
#   ss_scan_plan_decisions <plan_path> [foundation_dir]
#     Echoes TSV candidates to stdout. Empty output is a valid (good) result.
#
# Usage as script:
#   scan-plan.sh PLAN_PATH [FOUNDATION_DIR]
#     foundation_dir defaults to <repo>/.specswarm/

set -e

ss_scan_plan_decisions() {
  local plan="$1"
  local foundation_dir="${2:-}"

  [ -f "$plan" ] || return 0

  if [ -z "$foundation_dir" ]; then
    local repo_root
    repo_root=$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null \
      || dirname "$(dirname "$(dirname "$plan")")")
    foundation_dir="${repo_root}/.specswarm"
  fi

  local tech_stack="${foundation_dir}/tech-stack.md"
  local constitution="${foundation_dir}/constitution.md"

  # ─── Kind 1: NEEDS CLARIFICATION (SpecSwarm canonical) ────────────────────
  grep -nE 'NEEDS CLARIFICATION' "$plan" 2>/dev/null | while IFS=: read -r line rest; do
    excerpt=$(echo "$rest" | head -c 200)
    printf 'clarification\t%s\t%s\t%s\n' "$line" "$excerpt" ""
  done

  # ─── Kind 2: Conflict / adjudication markers ──────────────────────────────
  grep -nEi '(corpus[[:space:]]+conflict|adjudication|adjudicate|needs[[:space:]]+marty|surface[[:space:]]+for[[:space:]]+marty)' "$plan" 2>/dev/null \
    | while IFS=: read -r line rest; do
        excerpt=$(echo "$rest" | head -c 200)
        printf 'conflict\t%s\t%s\t%s\n' "$line" "$excerpt" ""
      done

  # ─── Kind 3: Constitution P1/P2/P3 callouts (only if constitution.md exists) ─
  if [ -f "$constitution" ]; then
    grep -nEi '\b(P1|P2|P3|principle[[:space:]]+[0-9]+)\b.*constitution|constitution.*\b(P1|P2|P3)\b' "$plan" 2>/dev/null \
      | while IFS=: read -r line rest; do
          excerpt=$(echo "$rest" | head -c 200)
          printf 'constitution\t%s\t%s\t%s\n' "$line" "$excerpt" ""
        done
  fi

  # ─── Kind 4: Version pins NOT in tech-stack.md ────────────────────────────
  if [ -f "$tech_stack" ]; then
    # Extract candidate <name>@<version> tokens from plan.md
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      pkg=$(echo "$match" | sed -E 's/@[0-9].*//')
      # Skip if the package name appears anywhere in tech-stack.md
      if ! grep -qF "$pkg" "$tech_stack" 2>/dev/null; then
        # Find first line where this pin appears
        line=$(grep -n -F "$match" "$plan" 2>/dev/null | head -n1 | cut -d: -f1)
        [ -z "$line" ] && line="?"
        printf 'version\t%s\t%s\t%s\n' "$line" "$match" "$pkg not anchored in tech-stack.md"
      fi
    done < <(grep -oE '@?[a-zA-Z0-9_./-]+@[0-9]+\.[0-9]+\.[0-9]+' "$plan" 2>/dev/null | sort -u)
  fi

  # ─── Kind 5: Multi-option language (OR / vs / preferred + fallback) ────────
  # Strict patterns to avoid false positives on natural-language "or"
  grep -nEi '(preferred[[:space:]]*[,;:]?[[:space:]]*fallback|fallback[[:space:]]*[,;:]|[a-zA-Z0-9_.-]+[[:space:]]+vs\.?[[:space:]]+[a-zA-Z0-9_.-]+|choice[[:space:]]*:)' "$plan" 2>/dev/null \
    | while IFS=: read -r line rest; do
        excerpt=$(echo "$rest" | head -c 200)
        printf 'multioption\t%s\t%s\t%s\n' "$line" "$excerpt" ""
      done

  # ─── Kind 6: Defer / include / optional language ──────────────────────────
  grep -nEi '(defer[[:space:]]+to[[:space:]]+(P[0-9.]+|next[[:space:]]+chunk|later|future)|defer[[:space:]]+(this|that)|include[[:space:]]+in[[:space:]]+this[[:space:]]+chunk|optionally[[:space:]]+ship|acceptable[[:space:]]+to[[:space:]]+ship)' "$plan" 2>/dev/null \
    | while IFS=: read -r line rest; do
        excerpt=$(echo "$rest" | head -c 200)
        printf 'defer\t%s\t%s\t%s\n' "$line" "$excerpt" ""
      done

  # ─── Kind 7: Placeholders ─────────────────────────────────────────────────
  grep -nE '\b(TBD|TODO|FIXME)\b|\[(TBD|TODO|FIXME|CHOICE|PLACEHOLDER|DECISION)[A-Z_ -]*\]' "$plan" 2>/dev/null \
    | while IFS=: read -r line rest; do
        excerpt=$(echo "$rest" | head -c 200)
        printf 'placeholder\t%s\t%s\t%s\n' "$line" "$excerpt" ""
      done
}

# Allow direct script invocation
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  ss_scan_plan_decisions "$@"
fi
