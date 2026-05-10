---
description: "[migrating to /ss:init] Interactive project initialization"
effort: medium
args:
  - name: --skip-detection
    description: Skip automatic technology detection
    required: false
  - name: --minimal
    description: Use minimal defaults without interactive questions
    required: false
---

## User Input

```text
$ARGUMENTS
```

## Goal

Initialize a new project with SpecSwarm by creating three foundation files:
1. `.specswarm/constitution.md` - Project governance and coding principles
2. `.specswarm/tech-stack.md` - Approved technologies and prohibited patterns
3. `.specswarm/quality-standards.md` - Quality gates and performance budgets

This command streamlines project setup from 3 manual steps to a single interactive workflow.

---

## Execution Steps

### Step 1: Check for Existing Files

```bash
echo "🔍 Checking for existing SpecSwarm configuration..."
echo ""

EXISTING_FILES=()

if [ -f ".specswarm/constitution.md" ]; then
  EXISTING_FILES+=("constitution.md")
fi

if [ -f ".specswarm/tech-stack.md" ]; then
  EXISTING_FILES+=("tech-stack.md")
fi

if [ -f ".specswarm/quality-standards.md" ]; then
  EXISTING_FILES+=("quality-standards.md")
fi

if [ -f ".specswarm/conventions.md" ]; then
  EXISTING_FILES+=("conventions.md")
fi

if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
  echo "⚠️  Found existing configuration files:"
  for file in "${EXISTING_FILES[@]}"; do
    echo "   - .specswarm/$file"
  done
  echo ""
fi
```

If existing files found, use **AskUserQuestion** tool:

```
Question: "Existing configuration files detected. What would you like to do?"
Header: "Existing Files"
Options:
  1. "Update existing files"
     Description: "Merge new settings with existing configuration"
  2. "Backup and recreate"
     Description: "Save existing files to .backup/ and create fresh configuration"
  3. "Cancel initialization"
     Description: "Abort and keep existing configuration unchanged"
```

Store response in `$EXISTING_ACTION`.

If `$EXISTING_ACTION` == "Cancel", exit with message.
If `$EXISTING_ACTION` == "Backup and recreate", create backups:

```bash
mkdir -p .specswarm/.backup/$(date +%Y%m%d-%H%M%S)
for file in "${EXISTING_FILES[@]}"; do
  cp ".specswarm/$file" ".specswarm/.backup/$(date +%Y%m%d-%H%M%S)/$file"
done
echo "✅ Backed up existing files to .specswarm/.backup/"
```

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

Use **AskUserQuestion** tool for configuration:

```
Question 1: "What is your project name?"
Header: "Project"
Options:
  - Auto-detected from package.json "name" field or current directory name
  - Allow custom input via "Other" option
```

Store in `$PROJECT_NAME`.

```
Question 2 (if AUTO_DETECT=true): "We detected your tech stack. Is this correct?"
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

```
Question 6: "Do you want to use default coding principles?"
Header: "Principles"
Options:
  1. "Yes, use defaults"
     Description: "DRY, SOLID, type safety, test coverage, documentation"
  2. "Let me provide custom principles"
     Description: "Define your own 3-5 principles"
```

Store in `$PRINCIPLES_CHOICE`.

If `$PRINCIPLES_CHOICE` == "Let me provide custom":
  Ask for custom principles (text input via "Other" option or multiple questions)

---

### Step 3.5: References Discovery (NEW in v6.1.0)

**Skip this step if `--minimal` flag is present.**

Discovers external authoritative sources this project depends on — spec corpus markdown docs, reference codebases (legacy / prototype / sibling repos), and Claude Code memory directories — and writes a populated `.specswarm/references.md`. SpecSwarm consults references at session start (verification), during `/ss:specify` (extracts from spec corpus instead of fabricating), and during `/ss:clarify` (skips questions already answered in corpus or memory).

```bash
echo ""
echo "🔗 Discovering external references..."
echo ""

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PARENT_DIR="$(cd "$REPO_ROOT/.." && pwd)"

# Auto-discovery: candidates accumulated as TSV (kind|name|path|verify-file|rationale)
DISCOVERED=()

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

Now write `.specswarm/references.md`:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DISCOVERY_TMP="$REPO_ROOT/.specswarm/.references-discovery.tmp"
REFS_FILE="$REPO_ROOT/.specswarm/references.md"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${PLUGIN_DIR}/templates/references.md.template"

# If user accepted nothing, skip writing entirely (keeps the repo clean)
if [ ! -s "$DISCOVERY_TMP.accepted" ] 2>/dev/null && [ -z "$ACCEPTED_ENTRIES" ]; then
  echo "  No references selected. Skipping .specswarm/references.md generation."
  rm -f "$DISCOVERY_TMP" "$DISCOVERY_TMP.accepted" 2>/dev/null
else
  # Build the file from template + accepted entries
  cat > "$REFS_FILE" << 'HEADER'
# References

> External authoritative sources this project depends on. Generated by `/ss:init`
> on initial setup; safe to hand-edit any time. SpecSwarm re-reads on every
> relevant command invocation.
>
> Schema reference: `plugins/ss/templates/references.md.template`

---

HEADER

  # Spec corpus section
  echo "## Spec corpus" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"
  while IFS='|' read -r kind name path verify_file rationale; do
    [ "$kind" = "spec" ] || continue
    echo "- path: $path" >> "$REFS_FILE"
  done < "${DISCOVERY_TMP}.accepted"
  # If empty section, leave a placeholder comment so user knows where to add later
  if ! grep -q '^- path:' <(awk '/^## Spec corpus/,/^## /' "$REFS_FILE"); then
    echo "<!-- No spec corpus configured. Add markdown docs SpecSwarm should consult during /ss:specify and /ss:clarify. -->" >> "$REFS_FILE"
  fi
  echo "" >> "$REFS_FILE"
  echo "---" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"

  # Reference codebases section
  echo "## Reference codebases" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"
  has_codebase=false
  while IFS='|' read -r kind name path verify_file rationale; do
    [ "$kind" = "codebase" ] || continue
    has_codebase=true
    {
      echo "- name: $name"
      echo "  path: $path"
      echo "  verify-file: $verify_file"
      echo "  rationale: $rationale"
      echo ""
    } >> "$REFS_FILE"
  done < "${DISCOVERY_TMP}.accepted"
  if [ "$has_codebase" = false ]; then
    echo "<!-- No reference codebases configured. Add legacy/prototype/sibling repos to be verified at session start. -->" >> "$REFS_FILE"
    echo "" >> "$REFS_FILE"
  fi
  echo "---" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"

  # Memory directories section
  echo "## Memory directories" >> "$REFS_FILE"
  echo "" >> "$REFS_FILE"
  while IFS='|' read -r kind name path verify_file rationale; do
    [ "$kind" = "memory" ] || continue
    echo "- path: $path" >> "$REFS_FILE"
  done < "${DISCOVERY_TMP}.accepted"
  if ! grep -q '^- path:' <(awk '/^## Memory directories/,0' "$REFS_FILE"); then
    echo "<!-- No memory directories configured. Add Claude Code memory paths so /ss:init can propose principles auto-extracted from feedback_*.md and project_*.md files. -->" >> "$REFS_FILE"
  fi

  # Cleanup
  rm -f "$DISCOVERY_TMP" "$DISCOVERY_TMP.accepted" 2>/dev/null

  ACCEPTED_COUNT=$(wc -l < "${DISCOVERY_TMP}.accepted" 2>/dev/null || echo "0")
  echo "✅ Created .specswarm/references.md ($ACCEPTED_COUNT entries)"
fi

echo ""
```

**Note for the implementer:** when the user picks "Use all discovered" the implementation should `cp "$DISCOVERY_TMP" "$DISCOVERY_TMP.accepted"`. When the user picks individually, append accepted entries to `$DISCOVERY_TMP.accepted`. When the user picks "Skip", leave `$DISCOVERY_TMP.accepted` empty / non-existent.

---

### Step 4: Create .specswarm/constitution.md

Use the **SlashCommand** tool to execute the existing constitution command with the gathered information:

```bash
echo "📝 Creating .specswarm/constitution.md..."

# If custom principles provided, pass them to constitution command
if [ "$PRINCIPLES_CHOICE" = "custom" ]; then
  # Use SlashCommand tool to run:
  # /ss:constitution with custom principles
else
  # Use SlashCommand tool to run:
  # /ss:constitution (will use defaults)
fi

echo "✅ Created .specswarm/constitution.md"
```

Use the **SlashCommand** tool:
```
/ss:constitution
```

<!-- ========== CONSTITUTIONAL HOOK GENERATION (SpecSwarm 5.3.0) ========== -->
<!-- Added by Marty Bonacci & Claude Code (2026) — invisible enforcement -->

**Generate constitutional warning hooks** from any structured rule blocks in the new constitution. Idempotent — never overwrites existing generated hooks.

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PLUGIN_DIR/lib/constitution-parser.sh" ]; then
  source "$PLUGIN_DIR/lib/constitution-parser.sh"
  generate_constitutional_hooks "${REPO_ROOT}/.specswarm/constitution.md" "${REPO_ROOT}/.specswarm/hooks/generated"
fi
```

Constitution authors can opt principles into mechanical enforcement by adding HTML-comment rule blocks beneath the principle. Three rule types are supported (`no-pattern`, `required-pattern`, `required-pair`). Hooks are warning-only and never block edits. See `plugins/specswarm/lib/constitution-parser.sh` header for the rule-block syntax.

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

e. **For each eligible memory file**, draft a principle in the constitution-hook format. Map to template:

   - **no-pattern-in-paths** — "X must never appear in files matching Y"
     Example (from `feedback_trade_secrets.md`):
     ```markdown
     ### Trade-secret math is server-side only
     <!-- specswarm:rule type=no-pattern-in-paths -->
     - forbidden-pattern: `from\s+['"].*board-calculator`
     - path-glob: `app/components/**`, `app/routes/**.client.*`, `app/lib/client/**`
     - rationale: feedback_trade_secrets.md — calculation engine math must never reach the frontend bundle
     <!-- /specswarm:rule -->
     ```

   - **required-import-in-files** — "Files matching Y must import/contain X"
     Example (from a hypothetical `feedback_v2_reference_required.md`):
     ```markdown
     ### v2 source mandatory for calc-engine work
     <!-- specswarm:rule type=required-import-in-files -->
     - required-pattern: `// v2-ref: customcult2/`
     - path-glob: `app/engine/**`
     - rationale: feedback_v2_reference_required.md — calc engine port delegates to v2 PHP as canonical
     <!-- /specswarm:rule -->
     ```

   - **required-pair-in-additions** — "When pattern A appears, pattern B must also appear in the same file"
     Example (from `project_admin_audit_log.md`):
     ```markdown
     ### Admin writes require audit_log entry
     <!-- specswarm:rule type=required-pair-in-additions -->
     - trigger-pattern: `db\.(insert|update|delete)`
     - pair-pattern: `audit_log\(`
     - path-glob: `app/routes/admin/**`
     - rationale: project_admin_audit_log.md — every admin mutation logs admin_audit_log row
     <!-- /specswarm:rule -->
     ```

f. **Surface each draft principle to the user** via **AskUserQuestion**:

```
Question: "Add this principle to constitution.md?"
Header: "Principle N/M"
Options:
  1. "Yes, add as drafted"
     Description: "[show the principle title + first line of rationale]"
  2. "Yes, but I'll edit later"
     Description: "Add now; user will hand-edit the regex / path-glob to match their conventions"
  3. "No, skip this one"
     Description: "Memory file is too prose-y / not enforceable / I'll keep this as memory only"
```

Track each accept/reject. Cap proposals at **10 principles per init** to keep the session bounded.

g. **For each accepted principle**, append it to `.specswarm/constitution.md` under a section header `## Imported from memory (auto-proposed YYYY-MM-DD)`. Don't overwrite existing sections.

h. **Re-run constitutional hook generation** so the newly-imported principles get their PostToolUse warning hooks generated. The same `generate_constitutional_hooks` function from Step 4 is called again — it's idempotent and will regenerate hooks for the new principles only.

```bash
if [ -f "$PLUGIN_DIR_SS_MEM/lib/constitution-parser.sh" ]; then
  source "$PLUGIN_DIR_SS_MEM/lib/constitution-parser.sh"
  generate_constitutional_hooks "${REPO_ROOT}/.specswarm/constitution.md" "${REPO_ROOT}/.specswarm/hooks/generated"
  echo ""
  echo "✅ Imported principles → regenerated constitutional warning hooks"
fi
```

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

### Step 5: Create .specswarm/tech-stack.md

```bash
echo "📝 Creating .specswarm/tech-stack.md..."

# Read template
TEMPLATE=$(cat plugins/specswarm/templates/tech-stack.template.md)

# Replace placeholders
OUTPUT="$TEMPLATE"
OUTPUT="${OUTPUT//\[PROJECT_NAME\]/$PROJECT_NAME}"
OUTPUT="${OUTPUT//\[DATE\]/$(date +%Y-%m-%d)}"
OUTPUT="${OUTPUT//\[AUTO_GENERATED\]/$([[ $AUTO_DETECT == true ]] && echo "Yes" || echo "No")}"
OUTPUT="${OUTPUT//\[FRAMEWORK\]/$FRAMEWORK}"
OUTPUT="${OUTPUT//\[VERSION\]/$FRAMEWORK_VERSION}"
OUTPUT="${OUTPUT//\[FRAMEWORK_NOTES\]/"Functional components only (if React), composition API (if Vue)"}"
OUTPUT="${OUTPUT//\[LANGUAGE\]/$LANGUAGE}"
OUTPUT="${OUTPUT//\[LANGUAGE_VERSION\]/$LANGUAGE_VERSION}"
OUTPUT="${OUTPUT//\[BUILD_TOOL\]/$BUILD_TOOL}"
OUTPUT="${OUTPUT//\[BUILD_TOOL_VERSION\]/$BUILD_TOOL_VERSION}"

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
OUTPUT="${OUTPUT//\[E2E_TEST_FRAMEWORK\]/$E2E_SECTION}"
OUTPUT="${OUTPUT//\[INTEGRATION_TEST_FRAMEWORK\]/${UNIT_TEST:-"Same as unit testing"}}"

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
echo "$OUTPUT" > .specswarm/tech-stack.md

echo "✅ Created .specswarm/tech-stack.md"
```

---

### Step 6: Create .specswarm/quality-standards.md

```bash
echo "📝 Creating .specswarm/quality-standards.md..."

# Read template
TEMPLATE=$(cat plugins/specswarm/templates/quality-standards.template.md)

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
echo "$OUTPUT" > .specswarm/quality-standards.md

echo "✅ Created .specswarm/quality-standards.md"
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
- 2-3 representative source files (largest files in `src/` or project root)
- `package.json` scripts section

**Generate `.specswarm/conventions.md`** with these sections:

```markdown
# Project Conventions
<!-- Auto-generated by /ss:init — edit freely -->

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
```

```bash
echo "📝 Generating .specswarm/conventions.md..."
echo "   Analyzing project files for coding conventions..."
```

Write the generated conventions to `.specswarm/conventions.md`.

```bash
echo "✅ Created .specswarm/conventions.md"
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

### Step 6.5: Seed Project Subagents from Tech Stack

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

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "         ✅ PROJECT INITIALIZATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 Created Configuration Files:"
echo "   ✓ .specswarm/constitution.md      (governance & principles)"
if [ "${ACCEPTED_COUNT:-0}" -gt 0 ]; then
echo "      └─ +$ACCEPTED_COUNT principle(s) imported from memory"
fi
echo "   ✓ .specswarm/tech-stack.md        (approved technologies)"
echo "   ✓ .specswarm/quality-standards.md (quality gates)"
echo "   ✓ .specswarm/conventions.md       (code style & patterns)"
if [ -f ".specswarm/references.md" ]; then
echo "   ✓ .specswarm/references.md        (external authoritative sources)"
fi
if [ -f ".mcp.json" ]; then
echo "   ✓ .mcp.json                      (MCP server configuration)"
fi
echo ""
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
echo "   1. Review the created files in .specswarm/"
echo "   2. Customize as needed"
echo "   3. Build your first feature:"
echo "      /ss:build \"your feature description\""
echo "   4. Ship when ready:"
echo "      /ss:ship"
echo ""
echo "💡 Tips:"
echo "   • Run /ss:build to start your first feature"
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

If configuration files already exist:
- **Update**: Merges new values with existing (preserves custom edits)
- **Backup**: Saves to `.specswarm/.backup/[timestamp]/` before recreating
- **Cancel**: Aborts initialization, keeps existing files

### Template Customization

Templates are located at:
- `plugins/specswarm/templates/tech-stack.template.md`
- `plugins/specswarm/templates/quality-standards.template.md`

Teams can customize these templates for organization-specific standards.

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

### Update Existing Configuration
```bash
/ss:init
# Detects existing files, offers to update
```
