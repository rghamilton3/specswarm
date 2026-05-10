#!/bin/bash
# SpecSwarm Constitution Dispatcher (6.3.0)
# PostToolUse hook for Edit|MultiEdit|Write.
# Iterates .specswarm/hooks/generated/*.sh and runs each with the changed file path.
# Routes hook output by severity marker:
#   🚫 line  → decision=block + reason (Claude is told to revert/fix)
#   ⚠️  line → decision=approve + systemMessage (Claude is informed but proceeds)
# Bypasses entirely (zero overhead) if .specswarm/hooks/generated/ doesn't exist.

set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
GENERATED_DIR="${REPO_ROOT}/.specswarm/hooks/generated"

# Fast-path: nothing to do if no generated hooks
if [ ! -d "$GENERATED_DIR" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Read the tool input from stdin (PostToolUse hook payload, JSON)
INPUT=$(cat 2>/dev/null || echo "{}")

# Extract file_path from the most common shapes:
# - tool_input.file_path (Edit, Write, MultiEdit)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Make absolute if relative
case "$FILE_PATH" in
  /*) ;;
  *) FILE_PATH="${REPO_ROOT}/${FILE_PATH}" ;;
esac

if [ ! -f "$FILE_PATH" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Hard cap on dispatcher work to avoid slowing down edits
TIMEOUT_SECONDS=2

# Run each generated hook and bucket output by severity marker.
# Hooks emit one of two prefixes on the first stderr line:
#   🚫 → block-severity violation (PostToolUse decision=block + reason)
#   ⚠️  → warn-severity (PostToolUse decision=approve + systemMessage)
BLOCKS=""
BLOCK_COUNT=0
WARNINGS=""
WARNING_COUNT=0

for hook in "$GENERATED_DIR"/*.sh; do
  [ -f "$hook" ] || continue
  [ -x "$hook" ] || chmod +x "$hook" 2>/dev/null || true

  HOOK_OUTPUT=$(timeout "$TIMEOUT_SECONDS" bash "$hook" "$FILE_PATH" 2>&1 1>/dev/null || true)
  [ -z "$HOOK_OUTPUT" ] && continue

  if echo "$HOOK_OUTPUT" | head -n1 | grep -q "🚫"; then
    BLOCKS="${BLOCKS}${HOOK_OUTPUT}\n"
    BLOCK_COUNT=$((BLOCK_COUNT + 1))
  else
    WARNINGS="${WARNINGS}${HOOK_OUTPUT}\n"
    WARNING_COUNT=$((WARNING_COUNT + 1))
  fi
done

# Audit log if available
AUDIT_LIB="$(dirname "$0")/../lib/audit-logger.sh"
if [ -f "$AUDIT_LIB" ]; then
  # shellcheck disable=SC1090
  source "$AUDIT_LIB" 2>/dev/null || true
  if declare -f audit_log >/dev/null 2>&1; then
    if [ "$BLOCK_COUNT" -gt 0 ] || [ "$WARNING_COUNT" -gt 0 ]; then
      audit_log "constitutional_violations" file="$FILE_PATH" block_count="$BLOCK_COUNT" warning_count="$WARNING_COUNT" 2>/dev/null || true
    fi
  fi
fi

# Decision routing: any block → decision=block (warnings folded into reason);
# warnings-only → decision=approve+systemMessage; nothing → silent approve.
if [ "$BLOCK_COUNT" -gt 0 ]; then
  REASON=$(printf "%b%b" "$BLOCKS" "$WARNINGS")
  jq -n -c --arg msg "$REASON" '{decision: "block", reason: $msg}'
elif [ "$WARNING_COUNT" -gt 0 ]; then
  jq -n -c --arg msg "$(printf "%b" "$WARNINGS")" '{decision: "approve", systemMessage: $msg}'
else
  echo '{"decision": "approve"}'
fi

exit 0
