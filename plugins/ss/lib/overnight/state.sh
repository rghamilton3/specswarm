#!/bin/bash
# SpecSwarm Overnight State (v7.10.0)
#
# Per-project state at .specswarm/overnight.{pid,log,state}. Same pattern
# as v7.9.0 watchdog/state.sh — keep them parallel for cognitive ease.
#
# State file format (key=value):
#   started_at=<ISO ts>
#   finished_at=<ISO ts>
#   feature=<feature_id>
#   exit_code=<int>
#   verdict=<success|blocked|aborted|timeout|partial>
#   notes=<one-line summary>
#
# Public API:
#   ss_overnight_pid_file
#   ss_overnight_log_file
#   ss_overnight_state_file
#   ss_overnight_is_running
#   ss_overnight_get <key>
#   ss_overnight_set <key> <value>
#   ss_overnight_log <msg>
#   ss_overnight_rotate_log
#   ss_overnight_state_init <feature_id>

set -e

__SS_ON_DIR() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local dir="${repo_root}/.specswarm"
  mkdir -p "$dir" 2>/dev/null || true
  echo "$dir"
}

ss_overnight_pid_file()   { echo "$(__SS_ON_DIR)/overnight.pid"; }
ss_overnight_log_file()   { echo "$(__SS_ON_DIR)/overnight.log"; }
ss_overnight_state_file() { echo "$(__SS_ON_DIR)/overnight.state"; }

ss_overnight_is_running() {
  local pid_file
  pid_file=$(ss_overnight_pid_file)
  [ -f "$pid_file" ] || return 1
  local pid
  pid=$(cat "$pid_file" 2>/dev/null)
  [ -z "$pid" ] && return 1
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  # Stale PID file
  rm -f "$pid_file" 2>/dev/null || true
  return 1
}

ss_overnight_get() {
  local key="$1"
  local file
  file=$(ss_overnight_state_file)
  [ -f "$file" ] || return 0
  grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2-
}

ss_overnight_set() {
  local key="$1"
  local value="$2"
  local file
  file=$(ss_overnight_state_file)
  touch "$file" 2>/dev/null || true

  local tmp
  tmp=$(mktemp 2>/dev/null) || return 1
  grep -vE "^${key}=" "$file" 2>/dev/null > "$tmp" || true
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file" 2>/dev/null || true
}

ss_overnight_log() {
  local msg="$*"
  local file
  file=$(ss_overnight_log_file)
  local ts
  ts=$(date -Iseconds 2>/dev/null || date)
  printf '[%s] %s\n' "$ts" "$msg" >> "$file" 2>/dev/null || true
}

ss_overnight_rotate_log() {
  local file
  file=$(ss_overnight_log_file)
  [ -f "$file" ] || return 0
  local max_bytes=5242880  # 5 MB — overnight runs produce more output than watchdog
  local size
  size=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null || echo 0)
  if [ "$size" -gt "$max_bytes" ]; then
    local tmp
    tmp=$(mktemp 2>/dev/null) || return 0
    tail -c "$max_bytes" "$file" > "$tmp" 2>/dev/null
    mv "$tmp" "$file" 2>/dev/null || true
    ss_overnight_log "log rotated (was ${size} bytes)"
  fi
}

ss_overnight_state_init() {
  local feature_id="$1"
  local file
  file=$(ss_overnight_state_file)
  local now
  now=$(date -Iseconds 2>/dev/null || date)
  cat > "$file" <<EOF
started_at=${now}
finished_at=
feature=${feature_id}
exit_code=
verdict=running
notes=
EOF
}
