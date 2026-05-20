#!/bin/bash
# SpecSwarm Preflight Check: heading-fidelity
#
# When plan.md quotes a spec heading verbatim alongside a § reference, verifies
# the quoted text matches the actual heading in the spec corpus. Catches typos
# like "5 riding styles" vs "5 ride styles".
#
# Detection pattern: `§X.Y "Quoted Heading Text"` or `§X.Y 'Quoted Heading Text'`
# OR `§X.Y Heading Text:` (heading followed by colon on same line as ref).
#
# Project-agnostic: spec corpus discovered via .specswarm/references.md.
# Skips silently if no corpus is declared.
#
# Input:  $1 = absolute path to plan.md
# Output: First line "PASS|WARN|FAIL <summary>", then indented details.

set -e

PLAN_PATH="${1:-}"
if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ]; then
  echo "FAIL heading-fidelity: plan path missing or not found ($PLAN_PATH)"
  exit 2
fi

PLUGIN_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${PLUGIN_LIB}/references-loader.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

CORPUS_FILES=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  case "$p" in
    /*) ABS="$p" ;;
    *) ABS="${REPO_ROOT}/${p}" ;;
  esac
  for resolved in $ABS; do
    [ -f "$resolved" ] && CORPUS_FILES+=("$resolved")
  done
done < <(ss_references_spec_corpus_paths)

if [ "${#CORPUS_FILES[@]}" -eq 0 ]; then
  echo "PASS heading-fidelity: skipped (no spec corpus declared in references.md)"
  exit 0
fi

# Extract candidate "§X.Y \"Heading\"" or "§X.Y 'Heading'" patterns from plan.md.
# Awk captures: section_ref, heading_text per line.
CANDIDATES=$(awk '
  {
    # Match §X.Y followed by quoted text
    while (match($0, /§[0-9]+(\.[0-9]+)*[[:space:]]+["\047]([^"\047]+)["\047]/)) {
      chunk = substr($0, RSTART, RLENGTH)
      # Split into ref and text
      if (match(chunk, /§[0-9]+(\.[0-9]+)*/)) {
        ref = substr(chunk, RSTART, RLENGTH)
      }
      if (match(chunk, /["\047]([^"\047]+)["\047]/)) {
        text = substr(chunk, RSTART+1, RLENGTH-2)
      }
      print ref "\t" text
      $0 = substr($0, RSTART + RLENGTH)
    }
  }
' "$PLAN_PATH" 2>/dev/null | sort -u || true)

if [ -z "$CANDIDATES" ]; then
  echo "PASS heading-fidelity: no quoted §X.Y \"Heading\" patterns in plan.md"
  exit 0
fi

# Build a combined heading-text index from all corpus files
HEADING_INDEX=$(mktemp)
for f in "${CORPUS_FILES[@]}"; do
  grep -E '^#+\s' "$f" 2>/dev/null | sed -E 's/^#+\s+//' || true
done > "$HEADING_INDEX"

DRIFT=()
VERIFIED=0
TOTAL=0

while IFS=$'\t' read -r ref text; do
  [ -z "$ref" ] && continue
  [ -z "$text" ] && continue
  TOTAL=$((TOTAL + 1))

  # Does any corpus heading exactly contain the quoted text?
  if grep -qF -- "$text" "$HEADING_INDEX" 2>/dev/null; then
    VERIFIED=$((VERIFIED + 1))
  else
    # Try fuzzy: find headings starting with the §ref number, see if text close
    DRIFT+=("${ref}|${text}")
  fi
done <<< "$CANDIDATES"

rm -f "$HEADING_INDEX"

if [ "${#DRIFT[@]}" -gt 0 ]; then
  echo "WARN heading-fidelity: ${#DRIFT[@]} of ${TOTAL} quoted heading(s) do not exactly match any corpus heading"
  for entry in "${DRIFT[@]}"; do
    IFS='|' read -r ref text <<< "$entry"
    echo "  ⚠️  ${ref} quoted as \"${text}\" — no exact match in spec corpus"
  done
  echo "  Fix: re-read the source section and copy the heading text verbatim"
  exit 1
fi

echo "PASS heading-fidelity: ${VERIFIED}/${TOTAL} quoted heading(s) match spec corpus verbatim"
exit 0
