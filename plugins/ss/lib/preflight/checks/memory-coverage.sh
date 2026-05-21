#!/bin/bash
# SpecSwarm Preflight Check: memory-coverage
#
# Verifies the integrity of the memory-file corpus referenced by the plan:
#   1. Every memory file path explicitly referenced from plan.md exists on disk
#   2. Every memory file in declared memory dirs appears in the project MEMORY.md
#      index (orphans flagged as warnings, not failures)
#
# Project-agnostic: discovers memory directories via .specswarm/references.md
# (Memory directories section). Skips silently if no memory dirs are declared.
#
# Input:  $1 = absolute path to plan.md
# Output: First line "PASS|WARN|FAIL <summary>", then indented details.

set -e

PLAN_PATH="${1:-}"
if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ]; then
  echo "FAIL memory-coverage: plan path missing or not found ($PLAN_PATH)"
  exit 2
fi

PLUGIN_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${PLUGIN_LIB}/references-loader.sh"

# Discover memory dirs (from references.md). Skip silently if none.
MEMORY_DIRS=()
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  [ -d "$dir" ] && MEMORY_DIRS+=("$dir")
done < <(ss_references_memory_dirs)

if [ "${#MEMORY_DIRS[@]}" -eq 0 ]; then
  echo "PASS memory-coverage: skipped (no memory directories declared in references.md)"
  exit 0
fi

# Pass 1: Extract memory file paths explicitly referenced from plan.md.
#
# SpecSwarm's universal memory taxonomy (see lib/references-loader.sh
# ss_memory_scan_files) is the five prefixes feedback_/project_/reference_/
# user_/intervention_. These are SpecSwarm-documented conventions, NOT
# project-specific, so the extractor is safe to key off them for ANY project.
#
# Three citation styles are recognised — a plan may use any mix:
#   1. path/extension form:  memory/feedback_x.md  OR  feedback_x.md
#   2. backtick bare-name:   `feedback_x`          (no .md, no path)
#   3. [[wiki-link]]:        [[feedback-x]] / [[feedback_x]]
#
# Style 2 (backtick) was the silent blind spot fixed in v7.11.0: plans that
# cite memory inline as `feedback_version_currency` extracted ZERO refs under
# the old .md-only matcher, yielding a misleading 0/0 PASS.
MEM_PREFIX='(feedback|project|reference|user|intervention)'

# Style 1: explicit .md (optionally memory/-prefixed)
REFERENCED_MD=$(grep -oE "(memory\/)?${MEM_PREFIX}_[a-zA-Z0-9_-]+\.md" "$PLAN_PATH" 2>/dev/null \
  | sed 's|^memory/||' \
  | sort -u || true)

# Style 2: backtick-wrapped bare slug (no extension) — append .md for matching
REFERENCED_BACKTICK=$(grep -oE "\`${MEM_PREFIX}_[a-zA-Z0-9_-]+\`" "$PLAN_PATH" 2>/dev/null \
  | tr -d '`' \
  | sed 's|$|.md|' \
  | sort -u || true)

REFERENCED=$(printf '%s\n%s\n' "$REFERENCED_MD" "$REFERENCED_BACKTICK" \
  | grep -v '^$' \
  | sort -u || true)

# Also extract [[wiki-link]] references that look like memory slugs
WIKI=$(grep -oE '\[\[[a-zA-Z0-9_-]+\]\]' "$PLAN_PATH" 2>/dev/null \
  | sed 's/^\[\[//;s/\]\]$//' \
  | sort -u || true)

# Build a master index of memory files that DO exist in declared dirs
EXISTING_FILES=$(mktemp)
for dir in "${MEMORY_DIRS[@]}"; do
  find "$dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null
done > "$EXISTING_FILES"

EXISTING_BASENAMES=$(awk -F/ '{print $NF}' "$EXISTING_FILES" | sort -u)

# Check 1: referenced files that don't exist
MISSING=()
if [ -n "$REFERENCED" ]; then
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    if ! echo "$EXISTING_BASENAMES" | grep -qFx "$ref"; then
      MISSING+=("$ref")
    fi
  done <<< "$REFERENCED"
fi

# Check 2: wiki-link references — only flag if they look like memory slugs
# (i.e., a corresponding memory_<slug>.md exists somewhere or the slug uses the convention)
WIKI_MISSING=()
if [ -n "$WIKI" ]; then
  while IFS= read -r slug; do
    [ -z "$slug" ] && continue
    # Only treat as a memory ref if the slug starts with feedback/project/reference/user prefix
    case "$slug" in
      feedback-*|project-*|reference-*|user-*|feedback_*|project_*|reference_*|user_*)
        # Convert kebab to snake for filename matching
        fname=$(echo "$slug" | tr '-' '_')
        if ! echo "$EXISTING_BASENAMES" | grep -qE "^${fname}\.md$"; then
          WIKI_MISSING+=("[[${slug}]]")
        fi
        ;;
    esac
  done <<< "$WIKI"
fi

# Check 3: orphans — memory files in declared dirs but absent from MEMORY.md index
ORPHANS=()
for dir in "${MEMORY_DIRS[@]}"; do
  INDEX="${dir%/}/MEMORY.md"
  [ -f "$INDEX" ] || continue
  while IFS= read -r mfile; do
    [ -z "$mfile" ] && continue
    base=$(basename "$mfile")
    # Skip MEMORY.md itself
    [ "$base" = "MEMORY.md" ] && continue
    # Only check files matching memory naming convention
    case "$base" in
      feedback_*|project_*|reference_*|user_*|intervention_*) ;;
      *) continue ;;
    esac
    if ! grep -qF "$base" "$INDEX" 2>/dev/null; then
      ORPHANS+=("${dir%/}/${base}")
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
done

rm -f "$EXISTING_FILES"

TOTAL_REFS=$(printf '%s\n' "$REFERENCED" | grep -c . || true)
TOTAL_REFS=${TOTAL_REFS:-0}
MISSING_COUNT=$(( ${#MISSING[@]} + ${#WIKI_MISSING[@]} ))
ORPHAN_COUNT=${#ORPHANS[@]}

if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "FAIL memory-coverage: ${MISSING_COUNT} memory reference(s) in plan.md point at missing files"
  for entry in "${MISSING[@]}"; do
    echo "  🚫 ${entry} — referenced in plan.md but not found in any declared memory dir"
  done
  for entry in "${WIKI_MISSING[@]}"; do
    echo "  🚫 ${entry} — wiki-link points at non-existent memory file"
  done
  if [ "$ORPHAN_COUNT" -gt 0 ]; then
    echo "  (also: ${ORPHAN_COUNT} orphan file(s) absent from MEMORY.md index — see WARN)"
  fi
  exit 2
fi

if [ "$ORPHAN_COUNT" -gt 0 ]; then
  echo "WARN memory-coverage: ${TOTAL_REFS} references verified; ${ORPHAN_COUNT} orphan file(s) not in MEMORY.md"
  for entry in "${ORPHANS[@]}"; do
    echo "  ⚠️  ${entry} — exists on disk but not indexed in MEMORY.md"
  done
  exit 1
fi

# WARN-on-zero (v7.11.0): memory dirs ARE declared, yet plan.md cites zero
# memory files in any recognised style. Either the plan genuinely references
# none (unusual for a SpecSwarm project that uses the references system), or
# the extractor missed a citation style. A 0/0 PASS hides the second case —
# surface it as a soft WARN instead. See feedback `pass_on_zero_is_a_smell`.
if [ "$TOTAL_REFS" -eq 0 ]; then
  echo "WARN memory-coverage: 0 memory references found in plan.md (${#MEMORY_DIRS[@]} memory dir(s) declared) — is this expected? Extractor may not match this plan's citation style."
  exit 1
fi

echo "PASS memory-coverage: ${TOTAL_REFS} memory reference(s) verified across ${#MEMORY_DIRS[@]} memory dir(s)"
exit 0
