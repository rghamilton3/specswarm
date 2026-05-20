#!/bin/bash
# SpecSwarm Tasks Completion Detector (v7.4.0)
#
# PostToolUse hook on Edit|MultiEdit|Write. Detects when a tasks.md edit
# flipped one or more SpecSwarm task checkboxes from [ ] to [x|X], queues
# verification markers under .specswarm/verify-queue/, and emits a
# systemMessage so Claude knows verification is pending.
#
# Fast-path (sub-second) when:
#   - Tool isn't Edit/MultiEdit/Write
#   - Edited file isn't named tasks.md
#   - Not in a git repo (no diff possible)
#   - No checkboxes flipped
#
# Project-agnostic — works for any project following SpecSwarm's canonical
# `- [ ] T### …` / `- [X] T### …` tasks.md format. Projects using
# heading-only or other formats silently skip auto-queue; manual
# /ss:verify T### still works.

set -e

INPUT=$(cat 2>/dev/null || echo "{}")

# Pull the changed file path from PostToolUse payload
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
if [ -z "$FILE_PATH" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Fast-path: only care about tasks.md edits
case "$(basename "$FILE_PATH")" in
  tasks.md) ;;
  *)
    echo '{"decision": "approve"}'
    exit 0
    ;;
esac

# Make absolute if relative
case "$FILE_PATH" in
  /*) ;;
  *)
    REPO_HEAD=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    FILE_PATH="${REPO_HEAD}/${FILE_PATH}"
    ;;
esac

if [ ! -f "$FILE_PATH" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Only care about tasks.md files inside .specswarm/features/
case "$FILE_PATH" in
  */.specswarm/features/*/tasks.md) ;;
  *)
    echo '{"decision": "approve"}'
    exit 0
    ;;
esac

# Source the helpers
PLUGIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/verify/queue.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/verify/task-context.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/verify/detect-completion.sh"

# Detect newly-checked task IDs (relative to HEAD)
NEWLY_CHECKED=$(ss_detect_newly_checked "$FILE_PATH" 2>/dev/null || echo "")
if [ -z "$NEWLY_CHECKED" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

FEATURE_DIR=$(dirname "$FILE_PATH")
FEATURE_NAME=$(basename "$FEATURE_DIR")
QUEUED=()

# Queue each newly-checked task
while IFS= read -r task_id; do
  [ -z "$task_id" ] && continue
  desc=$(ss_task_description "$FILE_PATH" "$task_id" 2>/dev/null || echo "")
  refs=$(ss_task_refs "$FILE_PATH" "$task_id" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
  ss_verify_queue_add "$task_id" "$FEATURE_DIR" "$FILE_PATH" "$desc" "$refs" 2>/dev/null || true
  QUEUED+=("$task_id")
done <<< "$NEWLY_CHECKED"

# Audit log if available
AUDIT_LIB="${PLUGIN_DIR}/lib/audit-logger.sh"
if [ -f "$AUDIT_LIB" ]; then
  # shellcheck disable=SC1090
  source "$AUDIT_LIB" 2>/dev/null || true
  if declare -f audit_log >/dev/null 2>&1; then
    audit_log "verify_queued" \
      feature="$FEATURE_NAME" \
      count="${#QUEUED[@]}" 2>/dev/null || true
  fi
fi

# Emit a tight systemMessage so Claude knows verification is queued.
# Keep it short — the Stop hook fires a louder reminder at the next pause.
COUNT=${#QUEUED[@]}
IDS=$(IFS=,; echo "${QUEUED[*]}")
MSG="🔍 SpecSwarm: ${COUNT} task(s) completed (${IDS}) — verification queued in .specswarm/verify-queue/. Run /ss:verify before /ss:ship."

jq -n -c --arg msg "$MSG" '{decision: "approve", systemMessage: $msg}'
