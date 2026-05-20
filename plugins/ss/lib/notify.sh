#!/bin/bash
# SpecSwarm Notification Helper
#
# Project-agnostic notification dispatch with cascading fallbacks:
#   Tier 1: convocli-notifier plugin script (if installed)
#   Tier 2: notify-send (Linux + libnotify)
#   Tier 3: osascript (macOS native)
#   Tier 4: terminal bell + stderr message
#
# Public API:
#   ss_notify_available
#     Exit 0 if any notification mechanism is available, 1 otherwise.
#
#   ss_notify [URGENCY] "<title>" "<message>"
#     URGENCY one of: urgent, success, info (default: info)
#     Maps to sound: urgent→bell, success→complete, info→chime
#     Debounced 10 seconds per (urgency, title) tuple.
#     Returns 0 if any tier fired; 1 if all tiers were unavailable.
#
# Design notes:
#   - Pure bash; no python/node dependency
#   - All tiers are non-blocking — never let a notification failure break a command
#   - Debounce is per-user (state in ~/.cache/specswarm/notify/) so concurrent
#     SpecSwarm runs across projects share throttling

set -e

# ─────────────────────────────────────────────────────────────────────────────
# Tier 1: Locate the convocli-notifier plugin's play-notification.sh
# Auto-discovers across cache (versioned) and marketplace (canonical) paths so
# we don't hardcode a version number.
# ─────────────────────────────────────────────────────────────────────────────

ss_notify_plugin_script() {
  local p
  for p in "$HOME/.claude/plugins/cache/convocli-notifier/notifier"/*/scripts/play-notification.sh; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  p="$HOME/.claude/plugins/marketplaces/convocli-notifier/plugins/notifier/scripts/play-notification.sh"
  [ -f "$p" ] && { echo "$p"; return 0; }
  return 1
}

ss_notify_available() {
  ss_notify_plugin_script >/dev/null 2>&1 && return 0
  command -v notify-send >/dev/null 2>&1 && return 0
  command -v osascript >/dev/null 2>&1 && return 0
  command -v termux-notification >/dev/null 2>&1 && return 0
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Debounce: avoid duplicate notifications within DEBOUNCE_SECONDS for the same
# (urgency, title) tuple. State persisted at ~/.cache/specswarm/notify/.
# ─────────────────────────────────────────────────────────────────────────────

__ss_notify_should_fire() {
  local urgency="$1"
  local title="$2"
  local debounce_seconds="${SS_NOTIFY_DEBOUNCE:-10}"

  local cache_dir="${HOME}/.cache/specswarm/notify"
  mkdir -p "$cache_dir" 2>/dev/null || return 0

  # Hash the tuple — sha256 if available, else basic sanitize
  local key
  if command -v sha256sum >/dev/null 2>&1; then
    key=$(printf '%s|%s' "$urgency" "$title" | sha256sum | cut -c1-16)
  else
    key=$(printf '%s_%s' "$urgency" "$title" | tr -c 'a-zA-Z0-9_' '_' | head -c 32)
  fi

  local stamp_file="${cache_dir}/${key}.ts"
  local now
  now=$(date +%s)

  if [ -f "$stamp_file" ]; then
    local last
    last=$(cat "$stamp_file" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt "$debounce_seconds" ]; then
      return 1
    fi
  fi

  echo "$now" > "$stamp_file" 2>/dev/null || true
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Urgency → sound mapping (for tier 1 notifier plugin)
# ─────────────────────────────────────────────────────────────────────────────

__ss_notify_sound_for() {
  case "$1" in
    urgent) echo "bell" ;;
    success) echo "complete" ;;
    info|*) echo "chime" ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Public: ss_notify
# ─────────────────────────────────────────────────────────────────────────────

ss_notify() {
  local urgency="info"
  case "${1:-}" in
    urgent|success|info)
      urgency="$1"; shift
      ;;
    --urgent) urgency="urgent"; shift ;;
    --success) urgency="success"; shift ;;
    --info) urgency="info"; shift ;;
  esac

  local title="${1:-SpecSwarm}"
  local message="${2:-}"

  __ss_notify_should_fire "$urgency" "$title" || return 0

  local fired=1

  # Tier 1: convocli-notifier plugin
  local notifier_script
  if notifier_script=$(ss_notify_plugin_script 2>/dev/null); then
    local sound
    sound=$(__ss_notify_sound_for "$urgency")
    # The plugin reads NOTIFIER_SOUND from env (overridable per-call).
    # Suppress its 2s debounce via NOTIFIER_PREVIEW_MODE so urgency-stacked
    # notifications can fire back-to-back when we want them to.
    NOTIFIER_SOUND="$sound" NOTIFIER_PREVIEW_MODE=true \
      bash "$notifier_script" >/dev/null 2>&1 &
    fired=0
  fi

  # Tier 2: notify-send (Linux libnotify) — also fires when tier 1 fires,
  # so the user sees a desktop banner with title/message, not just hears a sound
  if command -v notify-send >/dev/null 2>&1; then
    local nurg="normal"
    [ "$urgency" = "urgent" ] && nurg="critical"
    notify-send -u "$nurg" -- "$title" "$message" >/dev/null 2>&1 &
    fired=0
  fi

  # Tier 3: macOS native
  if [ "$fired" != 0 ] && command -v osascript >/dev/null 2>&1; then
    local sound_name="Pop"
    [ "$urgency" = "urgent" ] && sound_name="Sosumi"
    [ "$urgency" = "success" ] && sound_name="Glass"
    osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"$sound_name\"" \
      >/dev/null 2>&1 &
    fired=0
  fi

  # Tier 4: terminal bell + stderr
  if [ "$fired" != 0 ]; then
    printf '\a' >&2
    case "$urgency" in
      urgent) printf '🚫 %s: %s\n' "$title" "$message" >&2 ;;
      success) printf '✅ %s: %s\n' "$title" "$message" >&2 ;;
      *) printf '🔔 %s: %s\n' "$title" "$message" >&2 ;;
    esac
    fired=0
  fi

  return "$fired"
}

# If invoked directly as a script (not sourced), forward args to ss_notify.
# Lets the slash command call it cleanly:  bash notify.sh urgent "title" "msg"
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  ss_notify "$@"
fi
