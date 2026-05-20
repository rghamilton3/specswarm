#!/bin/bash
# SpecSwarm Overnight Autonomous Runner (v7.10.0)
#
# Invokable by cron / systemd / launchd / /schedule plugin. Runs a feature's
# /ss:preflight → /ss:implement → /ss:verify → /ss:retrospective chain
# autonomously via headless `claude --print`, with strict no-questions semantics
# (decisions must be pre-batched in decision-sheet.md).
#
# Usage:
#   run.sh <feature_num> [--timeout SECONDS] [--allow-dirty]
#
# Exit codes:
#   0   — success (full chain completed; commits may or may not have landed)
#   1   — preflight blocked (artifacts not ready)
#   2   — autonomous run errored or returned non-zero
#   3   — wall-clock timeout (SIGTERM'd the child)
#   4   — already running (PID file held by another process)
#
# Notifies via ss_notify on every terminal state.

set -e

PLUGIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/features-location.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/overnight/state.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/overnight/preflight.sh"
# shellcheck disable=SC1091
[ -f "${PLUGIN_DIR}/lib/notify.sh" ] && source "${PLUGIN_DIR}/lib/notify.sh"

# ─── Parse args ─────────────────────────────────────────────────────────────
FEATURE_NUM=""
TIMEOUT_SECONDS=$((8 * 3600))  # 8 hours default
ALLOW_DIRTY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)     TIMEOUT_SECONDS="$2"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=true;     shift ;;
    *)             [ -z "$FEATURE_NUM" ] && FEATURE_NUM="$1"; shift ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

if [ -z "$FEATURE_NUM" ]; then
  # Auto-resolve: current branch NNN-slug
  BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  FEATURE_NUM=$(echo "$BRANCH" | grep -oE '^[0-9]{3}' || echo "")
fi

if [ -z "$FEATURE_NUM" ] || ! find_feature_dir "$FEATURE_NUM" "$REPO_ROOT"; then
  echo "❌ overnight: cannot resolve feature (got '$FEATURE_NUM')" >&2
  exit 1
fi
FEATURE_ID=$(basename "$FEATURE_DIR")

# ─── Acquire PID lock ───────────────────────────────────────────────────────
PID_FILE=$(ss_overnight_pid_file)
LOG_FILE=$(ss_overnight_log_file)

if ss_overnight_is_running; then
  EXISTING_PID=$(cat "$PID_FILE")
  echo "❌ overnight: already running (pid=${EXISTING_PID})" >&2
  exit 4
fi

echo "$$" > "$PID_FILE"
ss_overnight_state_init "$FEATURE_ID"
ss_overnight_rotate_log
ss_overnight_log "── overnight run start ─────────────────────────────"
ss_overnight_log "feature:  $FEATURE_ID"
ss_overnight_log "timeout:  ${TIMEOUT_SECONDS}s"
ss_overnight_log "pid:      $$"

# Cleanup hooks for every exit path
finalize() {
  local verdict="$1"
  local exit_code="$2"
  local notes="$3"
  local now
  now=$(date -Iseconds 2>/dev/null || date)
  ss_overnight_set finished_at "$now"
  ss_overnight_set exit_code "$exit_code"
  ss_overnight_set verdict "$verdict"
  ss_overnight_set notes "$notes"
  ss_overnight_log "── overnight run end (verdict=${verdict}, exit=${exit_code}) ─"
  rm -f "$PID_FILE" 2>/dev/null || true

  if declare -f ss_notify >/dev/null 2>&1; then
    case "$verdict" in
      success)
        ss_notify success "SpecSwarm overnight: $FEATURE_ID" "$notes" || true
        ;;
      blocked|aborted|timeout|partial)
        ss_notify urgent "SpecSwarm overnight: $FEATURE_ID ${verdict}" "$notes" || true
        ;;
    esac
  fi
}
trap 'finalize "aborted" 130 "interrupted by signal"' INT TERM

# ─── Phase 1: Preflight ─────────────────────────────────────────────────────
ss_overnight_log "running preflight (allow_dirty=${ALLOW_DIRTY})"
PREFLIGHT_OUTPUT=$(ss_overnight_preflight "$FEATURE_DIR" "$ALLOW_DIRTY" 2>&1 || true)
echo "$PREFLIGHT_OUTPUT" >> "$LOG_FILE"

if ! echo "$PREFLIGHT_OUTPUT" | grep -qE 'STATUS:[[:space:]]+✅|STATUS:[[:space:]]+⚠️'; then
  finalize blocked 1 "preflight blocked; see ${LOG_FILE}"
  exit 1
fi

# ─── Phase 2: Autonomous claude --print dispatch ────────────────────────────
START_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "")
ss_overnight_log "start commit: ${START_COMMIT:0:12}"
ss_overnight_log "dispatching headless claude --print (timeout ${TIMEOUT_SECONDS}s)"

AUTONOMOUS_PROMPT=$(cat <<EOF
You are running an autonomous SpecSwarm overnight chunk for feature ${FEATURE_ID}.

Pre-conditions verified by /ss:overnight preflight:
- spec.md, plan.md, tasks.md are present
- decision-sheet.md is locked (read it for any decision you need to make)
- Git working tree is clean (or --allow-dirty acknowledged)

STRICT RULES (read these twice):
1. Do NOT call AskUserQuestion under any circumstances. If a strategic
   decision arises that isn't already locked in
   ${FEATURE_DIR}/decision-sheet.md, STOP work, write a short
   summary to ${FEATURE_DIR}/overnight-unanswered.md describing what
   couldn't be answered, and exit. The user will resolve it in the morning.

2. Do NOT run /ss:ship. Squash merge requires human sign-off. Leave the
   feature branch ready for /ss:ship.

3. Do NOT push to origin. Commits stay local for morning review.

WORKFLOW (run in order; stop and exit at first failure):
  1. /ss:preflight ${FEATURE_NUM}       — deterministic checks (any FAIL → exit early)
  2. /ss:implement                      — execute tasks from tasks.md
  3. /ss:verify --all                   — adversarial verification per task
  4. /ss:retrospective ${FEATURE_NUM}   — distill lessons into memory

At the end, print a single-line summary:
  OVERNIGHT_RESULT: <success|partial|blocked> <one-line notes>

The user has stepped away for the night. They are not watching this run.
EOF
)

OVERNIGHT_OUTPUT_FILE="${FEATURE_DIR}/overnight.output.log"

# Use timeout(1) to enforce the wall-clock cap. claude --print reads stdin.
set +e
echo "$AUTONOMOUS_PROMPT" | timeout --signal=TERM "${TIMEOUT_SECONDS}s" claude --print \
  > "$OVERNIGHT_OUTPUT_FILE" 2>> "$LOG_FILE"
CLAUDE_EXIT=$?
set -e

ss_overnight_log "claude --print exited with code ${CLAUDE_EXIT}"

# ─── Phase 3: Classify result ───────────────────────────────────────────────
END_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "")
COMMITS_ADDED=$(git -C "$REPO_ROOT" rev-list --count "${START_COMMIT}..${END_COMMIT}" 2>/dev/null || echo 0)
ss_overnight_log "end commit:   ${END_COMMIT:0:12} (${COMMITS_ADDED} new commit(s))"

case "$CLAUDE_EXIT" in
  0)
    # Look for an OVERNIGHT_RESULT line in the output
    RESULT_LINE=$(grep -E '^OVERNIGHT_RESULT:' "$OVERNIGHT_OUTPUT_FILE" 2>/dev/null | tail -n1)
    if echo "$RESULT_LINE" | grep -q 'success'; then
      finalize success 0 "${COMMITS_ADDED} commit(s); $(echo "$RESULT_LINE" | sed -E 's/^OVERNIGHT_RESULT:[[:space:]]*//;s/^success[[:space:]]*//')"
      exit 0
    elif echo "$RESULT_LINE" | grep -q 'partial'; then
      finalize partial 0 "${COMMITS_ADDED} commit(s); $(echo "$RESULT_LINE" | sed -E 's/^OVERNIGHT_RESULT:[[:space:]]*//;s/^partial[[:space:]]*//')"
      exit 2
    else
      # No explicit OVERNIGHT_RESULT line — infer from commits
      if [ "$COMMITS_ADDED" -gt 0 ]; then
        finalize partial 0 "${COMMITS_ADDED} commits landed but no OVERNIGHT_RESULT line; review output"
        exit 2
      else
        finalize blocked 0 "claude exited 0 but no commits landed; review output"
        exit 2
      fi
    fi
    ;;
  124|143)
    finalize timeout 3 "wall-clock timeout after ${TIMEOUT_SECONDS}s; ${COMMITS_ADDED} commit(s) landed"
    exit 3
    ;;
  *)
    finalize aborted "$CLAUDE_EXIT" "claude --print exited ${CLAUDE_EXIT}; ${COMMITS_ADDED} commit(s) landed"
    exit 2
    ;;
esac
