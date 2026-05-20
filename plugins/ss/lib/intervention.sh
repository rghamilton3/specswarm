#!/bin/bash
# SpecSwarm Intervention Helper
#
# Captures "wait, something feels off" moments as durable memory files. Each
# intervention is a structured observation that may later graduate into a
# rule, a hook, a check, or a constitution principle.
#
# Public API:
#   ss_intervention_dir
#     Echoes the absolute path of the directory to write interventions to.
#     Auto-discovers via cascading rules (see resolution order below).
#
#   ss_intervention_context
#     Echoes TSV: feature<TAB>task<TAB>branch<TAB>last_commit
#     Best-effort sniff of the current chunk context. Any unknown field is empty.
#
#   ss_intervention_slug "<text>"
#     Echoes a filesystem-safe slug derived from text (lowercase, kebab, ≤40 chars).
#
#   ss_intervention_filename "<text>"
#     Echoes intervention_YYYY-MM-DD_<slug>.md for use as the target filename.
#
#   ss_intervention_write <dir> <filename> <noticed> <should> <prevent> <status> <feature> <task>
#     Writes the intervention file from the template; returns absolute path on stdout.
#
#   ss_intervention_index_update <dir> <filename> <description>
#     If MEMORY.md exists in <dir>'s parent, appends a one-line index pointer.
#
#   ss_intervention_list [N]
#     Lists the last N (default 10) interventions across all discovered dirs.
#
# Resolution order for ss_intervention_dir:
#   1. .specswarm/references.md Memory directories section, first entry (if exists)
#   2. <repo_root>/memory/ if it exists with a sibling MEMORY.md
#   3. <repo_root>/.specswarm/interventions/ (created if missing)

set -e

PLUGIN_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${PLUGIN_LIB}/references-loader.sh"

ss_intervention_dir() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

  # 1. references.md memory dirs (first entry)
  local first_mem_dir
  first_mem_dir=$(ss_references_memory_dirs 2>/dev/null | head -n1)
  if [ -n "$first_mem_dir" ] && [ -d "$first_mem_dir" ]; then
    echo "$first_mem_dir"
    return 0
  fi

  # 2. <repo_root>/memory/ with sibling MEMORY.md
  if [ -d "${repo_root}/memory" ] && [ -f "${repo_root}/MEMORY.md" ]; then
    echo "${repo_root}/memory"
    return 0
  fi

  # 3. Project-local fallback
  local fallback="${repo_root}/.specswarm/interventions"
  mkdir -p "$fallback" 2>/dev/null || true
  echo "$fallback"
}

ss_intervention_context() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

  # Branch + last commit (best-effort)
  local branch=""
  local last_commit=""
  if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    last_commit=$(git -C "$repo_root" log -1 --pretty='%h %s' 2>/dev/null | head -c 80 || echo "")
  fi

  # Feature: derive from branch if NNN-slug, else from build-loop.state, else from latest .specswarm/features/ dir
  local feature=""
  if echo "$branch" | grep -qE '^[0-9]{3}-'; then
    feature="$branch"
  fi

  if [ -z "$feature" ]; then
    local state_file="${repo_root}/.specswarm/build-loop.state"
    if [ -f "$state_file" ]; then
      feature=$(grep -E '^branch_name=' "$state_file" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' || echo "")
    fi
  fi

  if [ -z "$feature" ]; then
    if [ -d "${repo_root}/.specswarm/features" ]; then
      feature=$(find "${repo_root}/.specswarm/features" -maxdepth 1 -type d -name '[0-9][0-9][0-9]-*' 2>/dev/null \
        | sort | tail -1 | xargs -n1 basename 2>/dev/null || echo "")
    fi
  fi

  # Task: best-effort from build-loop state or current tasks.md checkbox state
  local task=""
  local state_file="${repo_root}/.specswarm/build-loop.state"
  if [ -f "$state_file" ]; then
    task=$(grep -E '^current_task=' "$state_file" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"' || echo "")
  fi

  printf "%s\t%s\t%s\t%s\n" "${feature:-}" "${task:-}" "${branch:-}" "${last_commit:-}"
}

ss_intervention_slug() {
  local text="${1:-untitled}"
  echo "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed -E 's/-+/-/g; s/^-//; s/-$//' \
    | cut -c1-40
}

ss_intervention_filename() {
  local text="$1"
  local date_str
  date_str=$(date +%Y-%m-%d)
  local slug
  slug=$(ss_intervention_slug "$text")
  [ -z "$slug" ] && slug="untitled"
  echo "intervention_${date_str}_${slug}.md"
}

ss_intervention_write() {
  local dir="$1"
  local filename="$2"
  local noticed="$3"
  local should="$4"
  local prevent="$5"
  local status="${6:-open}"
  local feature="${7:-}"
  local task="${8:-}"

  [ -z "$dir" ] || [ -z "$filename" ] && return 1
  [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null

  local target="${dir%/}/${filename}"

  # Find template — relative to this lib dir
  local template="$(cd "${PLUGIN_LIB}/.." && pwd)/templates/intervention.template.md"

  local date_str
  date_str=$(date +%Y-%m-%d)

  local title
  title=$(echo "$noticed" | head -c 80 | tr '\n' ' ')

  # Derive memory `name:` slug from filename (strip .md, strip date prefix)
  local mem_name="${filename%.md}"
  mem_name="${mem_name#intervention_}"

  if [ -f "$template" ]; then
    sed \
      -e "s|{{NAME}}|intervention-${mem_name}|g" \
      -e "s|{{TITLE}}|${title//|/-}|g" \
      -e "s|{{DATE}}|${date_str}|g" \
      -e "s|{{STATUS}}|${status}|g" \
      -e "s|{{FEATURE}}|${feature}|g" \
      -e "s|{{TASK}}|${task}|g" \
      "$template" > "$target"
  else
    cat > "$target" <<EOF
---
name: intervention-${mem_name}
description: ${title}
metadata:
  type: intervention
  status: ${status}
  date: ${date_str}
  feature: ${feature}
  task: ${task}
---

## What I noticed

${noticed}

## What should have caught this

${should}

## How automation could prevent it next time

${prevent}

## Status notes

Status: ${status}

EOF
    echo "$target"
    return 0
  fi

  # Append the user-provided bodies AFTER frontmatter substitution.
  # Template body sections contain {{NOTICED}}/{{SHOULD}}/{{PREVENT}}/{{STATUS_NOTES}}
  # We do a final-pass substitution via a temp file because sed escaping of multi-line
  # user input is fragile.
  local tmp
  tmp=$(mktemp)
  awk -v noticed="$noticed" -v should="$should" -v prevent="$prevent" -v status="$status" '
    {
      gsub(/\{\{NOTICED\}\}/, noticed)
      gsub(/\{\{SHOULD\}\}/, should)
      gsub(/\{\{PREVENT\}\}/, prevent)
      gsub(/\{\{STATUS_NOTES\}\}/, "Status: " status)
      print
    }
  ' "$target" > "$tmp" && mv "$tmp" "$target"

  echo "$target"
}

ss_intervention_index_update() {
  local dir="$1"
  local filename="$2"
  local description="$3"

  # MEMORY.md typically sits at the parent of memory/, or alongside it
  local parent
  parent=$(dirname "$dir")
  local index=""
  if [ -f "${dir}/MEMORY.md" ]; then
    index="${dir}/MEMORY.md"
  elif [ -f "${parent}/MEMORY.md" ]; then
    index="${parent}/MEMORY.md"
  fi

  [ -z "$index" ] && return 0  # No index file to update; silent OK

  # Avoid duplicate entries
  if grep -qF "$filename" "$index" 2>/dev/null; then
    return 0
  fi

  # Append under an "Interventions" section, creating it if absent
  if ! grep -qE '^## Interventions' "$index" 2>/dev/null; then
    printf '\n## Interventions\n' >> "$index"
  fi

  # Insert one-liner directly after the "## Interventions" heading
  local short_desc
  short_desc=$(echo "$description" | head -c 100 | tr '\n' ' ')
  local rel_path="${filename}"
  # If the index is in the parent (not the dir itself), prefix with dir basename
  if [ "$(dirname "$index")" != "$dir" ]; then
    rel_path="$(basename "$dir")/${filename}"
  fi

  # Use awk to insert exactly after "## Interventions" line
  local tmp
  tmp=$(mktemp)
  awk -v entry="- [${short_desc}](${rel_path})" '
    /^## Interventions/ {
      print
      print entry
      inserted = 1
      next
    }
    { print }
  ' "$index" > "$tmp" && mv "$tmp" "$index"
}

ss_intervention_list() {
  local limit="${1:-10}"
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

  # Gather all candidate dirs (declared memory + repo-local fallbacks)
  local dirs=()
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] && dirs+=("$d")
  done < <(ss_references_memory_dirs 2>/dev/null)

  [ -d "${repo_root}/memory" ] && dirs+=("${repo_root}/memory")
  [ -d "${repo_root}/.specswarm/interventions" ] && dirs+=("${repo_root}/.specswarm/interventions")

  if [ "${#dirs[@]}" -eq 0 ]; then
    echo "(no memory directories declared and no project-local fallback dir found)"
    return 0
  fi

  local found=0
  for d in "${dirs[@]}"; do
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      found=$((found + 1))
      local base
      base=$(basename "$f")
      local desc
      desc=$(grep -E '^description:' "$f" 2>/dev/null | head -n1 | sed -E 's/^description:[[:space:]]*//')
      local status
      status=$(grep -E '^[[:space:]]*status:' "$f" 2>/dev/null | head -n1 | sed -E 's/^[[:space:]]*status:[[:space:]]*//')
      printf "  %-8s  %s\n      %s\n" "[${status:-open}]" "$base" "${desc:-(no description)}"
    done < <(find "$d" -maxdepth 1 -type f -name 'intervention_*.md' 2>/dev/null | sort -r | head -n "$limit")
  done

  if [ "$found" -eq 0 ]; then
    echo "(no interventions captured yet)"
  fi
}
