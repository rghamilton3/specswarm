#!/bin/bash
# SpecSwarm Watchdog State (v7.9.0)
#
# Single source of truth for the watchdog's per-project state. Each project
# has its own daemon writing to .specswarm/watchdog.{pid,log,state} — no
# cross-project state.
#
# State file format (key=value):
#   last_commit=<sha>
#   last_queue_pending=<int>
#   last_queue_flagged=<int>
#   last_check_at=<ISO timestamp>
#   started_at=<ISO timestamp>
#
# Public API:
#   ss_watchdog_pid_file
#   ss_watchdog_log_file
#   ss_watchdog_state_file
#   ss_watchdog_is_running   — exit 0 if PID file points at a live process
#   ss_watchdog_get <key>    — read a state field
#   ss_watchdog_set <key> <value>  — write a state field (atomic)
#   ss_watchdog_log <msg>    — append a timestamped log line
#   ss_watchdog_rotate_log   — truncate log to last 1MB
#   ss_watchdog_state_init   — clear/seed state on daemon start

set -e

__SS_WD_DIR() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local dir="${repo_root}/.specswarm"
  mkdir -p "$dir" 2>/dev/null || true
  echo "$dir"
}

ss_watchdog_pid_file() {
  echo "$(__SS_WD_DIR)/watchdog.pid"
}

ss_watchdog_log_file() {
  echo "$(__SS_WD_DIR)/watchdog.log"
}

ss_watchdog_state_file() {
  echo "$(__SS_WD_DIR)/watchdog.state"
}

ss_watchdog_is_running() {
  local pid_file
  pid_file=$(ss_watchdog_pid_file)
  [ -f "$pid_file" ] || return 1
  local pid
  pid=$(cat "$pid_file" 2>/dev/null)
  [ -z "$pid" ] && return 1
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  # Stale PID file — clean it up
  rm -f "$pid_file" 2>/dev/null || true
  return 1
}

ss_watchdog_get() {
  local key="$1"
  local file
  file=$(ss_watchdog_state_file)
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2-
}

ss_watchdog_set() {
  local key="$1"
  local value="$2"
  local file
  file=$(ss_watchdog_state_file)
  touch "$file" 2>/dev/null || true

  local tmp
  tmp=$(mktemp 2>/dev/null) || return 1

  # Preserve all other keys; replace or add the one we're setting
  grep -vE "^${key}=" "$file" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file" 2>/dev/null || true
}

ss_watchdog_log() {
  local msg="$*"
  local file
  file=$(ss_watchdog_log_file)
  local ts
  ts=$(date -Iseconds 2>/dev/null || date)
  printf '[%s] %s\n' "$ts" "$msg" >> "$file" 2>/dev/null || true
}

ss_watchdog_rotate_log() {
  local file
  file=$(ss_watchdog_log_file)
  [ -f "$file" ] || return 0

  local max_bytes=1048576  # 1 MB
  local size
  size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0)
  if [ "$size" -gt "$max_bytes" ]; then
    # Keep the last 1MB
    local tmp
    tmp=$(mktemp 2>/dev/null) || return 0
    tail -c "$max_bytes" "$file" > "$tmp" 2>/dev/null
    mv "$tmp" "$file" 2>/dev/null || true
    ss_watchdog_log "log rotated (was ${size} bytes)"
  fi
}

ss_watchdog_state_init() {
  local interval="${1:-30}"
  local with_verify="${2:-false}"
  local file
  file=$(ss_watchdog_state_file)

  local now
  now=$(date -Iseconds 2>/dev/null || date)

  cat > "$file" <<EOF
started_at=${now}
last_check_at=${now}
last_commit=
last_queue_pending=0
last_queue_flagged=0
interval=${interval}
with_verify=${with_verify}
EOF
}
