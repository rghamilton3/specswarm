#!/bin/bash
# SpecSwarm SessionStart Orientation Hook
# Surfaces a one-line context primer when a Claude session opens in a SpecSwarm-managed repo.
# Silent on non-SpecSwarm repos — never noisy, never blocks.

set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
STATE_FILE="${REPO_ROOT}/.specswarm/build-loop.state"

# Silent approve when not a SpecSwarm repo or no active build state
if [ ! -f "$STATE_FILE" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Read state — silent approve if file is corrupt
FEATURE_DESC=$(jq -r '.feature_description // ""' "$STATE_FILE" 2>/dev/null || echo "")
PHASE=$(jq -r '.current_phase // ""' "$STATE_FILE" 2>/dev/null || echo "")
FEATURE_NUM=$(jq -r '.feature_num // ""' "$STATE_FILE" 2>/dev/null || echo "")
ACTIVE=$(jq -r '.active // false' "$STATE_FILE" 2>/dev/null || echo "false")
BRANCH=$(jq -r '.branch_name // ""' "$STATE_FILE" 2>/dev/null || echo "")

if [ -z "$FEATURE_DESC" ] && [ -z "$PHASE" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Try to find the feature directory and read tasks.md to surface last/next task
LAST_TASK=""
NEXT_TASK=""
if [ -n "$FEATURE_NUM" ]; then
  FEATURES_DIR="${REPO_ROOT}/.specswarm/features"
  FEATURE_DIR=""
  if [ -d "$FEATURES_DIR" ]; then
    FEATURE_DIR=$(find "$FEATURES_DIR" -maxdepth 1 -type d -name "${FEATURE_NUM}-*" 2>/dev/null | head -n 1)
  fi
  if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/tasks.md" ]; then
    # Last completed task: most recent line matching "[x]"
    LAST_TASK=$(grep -E '^\s*-\s*\[x\]' "$FEATURE_DIR/tasks.md" 2>/dev/null | tail -n 1 | sed -E 's/^\s*-\s*\[x\]\s*//' | head -c 80)
    # Next pending task: first line matching "[ ]"
    NEXT_TASK=$(grep -E '^\s*-\s*\[ \]' "$FEATURE_DIR/tasks.md" 2>/dev/null | head -n 1 | sed -E 's/^\s*-\s*\[ \]\s*//' | head -c 80)
  fi
fi

# Build the orientation message — keep it to one line
MSG="🔄 SpecSwarm:"
[ -n "$FEATURE_DESC" ] && MSG="$MSG ${FEATURE_DESC:0:60}"
[ -n "$PHASE" ] && MSG="$MSG (phase: $PHASE)"
if [ "$ACTIVE" = "true" ]; then
  MSG="$MSG [active]"
fi
[ -n "$BRANCH" ] && MSG="$MSG • branch: $BRANCH"
[ -n "$LAST_TASK" ] && MSG="$MSG • last: \"$LAST_TASK\""
[ -n "$NEXT_TASK" ] && MSG="$MSG • next: \"$NEXT_TASK\""

# Emit JSON safely with jq
jq -n -c --arg msg "$MSG" '{decision: "approve", systemMessage: $msg}'

exit 0
