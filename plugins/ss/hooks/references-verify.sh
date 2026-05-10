#!/bin/bash
# SpecSwarm References Verify Hook (v6.1.0)
# SessionStart hook — checks that each reference codebase declared in
# .specswarm/references.md still resolves at session start, and warns
# (non-blocking) if any are missing. Silent + zero overhead when no
# references.md is present.
#
# Output: JSON envelope per Claude Code hook contract.

set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PLUGIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
LOADER="${PLUGIN_DIR}/lib/references-loader.sh"

# Fast-path: if loader missing, nothing to verify (degraded mode, allow exit)
if [ ! -f "$LOADER" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# shellcheck disable=SC1090
source "$LOADER"

# Fast-path: if references.md not present or empty, silent approve
if ! ss_references_exist; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Walk reference codebases — each emitted as TSV: name<TAB>path<TAB>verify-file<TAB>rationale
MISSING=()
PRESENT_COUNT=0

while IFS=$'\t' read -r name path verify_file rationale; do
  [ -z "$name" ] && continue

  ABS_PATH=$(ss_references_resolve_path "$path")

  # If verify-file is set, check that specific file. Else fall back to "is the dir there?"
  if [ -n "$verify_file" ]; then
    if [ -f "${ABS_PATH}/${verify_file}" ]; then
      PRESENT_COUNT=$((PRESENT_COUNT + 1))
    else
      MISSING+=("${name}|${path}|${verify_file}|${rationale}")
    fi
  else
    if [ -d "$ABS_PATH" ]; then
      PRESENT_COUNT=$((PRESENT_COUNT + 1))
    else
      MISSING+=("${name}|${path}||${rationale}")
    fi
  fi
done < <(ss_references_codebases)

# Audit log if available
AUDIT_LIB="${PLUGIN_DIR}/lib/audit-logger.sh"
if [ -f "$AUDIT_LIB" ]; then
  # shellcheck disable=SC1090
  source "$AUDIT_LIB" 2>/dev/null || true
  if declare -f audit_log >/dev/null 2>&1; then
    audit_log "references_verify" \
      present_count="$PRESENT_COUNT" \
      missing_count="${#MISSING[@]}" 2>/dev/null || true
  fi
fi

# Build the system message — keep it tight, one line per missing reference
if [ "${#MISSING[@]}" -eq 0 ]; then
  # All present — silent (or one-line confirmation if any exist)
  if [ "$PRESENT_COUNT" -gt 0 ]; then
    jq -n -c --arg msg "✓ SpecSwarm: $PRESENT_COUNT reference codebase(s) verified" \
      '{decision: "approve", systemMessage: $msg}'
  else
    echo '{"decision": "approve"}'
  fi
  exit 0
fi

# Some missing — emit warning with each missing reference's name + path + rationale
WARN="⚠️  SpecSwarm: ${#MISSING[@]} reference codebase(s) missing (work depending on them will produce incorrect results):"
for entry in "${MISSING[@]}"; do
  IFS='|' read -r name path verify_file rationale <<< "$entry"
  WARN="$WARN"$'\n'"   • ${name} (expected at: ${path}"
  if [ -n "$verify_file" ]; then
    WARN="$WARN/${verify_file}"
  fi
  WARN="$WARN)"
  if [ -n "$rationale" ]; then
    WARN="$WARN"$'\n'"     ↳ ${rationale}"
  fi
done
WARN="$WARN"$'\n'"   Edit .specswarm/references.md to fix paths, OR ask the user where the references actually live before proceeding with any work that depends on them."

jq -n -c --arg msg "$WARN" '{decision: "approve", systemMessage: $msg}'
exit 0
