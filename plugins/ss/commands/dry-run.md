---
description: Predict what a SpecSwarm chunk's execution would look like WITHOUT running it. Phase-aware — detects which artifacts exist, simulates everything still ahead. Produces a structured `dry-run.md` with anticipated decisions, risk register, out-of-scope guards, memory gaps, touchpoint estimate, predicted artifacts. Re-runnable; rewrites the same file each time.
effort: medium
args:
  - name: feature_num
    description: Feature number (e.g., 003). Defaults to current branch's feature, then latest feature dir.
    required: false
  - name: --phase
    description: Narrow simulation scope. One of plan, tasks, decisions, implement, auto (default).
    required: false
  - name: --history-limit
    description: Number of past intervention/verify-queue entries to feed the simulator. Default 20.
    required: false
---

# SpecSwarm Dry-Run Prediction

Marty's most expensive operation is *committing to a chunk that turns out to be the wrong shape*. The dual-session mentor↔builder pattern existed partly to catch this BEFORE it shipped. With v7.x's automation, the equivalent safety rail is **prediction**: read what will be built, surface what's likely to go wrong, let Marty redirect before code lands.

Run this at chunk start (or any point before `/ss:ship`) to get a structured prediction. Re-runnable — the report rewrites on each invocation as more artifacts come into existence.

## Phase 1: Resolve feature + phase scope

```bash
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/features-location.sh"
# shellcheck disable=SC1091
source "${PLUGIN_DIR}/lib/intervention.sh"
# shellcheck disable=SC1091
[ -f "${PLUGIN_DIR}/lib/notify.sh" ] && source "${PLUGIN_DIR}/lib/notify.sh"

FEATURE_NUM=""
PHASE="auto"
HISTORY_LIMIT=20

while [ $# -gt 0 ]; do
  case "$1" in
    --phase)         PHASE="$2";         shift 2 ;;
    --history-limit) HISTORY_LIMIT="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: /ss:dry-run [FEATURE_NUM] [options]

Predict the chunk's full execution path without running it.

Options:
  --phase SCOPE      auto (default) | plan | tasks | decisions | implement
  --history-limit N  Past intervention/verify entries to feed the simulator (default 20)

Examples:
  /ss:dry-run
  /ss:dry-run 003
  /ss:dry-run 003 --phase implement
  /ss:dry-run --history-limit 50
EOF
      exit 0
      ;;
    *)
      if [ -z "$FEATURE_NUM" ]; then FEATURE_NUM="$1"; fi
      shift
      ;;
  esac
done

# Validate --phase
case "$PHASE" in
  auto|plan|tasks|decisions|implement) ;;
  *)
    echo "❌ Invalid --phase '$PHASE' (use: auto|plan|tasks|decisions|implement)" >&2
    exit 2
    ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Resolve feature (same cascade as /ss:decisions and /ss:retrospective)
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
FEATURE_ID=$(basename "$FEATURE_DIR")

# Spec.md is mandatory — if it doesn't exist, /ss:specify hasn't run yet
SPEC_PATH="${FEATURE_DIR}/spec.md"
if [ ! -f "$SPEC_PATH" ]; then
  echo "❌ spec.md not found at $SPEC_PATH. Run /ss:specify first." >&2
  exit 2
fi

echo "🔮 Dry-run prediction for $FEATURE_ID"
echo "  feature_dir:    $FEATURE_DIR"
echo "  phase_scope:    $PHASE"
echo "  history_limit:  $HISTORY_LIMIT"
echo ""
```

## Phase 2: Detect which artifacts exist (phase detection)

```bash
ARTIFACTS_PRESENT=""
for name in spec.md plan.md tasks.md decision-sheet.md research.md data-model.md quickstart.md; do
  full="${FEATURE_DIR}/${name}"
  if [ -f "$full" ]; then
    size=$(stat -c %s "$full" 2>/dev/null || stat -f %z "$full" 2>/dev/null || echo 0)
    ARTIFACTS_PRESENT="${ARTIFACTS_PRESENT}${name}\t${full}\t${size}\n"
  fi
done

# Auto-detect implicit phase if user didn't override
DETECTED_PHASE="plan"  # default — spec only → next is plan
if [ -f "${FEATURE_DIR}/plan.md" ]; then DETECTED_PHASE="tasks"; fi
if [ -f "${FEATURE_DIR}/tasks.md" ]; then DETECTED_PHASE="decisions"; fi
if [ -f "${FEATURE_DIR}/decision-sheet.md" ]; then DETECTED_PHASE="implement"; fi

EFFECTIVE_PHASE="$PHASE"
[ "$PHASE" = "auto" ] && EFFECTIVE_PHASE="$DETECTED_PHASE"

echo "📋 Artifacts present:"
echo -e "$ARTIFACTS_PRESENT" | grep -v '^$' | awk -F'\t' '{printf "  • %s (%s bytes)\n", $1, $3}'
echo ""
echo "🎯 Effective phase scope: $EFFECTIVE_PHASE"
echo ""
```

## Phase 3: Gather foundation + memory + history signals

```bash
FOUNDATION_DIR="${REPO_ROOT}/.specswarm"
FOUNDATION_PATHS=""
for name in tech-stack constitution quality-standards conventions references; do
  p="${FOUNDATION_DIR}/${name}.md"
  if [ -f "$p" ]; then FOUNDATION_PATHS="${FOUNDATION_PATHS}${p}\n"; fi
done

MEM_DIR=$(ss_intervention_dir 2>/dev/null || echo "")

# Memory summary (filename: description for risk-pattern recognition)
MEMORY_SUMMARY=""
if [ -n "$MEM_DIR" ] && [ -d "$MEM_DIR" ]; then
  MEMORY_SUMMARY=$(find "$MEM_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort \
    | while IFS= read -r mf; do
        base=$(basename "$mf")
        [ "$base" = "MEMORY.md" ] && continue
        desc=$(grep -E '^description:' "$mf" 2>/dev/null | head -n1 | sed -E 's/^description:[[:space:]]*//' | head -c 140)
        echo "  - ${base}: ${desc}"
      done | head -c 12000)
fi

# Intervention history relevant to this feature (best-effort: filename mentions feature_id)
INTERVENTION_HISTORY=""
if [ -n "$MEM_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if grep -qF "$FEATURE_ID" "$f" 2>/dev/null; then
      INTERVENTION_HISTORY="${INTERVENTION_HISTORY}${f}\n"
    fi
  done < <(find "$MEM_DIR" -maxdepth 1 -type f -name 'intervention_*.md' 2>/dev/null | sort -r | head -n "$HISTORY_LIMIT")
fi

# Verify-queue history (from v7.4.0) — TSV: task_id\tverdict\tdetails
VERIFY_HISTORY=""
QUEUE_DIR="${REPO_ROOT}/.specswarm/verify-queue"
if [ -d "$QUEUE_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    tid=$(basename "$f" | sed -E 's/\.(verified|flagged)$//')
    verdict=$(grep -E '^verdict=' "$f" 2>/dev/null | head -n1 | cut -d= -f2-)
    details=$(grep -E '^details=' "$f" 2>/dev/null | head -n1 | cut -d= -f2- | head -c 160)
    VERIFY_HISTORY="${VERIFY_HISTORY}${tid}\t${verdict:-?}\t${details}\n"
  done < <(find "$QUEUE_DIR" -maxdepth 1 -type f \( -name '*.verified' -o -name '*.flagged' \) 2>/dev/null | sort -r | head -n "$HISTORY_LIMIT")
fi

echo "🧾 Signals gathered:"
echo "  foundation files:      $(echo -e "$FOUNDATION_PATHS" | grep -c .)"
echo "  memory_dir files:      $(echo -e "$MEMORY_SUMMARY" | grep -c '^  -')"
echo "  intervention history:  $(echo -e "$INTERVENTION_HISTORY" | grep -c .) for $FEATURE_ID"
echo "  verify history:        $(echo -e "$VERIFY_HISTORY" | grep -c .)"
echo ""
```

## Phase 4: Stash context bundle + write target path

```bash
CONTEXT_DIR="${REPO_ROOT}/.specswarm/dry-run"
mkdir -p "$CONTEXT_DIR"
CONTEXT_FILE="${CONTEXT_DIR}/${FEATURE_ID}.context"
OUTPUT_PATH="${FEATURE_DIR}/dry-run.md"

{
  echo "feature_id=${FEATURE_ID}"
  echo "feature_dir=${FEATURE_DIR}"
  echo "phase_hint=${EFFECTIVE_PHASE}"
  echo "output_path=${OUTPUT_PATH}"
  echo "memory_dir=${MEM_DIR}"
  echo "artifacts_present<<EOF_A"
  echo -e "$ARTIFACTS_PRESENT"
  echo "EOF_A"
  echo "foundation_paths<<EOF_F"
  echo -e "$FOUNDATION_PATHS"
  echo "EOF_F"
  echo "memory_summary<<EOF_M"
  echo "$MEMORY_SUMMARY"
  echo "EOF_M"
  echo "intervention_history<<EOF_I"
  echo -e "$INTERVENTION_HISTORY"
  echo "EOF_I"
  echo "verify_queue_history<<EOF_V"
  echo -e "$VERIFY_HISTORY"
  echo "EOF_V"
} > "$CONTEXT_FILE"

echo "📦 Context bundle: $CONTEXT_FILE"
echo "📝 Agent will write report to: $OUTPUT_PATH"
echo ""
```

## Phase 5: Dispatch dry-run-simulator subagent

**Claude — perform this:**

1. Read `${CONTEXT_FILE}` to load the structured context (heredoc-delimited fields: `EOF_A`, `EOF_F`, `EOF_M`, `EOF_I`, `EOF_V`).

2. Dispatch a single Task call:
   ```
   Task(
     subagent_type: "dry-run-simulator",
     description: "Dry-run prediction for <FEATURE_ID>",
     prompt: <<<END
   You are running a dry-run prediction for SpecSwarm feature <FEATURE_ID>.

   feature_id: <FEATURE_ID>
   feature_dir: <FEATURE_DIR>
   phase_hint: <EFFECTIVE_PHASE>
   output_path: <OUTPUT_PATH>
   memory_dir: <MEM_DIR>

   artifacts_present (TSV name\tpath\tsize):
   <ARTIFACTS_PRESENT>

   foundation_paths (one per line, absolute):
   <FOUNDATION_PATHS>

   memory_summary (one '<filename>: <description>' line per existing memory file):
   <MEMORY_SUMMARY>

   intervention_history (paths to intervention_*.md files that mention this feature_id):
   <INTERVENTION_HISTORY>

   verify_queue_history (TSV task_id\tverdict\tdetails from past verify-queue entries):
   <VERIFY_HISTORY>

   Per your system prompt: read relevant artifacts, scan history for drift
   patterns, write the 9-section dry-run.md report to <OUTPUT_PATH>, and return
   the structured DRY_RUN_WRITTEN / PHASE_SCOPE / HIGHEST_RISK /
   RECOMMENDATIONS_COUNT / TOUCHPOINT_ESTIMATE summary.
   END
   )
   ```

3. Parse the agent's return for the structured summary.

## Phase 6: Cleanup + final report

After the agent returns, Claude should:

```bash
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
[ -f "${PLUGIN_DIR}/lib/notify.sh" ] && source "${PLUGIN_DIR}/lib/notify.sh"

OUTPUT_PATH="<from earlier>"  # Claude substitutes
FEATURE_ID="<from earlier>"
HIGHEST_RISK="<parsed from agent return>"
RECS="<parsed from agent return>"
TOUCHPOINTS="<parsed from agent return>"

# Cleanup the context bundle
rm -f "${REPO_ROOT}/.specswarm/dry-run/${FEATURE_ID}.context" 2>/dev/null

# Brief summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Dry-run prediction complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  report:            $OUTPUT_PATH"
echo "  highest risk:      $HIGHEST_RISK"
echo "  recommendations:   $RECS"
echo "  touchpoint estimate: $TOUCHPOINTS"
echo ""
echo "Review the report; address any \"Recommendations BEFORE running this chunk\" items;"
echo "then proceed with /ss:plan or /ss:tasks or /ss:implement (whichever phase is next)."

if declare -f ss_notify >/dev/null 2>&1; then
  ss_notify info "SpecSwarm dry-run ready" "${FEATURE_ID}: ${HIGHEST_RISK}" || true
fi
```

## How this fits in the v7 toolchain

`/ss:dry-run` is invocable at MULTIPLE phases — each invocation rewrites the same `dry-run.md` with the latest prediction given the artifacts that now exist.

```
1. /ss:specify        — write spec.md
   ↓
   /ss:dry-run        — predict what plan + tasks + implement would look like
   ↓ (review, fix gaps, refine spec if needed)
2. /ss:plan           — write plan.md
   ↓
   /ss:preflight      — deterministic checks (v7.1.0)
   ↓
   /ss:dry-run        — re-predict; now with plan.md context, predictions sharpen
   ↓ (review, refine)
3. /ss:decisions      — pre-batch strategic decisions (v7.6.0)
   ↓
   /ss:dry-run        — final prediction before tasks/implement; should show
                        zero anticipated decisions, narrow risk list
   ↓
4. /ss:tasks → /ss:implement → /ss:verify → /ss:retrospective → /ss:ship
```

The win is *incremental refinement* — each `/ss:dry-run` invocation gives a sharper picture as more artifacts come into existence. Marty can stop and redirect at any sharpening point.

## Project-agnostic guarantees

- Feature resolution via `find_feature_dir` — no hardcoded paths
- Foundation files auto-discovered at `.specswarm/*.md`; each is optional
- Memory dir via existing v7.3.0 helpers
- Intervention + verify-queue history are optional inputs; agent uses what's available
- `--phase` override for narrowing scope when only one downstream phase matters
- Idempotent: re-runs rewrite `dry-run.md`; git history preserves past predictions
- No external mutations — agent writes ONLY to `dry-run.md`
