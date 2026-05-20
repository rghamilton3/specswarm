---
description: Fire a SpecSwarm notification (sound + desktop banner + optional phone vibrate via Termux) with cascading fallbacks. Useful inside long workflows to ping yourself when a chunk completes or a decision is needed.
effort: low
args:
  - name: message
    description: The notification message. Will be displayed in the desktop banner / heard via sound.
    required: false
  - name: --title
    description: Title for the notification. Defaults to "SpecSwarm".
    required: false
  - name: --urgent
    description: Mark as urgent — uses the bell sound (or 'critical' urgency on libnotify, 'Sosumi' on macOS).
    required: false
  - name: --success
    description: Mark as success — uses the complete sound (or 'Glass' on macOS).
    required: false
  - name: --info
    description: Mark as info — uses the chime sound (default).
    required: false
---

# SpecSwarm Notify

Sends a notification using whatever mechanism is available — convocli-notifier plugin (preferred), then `notify-send` (Linux libnotify), then `osascript` (macOS), then a terminal bell + stderr message.

**Project-agnostic** — works on any project regardless of installed plugins. Silent no-op only if none of the four tiers is available, which is rare.

## Fire the notification

```bash
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${PLUGIN_DIR}/lib/notify.sh"

if [ ! -f "$LIB" ]; then
  echo "❌ notify.sh helper not found at $LIB" >&2
  exit 2
fi

# Parse arguments
URGENCY="info"
TITLE="SpecSwarm"
MESSAGE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --urgent) URGENCY="urgent"; shift ;;
    --success) URGENCY="success"; shift ;;
    --info) URGENCY="info"; shift ;;
    --title) TITLE="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: /ss:notify [--urgent|--success|--info] [--title TITLE] [MESSAGE]

Fires a notification using the best-available channel.

Examples:
  /ss:notify "P1.3 ready for review"
  /ss:notify --urgent "Build broke at T012"
  /ss:notify --success --title "Chunk shipped" "P1.3 merged to main"
EOF
      exit 0
      ;;
    *)
      if [ -z "$MESSAGE" ]; then
        MESSAGE="$1"
      else
        MESSAGE="$MESSAGE $1"
      fi
      shift
      ;;
  esac
done

# shellcheck disable=SC1090
source "$LIB"

if ! ss_notify_available; then
  echo "⚠️  No notification mechanism available. Falling back to terminal bell + stderr."
fi

if ss_notify "$URGENCY" "$TITLE" "$MESSAGE"; then
  echo "🔔 Notified [${URGENCY}] ${TITLE}: ${MESSAGE}"
else
  echo "(notification suppressed — debounced within last ${SS_NOTIFY_DEBOUNCE:-10}s)"
fi
```

## Why this exists

The convocli-notifier plugin (when installed) already fires on every Claude Code Stop event — so you get a chime each time Claude finishes responding. That's the baseline.

`/ss:notify` adds **semantic notifications** on top: differentiated sounds for urgent/success/info, plus the ability to fire from inside a long-running workflow at a specific moment (e.g., midway through `/ss:build` when a strategic decision is needed).

It's also wired into the SpecSwarm runtime:
- `/ss:preflight` automatically fires an `urgent` notification when overall result is FAIL
- Future: `/ss:build`, `/ss:ship` will fire on completion
- You can call it manually from any script or terminal: `bash plugins/ss/lib/notify.sh urgent "title" "msg"`

## Cascading fallbacks (priority order)

1. **convocli-notifier plugin** (`~/.claude/plugins/cache/convocli-notifier/notifier/*/scripts/play-notification.sh`)
   - Plays one of: bell.wav (urgent), complete.wav (success), chime.wav (info)
   - Cross-platform: Linux (paplay/aplay), macOS (afplay), Termux (vibrate)
2. **`notify-send`** (Linux libnotify desktop banner)
   - Maps urgent → `-u critical`
3. **`osascript`** (macOS native notification center)
   - Maps urgent → `Sosumi`, success → `Glass`, info → `Pop`
4. **Terminal bell + stderr** (always works as last resort)

Multiple tiers may fire concurrently — e.g., on Linux with the notifier plugin installed, you'll both hear the sound AND see a libnotify banner.

## Debounce

Notifications are throttled to one per 10 seconds per `(urgency, title)` tuple. Override per-invocation by setting `SS_NOTIFY_DEBOUNCE=N` in the environment before calling.

State persists at `~/.cache/specswarm/notify/`. Delete that directory to reset all debounce timers.

## Usage examples

```bash
# Default info ping
/ss:notify "P1.3 ready for review"

# Custom title
/ss:notify --title "Build complete" "P1.3 merged in 3m 42s"

# Urgent — cuts through, uses bell + critical urgency
/ss:notify --urgent "Build broke at T012 — needs Marty"

# Success — happy sound
/ss:notify --success "Tests green; ready to /ss:ship"

# Programmatic use from a script
bash $CLAUDE_PLUGIN_ROOT/lib/notify.sh urgent "Migration failed" "rollback step 3 timed out"
```
