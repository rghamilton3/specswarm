---
description: "Initialize or refresh SpecSwarm guides for a project / sprint"
effort: medium
args:
  - name: --skip-detection
    description: Skip automatic technology detection
    required: false
  - name: --minimal
    description: Use minimal defaults without interactive questions
    required: false
  - name: --reset
    description: Discard existing .specswarm guides and regenerate from scratch (backup is still taken)
    required: false
  - name: --full-scan
    description: (v7.0.0) Lift the default depth bounds on source discovery (Step 3.0). Use when spec docs live outside docs/, specs/, documentation/.
    required: false
  - name: --include-user-memory
    description: (v7.0.0) Include user_*.md memory files in extraction (Step 4.0). Default is skip (personal context, not project rules).
    required: false
---

## User Input

```text
$ARGUMENTS
```

## Goal

Establish or refresh the SpecSwarm guides under `.specswarm/`:

1. `constitution.md` - Project governance and coding principles
2. `tech-stack.md` - Approved technologies and prohibited patterns
3. `quality-standards.md` - Quality gates and performance budgets
4. `references.md` - External authoritative sources (spec corpus, reference codebases, memory dirs)
5. `conventions.md` - Detected code style and patterns

`/ss:init` is designed to run at two points in a project's life:

- **At project / sprint kickoff** — to create the guides from scratch by detecting the tech stack, discovering external references, and proposing principles from memory.
- **Mid-development, any time** — to **reconcile** the guides against project reality. On re-run, the command reads both (a) the existing guide files and (b) current project state (package.json, CI, memory dirs, …), surfaces drift between the two, and only updates a guide after the developer accepts the proposed delta. Developer-authored content inside `<!-- ss:user-additions -->` blocks is always preserved verbatim. A full backup of all `.specswarm/*.md` is taken on every run as a safety net.

Pass `--reset` if you want to discard existing guides and regenerate from scratch (the backup is still taken; nothing is permanently lost).

---

## Execution Steps

### Step 1: Snapshot existing guides (unconditional)

Always back up every `.specswarm/*.md` file present at the start of the run. This is cheap, always safe, and protects the developer against any reconciliation bug downstream. No "Update / Backup / Cancel" prompt — re-running `/ss:init` is meant to be safe.

```bash
echo "🔍 Snapshotting existing SpecSwarm guides..."
echo ""

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$REPO_ROOT/.specswarm/.backup/$BACKUP_TS"

EXISTING_FILES=()
if [ -d "$REPO_ROOT/.specswarm" ]; then
  shopt -s nullglob
  for f in "$REPO_ROOT/.specswarm"/*.md; do
    EXISTING_FILES+=("$(basename "$f")")
  done
  shopt -u nullglob
fi

# Detect --reset flag from $ARGUMENTS
RESET_MODE=false
if echo "$ARGUMENTS" | grep -q -- '--reset'; then
  RESET_MODE=true
fi

# v7.0.0: Detect --full-scan and --include-user-memory flags
FULL_SCAN_FLAG=false
if echo "$ARGUMENTS" | grep -q -- '--full-scan'; then
  FULL_SCAN_FLAG=true
fi

INCLUDE_USER_MEMORY_FLAG=false
if echo "$ARGUMENTS" | grep -q -- '--include-user-memory'; then
  INCLUDE_USER_MEMORY_FLAG=true
fi

# Detect --minimal flag (referenced by v7.0.0 Steps 3.0 / 4.0 / 4.1 / 4.2 for short-circuit)
MINIMAL_MODE=false
if echo "$ARGUMENTS" | grep -q -- '--minimal'; then
  MINIMAL_MODE=true
fi

if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
  mkdir -p "$BACKUP_DIR"
  for file in "${EXISTING_FILES[@]}"; do
    cp "$REPO_ROOT/.specswarm/$file" "$BACKUP_DIR/$file"
  done

  echo "📦 Backed up ${#EXISTING_FILES[@]} existing guide(s) to:"
  echo "   .specswarm/.backup/$BACKUP_TS/"
  for file in "${EXISTING_FILES[@]}"; do
    echo "     - $file"
  done
  echo ""

  if [ "$RESET_MODE" = true ]; then
    echo "⚠️  --reset flag detected — existing guides will be discarded."
    echo "   Backup above is your recovery path if you change your mind."
    echo ""
  else
    echo "♻️  Reconciliation mode — existing guides will be merged with current project state."
    echo "   Developer-authored content in <!-- ss:user-additions --> blocks is preserved verbatim."
    echo "   You will be prompted to resolve any drift between declared and detected values."
    echo ""
  fi
fi
```

If `RESET_MODE=true`, treat the rest of the command exactly like a first-time init: skip every "if file exists, reconcile…" branch in Steps 3 / 3.5 / 4 / 5 / 6 and regenerate each guide from scratch.

---

### Step 1.5: Parse existing guides (NEW)

If `RESET_MODE=false` and any guide files exist, parse them into shell-readable form for downstream reconciliation. Failures here are non-fatal — a parser that can't make sense of a file just produces no output, and the relevant Step downgrades to "treat as new."

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Source parsers (all guards: silent failures are OK)
[ -f "$PLUGIN_DIR/lib/guide-parsers.sh" ]      && source "$PLUGIN_DIR/lib/guide-parsers.sh"
[ -f "$PLUGIN_DIR/lib/references-loader.sh" ]  && source "$PLUGIN_DIR/lib/references-loader.sh"
[ -f "$PLUGIN_DIR/lib/constitution-parser.sh" ] && source "$PLUGIN_DIR/lib/constitution-parser.sh"

declare -A EXISTING_TECH_STACK=()
declare -A EXISTING_QUALITY=()
EXISTING_HAS_REFERENCES=false
EXISTING_HAS_CONSTITUTION=false

if [ "$RESET_MODE" = false ]; then
  if [ -f "$REPO_ROOT/.specswarm/tech-stack.md" ] && declare -F ss_parse_tech_stack >/dev/null; then
    while IFS=$'\t' read -r k v; do
      [ -n "$k" ] && EXISTING_TECH_STACK["$k"]="$v"
    done < <(ss_parse_tech_stack "$REPO_ROOT/.specswarm/tech-stack.md")
  fi

  if [ -f "$REPO_ROOT/.specswarm/quality-standards.md" ] && declare -F ss_parse_quality_standards >/dev/null; then
    while IFS=$'\t' read -r k v; do
      [ -n "$k" ] && EXISTING_QUALITY["$k"]="$v"
    done < <(ss_parse_quality_standards "$REPO_ROOT/.specswarm/quality-standards.md")
  fi

  [ -f "$REPO_ROOT/.specswarm/references.md" ]   && EXISTING_HAS_REFERENCES=true
  [ -f "$REPO_ROOT/.specswarm/constitution.md" ] && EXISTING_HAS_CONSTITUTION=true

  if [ ${#EXISTING_TECH_STACK[@]} -gt 0 ] || [ ${#EXISTING_QUALITY[@]} -gt 0 ] || \
     [ "$EXISTING_HAS_REFERENCES" = true ]  || [ "$EXISTING_HAS_CONSTITUTION" = true ]; then
    echo "📖 Loaded existing guides for reconciliation:"
    [ ${#EXISTING_TECH_STACK[@]} -gt 0 ] && echo "   ✓ tech-stack.md       (${#EXISTING_TECH_STACK[@]} declared fields)"
    [ ${#EXISTING_QUALITY[@]} -gt 0 ]    && echo "   ✓ quality-standards.md (${#EXISTING_QUALITY[@]} thresholds)"
    [ "$EXISTING_HAS_REFERENCES" = true ]  && echo "   ✓ references.md"
    [ "$EXISTING_HAS_CONSTITUTION" = true ] && echo "   ✓ constitution.md"
    echo ""
  fi
fi
```

The downstream steps consult `EXISTING_TECH_STACK[key]`, `EXISTING_QUALITY[key]`, `EXISTING_HAS_REFERENCES`, and `EXISTING_HAS_CONSTITUTION` to choose between reconciliation and fresh-generation branches.

---

### Step 1.6: Sufficiency check (NEW)

A pre-existing guide can be *present* yet *unreadable* by SpecSwarm. Common cases:

- `constitution.md` has prose principles but no `<!-- specswarm-rule: ... -->` blocks → PostToolUse hooks have nothing to enforce.
- `tech-stack.md` was hand-authored as freeform markdown → `ss_parse_tech_stack` returns no fields → `/ss:build` can't enforce drift.
- `quality-standards.md` describes thresholds in prose ("80% coverage") with no YAML blocks → `/ss:ship` falls back to built-in defaults silently.
- `references.md` is a flat list of URLs → `ss_references_exist` returns false → `/ss:specify` never consults it.

This step evaluates each existing guide against SpecSwarm's machine-readable expectations. **Per the user's stated intent for `/ss:init`** (run any time mid-development to bring guides into congruence), evaluation happens on *every* run with no opt-out persistence — insufficient guides are surfaced until they're addressed.

If `RESET_MODE=true`, skip this step entirely (the user has asked for a clean regenerate).

```bash
if [ "$RESET_MODE" = false ]; then
  declare -A INSUFFICIENCY=()

  if [ -f "$REPO_ROOT/.specswarm/constitution.md" ]; then
    reason=$(ss_check_constitution_sufficient "$REPO_ROOT/.specswarm/constitution.md" 2>/dev/null) || INSUFFICIENCY[constitution]="$reason"
  fi
  if [ -f "$REPO_ROOT/.specswarm/tech-stack.md" ]; then
    reason=$(ss_check_tech_stack_sufficient "$REPO_ROOT/.specswarm/tech-stack.md" 2>/dev/null) || INSUFFICIENCY[tech_stack]="$reason"
  fi
  if [ -f "$REPO_ROOT/.specswarm/quality-standards.md" ]; then
    reason=$(ss_check_quality_standards_sufficient "$REPO_ROOT/.specswarm/quality-standards.md" 2>/dev/null) || INSUFFICIENCY[quality]="$reason"
  fi
  if [ -f "$REPO_ROOT/.specswarm/references.md" ]; then
    reason=$(ss_check_references_sufficient "$REPO_ROOT/.specswarm/references.md" 2>/dev/null) || INSUFFICIENCY[references]="$reason"
  fi

  if [ ${#INSUFFICIENCY[@]} -gt 0 ]; then
    echo "⚠️  Sufficiency check found ${#INSUFFICIENCY[@]} guide(s) that SpecSwarm can't fully use:"
    echo ""
    for key in "${!INSUFFICIENCY[@]}"; do
      echo "   • $key: ${INSUFFICIENCY[$key]}"
    done
    echo ""
  fi
fi

# Per-file mode flags — consulted by downstream Steps 3.5 / 4 / 5 / 6
CONSTITUTION_MODE="normal"
TECH_STACK_MODE="normal"
QUALITY_MODE="normal"
REFERENCES_MODE="normal"
```

**For each insufficient file**, use **AskUserQuestion** to choose a handling mode. The prompt names the specific gap so the user understands what they're picking:

```
Question: "<file> is insufficient: <reason>. How should /ss:init handle it?"
Header: "<file>"
Options:
  1. "Augment in place"
     Description: "Keep existing content verbatim, prepend SpecSwarm's canonical
                   structure above. Your content moves into a <!-- ss:user-additions -->
                   block so it survives future re-runs."
  2. "Reset to canonical template"
     Description: "Backup of your current file is already saved in .specswarm/.backup/.
                   Regenerate from the canonical template (same as a fresh /ss:init)."
  3. "Keep as-is"
     Description: "Leave the file untouched this run. SpecSwarm will continue to be
                   unable to enforce it. You'll be asked again next /ss:init."
```

Map answers to mode flags:

| Answer | Mode | Downstream behavior |
|---|---|---|
| "Augment in place" | `augment` | Call `ss_augment_with_skeleton` after Step 5/6 generates the canonical content. |
| "Reset to canonical template" | `reset` | Treat this single file as a fresh-init (skip reconciliation merge). |
| "Keep as-is" | `keep` | Skip the corresponding generation step entirely — file is left untouched. |

```bash
# Pseudocode the AI executes via AskUserQuestion + variable assignment:
#   for key in "${!INSUFFICIENCY[@]}"; do
#     ask_user_question(...)
#     case "$answer" in
#       "Augment in place")            mode="augment" ;;
#       "Reset to canonical template") mode="reset" ;;
#       "Keep as-is")                  mode="keep" ;;
#     esac
#     case "$key" in
#       constitution) CONSTITUTION_MODE="$mode" ;;
#       tech_stack)   TECH_STACK_MODE="$mode" ;;
#       quality)      QUALITY_MODE="$mode" ;;
#       references)   REFERENCES_MODE="$mode" ;;
#     esac
#   done
```

**Mode semantics for downstream steps**:

- `normal` — file is either absent (fresh-init path) or sufficient (v6.4.0 reconciliation path)
- `augment` — file exists but is insufficient; user chose to keep their content and prepend canonical structure
- `reset` — file exists, user explicitly wants it regenerated from template (their content is in `.backup/`)
- `keep` — file exists, user explicitly wants no changes this run

---

### Step 2: Auto-Detect Technology Stack

**Skip this step if `--skip-detection` flag is present.**

```bash
echo "🔍 Auto-detecting technology stack..."
echo ""

# Detect tech stack by reading project config files
# (Claude analyzes package.json, pyproject.toml, go.mod, etc. directly)
PLUGIN_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Attempt to detect tech stack from config files
if [ -f "package.json" ] || [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "go.mod" ] || [ -f "Cargo.toml" ] || [ -f "Gemfile" ] || [ -f "composer.json" ]; then
  AUTO_DETECT=true

  # Claude reads the config file and extracts framework, language, dependencies
  echo "✅ Configuration file detected — analyzing tech stack..."
else
  # No config file detected - manual configuration mode
  echo "ℹ️  No configuration file detected - auto-detection disabled"
  echo ""
  echo "📋 Supported configuration files:"
  echo "   • package.json (JavaScript/TypeScript)"
  echo "   • requirements.txt / pyproject.toml (Python)"
  echo "   • composer.json (PHP)"
  echo "   • go.mod (Go)"
  echo "   • Gemfile (Ruby)"
  echo "   • Cargo.toml (Rust)"
  echo ""
  echo "💡 Starting a new project?"
  echo ""
  echo "   Consider scaffolding your project first for automatic setup:"
  echo ""
  echo "   # JavaScript/TypeScript"
  echo "   npm create vite@latest . -- --template react-ts  # React + Vite"
  echo "   npx create-next-app@latest .                     # Next.js"
  echo "   npm create astro@latest .                        # Astro"
  echo "   npm create vue@latest .                          # Vue"
  echo ""
  echo "   # Python"
  echo "   pip install flask && flask init                  # Flask"
  echo "   django-admin startproject myproject .            # Django"
  echo "   pip install fastapi && touch main.py             # FastAPI"
  echo ""
  echo "   # PHP"
  echo "   composer create-project laravel/laravel .        # Laravel"
  echo ""
  echo "   # Go"
  echo "   go mod init github.com/username/project          # Go"
  echo ""
  echo "   # Ruby"
  echo "   rails new . --skip-bundle                        # Rails"
  echo ""
  echo "   # Rust"
  echo "   cargo init                                        # Rust"
  echo ""
  echo "   Then re-run /ss:init for automatic detection."
  echo ""
  echo "⚠️  Continuing with manual tech stack configuration..."
  echo ""
  read -p "Press Enter to continue with manual setup, or Ctrl+C to scaffold first..."
  echo ""
  AUTO_DETECT=false
fi
```

---

### Step 3: Interactive Configuration (if not --minimal)

**Skip this step if `--minimal` flag is present. Use detected values or sensible defaults.**

**Reconciliation rules for every question below:**

- If `RESET_MODE=true`, ignore `EXISTING_*` entirely — ask all questions fresh.
- If a value in `EXISTING_TECH_STACK[...]` or `EXISTING_QUALITY[...]` exists *and* matches the auto-detected value, skip the question entirely (no drift, no prompt).
- If a value exists in `EXISTING_*` *and* differs from auto-detected, present a drift-resolution prompt with both values plus a "Skip — flag for manual review" escape.
- If a value exists in `EXISTING_*` *and* there is no auto-detected counterpart, default option 1 to "Keep existing (Recommended)".
- If no `EXISTING_*` value, present the question fresh as the original flow did.

Use **AskUserQuestion** tool for configuration:

```
Question 1: "What is your project name?"
Header: "Project"
Options:
  - If EXISTING_TECH_STACK[project_name] is set, default to that (label "Keep existing (Recommended)")
  - Otherwise auto-detected from package.json "name" field or current directory name
  - Allow custom input via "Other" option
```

Store in `$PROJECT_NAME`.

**Drift-resolution pattern** (use for any field where existing-vs-detected disagree):

```
Question: "<Field> drift detected: which is canonical?"
Header: "<Field>"
Options:
  1. "Update guide to detected (<detected_value>)"
     Description: "package.json / project state is the source of truth — update tech-stack.md to match"
  2. "Keep declared (<existing_value>)"
     Description: "tech-stack.md is correct; treat the install drift as a fix-up to do separately"
  3. "Skip — flag for manual review"
     Description: "Leave existing value, append <!-- drift: detected <detected_value> on YYYY-MM-DD --> comment"
```

```
Question 2 (if AUTO_DETECT=true AND no EXISTING_TECH_STACK match): "We detected your tech stack. Is this correct?"
Header: "Tech Stack"
Options:
  1. "Yes, looks good"
     Description: "Use detected technologies as-is"
  2. "Let me modify"
     Description: "Adjust the detected stack"
  3. "Start from scratch"
     Description: "Manually specify all technologies"
```

Store in `$TECH_CONFIRM`.

If `$TECH_CONFIRM` == "Let me modify" or "Start from scratch" or AUTO_DETECT=false:

```
Question 3: "What is your primary framework?"
Header: "Framework"
Options:
  - If EXISTING_TECH_STACK[framework] is set, list it FIRST labelled "Keep existing: <name>"
  1. "React"
  2. "Vue"
  3. "Angular"
  4. "Next.js"
  5. "Node.js (backend)"
  6. "Other" (allow custom input)
```

```
Question 4: "What testing framework do you use?"
Header: "Testing"
multiSelect: true
Options:
  - If EXISTING_TECH_STACK[unit_test] / [e2e_test] is set, pre-select those options
  1. "Vitest (unit)"
  2. "Jest (unit)"
  3. "Playwright (e2e)"
  4. "Cypress (e2e)"
  5. "Testing Library"
  6. "Other" (allow custom input)
```

```
Question 5: "What quality thresholds do you want?"
Header: "Quality"
Options:
  - If EXISTING_QUALITY[min_quality_score] is set, derive the matching tier (or "Custom")
    and list it FIRST labelled "Keep existing: <tier> (<score>/<coverage>)"
  1. "Standard (80% coverage, 80 quality score)"
     Description: "Recommended for most projects"
  2. "Strict (90% coverage, 90 quality score)"
     Description: "For mission-critical applications"
  3. "Relaxed (70% coverage, 70 quality score)"
     Description: "For prototypes and experiments"
  4. "Custom" (allow custom input)
```

Store in `$QUALITY_LEVEL`.

Parse quality thresholds:
- Standard: min_quality_score=80, min_test_coverage=80
- Strict: min_quality_score=90, min_test_coverage=90
- Relaxed: min_quality_score=70, min_test_coverage=70
- Keep existing: use `EXISTING_QUALITY[min_quality_score]` / `[min_test_coverage]` verbatim

```
Question 6: "Do you want to use default coding principles?"
Header: "Principles"
Options:
  - Skip this question entirely if EXISTING_HAS_CONSTITUTION=true and RESET_MODE=false
    (existing constitution.md principles are preserved in Step 4 reconciliation)
  1. "Yes, use defaults"
     Description: "DRY, SOLID, type safety, test coverage, documentation"
  2. "Let me provide custom principles"
     Description: "Define your own 3-5 principles"
```

Store in `$PRINCIPLES_CHOICE`.

If `$PRINCIPLES_CHOICE` == "Let me provide custom":
  Ask for custom principles (text input via "Other" option or multiple questions)

---

### Step 3.0: Source Discovery (NEW in v7.0.0)

**Skip this step entirely if `MINIMAL_MODE=true`.** No subagent dispatch, no `.discovery.tmp` written. Downstream steps detect the missing file and fall back to v6.4.0 filesystem scans.

This step dispatches a single subagent to classify the project's documentation and configuration surface. The subagent's structured output (`.specswarm/.discovery.tmp`) is consumed by:

- Step 3.5 (references) — to filter candidate spec corpus docs and reference codebases
- Step 4.0 (extractors) — to build targeted reading lists per extractor
- Step 6.5 (conventions analysis) — to use a pre-classified source-code inventory

Parent context never sees the bulk of file content; only the structured classification summary. This is the architectural reason v7 can extract from 20K-line spec corpora without context exhaustion.

```bash
if [ "$MINIMAL_MODE" = true ]; then
  echo "⏭️  Step 3.0 skipped — --minimal mode."
  DISCOVERY_AVAILABLE=false
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  # Canonical Claude Code memory path (one per project).
  # Path encoding: replace each "/" in absolute repo path with "-".
  MEMORY_DIR="$HOME/.claude/projects/$(echo "$REPO_ROOT" | tr / -)/memory"

  mkdir -p "$REPO_ROOT/.specswarm"
  DISCOVERY_TMP="$REPO_ROOT/.specswarm/.discovery.tmp"
  rm -f "$DISCOVERY_TMP"

  echo ""
  echo "🔍 Step 3.0/7 — Discovering project sources..."
  echo "   Repo root:    $REPO_ROOT"
  echo "   Memory dir:   $MEMORY_DIR$([ -d "$MEMORY_DIR" ] && echo "" || echo "  (not present)")"
  echo "   Full scan:    $FULL_SCAN_FLAG"
  echo ""

  DISCOVERY_AVAILABLE=true
fi
```

**LLM action (only when `DISCOVERY_AVAILABLE=true`):**

Dispatch the source-discovery subagent via a single `Agent` tool call. The prompt body below is fed verbatim, with `<REPO_ROOT>`, `<FULL_SCAN_FLAG>`, and `<MEMORY_DIR>` interpolated from the shell variables above.

```
Agent({
  description: "Discover and classify SpecSwarm sources",
  subagent_type: "general-purpose",
  prompt: <prompt body below>
})
```

**Prompt body (ship verbatim, interpolating the three variables):**

> You are SpecSwarm's source-discovery agent. Map this project's documentation and configuration surface so the main `/ss:init` flow knows what to extract from.
>
> Repo root: `<REPO_ROOT>`
> Full-scan mode: `<FULL_SCAN_FLAG>` (default `false` — scan only `docs/`, `specs/`, `documentation/`, `.specswarm/specs/`, repo-root depth-1 `*.md`/`*.mdx`, and standard config files at repo root)
> Canonical memory dir: `<MEMORY_DIR>` (consult only if it exists)
>
> Procedure:
> 1. From repo root, list files respecting `.gitignore`. Skip `node_modules`, `.git`, `dist`, `build`, `vendor`, lockfiles, files > 1 MB.
> 2. For markdown files (`.md`, `.mdx`), read the first 50 + last 20 lines to classify and draft a one-sentence summary.
> 3. For configs (`package.json`, `tsconfig.json`, `vite.config.*`, `drizzle.config.*`, `composer.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `Gemfile`, `Cargo.toml`, …), note their presence; do not dump full contents.
> 4. Check the canonical Claude Code memory dir — list files if present.
> 5. Stem-filtered sibling-repo scan one level up: extract the current repo basename stem (chars before the first hyphen/underscore/dot) and list one-level-up siblings whose basename shares that stem.
>
> Classify each file into exactly one category:
> - `spec-doc` — markdown describing decisions, requirements, architecture, rules
> - `documentation` — README/CONTRIBUTING/CHANGELOG (general; not project decisions)
> - `config` — build/tooling configuration
> - `memory` — Claude Code memory file (`feedback_`/`project_`/`reference_`/`user_`)
> - `reference-codebase` — external repo referenced by docs
> - `source-code` — implementation files
> - `noise` — lockfiles, snapshots, auto-generated, irrelevant
>
> Write the output to `.specswarm/.discovery.tmp` as one record per line, tab-separated:
>
> ```
> <category>\t<path-relative-to-repo-root>\t<size-bytes>\t<one-sentence-summary-or-empty>
> ```
>
> Spec-doc records MUST have a non-empty summary (one sentence, no embedded tabs or newlines). Other categories may have empty summaries.
>
> End the file with one rollup row:
>
> ```
> noise-rollup\t\t<total-noise-files>\t<dominant-extensions-with-counts>
> ```
>
> Cap the total at 200 classified entries plus the rollup row. Cite paths relative to repo root. Do NOT summarize entire files — one sentence each.
>
> When you've written the file, return a brief acknowledgment in this exact form:
> `Discovered <N> spec-docs, <M> memory files, <K> configs, <noise-count> noise.`

**After the subagent returns:**

```bash
if [ "$DISCOVERY_AVAILABLE" = true ]; then
  if [ -s "$DISCOVERY_TMP" ]; then
    SPEC_DOC_COUNT=$(awk -F'\t' '$1=="spec-doc"' "$DISCOVERY_TMP" | wc -l | tr -d ' ')
    MEMORY_FILE_COUNT=$(awk -F'\t' '$1=="memory"' "$DISCOVERY_TMP" | wc -l | tr -d ' ')
    CONFIG_COUNT=$(awk -F'\t' '$1=="config"' "$DISCOVERY_TMP" | wc -l | tr -d ' ')
    echo "   ✓ Discovered ${SPEC_DOC_COUNT} spec-docs, ${MEMORY_FILE_COUNT} memory files, ${CONFIG_COUNT} configs."
  else
    echo "   ⚠️  Discovery returned no output — falling back to v6.4.0 filesystem scans for Steps 3.5/6.5."
    DISCOVERY_AVAILABLE=false
  fi
fi
```

If `DISCOVERY_AVAILABLE=false` at this point (either due to `--minimal` or empty subagent output), Steps 3.5 and 6.5 use their pre-v7 filesystem-scan code paths.

---

### Step 3.5: References Discovery & Reconciliation

**Skip this step if `--minimal` flag is present, or if `REFERENCES_MODE=keep`.**

Discovers external authoritative sources this project depends on — spec corpus markdown docs, reference codebases (legacy / prototype / sibling repos), and Claude Code memory directories — and writes a populated `.specswarm/references.md`. SpecSwarm consults references at session start (verification), during `/ss:specify` (extracts from spec corpus instead of fabricating), and during `/ss:clarify` (skips questions already answered in corpus or memory).

Mode behavior:

| Mode | Behavior |
|---|---|
| `keep` | Skip Step 3.5 entirely. |
| `reset` | Discard existing entries; run normal discovery flow as if the file didn't exist. |
| `augment` | Run normal discovery + write, then call `ss_augment_with_skeleton` to wrap any pre-existing freeform content beneath the canonical schema. |
| `normal` (default) | v6.4.0 reconciliation: load existing entries, dedupe against discovery candidates, flag stale paths, write `existing + accepted` to canonical schema. |

For mode=`normal` reconciliation specifically:

- Existing entries in `references.md` are loaded and kept (developer-curated content survives).
- Auto-discovery still runs; candidates **already present** in the existing file are dropped from the prompt (no duplicate noise).
- For each existing entry whose `path` no longer exists on disk, append a `<!-- stale: path not found YYYY-MM-DD -->` comment beneath it. Never delete entries — let the developer decide whether to clean up.
- The new `references.md` is `existing entries (preserved) + newly accepted candidates`.

```bash
if [ "$REFERENCES_MODE" = "keep" ]; then
  echo "⏭️  REFERENCES_MODE=keep — skipping Step 3.5."
  # Skip the entire Step 3.5 block below
fi

if [ "$REFERENCES_MODE" != "keep" ]; then

# Snapshot the pre-augment file so we can wrap it after normal generation.
PRE_AUGMENT_REFS=""
if [ "$REFERENCES_MODE" = "augment" ] && [ -f "$REPO_ROOT/.specswarm/references.md" ]; then
  PRE_AUGMENT_REFS="$(mktemp)"
  cp "$REPO_ROOT/.specswarm/references.md" "$PRE_AUGMENT_REFS"
  echo "🛠️  REFERENCES_MODE=augment — existing content will be wrapped after canonical generation."
  # In augment mode, drop existing-references tracking so we generate fresh
  EXISTING_HAS_REFERENCES=false
fi

# In reset mode, also drop existing-references tracking
if [ "$REFERENCES_MODE" = "reset" ]; then
  EXISTING_HAS_REFERENCES=false
fi

echo ""
echo "🔗 Discovering external references..."
echo ""

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PARENT_DIR="$(cd "$REPO_ROOT/.." && pwd)"

# Reconciliation: load existing entries (if any) so we can filter duplicates from discovery
EXISTING_REFS_TMP=""
if [ "$EXISTING_HAS_REFERENCES" = true ] && [ "$RESET_MODE" = false ]; then
  EXISTING_REFS_TMP="$(mktemp)"
  # Spec corpus paths
  if declare -F ss_references_spec_corpus_paths >/dev/null; then
    while IFS= read -r p; do
      [ -n "$p" ] && printf 'spec|%s|%s||\n' "$(basename "$p")" "$p" >> "$EXISTING_REFS_TMP"
    done < <(ss_references_spec_corpus_paths)
  fi
  # Reference codebases (already TSV from loader: name<TAB>path<TAB>verify-file<TAB>rationale)
  if declare -F ss_references_codebases >/dev/null; then
    while IFS=$'\t' read -r name path verify rationale; do
      [ -n "$name" ] && printf 'codebase|%s|%s|%s|%s\n' "$name" "$path" "$verify" "$rationale" >> "$EXISTING_REFS_TMP"
    done < <(ss_references_codebases)
  fi
  # Memory directories
  if declare -F ss_references_memory_dirs >/dev/null; then
    while IFS= read -r p; do
      [ -n "$p" ] && printf 'memory|%s|%s||\n' "$(basename "$p")" "$p" >> "$EXISTING_REFS_TMP"
    done < <(ss_references_memory_dirs)
  fi

  EXISTING_REFS_COUNT=$(wc -l < "$EXISTING_REFS_TMP" 2>/dev/null || echo "0")
  if [ "$EXISTING_REFS_COUNT" -gt 0 ]; then
    echo "♻️  Found $EXISTING_REFS_COUNT existing reference(s) in .specswarm/references.md — these will be preserved."
    echo ""
  fi
fi

# Auto-discovery: candidates accumulated as TSV (kind|name|path|verify-file|rationale)
DISCOVERED=()

# 0. (v7.0.0) Discovery-output consumer — preferred over static pattern scan when available
#    Reads .specswarm/.discovery.tmp (written by Step 3.0) and adds:
#      - spec-doc records as "spec|<basename>|<rel-path>||"
#      - reference-codebase records as "codebase|<name>|<path>|README.md|<one-sentence-summary>"
#    The static scans below (sections 1, 2, 3) still run; they catch anything discovery missed.
if [ "${DISCOVERY_AVAILABLE:-false}" = true ] && [ -s "$REPO_ROOT/.specswarm/.discovery.tmp" ]; then
  echo "🔄 Step 3.5: consuming discovery output for candidate filtering..."
  while IFS=$'\t' read -r category path size summary; do
    case "$category" in
      spec-doc)
        [ -z "$path" ] && continue
        DISCOVERED+=("spec|$(basename "$path")|$path||")
        ;;
      reference-codebase)
        [ -z "$path" ] && continue
        DISCOVERED+=("codebase|$(basename "$path")|$path|README.md|${summary:-Reference codebase (from discovery)}")
        ;;
    esac
  done < "$REPO_ROOT/.specswarm/.discovery.tmp"
fi

# 1. Sibling git repos that share a name stem with the current repo
#    (Stem = chars before first hyphen/underscore/dot in the current repo's basename.
#     This filters out unrelated siblings in shared parent dirs like ~/code-projects/.)
REPO_NAME="$(basename "$REPO_ROOT")"
REPO_STEM=$(echo "$REPO_NAME" | sed -E 's/[-._].*$//')

if [ -d "$PARENT_DIR" ] && [ -n "$REPO_STEM" ]; then
  for sibling in "$PARENT_DIR"/*/; do
    [ -d "$sibling/.git" ] || continue
    sibling_path="${sibling%/}"
    sibling_name="$(basename "$sibling_path")"
    [ "$sibling_name" = "$REPO_NAME" ] && continue

    # Stem-similarity filter: sibling name must contain our stem as a substring
    # (case-insensitive). Skip otherwise.
    if ! echo "$sibling_name" | grep -qiF "$REPO_STEM"; then
      continue
    fi

    # Auto-detect a verify-file by walking common manifest filenames
    verify_file=""
    for candidate in package.json Cargo.toml go.mod pyproject.toml requirements.txt composer.json Gemfile pom.xml build.gradle; do
      if [ -f "$sibling_path/$candidate" ]; then
        verify_file="$candidate"
        break
      fi
    done
    [ -z "$verify_file" ] && verify_file="README.md"

    DISCOVERED+=("codebase|$sibling_name|../$sibling_name|$verify_file|Sibling repository (auto-detected; shares '$REPO_STEM' stem)")
  done
fi

# 2. Common spec doc patterns in repo root, ../docs/, ../spec/, parent dir
SPEC_PATTERNS=(
  "PRD.md" "ARCHITECTURE.md" "ROADMAP.md" "DESIGN.md" "SPEC.md" "REQUIREMENTS.md"
  "INTERACTION-FLOWS.md" "CREATING-THE-STRATEGY.md" "BUILDER-KICKOFF.md" "SPEC-BACKLOG.md"
)
SEARCH_DIRS=("$REPO_ROOT" "$REPO_ROOT/docs" "$PARENT_DIR" "$PARENT_DIR/docs" "$PARENT_DIR/spec")

for dir in "${SEARCH_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for pattern in "${SPEC_PATTERNS[@]}"; do
    [ -f "$dir/$pattern" ] || continue
    # Compute path relative to repo root
    rel_path=$(realpath --relative-to="$REPO_ROOT" "$dir/$pattern" 2>/dev/null || echo "$dir/$pattern")
    DISCOVERED+=("spec|$pattern|$rel_path||")
  done
done

# 3. Claude Code memory directory at the canonical path for this repo
MEM_PATH_KEY=$(echo "$REPO_ROOT" | tr / -)
CANONICAL_MEM_DIR="$HOME/.claude/projects/${MEM_PATH_KEY}/memory"
GENERIC_MEM_DIR="$HOME/.claude/memory"

if [ -d "$CANONICAL_MEM_DIR" ]; then
  DISCOVERED+=("memory|claude-project-memory|$CANONICAL_MEM_DIR||")
fi
if [ -d "$GENERIC_MEM_DIR" ]; then
  DISCOVERED+=("memory|claude-global-memory|$GENERIC_MEM_DIR||")
fi

# Display discovered candidates
DISCOVERED_COUNT=${#DISCOVERED[@]}

if [ "$DISCOVERED_COUNT" -eq 0 ]; then
  echo "ℹ️  No reference candidates auto-discovered."
  echo "   You can manually edit .specswarm/references.md after init if you have"
  echo "   external spec docs, legacy/prototype codebases, or memory directories"
  echo "   you want SpecSwarm to consult."
  echo ""
else
  echo "Found $DISCOVERED_COUNT candidate reference(s):"
  echo ""
  spec_count=0
  codebase_count=0
  memory_count=0
  for entry in "${DISCOVERED[@]}"; do
    IFS='|' read -r kind name path verify_file rationale <<< "$entry"
    case "$kind" in
      spec)     echo "  📄 [spec corpus]    $path"; spec_count=$((spec_count+1)) ;;
      codebase) echo "  📦 [codebase]       $name → $path (verify: $verify_file)"; codebase_count=$((codebase_count+1)) ;;
      memory)   echo "  🧠 [memory dir]     $path"; memory_count=$((memory_count+1)) ;;
    esac
  done
  echo ""
fi

# Save discovered candidates to a temp file for the AskUserQuestion step
mkdir -p "$REPO_ROOT/.specswarm"
DISCOVERY_TMP="$REPO_ROOT/.specswarm/.references-discovery.tmp"
printf '%s\n' "${DISCOVERED[@]}" > "$DISCOVERY_TMP"

# Reconciliation: filter out candidates already present in EXISTING_REFS_TMP (matched by path)
if [ -n "$EXISTING_REFS_TMP" ] && [ -s "$EXISTING_REFS_TMP" ]; then
  FILTERED_TMP="$(mktemp)"
  while IFS='|' read -r kind name path verify_file rationale; do
    [ -z "$kind" ] && continue
    if grep -qE "^${kind}\|[^|]*\|${path}\|" "$EXISTING_REFS_TMP"; then
      continue  # already known
    fi
    printf '%s|%s|%s|%s|%s\n' "$kind" "$name" "$path" "$verify_file" "$rationale" >> "$FILTERED_TMP"
  done < "$DISCOVERY_TMP"
  mv "$FILTERED_TMP" "$DISCOVERY_TMP"
  DISCOVERED_COUNT=$(wc -l < "$DISCOVERY_TMP" 2>/dev/null || echo "0")
  echo "🔎 After filtering already-known references: $DISCOVERED_COUNT new candidate(s)."
  echo ""
fi
```

If `$DISCOVERED_COUNT > 0`, use **AskUserQuestion**:

```
Question: "Use the discovered references?"
Header: "References"
Options:
  1. "Use all discovered"
     Description: "Add all candidates above to .specswarm/references.md as-is. You can edit the file after."
  2. "Pick which to use"
     Description: "Walk through each candidate and accept/reject individually."
  3. "Skip — none of these"
     Description: "Don't generate references.md from auto-discovery. You can manually create it later."
```

Store in `$REF_DISCOVERY_CHOICE`.

If `$REF_DISCOVERY_CHOICE` == "Pick which to use":

For each entry in the discovery temp file, use **AskUserQuestion**:

```
Question: "Include {name} ({kind})?"
Header: "Reference"
Options:
  1. "Yes, include"
     Description: "{path} (verify-file: {verify_file})"
  2. "No, skip"
     Description: "Don't add this reference"
```

Track the user's accept/reject choices in `$ACCEPTED_ENTRIES` (re-using the TSV format).

If `$REF_DISCOVERY_CHOICE` == "Use all discovered":
  `$ACCEPTED_ENTRIES = $DISCOVERED`

If `$REF_DISCOVERY_CHOICE` == "Skip — none of these":
  `$ACCEPTED_ENTRIES = empty`

Use **AskUserQuestion** to allow manual additions:

```
Question: "Add reference codebases or spec docs not auto-discovered?"
Header: "More references"
Options:
  1. "No, that's enough"
     Description: "Use only what was discovered + accepted."
  2. "Add a reference codebase"
     Description: "Specify a path to a legacy/prototype/sibling repo manually."
  3. "Add a spec corpus document"
     Description: "Specify a path to a markdown spec document manually."
```

If user picks "Add a reference codebase" or "Add a spec corpus document", prompt for path, name (codebases only), verify-file (codebases only — auto-detect if possible), and rationale (codebases only). Append to `$ACCEPTED_ENTRIES`. Loop until user picks "No, that's enough" or has added 5 entries (cap to keep init bounded).

Now write `.specswarm/references.md`. The merged file is `existing entries (preserved) + newly accepted candidates`.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DISCOVERY_TMP="$REPO_ROOT/.specswarm/.references-discovery.tmp"
REFS_FILE="$REPO_ROOT/.specswarm/references.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="${PLUGIN_DIR}/templates/references.md.template"

# Build the final set of entries to write:
#   FINAL_TMP = EXISTING_REFS_TMP (preserved) + DISCOVERY_TMP.accepted (new)
FINAL_TMP="$(mktemp)"
[ -s "$EXISTING_REFS_TMP" ] && cat "$EXISTING_REFS_TMP" >> "$FINAL_TMP"
[ -s "${DISCOVERY_TMP}.accepted" ] && cat "${DISCOVERY_TMP}.accepted" >> "$FINAL_TMP"

# Skip writing entirely if there's nothing to write AND no existing file to preserve.
# (A pre-existing references.md with EVERYTHING dropped on this run should still be
#  preserved verbatim — the early-load step already captured its content.)
if [ ! -s "$FINAL_TMP" ]; then
  echo "  No references selected. Skipping .specswarm/references.md generation."
  rm -f "$DISCOVERY_TMP" "${DISCOVERY_TMP}.accepted" "$FINAL_TMP" "$EXISTING_REFS_TMP" 2>/dev/null
else
  # Start from the canonical template header (just the doc-block / schema notice),
  # then re-emit each section from FINAL_TMP. Falls back to inline header if the
  # template file is unavailable.
  if [ -f "$TEMPLATE" ]; then
    # Take everything from the template up to (but not including) the first "## Spec corpus" heading.
    awk '/^## Spec corpus/ { exit } { print }' "$TEMPLATE" > "$REFS_FILE"
  else
    cat > "$REFS_FILE" << 'HEADER'
# References

> External authoritative sources this project depends on. Generated by `/ss:init`
> on initial setup; safe to hand-edit any time. SpecSwarm re-reads on every
> relevant command invocation.
>
> Schema reference: `plugins/ss/templates/references.md.template`

---

HEADER
  fi

  # Spec corpus section
  echo "## Spec corpus" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"
  spec_count=0
  while IFS='|' read -r kind name path verify_file rationale; do
    [ "$kind" = "spec" ] || continue
    echo "- path: $path" >> "$REFS_FILE"
    # Stale-flag if path no longer exists
    abs_path="$path"
    [[ "$abs_path" != /* ]] && abs_path="$REPO_ROOT/$path"
    if [ ! -e "$abs_path" ]; then
      echo "  <!-- stale: path not found $(date +%Y-%m-%d) -->" >> "$REFS_FILE"
    fi
    spec_count=$((spec_count+1))
  done < "$FINAL_TMP"
  if [ "$spec_count" -eq 0 ]; then
    echo "<!-- No spec corpus configured. Add markdown docs SpecSwarm should consult during /ss:specify and /ss:clarify. -->" >> "$REFS_FILE"
  fi
  echo "" >> "$REFS_FILE"
  echo "---" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"

  # Reference codebases section
  echo "## Reference codebases" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"
  codebase_count=0
  while IFS='|' read -r kind name path verify_file rationale; do
    [ "$kind" = "codebase" ] || continue
    {
      echo "- name: $name"
      echo "  path: $path"
      echo "  verify-file: $verify_file"
      echo "  rationale: $rationale"
    } >> "$REFS_FILE"
    abs_path="$path"
    [[ "$abs_path" != /* ]] && abs_path="$REPO_ROOT/$path"
    if [ ! -e "$abs_path" ]; then
      echo "  <!-- stale: path not found $(date +%Y-%m-%d) -->" >> "$REFS_FILE"
    fi
    echo "" >> "$REFS_FILE"
    codebase_count=$((codebase_count+1))
  done < "$FINAL_TMP"
  if [ "$codebase_count" -eq 0 ]; then
    echo "<!-- No reference codebases configured. Add legacy/prototype/sibling repos to be verified at session start. -->" >> "$REFS_FILE"
    echo "" >> "$REFS_FILE"
  fi
  echo "---" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"

  # Memory directories section
  echo "## Memory directories" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"
  memory_count=0
  while IFS='|' read -r kind name path verify_file rationale; do
    [ "$kind" = "memory" ] || continue
    echo "- path: $path" >> "$REFS_FILE"
    # Memory paths can be ~-relative; expand for existence check
    abs_path="${path/#\~/$HOME}"
    if [ ! -e "$abs_path" ]; then
      echo "  <!-- stale: path not found $(date +%Y-%m-%d) -->" >> "$REFS_FILE"
    fi
    memory_count=$((memory_count+1))
  done < "$FINAL_TMP"
  if [ "$memory_count" -eq 0 ]; then
    echo "<!-- No memory directories configured. Add Claude Code memory paths so /ss:init can propose principles auto-extracted from feedback_*.md and project_*.md files. -->" >> "$REFS_FILE"
  fi

  TOTAL_REF_ENTRIES=$((spec_count + codebase_count + memory_count))
  echo "✅ Wrote .specswarm/references.md ($TOTAL_REF_ENTRIES entries)"

  # Augment mode: wrap the pre-augment freeform content beneath the canonical schema
  if [ "$REFERENCES_MODE" = "augment" ] && [ -n "$PRE_AUGMENT_REFS" ] && [ -f "$PRE_AUGMENT_REFS" ]; then
    ss_augment_with_skeleton \
      "$PRE_AUGMENT_REFS" \
      "$REFS_FILE" \
      "Existing freeform content moved to 'Pre-existing Content' so SpecSwarm can read the canonical schema above."
    mv "$PRE_AUGMENT_REFS" "$REFS_FILE"
    echo "✅ Augmented .specswarm/references.md (existing content wrapped in ss:user-additions)"
  fi

  # Cleanup
  rm -f "$DISCOVERY_TMP" "${DISCOVERY_TMP}.accepted" "$FINAL_TMP" "$EXISTING_REFS_TMP" 2>/dev/null
fi

fi  # end: if [ "$REFERENCES_MODE" != "keep" ]

echo ""
```

**Note for the implementer:** when the user picks "Use all discovered" the implementation should `cp "$DISCOVERY_TMP" "${DISCOVERY_TMP}.accepted"`. When the user picks individually, append accepted entries to `${DISCOVERY_TMP}.accepted`. When the user picks "Skip", leave `${DISCOVERY_TMP}.accepted` empty / non-existent. The reconciliation merge with existing entries happens after, via `FINAL_TMP`.

---

### Step 4: Create, reconcile, or augment .specswarm/constitution.md

**Branching logic by mode** (`CONSTITUTION_MODE` set in Step 1.6, defaults to `normal`):

| Condition | Action |
|---|---|
| `CONSTITUTION_MODE=keep` | Skip Step 4 entirely. User asked for no changes this run. |
| `EXISTING_HAS_CONSTITUTION=false` OR `RESET_MODE=true` OR `CONSTITUTION_MODE=reset` | Invoke `/ss:constitution` via **SlashCommand** to generate fresh (it wholesale-overwrites, which is what we want here). |
| `CONSTITUTION_MODE=augment` | Call `ss_augment_with_skeleton` with `plugins/ss/templates/constitution.skeleton.md`. User's prose principles are preserved inside an `ss:user-additions` block at the bottom; the canonical skeleton with rule-block examples is prepended. |
| `EXISTING_HAS_CONSTITUTION=true` AND mode=`normal` | Reconciliation: leave file in place, run only the memory-driven proposals (Step 4.5) and stale-glob check below. **Do NOT call `/ss:constitution`** — its wholesale-rewrite would clobber developer content. |

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

if [ "$CONSTITUTION_MODE" = "keep" ]; then
  echo "⏭️  CONSTITUTION_MODE=keep — skipping Step 4."
elif [ "$CONSTITUTION_MODE" = "augment" ]; then
  echo "🛠️  Augmenting .specswarm/constitution.md with canonical rule-block skeleton..."
  ss_augment_with_skeleton \
    "$REPO_ROOT/.specswarm/constitution.md" \
    "$PLUGIN_DIR/templates/constitution.skeleton.md" \
    "Add <!-- specswarm-rule: ... --> blocks beneath the example principles, or beneath your own preserved content below."
  echo "✅ Augmented .specswarm/constitution.md"
elif [ "$EXISTING_HAS_CONSTITUTION" = false ] || [ "$RESET_MODE" = true ] || [ "$CONSTITUTION_MODE" = "reset" ]; then
  echo "📝 Creating .specswarm/constitution.md..."
  # Use SlashCommand tool to run:
  #   /ss:constitution
  # (with custom principles if PRINCIPLES_CHOICE = "custom")
  echo "✅ Created .specswarm/constitution.md"
else
  echo "♻️  Reconciling existing .specswarm/constitution.md (preserving all principles)..."
fi
```

**Stale rule-block check** (runs if `constitution.md` exists AND `CONSTITUTION_MODE != keep`). For each rule block whose `path-glob` no longer matches any file in the repo, append `<!-- stale: glob matches no files YYYY-MM-DD -->` after the block. Never delete principles.

```bash
if [ -f "$REPO_ROOT/.specswarm/constitution.md" ] && [ "$CONSTITUTION_MODE" != "keep" ]; then
  awk -v today="$(date +%Y-%m-%d)" '
    BEGIN { glob = "" }
    /<!-- path-glob:/ {
      glob = $0
      sub(/.*<!-- path-glob:[[:space:]]*/, "", glob)
      sub(/[[:space:]]*-->.*/, "", glob)
    }
    /<!-- summary:.*-->/ && glob != "" {
      # End of a rule block. Check if glob matches anything.
      cmd = "compgen -G \"" glob "\" 2>/dev/null | head -1"
      cmd | getline match_result
      close(cmd)
      print
      if (match_result == "") {
        print "<!-- stale: glob matches no files " today " -->"
      }
      glob = ""
      next
    }
    { print }
  ' "$REPO_ROOT/.specswarm/constitution.md" > "$REPO_ROOT/.specswarm/constitution.md.tmp" \
    && mv "$REPO_ROOT/.specswarm/constitution.md.tmp" "$REPO_ROOT/.specswarm/constitution.md"
fi
```

<!-- ========== CONSTITUTIONAL HOOK GENERATION (SpecSwarm 5.3.0) ========== -->
<!-- Added by Marty Bonacci & Claude Code (2026) — invisible enforcement -->

**Generate constitutional warning hooks** from any structured rule blocks in the constitution. Idempotent — never overwrites existing generated hooks. Runs on every `/ss:init` invocation so newly-added principles always pick up hooks.

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLUGIN_DIR/lib/constitution-parser.sh" ]; then
  source "$PLUGIN_DIR/lib/constitution-parser.sh"
  generate_constitutional_hooks "${REPO_ROOT}/.specswarm/constitution.md" "${REPO_ROOT}/.specswarm/hooks/generated"
fi
```

Constitution authors can opt principles into mechanical enforcement by adding HTML-comment rule blocks beneath the principle. Three rule types are supported (`no-pattern`, `required-pattern`, `required-pair`). Hooks are warning-only by default; `severity: block` produces blocking hooks. See `plugins/ss/lib/constitution-parser.sh` header for the rule-block syntax.

<!-- ========== END CONSTITUTIONAL HOOK GENERATION ========== -->

---

### Step 4.5: Memory-Driven Principle Import (NEW in v6.2.0)

**Skip this step if `--minimal` flag is present.**

If the user populated memory directories in `.specswarm/references.md` (Step 3.5), this step scans those directories for `feedback_*.md` / `project_*.md` / `reference_*.md` files, surfaces them as candidate principles, and appends accepted ones to `.specswarm/constitution.md`. Skipped silently if no memory dirs are configured.

The pattern: Claude Code memory files often encode opinionated rules in prose ("calculation engine math must NEVER be on the frontend") that map cleanly onto the SpecSwarm constitutional-hook format (`no-pattern-in-paths` / `required-import-in-files` / `required-pair-in-additions`). This step does that translation interactively — the user wrote the memory once, SpecSwarm proposes the mechanical enforcement, the user accepts or rejects each proposal.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PLUGIN_DIR_SS_MEM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOADER_MEM="${PLUGIN_DIR_SS_MEM}/lib/references-loader.sh"

MEMORY_AVAILABLE=false

if [ -f "$LOADER_MEM" ]; then
  # shellcheck disable=SC1090
  source "$LOADER_MEM"

  if ss_references_exist; then
    MEM_FILE_COUNT=$(ss_memory_scan_files | wc -l)
    if [ "$MEM_FILE_COUNT" -gt 0 ]; then
      MEMORY_AVAILABLE=true
    fi
  fi
fi

if [ "$MEMORY_AVAILABLE" = true ]; then
  echo ""
  echo "🧠 Memory-Driven Principle Import"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Found $MEM_FILE_COUNT memory file(s) across declared memory directories."
  echo ""
  ss_memory_count_by_kind | while IFS=$'\t' read -r kind count; do
    [ "$count" -eq 0 ] && continue
    case "$kind" in
      feedback)  echo "   📐 $count feedback file(s)   — opinionated rules / preferences (high principle yield)" ;;
      project)   echo "   📋 $count project file(s)    — project state / context (lower yield)" ;;
      reference) echo "   🔗 $count reference file(s)  — cross-references" ;;
      user)      echo "   👤 $count user file(s)       — user-profile context" ;;
    esac
  done
  echo ""
fi
```

**If `MEMORY_AVAILABLE = true`, you (Claude) MUST do the following:**

a. **Ask the user first**, before reading anything, via **AskUserQuestion**:

```
Question: "Scan memory files to propose constitution principles?"
Header: "Memory import"
Options:
  1. "Yes, scan all"
     Description: "Read every memory file and propose principles. You'll review/accept/reject each proposal individually."
  2. "Yes, feedback files only"
     Description: "Skip project/reference/user files — they rarely yield principles. Reads only feedback_*.md (highest yield)."
  3. "Skip memory import"
     Description: "Constitution stays as generated by Step 4. You can re-run /ss:init later or hand-author additions."
```

Store as `$MEMORY_SCAN_SCOPE`.

b. **If `$MEMORY_SCAN_SCOPE` == "Skip memory import"**, jump straight to Step 5.

c. **Otherwise, scan memory files in scope:**
- Use `Bash` to enumerate: `ss_memory_scan_files | while read f; do kind=$(ss_memory_classify_kind "$f"); ...`
- For "feedback files only" mode: filter to `kind == "feedback"`
- For "scan all" mode: include feedback + project + reference (skip `user_*.md` — rarely encodes enforceable rules)

d. **For each in-scope memory file**, use the `Read` tool to load its content. Then analyze: does this memory entry describe an *enforceable* rule that maps to one of the three constitutional-hook templates?

   **Eligibility heuristics — propose a principle when the memory contains:**
   - Imperative language: "must NEVER", "always", "required to", "forbidden", "only"
   - Mechanical enforcement signal: a specific pattern that can be regex-matched in source code (e.g., import statements, function calls, file path globs)
   - Rationale: a "why" the rule exists (the memory itself usually has this)

   **Skip files that are pure context/state, not rules:**
   - Lists of decisions made (use spec corpus consultation in /ss:specify, not constitution)
   - Tech stack inventories (handled by tech-stack.md, not constitution)
   - Project metadata (status, contacts, links)
   - Memory whose enforcement would require runtime semantics, not static-text matching

e. **For each eligible memory file**, draft a principle in the constitution-hook format the parser actually accepts (`lib/constitution-parser.sh`). Each rule block is a contiguous run of HTML comments, one `key: value` per line, with the rule type on the first line. Map to one of three types:

   - **no-pattern** — "X must never appear in files matching Y"
     Example (drafted from `feedback_trade_secrets.md`):
     ```markdown
     ### Trade-secret math is server-side only

     <!-- specswarm-rule: no-pattern -->
     <!-- path-glob: app/components/** -->
     <!-- bad-pattern: from\s+['"].*board-calculator -->
     <!-- summary: Trade-secret math is server-side only -->
     <!-- severity: block -->
     ```
     Rationale source: `feedback_trade_secrets.md` — calculation engine math must never reach the frontend bundle. Severity=block because leakage is unrecoverable.

   - **required-pattern** — "Files matching Y must contain X"
     Example (drafted from a hypothetical `feedback_v2_reference_required.md`):
     ```markdown
     ### v2 source mandatory for calc-engine work

     <!-- specswarm-rule: required-pattern -->
     <!-- path-glob: app/engine/** -->
     <!-- required-pattern: // v2-ref: customcult2/ -->
     <!-- summary: v2 source mandatory for calc-engine work -->
     ```
     Rationale source: `feedback_v2_reference_required.md` — calc engine port delegates to v2 PHP as canonical. Severity default (warn) — missing tag is fixable, not a leak.

   - **required-pair** — "When pattern A appears, pattern B must also appear in the same file"
     Example (drafted from `project_admin_audit_log.md`):
     ```markdown
     ### Admin writes require audit_log entry

     <!-- specswarm-rule: required-pair -->
     <!-- path-glob: app/routes/admin/** -->
     <!-- trigger-pattern: db\.(insert|update|delete) -->
     <!-- pair-pattern: audit_log\( -->
     <!-- summary: Admin writes require audit_log entry -->
     <!-- severity: block -->
     ```
     Rationale source: `project_admin_audit_log.md` — every admin mutation logs admin_audit_log row. Severity=block because silent audit-log skipping is a compliance gap.

   **Severity selection heuristic (v6.3.0).** Default to `severity: warn` (or omit the field). Propose `severity: block` when the source memory entry contains any of these gravity signals: `must NEVER`, `trade secret`, `compliance`, `audit`, `leak`, `pii`, `secret`, `forbidden`, `unrecoverable`, or explicit language indicating that a false negative produces irreversible damage. When in doubt, propose warn — the user can re-rank to block in step f below.

f. **Surface each draft principle to the user** via **AskUserQuestion**, including a severity choice:

```
Question: "Add this principle to constitution.md?"
Header: "Principle N/M"
Options:
  1. "Yes — add at proposed severity (<warn|block>)"
     Description: "[show principle title + drafted severity + first line of rationale]"
  2. "Yes — but flip severity to <opposite>"
     Description: "Same principle, opposite severity. Pick this if you want stronger/weaker enforcement than the heuristic chose."
  3. "Yes — but I'll edit later"
     Description: "Add at proposed severity; you'll hand-edit the regex/glob/severity in constitution.md after init."
  4. "No, skip this one"
     Description: "Memory file is too prose-y / not enforceable / I'll keep this as memory only."
```

Track each accept/reject + severity choice. Cap proposals at **10 principles per init** to keep the session bounded.

g. **For each accepted principle**, append it to `.specswarm/constitution.md` under a section header `## Imported from memory (auto-proposed YYYY-MM-DD)`. Don't overwrite existing sections.

h. **Re-run constitutional hook generation** so the newly-imported principles get their PostToolUse hooks generated. The same `generate_constitutional_hooks` function from Step 4 is called again — it's idempotent and only creates hooks for principles that don't already have one.

```bash
if [ -f "$PLUGIN_DIR_SS_MEM/lib/constitution-parser.sh" ]; then
  source "$PLUGIN_DIR_SS_MEM/lib/constitution-parser.sh"
  generate_constitutional_hooks "${REPO_ROOT}/.specswarm/constitution.md" "${REPO_ROOT}/.specswarm/hooks/generated"
  echo ""
  echo "✅ Imported principles → generated constitutional hooks (warn + block)"
fi
```

**Note on severity changes:** the generator preserves existing hook files (so user edits aren't clobbered). If you change a principle's severity in `constitution.md` after import, delete the corresponding file under `.specswarm/hooks/generated/` to force regeneration with the new severity.

i. **Display summary**:
```bash
echo ""
echo "🧠 Memory Import Summary"
echo "   Files scanned:        $SCANNED_COUNT"
echo "   Principles proposed:  $PROPOSED_COUNT"
echo "   Principles accepted:  $ACCEPTED_COUNT"
echo "   Constitution.md:      .specswarm/constitution.md"
echo "   Generated hooks:      .specswarm/hooks/generated/"
echo ""
```

**If `MEMORY_AVAILABLE = false`**, skip Step 4.5 entirely. Proceed to Step 5. No banner, no prompts, no constitution edits — backward-compatible with v6.1.0 behavior when no memory dirs are declared.

---

### Step 5: Create, reconcile, or augment .specswarm/tech-stack.md

Behavior depends on `TECH_STACK_MODE` (set in Step 1.6, defaults to `normal`):

| Mode | Behavior |
|---|---|
| `keep` | Skip Step 5 entirely. |
| `reset` | Treat as fresh-init for this file (skip `ss_preserve_user_sections`; existing content lives only in `.backup/`). |
| `augment` | Run normal generation, then call `ss_augment_with_skeleton` so the canonical structure leads and user's original content is wrapped in `ss:user-additions` at the bottom. |
| `normal` | v6.4.0 reconciliation flow — generate from template, preserve `ss:user-additions` blocks from the prior file. |

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
TECH_STACK_FILE="$REPO_ROOT/.specswarm/tech-stack.md"

if [ "$TECH_STACK_MODE" = "keep" ]; then
  echo "⏭️  TECH_STACK_MODE=keep — skipping Step 5."
  # Use a flag so the trailing write block below is skipped too. The whole
  # block is enclosed in: if [ "$TECH_STACK_MODE" != "keep" ]; then ... fi
fi

if [ "$TECH_STACK_MODE" != "keep" ]; then

if [ "$TECH_STACK_MODE" = "augment" ]; then
  # Preserve the existing file's full content for augmentation after generation.
  PRE_AUGMENT_TECH_STACK="$(mktemp)"
  cp "$TECH_STACK_FILE" "$PRE_AUGMENT_TECH_STACK"
  echo "🛠️  Augmenting .specswarm/tech-stack.md (canonical structure will lead; your content moves into ss:user-additions block)..."
  OLD_TECH_STACK=""  # don't run preserve_user_sections; existing file has none
elif [ -f "$TECH_STACK_FILE" ] && [ "$RESET_MODE" = false ] && [ "$TECH_STACK_MODE" != "reset" ]; then
  echo "♻️  Reconciling .specswarm/tech-stack.md (preserving ss:user-additions blocks)..."
  OLD_TECH_STACK="$(mktemp)"
  cp "$TECH_STACK_FILE" "$OLD_TECH_STACK"
else
  echo "📝 Creating .specswarm/tech-stack.md..."
  OLD_TECH_STACK=""
fi

# Read template
TEMPLATE=$(cat "$PLUGIN_DIR/templates/tech-stack.template.md")

# Replace placeholders
OUTPUT="$TEMPLATE"
OUTPUT="${OUTPUT//\[PROJECT_NAME\]/$PROJECT_NAME}"
OUTPUT="${OUTPUT//\[DATE\]/$(date +%Y-%m-%d)}"
OUTPUT="${OUTPUT//\[AUTO_GENERATED\]/$([[ $AUTO_DETECT == true ]] && echo "Yes" || echo "No")}"
OUTPUT="${OUTPUT//\[FRAMEWORK\]/$FRAMEWORK}"
OUTPUT="${OUTPUT//\[FRAMEWORK_VERSION\]/$FRAMEWORK_VERSION}"
OUTPUT="${OUTPUT//\[FRAMEWORK_NOTES\]/"Functional components only (if React), composition API (if Vue)"}"
OUTPUT="${OUTPUT//\[LANGUAGE\]/$LANGUAGE}"
OUTPUT="${OUTPUT//\[LANGUAGE_VERSION\]/$LANGUAGE_VERSION}"
OUTPUT="${OUTPUT//\[LANGUAGE_NOTES\]/}"
OUTPUT="${OUTPUT//\[BUILD_TOOL\]/$BUILD_TOOL}"
OUTPUT="${OUTPUT//\[BUILD_TOOL_VERSION\]/$BUILD_TOOL_VERSION}"
OUTPUT="${OUTPUT//\[BUILD_TOOL_NOTES\]/}"

# State management section
if [ -n "$STATE_MGMT" ]; then
  STATE_SECTION="- **$STATE_MGMT**
  - Purpose: Application state management
  - Notes: Preferred over alternatives"
else
  STATE_SECTION="- No state management library detected
  - Recommendation: Use React Context for simple state, Zustand for complex state"
fi
OUTPUT="${OUTPUT//\[STATE_MANAGEMENT_SECTION\]/$STATE_SECTION}"

# Styling section
if [ -n "$STYLING" ]; then
  STYLE_SECTION="- **$STYLING**
  - Purpose: Component styling
  - Notes: Follow established patterns in codebase"
else
  STYLE_SECTION="- No styling framework detected
  - Recommendation: Consider Tailwind CSS for utility-first styling"
fi
OUTPUT="${OUTPUT//\[STYLING_SECTION\]/$STYLE_SECTION}"

# Testing section
UNIT_SECTION="${UNIT_TEST:-"Not configured - recommended: Vitest"}"
E2E_SECTION="${E2E_TEST:-"Not configured - recommended: Playwright"}"
OUTPUT="${OUTPUT//\[UNIT_TEST_FRAMEWORK\]/$UNIT_SECTION}"
OUTPUT="${OUTPUT//\[UNIT_TEST_VERSION\]/${UNIT_TEST_VERSION:-}}"
OUTPUT="${OUTPUT//\[E2E_TEST_FRAMEWORK\]/$E2E_SECTION}"
OUTPUT="${OUTPUT//\[E2E_TEST_VERSION\]/${E2E_TEST_VERSION:-}}"
OUTPUT="${OUTPUT//\[INTEGRATION_TEST_FRAMEWORK\]/${UNIT_TEST:-"Same as unit testing"}}"
OUTPUT="${OUTPUT//\[INTEGRATION_TEST_VERSION\]/${INTEGRATION_TEST_VERSION:-${UNIT_TEST_VERSION:-}}}"

# Approved libraries section
APPROVED_SECTION="### Data Validation
- Zod v4+ (runtime type validation)

### Utilities
- date-fns (date manipulation)
- lodash-es (utility functions, tree-shakeable)

### Forms (if applicable)
- React Hook Form (if using React)
- Zod validation integration

*Add project-specific approved libraries here*"
OUTPUT="${OUTPUT//\[APPROVED_LIBRARIES_SECTION\]/$APPROVED_SECTION}"

# Prohibited section
PROHIBITED_SECTION="### State Management
- ❌ Redux (use Zustand or Context API instead)
- ❌ MobX (prefer simpler alternatives)

### Deprecated Patterns
- ❌ Class components (use functional components with hooks)
- ❌ PropTypes (use TypeScript instead)
- ❌ Moment.js (use date-fns instead - smaller bundle)

*Add project-specific prohibited patterns here*"
OUTPUT="${OUTPUT//\[PROHIBITED_SECTION\]/$PROHIBITED_SECTION}"

# Notes section
NOTES_SECTION="- This file was ${AUTO_DETECT:+auto-detected from package.json and }created by \`/ss:init\`
- Update this file when adding new technologies or patterns
- Run \`/ss:init\` again to update with new detections"
OUTPUT="${OUTPUT//\[NOTES_SECTION\]/$NOTES_SECTION}"

# Write file
echo "$OUTPUT" > "$TECH_STACK_FILE"

# Preserve developer-edited regions from the previous version (if any)
if [ -n "$OLD_TECH_STACK" ] && [ -f "$OLD_TECH_STACK" ]; then
  if declare -F ss_preserve_user_sections >/dev/null; then
    ss_preserve_user_sections "$OLD_TECH_STACK" "$TECH_STACK_FILE"
  fi
  rm -f "$OLD_TECH_STACK"
  echo "✅ Reconciled .specswarm/tech-stack.md"
elif [ "$TECH_STACK_MODE" = "augment" ] && [ -n "$PRE_AUGMENT_TECH_STACK" ] && [ -f "$PRE_AUGMENT_TECH_STACK" ]; then
  # The file we just generated IS the canonical skeleton. Wrap the pre-augment
  # content beneath it via ss_augment_with_skeleton (which uses the just-written
  # file as the skeleton source).
  ss_augment_with_skeleton \
    "$PRE_AUGMENT_TECH_STACK" \
    "$TECH_STACK_FILE" \
    "Existing unstructured content was moved to the 'Pre-existing Content' section so SpecSwarm can read the canonical structure above."
  mv "$PRE_AUGMENT_TECH_STACK" "$TECH_STACK_FILE"
  echo "✅ Augmented .specswarm/tech-stack.md (existing content wrapped in ss:user-additions)"
else
  echo "✅ Created .specswarm/tech-stack.md"
fi

fi  # end: if [ "$TECH_STACK_MODE" != "keep" ]
```

---

### Step 6: Create, reconcile, or augment .specswarm/quality-standards.md

Same `QUALITY_MODE`-driven branching as Step 5 (`keep` / `reset` / `augment` / `normal`).

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
QUALITY_FILE="$REPO_ROOT/.specswarm/quality-standards.md"

if [ "$QUALITY_MODE" = "keep" ]; then
  echo "⏭️  QUALITY_MODE=keep — skipping Step 6."
fi

if [ "$QUALITY_MODE" != "keep" ]; then

if [ "$QUALITY_MODE" = "augment" ]; then
  PRE_AUGMENT_QUALITY="$(mktemp)"
  cp "$QUALITY_FILE" "$PRE_AUGMENT_QUALITY"
  echo "🛠️  Augmenting .specswarm/quality-standards.md (canonical YAML thresholds will lead; your content moves into ss:user-additions block)..."
  OLD_QUALITY=""
elif [ -f "$QUALITY_FILE" ] && [ "$RESET_MODE" = false ] && [ "$QUALITY_MODE" != "reset" ]; then
  echo "♻️  Reconciling .specswarm/quality-standards.md (preserving ss:user-additions blocks)..."
  OLD_QUALITY="$(mktemp)"
  cp "$QUALITY_FILE" "$OLD_QUALITY"
else
  echo "📝 Creating .specswarm/quality-standards.md..."
  OLD_QUALITY=""
fi

# Read template
TEMPLATE=$(cat "$PLUGIN_DIR/templates/quality-standards.template.md")

# Replace placeholders based on quality level
OUTPUT="$TEMPLATE"
OUTPUT="${OUTPUT//\[PROJECT_NAME\]/$PROJECT_NAME}"
OUTPUT="${OUTPUT//\[DATE\]/$(date +%Y-%m-%d)}"
OUTPUT="${OUTPUT//\[AUTO_GENERATED\]/Yes}"

# Quality thresholds
case "$QUALITY_LEVEL" in
  "Standard")
    MIN_QUALITY=80
    MIN_COVERAGE=80
    ;;
  "Strict")
    MIN_QUALITY=90
    MIN_COVERAGE=90
    ;;
  "Relaxed")
    MIN_QUALITY=70
    MIN_COVERAGE=70
    ;;
  "Custom")
    # Would be provided by user
    MIN_QUALITY="${CUSTOM_QUALITY:-80}"
    MIN_COVERAGE="${CUSTOM_COVERAGE:-80}"
    ;;
  *)
    MIN_QUALITY=80
    MIN_COVERAGE=80
    ;;
esac

OUTPUT="${OUTPUT//\[MIN_QUALITY_SCORE\]/$MIN_QUALITY}"
OUTPUT="${OUTPUT//\[MIN_TEST_COVERAGE\]/$MIN_COVERAGE}"
OUTPUT="${OUTPUT//\[ENFORCE_GATES\]/true}"

# Performance budgets
OUTPUT="${OUTPUT//\[ENFORCE_BUDGETS\]/true}"
OUTPUT="${OUTPUT//\[MAX_BUNDLE_SIZE\]/500}"
OUTPUT="${OUTPUT//\[MAX_INITIAL_LOAD\]/1000}"
OUTPUT="${OUTPUT//\[MAX_CHUNK_SIZE\]/200}"

# Code quality
OUTPUT="${OUTPUT//\[COMPLEXITY_THRESHOLD\]/10}"
OUTPUT="${OUTPUT//\[MAX_FILE_LINES\]/300}"
OUTPUT="${OUTPUT//\[MAX_FUNCTION_LINES\]/50}"
OUTPUT="${OUTPUT//\[MAX_FUNCTION_PARAMS\]/5}"

# Testing
OUTPUT="${OUTPUT//\[REQUIRE_TESTS\]/true}"

# Code review
OUTPUT="${OUTPUT//\[REQUIRE_CODE_REVIEW\]/true}"
OUTPUT="${OUTPUT//\[MIN_REVIEWERS\]/1}"

# CI/CD
OUTPUT="${OUTPUT//\[BLOCK_MERGE_ON_FAILURE\]/true}"

# Custom checks section
CUSTOM_CHECKS="### Performance Monitoring
- Monitor Core Web Vitals (LCP, FID, CLS)
- Set performance budgets in CI/CD

### Accessibility
- WCAG 2.1 Level AA compliance
- Automated a11y testing with axe-core

*Add project-specific checks here*"
OUTPUT="${OUTPUT//\[CUSTOM_CHECKS_SECTION\]/$CUSTOM_CHECKS}"

# Exemptions section
EXEMPTIONS="*No exemptions currently granted. Request exemptions via team discussion.*"
OUTPUT="${OUTPUT//\[EXEMPTIONS_SECTION\]/$EXEMPTIONS}"

# Notes section
NOTES="- Quality level: $QUALITY_LEVEL
- Created by \`/ss:init\`
- Enforced by \`/ss:ship\` before merge
- Review and adjust these standards for your team's needs"
OUTPUT="${OUTPUT//\[NOTES_SECTION\]/$NOTES}"

# Write file
echo "$OUTPUT" > "$QUALITY_FILE"

# Preserve developer-edited regions from the previous version (if any)
if [ -n "$OLD_QUALITY" ] && [ -f "$OLD_QUALITY" ]; then
  if declare -F ss_preserve_user_sections >/dev/null; then
    ss_preserve_user_sections "$OLD_QUALITY" "$QUALITY_FILE"
  fi
  rm -f "$OLD_QUALITY"
  echo "✅ Reconciled .specswarm/quality-standards.md"
elif [ "$QUALITY_MODE" = "augment" ] && [ -n "$PRE_AUGMENT_QUALITY" ] && [ -f "$PRE_AUGMENT_QUALITY" ]; then
  ss_augment_with_skeleton \
    "$PRE_AUGMENT_QUALITY" \
    "$QUALITY_FILE" \
    "Existing prose moved to 'Pre-existing Content' so /ss:ship can read the canonical YAML thresholds above."
  mv "$PRE_AUGMENT_QUALITY" "$QUALITY_FILE"
  echo "✅ Augmented .specswarm/quality-standards.md (existing content wrapped in ss:user-additions)"
else
  echo "✅ Created .specswarm/quality-standards.md"
fi

fi  # end: if [ "$QUALITY_MODE" != "keep" ]
```

---

### Step 6.5: Generate Convention Analysis

**Automatic — no user input required.**

Generate `.specswarm/conventions.md` by having Claude read key project files and synthesize coding conventions.

**Files to read** (if they exist):
- ESLint config (`.eslintrc.*`, `eslint.config.*`)
- TypeScript config (`tsconfig.json`)
- Prettier config (`.prettierrc*`)
- Biome config (`biome.json`, `biome.jsonc`)
- Existing `CLAUDE.md` or `AGENTS.md`
- 2-3 representative source files (see source-inventory note below)
- `package.json` scripts section

**Source-inventory note (v7.0.0):** when `DISCOVERY_AVAILABLE=true` and `.specswarm/.discovery.tmp` exists, the source files to read are the 3 largest `source-code` records by size from that file, parsed via:

```bash
awk -F'\t' '$1=="source-code" {print $3"\t"$2}' "$REPO_ROOT/.specswarm/.discovery.tmp" \
  | sort -nr | head -3 | cut -f2
```

Falls back to "largest 2-3 files in `src/` or project root" when discovery is unavailable. Either path yields a similar set in practice; the discovery-output path avoids a redundant filesystem traversal and respects the same `.gitignore` / size-cap policy used elsewhere in v7.

**Generate `.specswarm/conventions.md`** with these sections (note the `<!-- ss:user-additions -->` block at the bottom — content there is preserved across re-runs):

```markdown
# Project Conventions
<!-- Auto-generated by /ss:init — auto-detected sections are regenerated each run -->

## Code Style
- [Detected formatting rules: indent style, quotes, semicolons, etc.]
- [Linter configuration summary]

## Naming Conventions
- [File naming patterns observed in project]
- [Component/function naming patterns]
- [Variable naming conventions]

## Project Patterns
- [Import organization style]
- [Export patterns (named vs default)]
- [Error handling patterns]
- [State management patterns if applicable]

## Testing Conventions
- [Test file location and naming]
- [Testing patterns (describe/it, test, etc.)]
- [Mock/fixture patterns]

## Git Conventions
- [Branch naming from git log]
- [Commit message style from recent commits]

## Custom Conventions

<!-- ss:user-additions -->
<!-- Add project-specific conventions below. Content here is preserved on /ss:init re-run. -->
<!-- ss:end -->
```

```bash
CONVENTIONS_FILE="$REPO_ROOT/.specswarm/conventions.md"

if [ -f "$CONVENTIONS_FILE" ] && [ "$RESET_MODE" = false ]; then
  echo "♻️  Reconciling .specswarm/conventions.md (preserving ss:user-additions block)..."
  OLD_CONVENTIONS="$(mktemp)"
  cp "$CONVENTIONS_FILE" "$OLD_CONVENTIONS"
else
  echo "📝 Generating .specswarm/conventions.md..."
  OLD_CONVENTIONS=""
fi
echo "   Analyzing project files for coding conventions..."
```

Write the generated conventions to `.specswarm/conventions.md`. Then preserve any prior user additions.

```bash
if [ -n "$OLD_CONVENTIONS" ] && [ -f "$OLD_CONVENTIONS" ]; then
  if declare -F ss_preserve_user_sections >/dev/null; then
    ss_preserve_user_sections "$OLD_CONVENTIONS" "$CONVENTIONS_FILE"
  fi
  rm -f "$OLD_CONVENTIONS"
  echo "✅ Reconciled .specswarm/conventions.md"
else
  echo "✅ Created .specswarm/conventions.md"
fi
echo ""
```

---

### Step 6.7: MCP Server Recommendations

**Automatic — recommend and configure MCP servers based on detected tech stack.**

**Skip this step entirely if `--minimal` flag is present.**

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔌 MCP Server Recommendations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "MCP servers extend Claude Code with real-time access to"
echo "documentation, databases, browsers, and more."
echo ""
```

**Step 6.7a: Check for existing `.mcp.json`**

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
EXISTING_MCP=""
if [ -f "$REPO_ROOT/.mcp.json" ]; then
  EXISTING_MCP=$(cat "$REPO_ROOT/.mcp.json")
  echo "Found existing .mcp.json — will merge new servers with existing config."
  echo ""
fi
```

**Step 6.7b: Build curated recommendations from detected tech stack**

Match the detected technologies against this verified MCP server list. For each match, add it to the recommendations. **Do NOT recommend servers already configured in existing `.mcp.json`.**

| Detection Signal | Server Name | Type | Config | Benefit |
|---|---|---|---|---|
| Any project with a dependency file | `context7` | stdio | `npx -y @upstash/context7-mcp` | Version-specific docs for all dependencies — prevents using outdated APIs |
| `@supabase/supabase-js` in package.json or `supabase` in composer.json | `supabase` | http | url: `https://mcp.supabase.com/mcp` | Direct database queries, auth management, storage |
| `firebase` or `@firebase/*` in package.json | `firebase` | stdio | `npx -y firebase-tools@latest mcp` | Firestore, Cloud Functions, auth, hosting |
| `composer.json` exists AND Laravel framework detected | `laravel-boost` | stdio | `php artisan boost:mcp` | Artisan commands, Eloquent guidance, migration help |
| `playwright` or `@playwright/test` in package.json | `playwright` | stdio | `npx @playwright/mcp@latest` | Browser automation, E2E testing, visual validation |
| Git remote contains `github.com` | `github` | http | url: `https://api.githubcopilot.com/mcp/`, headers: `Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}` | PR management, issue tracking, code search |
| Git remote contains `gitlab` | `gitlab` | http | url: `https://gitlab.com/api/v4/mcp` | Merge requests, CI/CD pipelines, issue tracking |

**Step 6.7c: Dynamic discovery for remaining dependencies**

For each major dependency detected in Step 2 that is NOT covered by the curated list above:

1. Use the **WebSearch** tool to search for: `"[dependency-name] MCP server" site:github.com OR site:npmjs.com`
2. Filter results for official repositories (published by the technology vendor, not community forks)
3. If an official MCP server is found, extract its configuration (command, URL, env vars)
4. Add it to recommendations with a `[discovered]` label

Limit dynamic discovery to the **top 5 most significant dependencies** (by import frequency or prominence in the project) to avoid excessive searching. Skip dependencies that are utilities (lodash, date-fns) or build tools (vite, webpack) — focus on frameworks, databases, and services.

**Step 6.7d: Present recommendations to user**

Use the **AskUserQuestion** tool with multiSelect:

```
Question: "Which MCP servers should we configure for your project?"
Header: "MCP Servers"
multiSelect: true
Options (curated servers first, then discovered):
  - "context7 — Version-specific docs for all dependencies [verified]"
  - "[other curated matches]"
  - "[any discovered servers with [discovered] label]"
```

**Step 6.7e: Create or update `.mcp.json`**

For each approved server, build the `.mcp.json` configuration:

**stdio servers:**
```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
```

**http servers:**
```json
{
  "mcpServers": {
    "supabase": {
      "type": "http",
      "url": "https://mcp.supabase.com/mcp"
    }
  }
}
```

If `.mcp.json` already exists, merge new servers into the existing `mcpServers` object — do NOT overwrite existing server configurations.

Write the file to the project root.

**Step 6.7f: Display summary**

```bash
echo ""
echo "🔌 MCP Server Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
# For each configured server:
echo "   ✓ context7     — Version-specific docs for all dependencies"
echo "   ✓ supabase     — Database, auth, storage management"
# For each skipped server:
echo "   ✗ playwright   — Skipped"
echo ""
echo "📄 Created .mcp.json with MCP server configuration"
echo ""
echo "⚠️  RESTART Claude Code to activate MCP servers."
echo "   After restart, run /mcp to verify servers are connected."
echo ""
```

If no servers were approved, skip `.mcp.json` creation and display:
```bash
echo "ℹ️  No MCP servers configured. You can add them later with:"
echo "   claude mcp add context7 -- npx -y @upstash/context7-mcp"
echo ""
```

---

<!-- ========== PROJECT SUBAGENT SEEDING (SpecSwarm 5.3.0) ========== -->
<!-- Added by Marty Bonacci & Claude Code (2026) — invisible scaffolding -->

### Step 6.8: Seed Project Subagents from Tech Stack

**Purpose**: Generate `.claude/agents/ss-*.md` files matched to the detected tech stack so future `/ss:build` and `/ss:fix` runs can dispatch project-specific implementers. Idempotent — never overwrites existing files.

**YOU MUST run this seeding step:**

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLUGIN_DIR/lib/agent-generator.sh" ]; then
  source "$PLUGIN_DIR/lib/agent-generator.sh"
  generate_project_agents "$REPO_ROOT" ""
fi
```

The function will:
1. Read `.specswarm/tech-stack.md` to detect stack (React, Node API, Python, DB, etc.)
2. For each detected pattern, create a corresponding `.claude/agents/ss-<slug>.md` if not already present
3. Maintain `.specswarm/agents/manifest.json` so the orchestrator can route to the new agents
4. Print a one-line summary per generated agent (or stay silent if none generated)

**No user interaction required.** If no patterns are detected, the function emits nothing.

---

### Step 7: Summary and Next Steps

The summary distinguishes **fresh init** (no `.specswarm/` existed at start) from **reconciliation** (existing guides found). Reconciliation runs show per-file delta counts and the backup path.

```bash
RECONCILIATION_MODE=false
[ ${#EXISTING_FILES[@]} -gt 0 ] && [ "$RESET_MODE" = false ] && RECONCILIATION_MODE=true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RECONCILIATION_MODE" = true ]; then
  echo "         ✅ SPECSWARM GUIDES RECONCILED"
else
  echo "         ✅ PROJECT INITIALIZATION COMPLETE"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 SpecSwarm Guides:"
echo "   ✓ .specswarm/constitution.md      (governance & principles)"
if [ "${ACCEPTED_COUNT:-0}" -gt 0 ]; then
echo "      └─ +$ACCEPTED_COUNT principle(s) imported from memory"
fi
echo "   ✓ .specswarm/tech-stack.md        (approved technologies)"
echo "   ✓ .specswarm/quality-standards.md (quality gates)"
echo "   ✓ .specswarm/conventions.md       (code style & patterns)"
if [ -f "$REPO_ROOT/.specswarm/references.md" ]; then
echo "   ✓ .specswarm/references.md        (external authoritative sources)"
fi
if [ -f "$REPO_ROOT/.mcp.json" ]; then
echo "   ✓ .mcp.json                      (MCP server configuration)"
fi
echo ""

if [ "$RECONCILIATION_MODE" = true ]; then
  echo "♻️  Reconciliation:"
  echo "   Existing guides loaded:  ${#EXISTING_FILES[@]} file(s)"
  echo "   Backup location:         .specswarm/.backup/$BACKUP_TS/"
  echo "   Developer content:       <!-- ss:user-additions --> blocks preserved verbatim"
  echo ""
  STALE_COUNT=$(grep -rl 'stale: ' "$REPO_ROOT/.specswarm/"*.md 2>/dev/null | wc -l)
  if [ "$STALE_COUNT" -gt 0 ]; then
    echo "⚠️  $STALE_COUNT guide(s) contain new <!-- stale: ... --> markers — review and clean up."
    echo ""
  fi
fi

echo "📊 Configuration Summary:"
echo "   Project:        $PROJECT_NAME"
echo "   Framework:      $FRAMEWORK $FRAMEWORK_VERSION"
echo "   Language:       $LANGUAGE"
echo "   Quality Level:  $QUALITY_LEVEL"
echo "   Min Quality:    $MIN_QUALITY/100"
echo "   Min Coverage:   $MIN_COVERAGE%"
echo ""
echo "📚 Next Steps:"
echo ""
if [ "$RECONCILIATION_MODE" = true ]; then
  echo "   1. Review the reconciled guides in .specswarm/"
  echo "   2. Resolve any <!-- stale: ... --> markers"
  echo "   3. Continue development:"
  echo "      /ss:build \"your next feature\""
else
  echo "   1. Review the created files in .specswarm/"
  echo "   2. Customize as needed"
  echo "   3. Build your first feature:"
  echo "      /ss:build \"your feature description\""
  echo "   4. Ship when ready:"
  echo "      /ss:ship"
fi
echo ""
echo "💡 Tips:"
echo "   • Re-run /ss:init mid-development to refresh guides against project state"
echo "   • Add content inside <!-- ss:user-additions --> blocks to survive re-init"
echo "   • Tech stack enforcement prevents drift across features"
echo "   • Quality gates ensure consistent code quality"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

---

## Important Notes

### Auto-Detection Accuracy

The auto-detection logic parses `package.json` to identify:
- Framework (React, Vue, Angular, Next.js)
- Language (TypeScript vs JavaScript)
- Build tool (Vite, Webpack, built-in)
- State management (Zustand, Redux Toolkit, Jotai)
- Styling (Tailwind, Styled Components, Emotion)
- Testing frameworks (Vitest, Jest, Playwright, Cypress)

Detection is **best-effort** - users can always modify or override detected values.

### File Conflict Handling

If `.specswarm/*.md` guides already exist, `/ss:init` **reconciles** rather than overwrites:

- Every existing guide is backed up to `.specswarm/.backup/<timestamp>/` at the start of the run.
- Auto-generated portions are refreshed from current project state (with drift prompts).
- Developer-authored content inside `<!-- ss:user-additions -->` blocks is preserved verbatim.
- `references.md` entries are preserved; auto-discovery only proposes *new* candidates.
- `constitution.md` principles are never deleted; stale rule-block globs are flagged via HTML comment only.

Pass `--reset` to skip reconciliation and regenerate everything from scratch (backup still taken).

### Template Customization

Templates are located at:
- `plugins/ss/templates/tech-stack.template.md`
- `plugins/ss/templates/quality-standards.template.md`
- `plugins/ss/templates/references.md.template`

Teams can customize these templates for organization-specific standards. Preserve the `<!-- ss:user-additions -->` markers — they delineate the regions whose content survives `/ss:init` re-runs.

### Integration with Existing Commands

Once initialized, other commands reference these files:
- `/ss:build` - Enforces tech stack
- `/ss:ship` - Enforces quality gates
- `/ss:analyze-quality` - Reports against standards
- `/ss:upgrade` - Updates tech-stack.md

---

## Example Usage

### Basic Initialization
```bash
/ss:init
# Interactive questions, auto-detect tech stack
```

### Minimal Setup (No Questions)
```bash
/ss:init --minimal
# Uses all detected values and defaults
```

### Manual Tech Stack (No Auto-Detection)
```bash
/ss:init --skip-detection
# Asks for all technologies manually
```

### Mid-Development Refresh (Reconcile)
```bash
/ss:init
# When .specswarm/ exists: backs up + reconciles existing guides against current
# project state. User-authored ss:user-additions blocks are preserved verbatim.
```

### Discard Existing Guides and Start Over
```bash
/ss:init --reset
# Backs up existing guides, then regenerates everything from scratch.
# The backup at .specswarm/.backup/<TS>/ is your recovery path.
```
