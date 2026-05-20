#!/bin/bash
# SpecSwarm Verify Queue Prompt (v7.4.0)
#
# Stop hook. At every natural pause point (Claude finishes responding),
# checks .specswarm/verify-queue/ for pending verifications and emits a
# systemMessage prompting Claude (or the user) to run /ss:verify.
#
# Silent when:
#   - No verify-queue directory exists
#   - No .pending files in the queue
#
# Does NOT block Claude — always returns decision=approve. The point is
# to surface the recommendation, not to gate further work.

set -e

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
QUEUE_DIR="${REPO_ROOT}/.specswarm/verify-queue"

if [ ! -d "$QUEUE_DIR" ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Collect pending task IDs (fast — no helper sourcing needed for the common case)
PENDING_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && PENDING_FILES+=("$f")
done < <(find "$QUEUE_DIR" -maxdepth 1 -type f -name '*.pending' 2>/dev/null | sort)

if [ "${#PENDING_FILES[@]}" -eq 0 ]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Build a compact list of "T### (feature/desc snippet)"
ITEMS=()
for f in "${PENDING_FILES[@]}"; do
  task_id=$(basename "$f" .pending)
  desc=$(grep -E '^task_desc=' "$f" 2>/dev/null | head -n1 | cut -d= -f2- | head -c 80)
  feature=$(grep -E '^feature_dir=' "$f" 2>/dev/null | head -n1 | cut -d= -f2- | xargs -n1 basename 2>/dev/null)
  if [ -n "$desc" ]; then
    ITEMS+=("${task_id} — ${desc}")
  else
    ITEMS+=("${task_id} (${feature})")
  fi
done

COUNT="${#PENDING_FILES[@]}"
LIST=$(printf '  • %s\n' "${ITEMS[@]}")

MSG="🔍 SpecSwarm verification queue: ${COUNT} task(s) pending adversarial review.
${LIST}
Recommended: run \`/ss:verify\` (or \`/ss:verify T###\` for a specific task) before /ss:ship.
Each pending task lives in .specswarm/verify-queue/<TaskID>.pending."

jq -n -c --arg msg "$MSG" '{decision: "approve", systemMessage: $msg}'
