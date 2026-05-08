#!/bin/bash
# SpecSwarm Constitution Parser (5.3.0)
# Reads .specswarm/constitution.md, finds structured rule blocks, and emits
# warning-only PostToolUse hooks under .specswarm/hooks/generated/.
#
# Constitution authors opt in to a hook by adding a structured comment block
# beneath the principle. Three formats are supported:
#
#   <!-- specswarm-rule: no-pattern -->
#   <!-- path-glob: src/**/*.ts -->
#   <!-- bad-pattern: console\.log\( -->
#   <!-- summary: No console.log in production source files -->
#
#   <!-- specswarm-rule: required-pattern -->
#   <!-- path-glob: migrations/**/*.ts -->
#   <!-- required-pattern: import .* migrationHelper -->
#   <!-- summary: Migration files must use migrationHelper -->
#
#   <!-- specswarm-rule: required-pair -->
#   <!-- path-glob: routes/**/*.ts -->
#   <!-- trigger-pattern: app\.(get|post|put|delete) -->
#   <!-- pair-pattern: requireAuth -->
#   <!-- summary: Route handlers must use requireAuth middleware -->
#
# All hooks are warning-only and never block. Anything not matching one of
# these structured forms is logged as `principle_unhandled` and ignored.

__SS_CONST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pull in audit logger if available
if [ -f "$__SS_CONST_LIB_DIR/audit-logger.sh" ]; then
  # shellcheck disable=SC1091
  source "$__SS_CONST_LIB_DIR/audit-logger.sh"
fi

# Slugify text for filenames
__ss_const_slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | head -c 60
}

# Render a hook from a template, substituting placeholders.
# Args: template_path, output_path, key1=val1, key2=val2, ...
# Uses bash parameter expansion (NOT awk) so backslash escapes in regex values
# are preserved verbatim — critical for emitting valid grep/regex patterns.
__ss_const_render() {
  local template="$1"; shift
  local out="$1"; shift
  [ -f "$template" ] || return 1

  local content
  content=$(cat "$template")

  local pair key val placeholder
  for pair in "$@"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    placeholder="__${key}__"
    # Bash native string replace is escape-safe on the replacement side.
    content="${content//${placeholder}/${val}}"
  done

  printf '%s\n' "$content" > "$out"
  chmod +x "$out" 2>/dev/null || true
}

# Public: parse constitution.md and generate hooks.
# Usage: generate_constitutional_hooks <constitution_path> <hooks_out_dir>
generate_constitutional_hooks() {
  local constitution="${1:-.specswarm/constitution.md}"
  local out_dir="${2:-.specswarm/hooks/generated}"

  [ -f "$constitution" ] || return 0

  mkdir -p "$out_dir" 2>/dev/null

  local plugin_dir
  plugin_dir="$(cd "$__SS_CONST_LIB_DIR/.." && pwd)"
  local tmpl_dir="$plugin_dir/templates/constitutional-hooks"

  local tmpl_no_pattern="$tmpl_dir/no-pattern-in-paths.sh.template"
  local tmpl_required="$tmpl_dir/required-import-in-files.sh.template"
  local tmpl_pair="$tmpl_dir/required-pair-in-additions.sh.template"

  # Use awk to extract structured rule blocks. Each block is a contiguous run of
  # <!-- key: value --> comments starting with <!-- specswarm-rule: ... -->.
  # Output one tab-separated record per block: rule_type<TAB>key=val|key=val|...
  local blocks
  blocks=$(awk '
    /<!-- specswarm-rule:/ {
      in_block = 1
      delete kv
      gsub(/.*<!-- specswarm-rule:[[:space:]]*/, "")
      gsub(/[[:space:]]*-->.*/, "")
      rule_type = $0
      next
    }
    in_block && /<!-- [a-zA-Z_-]+:.*-->/ {
      line = $0
      sub(/^[[:space:]]*<!--[[:space:]]*/, "", line)
      sub(/[[:space:]]*-->[[:space:]]*$/, "", line)
      key = line; sub(/:[[:space:]]*.*/, "", key)
      val = line; sub(/^[^:]+:[[:space:]]*/, "", val)
      kv[key] = val
      next
    }
    in_block && !/<!--.*-->/ && NF > 0 {
      # End of block — emit
      printf "%s", rule_type
      for (k in kv) printf "\t%s=%s", k, kv[k]
      print ""
      in_block = 0
    }
    END {
      if (in_block) {
        printf "%s", rule_type
        for (k in kv) printf "\t%s=%s", k, kv[k]
        print ""
      }
    }
  ' "$constitution")

  local generated=0
  local skipped=0
  local unhandled=0
  local generated_list=""

  while IFS=$'\t' read -r rule_type rest; do
    [ -z "$rule_type" ] && continue

    # Parse key=val pairs into an associative array
    declare -A fields
    fields=()
    local pair k v
    while IFS= read -r pair; do
      [ -z "$pair" ] && continue
      k="${pair%%=*}"
      v="${pair#*=}"
      fields["$k"]="$v"
    done <<< "$(echo "$rest" | tr '\t' '\n')"

    local summary="${fields[summary]:-Unnamed principle}"
    local slug
    slug=$(__ss_const_slugify "$summary")
    [ -z "$slug" ] && slug="rule-$RANDOM"
    local out_file="$out_dir/${slug}.sh"

    # Skip if file already exists (preserve user edits and prior generations)
    if [ -f "$out_file" ]; then
      skipped=$((skipped + 1))
      unset fields
      continue
    fi

    case "$rule_type" in
      no-pattern)
        if [ -n "${fields[path-glob]:-}" ] && [ -n "${fields[bad-pattern]:-}" ]; then
          __ss_const_render "$tmpl_no_pattern" "$out_file" \
            "PATH_GLOB=${fields[path-glob]}" \
            "BAD_PATTERN=${fields[bad-pattern]}" \
            "PRINCIPLE_TEXT=${summary}" \
            "PRINCIPLE_SUMMARY=${summary}"
          generated=$((generated + 1))
          generated_list="$generated_list\n   ✓ $summary → ${slug}.sh"
          if declare -f audit_log >/dev/null 2>&1; then
            audit_log "constitutional_hook_generated" rule_type="no-pattern" slug="$slug" summary="$summary"
          fi
        else
          unhandled=$((unhandled + 1))
          if declare -f audit_log >/dev/null 2>&1; then
            audit_log "principle_unhandled" reason="missing_required_fields" rule_type="$rule_type" summary="$summary"
          fi
        fi
        ;;
      required-pattern)
        if [ -n "${fields[path-glob]:-}" ] && [ -n "${fields[required-pattern]:-}" ]; then
          __ss_const_render "$tmpl_required" "$out_file" \
            "PATH_GLOB=${fields[path-glob]}" \
            "REQUIRED_PATTERN=${fields[required-pattern]}" \
            "PRINCIPLE_TEXT=${summary}" \
            "PRINCIPLE_SUMMARY=${summary}"
          generated=$((generated + 1))
          generated_list="$generated_list\n   ✓ $summary → ${slug}.sh"
          if declare -f audit_log >/dev/null 2>&1; then
            audit_log "constitutional_hook_generated" rule_type="required-pattern" slug="$slug" summary="$summary"
          fi
        else
          unhandled=$((unhandled + 1))
          if declare -f audit_log >/dev/null 2>&1; then
            audit_log "principle_unhandled" reason="missing_required_fields" rule_type="$rule_type" summary="$summary"
          fi
        fi
        ;;
      required-pair)
        if [ -n "${fields[path-glob]:-}" ] && [ -n "${fields[trigger-pattern]:-}" ] && [ -n "${fields[pair-pattern]:-}" ]; then
          __ss_const_render "$tmpl_pair" "$out_file" \
            "PATH_GLOB=${fields[path-glob]}" \
            "TRIGGER_PATTERN=${fields[trigger-pattern]}" \
            "PAIR_PATTERN=${fields[pair-pattern]}" \
            "PRINCIPLE_TEXT=${summary}" \
            "PRINCIPLE_SUMMARY=${summary}"
          generated=$((generated + 1))
          generated_list="$generated_list\n   ✓ $summary → ${slug}.sh"
          if declare -f audit_log >/dev/null 2>&1; then
            audit_log "constitutional_hook_generated" rule_type="required-pair" slug="$slug" summary="$summary"
          fi
        else
          unhandled=$((unhandled + 1))
          if declare -f audit_log >/dev/null 2>&1; then
            audit_log "principle_unhandled" reason="missing_required_fields" rule_type="$rule_type" summary="$summary"
          fi
        fi
        ;;
      *)
        unhandled=$((unhandled + 1))
        if declare -f audit_log >/dev/null 2>&1; then
          audit_log "principle_unhandled" reason="unknown_rule_type" rule_type="$rule_type" summary="$summary"
        fi
        ;;
    esac

    unset fields
  done <<< "$blocks"

  # User-visible summary (silent if nothing happened)
  if [ "$generated" -gt 0 ] || [ "$skipped" -gt 0 ] || [ "$unhandled" -gt 0 ]; then
    echo "🛡️  Constitutional hooks:"
    if [ "$generated" -gt 0 ]; then
      echo -e "$generated_list"
    fi
    if [ "$skipped" -gt 0 ]; then
      echo "   (skipped $skipped — already generated; existing files preserved)"
    fi
    if [ "$unhandled" -gt 0 ]; then
      echo "   ⊘ $unhandled rule block(s) skipped (missing required fields or unknown type — see audit log)"
    fi
  fi

  return 0
}
