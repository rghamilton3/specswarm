#!/bin/bash
# SpecSwarm Preflight Check: grep-word-boundary
#
# Flags grep/rg invocations in plan.md (typically in code blocks describing
# verification steps) that use short literal patterns without word boundaries.
# These often produce false positives — e.g., grepping for `pnpm` matches
# `pnpm-lock.yaml` lines too.
#
# Heuristic: a pattern is risky if it's a short alpha word (≤8 chars) without
# any of: \b, -w flag, ^, $, |, [, (, regex metacharacters.
#
# Input:  $1 = absolute path to plan.md
# Output: First line "PASS|WARN|FAIL <summary>", then indented details.

set -e

PLAN_PATH="${1:-}"
if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ]; then
  echo "FAIL grep-word-boundary: plan path missing or not found ($PLAN_PATH)"
  exit 2
fi

# Collect grep/rg invocation lines from plan.md (skip the heading line itself)
GREP_LINES=$(grep -nE '(^|[[:space:]`])(grep|rg|egrep|fgrep)([[:space:]]|$)' "$PLAN_PATH" 2>/dev/null \
  | grep -vE '^[0-9]+:#+\s' || true)

if [ -z "$GREP_LINES" ]; then
  echo "PASS grep-word-boundary: no grep/rg invocations found in plan.md"
  exit 0
fi

FLAGGED=()
TOTAL=0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  TOTAL=$((TOTAL + 1))

  # Extract the grep command portion (everything after the tool name)
  # Skip lines that already use -w (whole-word) or -F (fixed strings safe)
  if echo "$line" | grep -qE '(grep|rg|egrep|fgrep)\s+(-[a-zA-Z]*w[a-zA-Z]*|--word-regexp)'; then
    continue
  fi

  # Extract the first non-flag argument after grep — that's typically the pattern
  pattern=$(echo "$line" | sed -nE 's/.*(grep|rg|egrep|fgrep)[[:space:]]+((-[a-zA-Z]+[[:space:]]+)*)([^[:space:]\\"`]+).*/\4/p' | head -1)
  pattern=$(echo "$pattern" | sed -E 's/^["'"'"']//;s/["'"'"']$//')

  [ -z "$pattern" ] && continue

  # Heuristic: short literal word without regex anchors/escapes/metas
  if [ "${#pattern}" -le 8 ] \
     && echo "$pattern" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'; then
    FLAGGED+=("$line")
  fi
done <<< "$GREP_LINES"

if [ "${#FLAGGED[@]}" -gt 0 ]; then
  echo "WARN grep-word-boundary: ${#FLAGGED[@]} of ${TOTAL} grep/rg pattern(s) may produce false positives (short literal, no word boundary)"
  for entry in "${FLAGGED[@]}"; do
    # entry is "lineno:content"
    lno=$(echo "$entry" | cut -d: -f1)
    content=$(echo "$entry" | cut -d: -f2- | sed 's/^[[:space:]]*//' | head -c 120)
    echo "  ⚠️  line ${lno}: ${content}"
  done
  echo "  Fix: add -w (whole-word) flag or \\bWORD\\b boundaries to avoid substring matches"
  exit 1
fi

echo "PASS grep-word-boundary: ${TOTAL} grep/rg invocation(s) checked, none flagged"
exit 0
