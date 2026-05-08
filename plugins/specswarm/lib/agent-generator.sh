#!/bin/bash
# SpecSwarm Project Subagent Generator (5.3.0)
# Generates .claude/agents/ss-*.md files based on tech stack and tasks.md patterns.
# Idempotent: existing generated files are NOT overwritten (preserves user edits).
# Logs every generation as audit event `agent_generated`.

# Resolve plugin lib dir for sourcing audit-logger
__SS_AGEN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pull in audit logger if available
if [ -f "$__SS_AGEN_LIB_DIR/audit-logger.sh" ]; then
  # shellcheck disable=SC1091
  source "$__SS_AGEN_LIB_DIR/audit-logger.sh"
fi

# Slugify a phrase for use in filenames
__ss_slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# Detect stack-derived agent seeds from .specswarm/tech-stack.md
# Echos one line per seed: <slug>|<task_type>|<trigger_substring>|<specialty_one_liner>
__ss_detect_stack_seeds() {
  local tech_file="$1"
  [ -f "$tech_file" ] || return 0

  # Use a temp file to dedupe seeds we emit
  local seen=":"

  __ss_emit() {
    local slug="$1" type="$2" trigger="$3" specialty="$4"
    case "$seen" in
      *":$slug:"*) return ;;
    esac
    seen="$seen$slug:"
    echo "${slug}|${type}|${trigger}|${specialty}"
  }

  # Lowercase the file once for matching
  local lower
  lower=$(tr '[:upper:]' '[:lower:]' < "$tech_file" 2>/dev/null || echo "")

  case "$lower" in
    *react*|*next.js*|*nextjs*)
      __ss_emit "react-component-implementer" "React component" "react component" \
        "Build idiomatic React components matching the existing component conventions in this repo. Prefer function components, hooks, and the styling system already in use." ;;
  esac
  case "$lower" in
    *typescript*|*ts*)
      __ss_emit "typescript-module-implementer" "TypeScript module" "typescript module" \
        "Author strongly-typed TypeScript modules. Match tsconfig strictness, existing import paths, and the project's type conventions." ;;
  esac
  case "$lower" in
    *express*|*fastify*|*nestjs*|*node.js*|*nodejs*)
      __ss_emit "api-endpoint-implementer" "API endpoint" "api endpoint" \
        "Implement HTTP API endpoints following the project's framework conventions, request/response validation, and error handling patterns." ;;
  esac
  case "$lower" in
    *python*|*fastapi*|*django*|*flask*)
      __ss_emit "python-module-implementer" "Python module" "python module" \
        "Author Pythonic modules using the project's testing, typing, and dependency conventions." ;;
  esac
  case "$lower" in
    *postgres*|*mysql*|*sqlite*|*drizzle*|*prisma*|*sqlalchemy*|*migration*)
      __ss_emit "db-migration-implementer" "Database migration" "database migration" \
        "Author database migrations using the project's migration tooling. Append-only, reversible where possible, and never destructive without explicit confirmation." ;;
  esac
  case "$lower" in
    *playwright*|*cypress*|*vitest*|*jest*|*pytest*)
      __ss_emit "test-implementer" "Test suite" "test" \
        "Write tests using the project's existing test framework, mirroring existing test conventions and helpers." ;;
  esac
}

# Detect task-derived agents from tasks.md
# Outputs one line per task type that has >=3 occurrences:
#   <slug>|<task_type>|<trigger_substring>|<specialty_one_liner>
__ss_detect_task_seeds() {
  local tasks_file="$1"
  [ -f "$tasks_file" ] || return 0

  # Extract task lines and lowercase
  local lines
  lines=$(grep -E '^\s*-?\s*\[[ xX]\]' "$tasks_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')

  # Generic patterns: count keywords across task descriptions
  declare -A counts
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      *"react component"*|*"<component"*|*"create component"*) counts[react-component]=$((${counts[react-component]:-0}+1)) ;;
    esac
    case "$line" in
      *"api endpoint"*|*"rest endpoint"*|*"http endpoint"*|*"add route"*) counts[api-endpoint]=$((${counts[api-endpoint]:-0}+1)) ;;
    esac
    case "$line" in
      *"migration"*|*"add column"*|*"alter table"*|*"create table"*) counts[migration]=$((${counts[migration]:-0}+1)) ;;
    esac
    case "$line" in
      *"unit test"*|*"integration test"*|*"e2e test"*|*"add test"*|*"write test"*) counts[test]=$((${counts[test]:-0}+1)) ;;
    esac
    case "$line" in
      *"port "*|*"convert "*|*"migrate "*|*"translate "*) counts[port]=$((${counts[port]:-0}+1)) ;;
    esac
    case "$line" in
      *"refactor "*|*"simplify "*|*"clean up "*|*"consolidate "*) counts[refactor]=$((${counts[refactor]:-0}+1)) ;;
    esac
    case "$line" in
      *"document "*|*"docstring"*|*"jsdoc"*|*"readme"*) counts[docs]=$((${counts[docs]:-0}+1)) ;;
    esac
  done <<< "$lines"

  for key in "${!counts[@]}"; do
    local n=${counts[$key]}
    [ "$n" -ge 3 ] || continue
    case "$key" in
      react-component) echo "react-component-implementer|React component|react component|Implement React components matching the existing patterns and styling system." ;;
      api-endpoint) echo "api-endpoint-implementer|API endpoint|api endpoint|Implement API endpoints with the project's framework conventions, validation, and error handling." ;;
      migration) echo "db-migration-implementer|Database migration|database migration|Author database migrations using the project's migration tooling. Append-only and reversible." ;;
      test) echo "test-implementer|Test suite|test|Write tests with the project's existing test framework and helpers." ;;
      port) echo "port-implementer|Port/translation|port |Carefully translate code between languages or frameworks while preserving behavior." ;;
      refactor) echo "refactor-implementer|Refactor|refactor|Improve code quality without changing behavior. Add tests where missing before changing." ;;
      docs) echo "docs-implementer|Documentation|document|Author and update documentation with the project's existing tone and structure." ;;
    esac
  done
}

# Render the agent template into a target file
# Args: slug, task_type, trigger, specialty, template_path, output_path
__ss_render_agent() {
  local slug="$1" task_type="$2" trigger="$3" specialty="$4" template="$5" out="$6"
  [ -f "$template" ] || return 1

  local agent_name="ss-${slug}"
  local agent_desc="Project-specific implementer for ${task_type} tasks. Auto-generated by SpecSwarm; safe to edit."
  local agent_title="${task_type} Implementer (${slug})"

  # Use awk to safely substitute placeholders without regex escape pain
  awk \
    -v name="$agent_name" \
    -v desc="$agent_desc" \
    -v title="$agent_title" \
    -v ttype="$task_type" \
    -v specialty="$specialty" \
    '{
      gsub(/__AGENT_NAME__/, name);
      gsub(/__AGENT_DESCRIPTION__/, desc);
      gsub(/__AGENT_TITLE__/, title);
      gsub(/__TASK_TYPE__/, ttype);
      gsub(/__SPECIALTY_GUIDANCE__/, specialty);
      print
    }' "$template" > "$out"
}

# Public: generate project agents
# Usage: generate_project_agents <repo_root> [feature_dir]
generate_project_agents() {
  local repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local feature_dir="${2:-}"

  local plugin_dir
  plugin_dir="$(cd "$__SS_AGEN_LIB_DIR/.." && pwd)"
  local template="$plugin_dir/templates/agents/ss-implementer.md.template"

  local agents_dir="$repo_root/.claude/agents"
  local manifest_dir="$repo_root/.specswarm/agents"
  local manifest_file="$manifest_dir/manifest.json"

  mkdir -p "$agents_dir" "$manifest_dir" 2>/dev/null

  # Initialize manifest if missing
  if [ ! -f "$manifest_file" ]; then
    echo '{"generated_agents": []}' > "$manifest_file"
  fi

  local tech_file="$repo_root/.specswarm/tech-stack.md"
  local tasks_file=""
  if [ -n "$feature_dir" ] && [ -f "$feature_dir/tasks.md" ]; then
    tasks_file="$feature_dir/tasks.md"
  fi

  # Collect seeds: stack first, tasks second
  local seeds=""
  seeds="$(__ss_detect_stack_seeds "$tech_file")"
  if [ -n "$tasks_file" ]; then
    seeds="$seeds"$'\n'"$(__ss_detect_task_seeds "$tasks_file")"
  fi

  local generated_count=0
  local skipped_count=0
  local generated_list=""

  while IFS='|' read -r slug task_type trigger specialty; do
    [ -z "$slug" ] && continue
    local out_file="$agents_dir/ss-${slug}.md"

    if [ -f "$out_file" ]; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if __ss_render_agent "$slug" "$task_type" "$trigger" "$specialty" "$template" "$out_file"; then
      generated_count=$((generated_count + 1))
      generated_list="$generated_list\n   ✓ ss-${slug} (matches: \"${trigger}\")"

      # Update manifest atomically
      local ts
      ts=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S%z")
      local tmp="$manifest_file.tmp"
      jq --arg name "ss-${slug}" \
         --arg file ".claude/agents/ss-${slug}.md" \
         --arg trigger "$trigger" \
         --arg ttype "$task_type" \
         --arg ts "$ts" \
         '.generated_agents += [{"name": $name, "file": $file, "trigger": $trigger, "task_type": $ttype, "generated_at": $ts}]' \
         "$manifest_file" > "$tmp" 2>/dev/null && mv "$tmp" "$manifest_file"

      # Audit log
      if declare -f audit_log >/dev/null 2>&1; then
        audit_log "agent_generated" name="ss-${slug}" task_type="$task_type" trigger="$trigger"
      fi
    fi
  done <<< "$(echo -e "$seeds" | sort -u)"

  # User-visible summary (compact; only emits if anything happened)
  if [ "$generated_count" -gt 0 ]; then
    echo "🤖 Generated $generated_count project agent(s):"
    echo -e "$generated_list"
  fi
  if [ "$skipped_count" -gt 0 ]; then
    echo "   (skipped $skipped_count agent(s) — files already exist; user edits preserved)"
  fi

  return 0
}

# Public: read an agent name for a given task content using the manifest.
# Echos the agent name (e.g., ss-react-component-implementer) or empty if no match.
# Usage: lookup_generated_agent <task_content> [repo_root]
lookup_generated_agent() {
  local task_content="$1"
  local repo_root="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local manifest="$repo_root/.specswarm/agents/manifest.json"

  [ -f "$manifest" ] || { echo ""; return 0; }

  local lower
  lower=$(echo "$task_content" | tr '[:upper:]' '[:lower:]')

  # Walk the manifest entries; first trigger that's a substring of the task content wins
  local triggers
  triggers=$(jq -r '.generated_agents[]? | "\(.trigger)|\(.name)"' "$manifest" 2>/dev/null)

  while IFS='|' read -r trig name; do
    [ -z "$trig" ] && continue
    case "$lower" in
      *"$trig"*) echo "$name"; return 0 ;;
    esac
  done <<< "$triggers"

  echo ""
}
