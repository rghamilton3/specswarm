---
description: Run a SpecSwarm chunk autonomously while you sleep. Combines pre-batched decisions (v7.6.0) + verification queue (v7.4.0) + headless `claude --print` to execute /ss:preflight → /ss:implement → /ss:verify → /ss:retrospective without user input. Default mode is --check (validate readiness). --exec opt-in actually runs autonomously. Designed for cron / systemd / launchd invocation.
effort: medium
args:
  - name: subcommand
    description: One of check, status, logs, exec, abort, schedule. Default is check.
    required: false
  - name: feature_num
    description: Feature number to run (e.g., 002). Defaults to current branch's NNN-slug.
    required: false
  - name: --timeout
    description: Wall-clock cap in seconds for the headless Claude run. Default 28800 (8 hours).
    required: false
  - name: --allow-dirty
    description: Allow autonomous run even if git working tree has uncommitted changes. Default false.
    required: false
  - name: --tail
    description: Lines to tail with the logs subcommand. Default 60.
    required: false
---

# SpecSwarm Overnight Autonomous Execution

Marty's most ambitious automation. Pre-batch decisions before bed, schedule this command to run between 10pm-6am, wake to a green PR or a phone notification flagging exactly what needs attention.

**This is the most invasive command in v7.x** — it spawns a long-running headless Claude session that costs real tokens and lands real commits. Conservative defaults: `--check` mode validates readiness without executing. `--exec` is the explicit opt-in.

**Architectural reality check:** The `/schedule` plugin runs scheduled agents in **Anthropic's remote infrastructure** — they cannot touch a local filesystem. The right scheduler for "run /ss:implement on my local repo overnight" is the LOCAL OS scheduler: cron (Linux/macOS), systemd timer (Linux), launchd (macOS). `/ss:overnight --schedule` prints copy-paste snippets for all three.

## Subcommand dispatch

```bash
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/features-location.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/overnight/state.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/overnight/preflight.sh"

# Parse args
SUBCOMMAND="check"
FEATURE_NUM=""
TIMEOUT=28800
ALLOW_DIRTY=false
TAIL_LINES=60

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout)     TIMEOUT="$2";     shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=true; shift ;;
    --tail)        TAIL_LINES="$2";  shift 2 ;;
    check|status|logs|exec|abort|schedule)
      SUBCOMMAND="$1"; shift ;;
    -h|--help)
      cat <<EOF
Usage: /ss:overnight [SUBCOMMAND] [FEATURE_NUM] [options]

Subcommands:
  check     (default) Validate readiness without executing
  status              Show last/current overnight run state
  logs                Tail .specswarm/overnight.log
  exec                EXEC: dispatch headless claude --print (costs tokens)
  abort               Send SIGTERM to a running overnight run
  schedule            Print cron/systemd/launchd snippets

Options:
  --timeout N       Wall-clock cap in seconds (default 28800 = 8h)
  --allow-dirty     Permit uncommitted working tree changes
  --tail N          Lines for logs subcommand (default 60)

State lives at: .specswarm/overnight.{pid,log,state}
Output log:     <feature_dir>/overnight.output.log

Examples:
  /ss:overnight                       # check readiness for current feature
  /ss:overnight check 003
  /ss:overnight schedule              # show cron/systemd/launchd snippets
  /ss:overnight exec --timeout 14400  # run NOW with 4h cap
  /ss:overnight status
  /ss:overnight logs --tail 200
  /ss:overnight abort
EOF
      exit 0
      ;;
    *)
      [ -z "$FEATURE_NUM" ] && FEATURE_NUM="$1"
      shift
      ;;
  esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Resolve feature unless we're in a mode that doesn't need it
case "$SUBCOMMAND" in
  status|logs|abort|schedule)
    : ;;
  *)
    if [ -z "$FEATURE_NUM" ]; then
      BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
      FEATURE_NUM=$(echo "$BRANCH" | grep -oE '^[0-9]{3}' || echo "")
    fi
    if [ -z "$FEATURE_NUM" ]; then
      get_features_dir "$REPO_ROOT"
      FEATURE_NUM=$(find "$FEATURES_DIR" -maxdepth 1 -type d -name '[0-9][0-9][0-9]-*' 2>/dev/null \
        | sort | tail -1 | xargs -n1 basename 2>/dev/null \
        | grep -oE '^[0-9]{3}' || echo "")
    fi
    if [ -z "$FEATURE_NUM" ]; then
      echo "❌ No feature number provided and no feature dirs found." >&2
      exit 2
    fi
    if ! find_feature_dir "$FEATURE_NUM" "$REPO_ROOT"; then
      echo "❌ Feature $FEATURE_NUM not found." >&2
      exit 2
    fi
    ;;
esac
```

## `check` — validate readiness without executing (default)

```bash
case "$SUBCOMMAND" in
  check)
    ss_overnight_preflight "$FEATURE_DIR" "$ALLOW_DIRTY"
    rc=$?
    echo ""
    if [ "$rc" -eq 0 ]; then
      echo "Next: /ss:overnight exec   (or wire up cron via /ss:overnight schedule)"
    else
      echo "Resolve the BLOCKED items above before scheduling."
    fi
    exit "$rc"
    ;;
```

## `status` — show last/current run state

```bash
  status)
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SpecSwarm overnight status"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if ss_overnight_is_running; then
      PID=$(cat "$(ss_overnight_pid_file)")
      echo "  state:       🟢 running"
      echo "  pid:         ${PID}"
    else
      echo "  state:       ⚫ idle"
    fi
    echo "  pid_file:    $(ss_overnight_pid_file)"
    echo "  log_file:    $(ss_overnight_log_file)"
    echo "  state_file:  $(ss_overnight_state_file)"
    echo ""

    STATE_FILE=$(ss_overnight_state_file)
    if [ -f "$STATE_FILE" ]; then
      echo "Persisted state:"
      while IFS='=' read -r k v; do
        [ -z "$k" ] && continue
        printf "  %-14s %s\n" "$k" "$v"
      done < "$STATE_FILE"
    else
      echo "(no run has completed yet)"
    fi
    ;;
```

## `logs` — tail overnight log

```bash
  logs)
    LOG=$(ss_overnight_log_file)
    if [ ! -f "$LOG" ]; then
      echo "(no log file at $LOG)"
      exit 0
    fi
    tail -n "$TAIL_LINES" "$LOG"
    ;;
```

## `exec` — dispatch headless run NOW (EXPENSIVE, opt-in)

```bash
  exec)
    if ss_overnight_is_running; then
      echo "⚠️  Overnight run already in progress (pid=$(cat "$(ss_overnight_pid_file)"))." >&2
      echo "    Use /ss:overnight status to check, or /ss:overnight abort to cancel." >&2
      exit 4
    fi

    echo "🌙 Dispatching headless overnight run for $(basename "$FEATURE_DIR")"
    echo "   timeout:       ${TIMEOUT}s"
    echo "   allow_dirty:   ${ALLOW_DIRTY}"
    echo "   log:           $(ss_overnight_log_file)"
    echo ""
    echo "Detaching (nohup + setsid). Returns immediately; check status with /ss:overnight status"
    echo ""

    RUN_SCRIPT="${PLUGIN_DIR}/lib/overnight/run.sh"
    DIRTY_ARG=""
    [ "$ALLOW_DIRTY" = "true" ] && DIRTY_ARG="--allow-dirty"

    # Detached so the foreground shell returns immediately
    nohup setsid bash "$RUN_SCRIPT" "$FEATURE_NUM" --timeout "$TIMEOUT" $DIRTY_ARG \
      </dev/null >> "$(ss_overnight_log_file)" 2>&1 &
    disown 2>/dev/null || true
    sleep 1

    if ss_overnight_is_running; then
      echo "✅ Overnight run started (pid=$(cat "$(ss_overnight_pid_file)"))"
      echo "   Tail: /ss:overnight logs"
      echo "   Stop: /ss:overnight abort"
    else
      echo "⚠️  Run may have failed to start. Check the log:"
      tail -n 20 "$(ss_overnight_log_file)"
    fi
    ;;
```

## `abort` — kill in-progress run

```bash
  abort)
    if ! ss_overnight_is_running; then
      echo "ℹ️  No overnight run in progress."
      exit 0
    fi
    PID=$(cat "$(ss_overnight_pid_file)")
    echo "Aborting overnight run (pid=${PID})..."
    kill "$PID" 2>/dev/null || true

    for _ in 1 2 3 4 5 6; do
      if ! kill -0 "$PID" 2>/dev/null; then break; fi
      sleep 0.5
    done

    if kill -0 "$PID" 2>/dev/null; then
      echo "⚠️  Process didn't exit cleanly; sending SIGKILL"
      kill -9 "$PID" 2>/dev/null || true
    fi
    rm -f "$(ss_overnight_pid_file)" 2>/dev/null || true
    echo "✅ Overnight run aborted"
    ;;
```

## `schedule` — print cron / systemd / launchd snippets

```bash
  schedule)
    RUN_SCRIPT="${PLUGIN_DIR}/lib/overnight/run.sh"
    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Scheduling snippets — pick one per OS preference
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

────────────  cron (Linux + macOS)  ────────────────
Add via \`crontab -e\` (10pm nightly, Mon-Fri):

  0 22 * * 1-5 cd "${REPO_ROOT}" && bash "${RUN_SCRIPT}" --allow-dirty >> .specswarm/overnight.cron.log 2>&1

────────────  systemd timer (Linux)  ───────────────
Save as ~/.config/systemd/user/specswarm-overnight.service:

  [Unit]
  Description=SpecSwarm overnight autonomous chunk

  [Service]
  Type=oneshot
  WorkingDirectory=${REPO_ROOT}
  ExecStart=/usr/bin/bash ${RUN_SCRIPT} --allow-dirty

Save as ~/.config/systemd/user/specswarm-overnight.timer:

  [Unit]
  Description=Nightly SpecSwarm chunk

  [Timer]
  OnCalendar=Mon-Fri 22:00
  Persistent=true

  [Install]
  WantedBy=timers.target

Enable:
  systemctl --user daemon-reload
  systemctl --user enable --now specswarm-overnight.timer

────────────  launchd (macOS)  ─────────────────────
Save as ~/Library/LaunchAgents/com.specswarm.overnight.plist:

  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>Label</key><string>com.specswarm.overnight</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${RUN_SCRIPT}</string>
      <string>--allow-dirty</string>
    </array>
    <key>WorkingDirectory</key><string>${REPO_ROOT}</string>
    <key>StartCalendarInterval</key>
    <dict>
      <key>Hour</key><integer>22</integer>
      <key>Minute</key><integer>0</integer>
    </dict>
  </dict>
  </plist>

Load with:
  launchctl load ~/Library/LaunchAgents/com.specswarm.overnight.plist

────────────  /schedule plugin  ────────────────────
NOTE: /schedule runs agents in Anthropic's remote infrastructure — they
CANNOT touch your local filesystem. /schedule is NOT appropriate for
running /ss:overnight against your local repo. Use cron/systemd/launchd
above for the actual execution.

/schedule CAN still be useful as a 9pm reminder ping:
  /schedule add "Remind me to run /ss:decisions before bed"

EOF
    ;;
esac
```

## How v7.10.0 fits with v7.4.0 + v7.6.0 + v7.9.0

The full unattended-chunk workflow:

1. **Day phase (~9pm):** Marty runs `/ss:decisions` to pre-batch the night's strategic answers
2. **9:50pm:** Marty optionally starts `/ss:watchdog start` for redundant monitoring
3. **10pm:** cron / systemd / launchd fires `lib/overnight/run.sh`
4. **10pm-6am:** headless Claude session:
   - Runs `/ss:preflight` (deterministic, free)
   - Runs `/ss:implement` (uses decision-sheet.md for any choice; refuses to ask)
   - Runs `/ss:verify --all` (spec-mentor adversarial per task)
   - Runs `/ss:retrospective` (writes durable memory)
5. **Overnight notifications:**
   - On success: `ss_notify success` → Marty's phone shows "P1.3 succeeded; ready for /ss:ship"
   - On any flag/timeout/error: `ss_notify urgent` → Marty's phone shows "P1.3 needs review"
6. **Morning:** Marty checks `/ss:overnight status`, reviews `<feature_dir>/overnight.output.log`, runs `/ss:ship` if green

If the run blocks on an unanswered decision, `overnight-unanswered.md` lands in the feature dir for Marty's morning review.

## Project-agnostic guarantees

- Feature resolution via `find_feature_dir` — no hardcoded paths
- All artifact checks operate on `.specswarm/features/NNN-name/*` SpecSwarm conventions
- `claude` CLI dependency surfaced explicitly in preflight (`exec` mode aborts cleanly if absent)
- ss_notify graceful fallback chain (v7.2.0)
- Scheduler-agnostic: cron / systemd / launchd / any tool that can call a bash script
- Single-instance lock prevents accidental double-runs
- `--timeout` caps wall-clock so a stuck run can't burn unlimited tokens

## What this command does NOT do

- Does not run `/ss:ship` (requires human sign-off in the morning)
- Does not push to origin (commits stay local)
- Does not auto-resolve unanswered decisions (it stops and waits)
- Does not work with `/schedule` plugin for the actual execution (remote agents can't see local filesystem) — see the `schedule` subcommand for the reasoning
- Does not auto-restart on reboot (re-add the cron/systemd/launchd config if your machine reboots)
