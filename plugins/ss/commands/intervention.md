---
description: Capture a "wait, something feels off" moment as a durable memory file. Each intervention becomes training data for future SpecSwarm automation (preflight, spec-mentor, hooks). Today's manual catch → tomorrow's automatic catch.
effort: low
args:
  - name: noticed
    description: One-line summary of what you noticed. Becomes the file's description + filename slug. If omitted, an interactive flow collects all 4 fields.
    required: false
  - name: --should
    description: What kind of check should have caught this (verification angle).
    required: false
  - name: --prevent
    description: How automation could prevent it next time (suggested fix).
    required: false
  - name: --status
    description: open (default) | graduated (rule has shipped) | wontfix
    required: false
  - name: --feature
    description: Override the auto-detected feature (e.g., 003-custom-auth). Auto-detected from branch / build-loop.state otherwise.
    required: false
  - name: --task
    description: Override the auto-detected task ID (e.g., T011). Auto-detected from build-loop.state.
    required: false
  - name: --list
    description: List the most recent N (default 10) interventions instead of capturing a new one.
    required: false
---

# SpecSwarm Intervention Capture

Records a moment when you noticed something the automation missed. Each intervention is a structured 4-field observation:

1. **What I noticed** — the symptom you caught
2. **What should have caught this** — the verification angle
3. **How automation could prevent it next time** — a suggested fix or check
4. **Status** — open / graduated / wontfix

Over time, accumulated interventions become the "pattern library" that future automation (spec-mentor agent, new preflight checks, new constitution hooks) trains against. After 10–15 interventions in a project, the patterns repeat — and that's where new automation comes from.

## Write the intervention

```bash
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
source "${PLUGIN_DIR}/lib/intervention.sh"
# shellcheck disable=SC1090
source "${PLUGIN_DIR}/lib/notify.sh" 2>/dev/null || true

# Parse arguments
NOTICED=""
SHOULD=""
PREVENT=""
STATUS="open"
FEATURE_OVERRIDE=""
TASK_OVERRIDE=""
LIST_MODE=false
LIST_LIMIT=10

while [ $# -gt 0 ]; do
  case "$1" in
    --should)   SHOULD="$2";           shift 2 ;;
    --prevent)  PREVENT="$2";          shift 2 ;;
    --status)   STATUS="$2";           shift 2 ;;
    --feature)  FEATURE_OVERRIDE="$2"; shift 2 ;;
    --task)     TASK_OVERRIDE="$2";    shift 2 ;;
    --list)
      LIST_MODE=true
      shift
      # Optional numeric limit
      if [ "${1:-}" =~ ^[0-9]+$ ]; then LIST_LIMIT="$1"; shift; fi
      ;;
    -h|--help)
      cat <<EOF
Usage: /ss:intervention [NOTICED] [options]
       /ss:intervention --list [N]

Capture a "something feels off" moment as a durable memory file.

Options:
  --should TEXT      What check should have caught it (verification angle)
  --prevent TEXT     How automation could prevent it next time
  --status STATUS    open (default) | graduated | wontfix
  --feature ID       Override auto-detected feature
  --task ID          Override auto-detected task
  --list [N]         List recent interventions instead of capturing

Examples:
  /ss:intervention "plan.md says 43 columns but spec says 47"
  /ss:intervention "version pin doesn't exist" --should "verify against npm registry" --prevent "ship in /ss:preflight"
  /ss:intervention --status graduated --noticed "postgres.js drift" --prevent "/ss:preflight v7.1.0 catches it"
  /ss:intervention --list 5
EOF
      exit 0
      ;;
    *)
      if [ -z "$NOTICED" ]; then NOTICED="$1"; else NOTICED="$NOTICED $1"; fi
      shift
      ;;
  esac
done

# ─── List mode ────────────────────────────────────────────────────────────────
if [ "$LIST_MODE" = true ]; then
  echo "📋 Recent SpecSwarm interventions (last ${LIST_LIMIT}):"
  echo ""
  ss_intervention_list "$LIST_LIMIT"
  exit 0
fi

# ─── Capture mode ─────────────────────────────────────────────────────────────
DIR=$(ss_intervention_dir)

# Sniff current context
IFS=$'\t' read -r AUTO_FEATURE AUTO_TASK AUTO_BRANCH AUTO_COMMIT < <(ss_intervention_context)
FEATURE="${FEATURE_OVERRIDE:-$AUTO_FEATURE}"
TASK="${TASK_OVERRIDE:-$AUTO_TASK}"

# Interactive path: if NOTICED was not provided, signal to Claude to gather inputs
if [ -z "$NOTICED" ]; then
  echo "🎙️  Interactive intervention capture"
  echo ""
  echo "Context detected:"
  echo "  feature: ${FEATURE:-(none)}"
  echo "  task:    ${TASK:-(none)}"
  echo "  branch:  ${AUTO_BRANCH:-(none)}"
  echo "  commit:  ${AUTO_COMMIT:-(none)}"
  echo ""
  echo "Will write to: ${DIR}"
  echo ""
  echo "<<<INTERACTIVE>>>"
  echo "Please now use AskUserQuestion to collect 4 fields from the user:"
  echo "  1. 'What did you notice?' (the symptom)"
  echo "  2. 'What check should have caught this?' (verification angle)"
  echo "  3. 'How could automation prevent this next time?' (suggested fix)"
  echo "  4. 'Status?' — options: open | graduated | wontfix"
  echo "Then re-invoke /ss:intervention with all flags populated."
  echo "<<<END>>>"
  exit 10
fi

# Validate STATUS
case "$STATUS" in
  open|graduated|wontfix) ;;
  *) echo "❌ Invalid --status '${STATUS}' (use: open | graduated | wontfix)" >&2; exit 2 ;;
esac

# Fill missing fields with placeholders so the file is still useful
[ -z "$SHOULD" ]  && SHOULD="(not specified — fill in when you know)"
[ -z "$PREVENT" ] && PREVENT="(not specified — fill in when you know)"

# Generate filename + write
FILENAME=$(ss_intervention_filename "$NOTICED")
TARGET=$(ss_intervention_write "$DIR" "$FILENAME" "$NOTICED" "$SHOULD" "$PREVENT" "$STATUS" "$FEATURE" "$TASK")

# Update MEMORY.md index if present
ss_intervention_index_update "$DIR" "$FILENAME" "$NOTICED" 2>/dev/null || true

# Confirmation
echo ""
echo "✅ Intervention captured"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "File:    ${TARGET}"
echo "Feature: ${FEATURE:-(none)}"
echo "Task:    ${TASK:-(none)}"
echo "Status:  ${STATUS}"
echo ""
echo "Noticed: ${NOTICED}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Fire a quiet info-level notification (cheap signal that capture succeeded)
if declare -f ss_notify >/dev/null 2>&1; then
  ss_notify info "SpecSwarm intervention captured" "${NOTICED:0:80}" || true
fi
```

## How interventions feed automation

| Today (v7.3.0) | Tomorrow (planned) |
|---|---|
| Captured as `intervention_*.md` in your memory dir | `spec-mentor` agent reads them on every invocation |
| Classified as `kind=intervention` by `ss_memory_classify_kind` | New preflight checks codify recurring patterns |
| Indexed in `MEMORY.md` under "Interventions" section | Status `graduated` marks ones that have shipped |

The lifecycle:
1. **open** — captured, not yet codified anywhere
2. **graduated** — pattern was turned into a deterministic check, hook, or constitution principle
3. **wontfix** — judged not worth automating (e.g., one-off oddity, false alarm)

## Where the file is written (project-agnostic discovery)

1. **First memory dir declared in `.specswarm/references.md`** (preferred — matches existing SpecSwarm convention)
2. **`<repo-root>/memory/`** if it exists with a sibling `MEMORY.md`
3. **`<repo-root>/.specswarm/interventions/`** as a project-local fallback (created if missing, git-trackable)

Filename format: `intervention_YYYY-MM-DD_<slug>.md` where slug is derived from your "noticed" text.

## Auto-detected context

The command sniffs your current chunk context, so you don't have to type it:

- **Feature** — from current git branch (if `NNN-slug`), else `.specswarm/build-loop.state`, else most recent feature dir
- **Task** — from `.specswarm/build-loop.state` `current_task=` line
- **Branch** + **last commit** — from git

Override either with `--feature` / `--task` if the auto-detection picked wrong.

## Usage examples

```bash
# Minimal — one-arg capture, status defaults to open
/ss:intervention "plan.md says 43 columns but spec says 47"

# Fully specified upfront
/ss:intervention "version pin doesn't exist" \
  --should "verify against npm registry" \
  --prevent "ship in /ss:preflight version-currency check"

# Mark an intervention as graduated (after the pattern was codified)
/ss:intervention "postgres.js drift" \
  --status graduated \
  --prevent "/ss:preflight version-currency check shipped v7.1.0"

# Interactive — Claude walks through 4 AskUserQuestion prompts
/ss:intervention

# List recent
/ss:intervention --list
/ss:intervention --list 20
```
