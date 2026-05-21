#!/bin/bash
# SpecSwarm Preflight Check: spec-section-existence
#
# Verifies that every "§X.Y" section reference in plan.md resolves to a real
# heading in at least one declared spec-corpus document.
#
# Project-agnostic: spec corpus is discovered via .specswarm/references.md
# (Spec corpus section). Skips silently if no corpus is declared.
#
# Section ref format: § followed by digits and dots: §1, §1.2, §3.4.5, etc.
#
# Input:  $1 = absolute path to plan.md
# Output: First line "PASS|WARN|FAIL <summary>", then indented details.

set -e

PLAN_PATH="${1:-}"
if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ]; then
  echo "FAIL spec-section-existence: plan path missing or not found ($PLAN_PATH)"
  exit 2
fi

PLUGIN_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${PLUGIN_LIB}/references-loader.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Discover spec corpus paths. Resolve relative paths against repo root.
# Skip silently if no corpus declared.
CORPUS_FILES=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  case "$p" in
    /*) ABS="$p" ;;
    *) ABS="${REPO_ROOT}/${p}" ;;
  esac
  # Glob expansion (e.g., docs/architecture/*.md)
  for resolved in $ABS; do
    [ -f "$resolved" ] && CORPUS_FILES+=("$resolved")
  done
done < <(ss_references_spec_corpus_paths)

if [ "${#CORPUS_FILES[@]}" -eq 0 ]; then
  echo "PASS spec-section-existence: skipped (no spec corpus declared in references.md)"
  exit 0
fi

# Extract all §X.Y section references from plan.md (deduped)
REFS=$(grep -oE '§[0-9]+(\.[0-9]+)*' "$PLAN_PATH" 2>/dev/null | sort -u || true)

if [ -z "$REFS" ]; then
  # WARN-on-zero (v7.11.0): a spec corpus IS declared, yet plan.md cites zero
  # §X.Y sections. May be legitimate, or the plan references sections in a
  # style the extractor misses ("section 3.4" without §) — in which case a
  # broken cross-reference slips past a 0/0 PASS. See feedback
  # `pass_on_zero_is_a_smell`.
  echo "WARN spec-section-existence: 0 §X.Y references found in plan.md (${#CORPUS_FILES[@]} corpus file(s) declared) — is this expected?"
  exit 1
fi

# Pre-build a unified heading index from all corpus files.
# We capture both:
#   "§X.Y" appearing in headings (e.g., "## §3.4 Foo")
#   bare "X.Y" appearing in numbered headings (e.g., "### 3.4 Foo")
HEADING_INDEX=$(mktemp)
for f in "${CORPUS_FILES[@]}"; do
  grep -E '^#+\s' "$f" 2>/dev/null || true
done > "$HEADING_INDEX"

# For each reference, check if any heading line contains it
MISSING=()
VERIFIED=0
TOTAL=0

while IFS= read -r ref; do
  [ -z "$ref" ] && continue
  TOTAL=$((TOTAL + 1))
  # Strip § for bare numeric match
  num=${ref#§}
  if grep -qF "$ref" "$HEADING_INDEX" 2>/dev/null \
     || grep -qE "^#+\s+${num//./\\.}([[:space:]]|$)" "$HEADING_INDEX" 2>/dev/null \
     || grep -qE "^#+\s+${num//./\\.}\b" "$HEADING_INDEX" 2>/dev/null; then
    VERIFIED=$((VERIFIED + 1))
  else
    MISSING+=("$ref")
  fi
done <<< "$REFS"

rm -f "$HEADING_INDEX"

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "FAIL spec-section-existence: ${#MISSING[@]} of ${TOTAL} § reference(s) do not resolve to any spec corpus heading"
  for ref in "${MISSING[@]}"; do
    echo "  🚫 ${ref} — not found in any of ${#CORPUS_FILES[@]} corpus file(s)"
  done
  echo "  Corpus searched:"
  for f in "${CORPUS_FILES[@]}"; do
    echo "    • ${f#${REPO_ROOT}/}"
  done
  exit 2
fi

echo "PASS spec-section-existence: ${VERIFIED}/${TOTAL} § reference(s) resolved across ${#CORPUS_FILES[@]} corpus file(s)"
exit 0
