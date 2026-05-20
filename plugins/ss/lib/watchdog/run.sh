#!/bin/bash
# SpecSwarm Watchdog Daemon (v7.9.0)
#
# Background polling loop. Calls check-cycle.sh on every tick, sleeps, repeats.
# Survives terminal close via nohup+setsid (handled by the launching command).
# Exits cleanly on SIGTERM (writes a final log line, removes PID file).
#
# Invoked by /ss:watchdog start. Do not run this directly unless you know
# what you're doing — it's designed to be detached.

set -e

PLUGIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/watchdog/state.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/watchdog/check-cycle.sh"

PID_FILE=$(ss_watchdog_pid_file)
LOG_FILE=$(ss_watchdog_log_file)

# Write our PID
echo "$$" > "$PID_FILE"
ss_watchdog_log "daemon started (pid=$$, interval=$(ss_watchdog_get interval)s, with_verify=$(ss_watchdog_get with_verify))"

# Clean shutdown on SIGTERM/SIGINT
cleanup() {
  ss_watchdog_log "daemon shutting down (received signal)"
  rm -f "$PID_FILE" 2>/dev/null || true
  exit 0
}
trap cleanup TERM INT

# Main loop
INTERVAL=$(ss_watchdog_get interval)
INTERVAL=${INTERVAL:-30}

CHECK_SCRIPT="${PLUGIN_DIR}/lib/watchdog/check-cycle.sh"

while true; do
  # Bounded — never let a single cycle hang the loop
  if ! timeout 60 bash "$CHECK_SCRIPT" >> "$LOG_FILE" 2>&1; then
    ss_watchdog_log "check-cycle returned non-zero or timed out — continuing loop"
  fi
  sleep "$INTERVAL"
done
