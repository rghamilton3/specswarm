#!/bin/bash
# SpecSwarm Guide Parsers (v6.4.0)
# Reads .specswarm/tech-stack.md and .specswarm/quality-standards.md, plus a
# generic helper for preserving user-edit zones across /ss:init re-runs and
# a set of sufficiency-check + augmentation helpers used by /ss:init Step 1.6.
#
# Public functions (after sourcing this file):
#   ss_parse_tech_stack <file>           — emit key<TAB>value per declared field
#   ss_parse_quality_standards <file>    — emit key<TAB>value per declared threshold
#   ss_preserve_user_sections <old> <new>
#                                        — splice <!-- ss:user-additions --> ...
#                                          <!-- ss:end --> blocks from <old> into
#                                          <new>, matched by ordinal index
#   ss_check_constitution_sufficient <file>
#   ss_check_tech_stack_sufficient <file>
#   ss_check_quality_standards_sufficient <file>
#   ss_check_references_sufficient <file>
#                                        — exit 0 if SpecSwarm can read & enforce;
#                                          exit 1 + reason on stdout if not
#   ss_augment_with_skeleton <target_file> <skeleton_file> <banner_text>
#                                        — non-destructive: prepends banner +
#                                          skeleton, wraps target's existing
#                                          content in <!-- ss:user-additions -->
#                                          at the end
#
# Convention:
#   - Pure Bash + awk/sed/grep, no Python
#   - Parsers are best-effort and silent on missing/malformed input — emit only
#     keys whose values are confidently extractable; caller checks for absence
#   - Values that still contain unresolved [PLACEHOLDER] tokens are skipped
#     (a hallmark of broken template substitution from older /ss:init runs)
#   - DOES NOT enable `set -e`. Sufficiency-check functions intentionally return
#     non-zero exit codes to signal "insufficient"; `set -e` would cause the
#     caller's shell to abort at the first negative verdict, defeating the API.

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

# Skip "values" that are clearly unsubstituted template placeholders.
__ss_guide_value_is_placeholder() {
  case "$1" in
    "" | "["*"]") return 0 ;;
    *) return 1 ;;
  esac
}

# Trim leading/trailing whitespace.
__ss_guide_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Emit a key<TAB>value line if value is non-empty and not a placeholder.
__ss_guide_emit() {
  local key="$1" value
  value="$(__ss_guide_trim "$2")"
  __ss_guide_value_is_placeholder "$value" && return 0
  printf '%s\t%s\n' "$key" "$value"
}

# -----------------------------------------------------------------------------
# ss_parse_tech_stack
# -----------------------------------------------------------------------------
# Parse a tech-stack.md file and emit declared values as TSV.
# Looks for `**Name** version` bullets under named section headers.
#
# Recognized keys:
#   framework, framework_version
#   language,  language_version
#   build_tool, build_tool_version
#   state_mgmt
#   styling
#   unit_test
#   integration_test
#   e2e_test
ss_parse_tech_stack() {
  local file="$1"
  [ -f "$file" ] || return 0

  awk '
    # Track the current top-level (## …) and sub (### …) sections.
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function emit_pair(prefix, line) {
      # Pull "**Name**" and optional trailing version from a bullet line.
      # Bullet format:   - **Name** version    OR    - **Name**
      if (match(line, /\*\*[^*]+\*\*/)) {
        name = substr(line, RSTART+2, RLENGTH-4)
        rest = substr(line, RSTART+RLENGTH)
        sub(/^[[:space:]]+/, "", rest)
        # Strip trailing comments / inline notes
        sub(/[[:space:]]+-.*$/, "", rest)
        rest = trim(rest)
        if (name != "" && name !~ /^\[.*\]$/) {
          printf("%s\t%s\n", prefix, name)
          if (rest != "" && rest !~ /^\[.*\]$/) {
            printf("%s_version\t%s\n", prefix, rest)
          }
        }
      }
    }

    /^## / { top = tolower($0); sub(/^## +/, "", top); sub_section = ""; next }
    /^### / { sub_section = tolower($0); sub(/^### +/, "", sub_section); next }

    # Match the first bullet under each recognized sub-section
    /^- / {
      if (top == "core technologies") {
        if (sub_section == "framework")  { emit_pair("framework",  $0) }
        if (sub_section == "language")   { emit_pair("language",   $0) }
        if (sub_section == "build tool") { emit_pair("build_tool", $0) }
      } else if (top == "state management") {
        emit_pair("state_mgmt", $0)
        top = "__consumed_state"
      } else if (top == "styling") {
        emit_pair("styling", $0)
        top = "__consumed_styling"
      } else if (top == "testing") {
        if (sub_section == "unit testing")        { emit_pair("unit_test",        $0) }
        if (sub_section == "integration testing") { emit_pair("integration_test", $0) }
        if (sub_section == "end-to-end testing")  { emit_pair("e2e_test",         $0) }
      }
    }
  ' "$file"
}

# -----------------------------------------------------------------------------
# ss_parse_quality_standards
# -----------------------------------------------------------------------------
# Parse a quality-standards.md file and emit thresholds as TSV.
# Looks for `key: value` lines inside fenced YAML-style code blocks.
#
# Recognized keys:
#   min_quality_score, min_test_coverage, enforce_gates
#   enforce_budgets, max_bundle_size, max_initial_load, max_chunk_size
#   complexity_threshold, max_file_lines, max_function_lines, max_function_params
#   require_tests, require_code_review, min_reviewers
#   block_merge_on_failure
ss_parse_quality_standards() {
  local file="$1"
  [ -f "$file" ] || return 0

  awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    BEGIN {
      keys = "min_quality_score min_test_coverage enforce_gates "
      keys = keys "enforce_budgets max_bundle_size max_initial_load max_chunk_size "
      keys = keys "complexity_threshold max_file_lines max_function_lines max_function_params "
      keys = keys "require_tests require_code_review min_reviewers block_merge_on_failure"
      n = split(keys, k_arr, " ")
      for (i = 1; i <= n; i++) wanted[k_arr[i]] = 1
    }
    /^```/ { in_block = !in_block; next }
    in_block && /:/ {
      line = $0
      sub(/#.*$/, "", line)        # strip trailing comment
      key = line; sub(/:.*$/, "", key); key = trim(key)
      val = line; sub(/^[^:]*:/, "", val); val = trim(val)
      if (key in wanted && val != "" && val !~ /^\[.*\]$/) {
        printf("%s\t%s\n", key, val)
      }
    }
  ' "$file"
}

# -----------------------------------------------------------------------------
# ss_preserve_user_sections
# -----------------------------------------------------------------------------
# Splice every <!-- ss:user-additions --> ... <!-- ss:end --> block from <old>
# into the corresponding block in <new>, matched by ordinal index (1st old
# block → 1st new block, etc.).
#
# Behavior:
#   - If <old> has more blocks than <new>: extra old blocks are dropped silently
#   - If <new> has more blocks than <old>: extra new blocks retain template content
#   - If <old> doesn't exist: <new> left untouched
#   - The block markers themselves are preserved; only the body between them is
#     replaced
#
# Writes the result back to <new> in-place.
ss_preserve_user_sections() {
  local old_file="$1"
  local new_file="$2"

  [ -f "$old_file" ] || return 0
  [ -f "$new_file" ] || return 0

  local tmp
  tmp="$(mktemp)"

  # Markers must be alone on their line (modulo whitespace). This prevents
  # documentation strings that *mention* the markers (e.g. in a top-of-file
  # docstring) from being mis-parsed as actual marker blocks.
  awk -v oldf="$old_file" '
    function is_open(s)  { return s ~ /^[[:space:]]*<!--[[:space:]]*ss:user-additions[[:space:]]*-->[[:space:]]*$/ }
    function is_close(s) { return s ~ /^[[:space:]]*<!--[[:space:]]*ss:end[[:space:]]*-->[[:space:]]*$/ }

    function read_old_bodies(   line, idx, in_b, body) {
      idx = 0
      in_b = 0
      body = ""
      while ((getline line < oldf) > 0) {
        if (is_open(line)) {
          in_b = 1
          body = ""
          continue
        }
        if (is_close(line)) {
          if (in_b) {
            idx++
            old_bodies[idx] = body
          }
          in_b = 0
          body = ""
          continue
        }
        if (in_b) {
          body = body line "\n"
        }
      }
      close(oldf)
      return idx
    }
    BEGIN {
      n_old = read_old_bodies()
      block_idx = 0
      skipping = 0
    }
    {
      if (is_open($0)) {
        print
        block_idx++
        if (block_idx <= n_old) {
          body = old_bodies[block_idx]
          sub(/\n$/, "", body)
          if (body != "") print body
          skipping = 1
        } else {
          skipping = 0
        }
        next
      }
      if (is_close($0)) {
        print
        skipping = 0
        next
      }
      if (!skipping) print
    }
  ' "$new_file" > "$tmp"

  mv "$tmp" "$new_file"
}

# -----------------------------------------------------------------------------
# Sufficiency checks
# -----------------------------------------------------------------------------
# Each returns:
#   exit 0 if the file is sufficient for SpecSwarm's needs (or absent — absent
#          is not a sufficiency problem, it's a creation problem handled by the
#          fresh-init path)
#   exit 1 + a single-line reason on stdout if the file is present but
#          unparseable / unenforceable
#
# These functions encode "what does SpecSwarm need to *do something* with this
# file?", not "is this file complete?" A prose-only constitution is treated as
# insufficient because SpecSwarm hooks have nothing to enforce — the user can
# still decide to keep it that way via the Step 1.6 prompt.

ss_check_constitution_sufficient() {
  local file="$1"
  [ -f "$file" ] || return 0  # absent = not insufficient

  if ! grep -q '<!--[[:space:]]*specswarm-rule:' "$file"; then
    echo "no <!-- specswarm-rule: ... --> blocks — PostToolUse hooks have nothing to enforce"
    return 1
  fi
  return 0
}

ss_check_tech_stack_sufficient() {
  local file="$1"
  [ -f "$file" ] || return 0

  local fields
  fields=$(ss_parse_tech_stack "$file" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${fields:-0}" -eq 0 ]; then
    echo "no parseable Core Technologies / Testing structure — /ss:build can't enforce drift"
    return 1
  fi

  if ! grep -qE '^[[:space:]]*<!--[[:space:]]*ss:user-additions[[:space:]]*-->[[:space:]]*$' "$file"; then
    echo "no <!-- ss:user-additions --> markers — hand-edits won't survive future /ss:init runs"
    return 1
  fi
  return 0
}

ss_check_quality_standards_sufficient() {
  local file="$1"
  [ -f "$file" ] || return 0

  local keys
  keys=$(ss_parse_quality_standards "$file" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${keys:-0}" -eq 0 ]; then
    echo "no YAML threshold keys parseable — /ss:ship will fall back to built-in defaults instead of declared values"
    return 1
  fi
  return 0
}

ss_check_references_sufficient() {
  local file="$1"
  [ -f "$file" ] || return 0

  # ss_references_exist (from references-loader.sh) is the canonical readability
  # check. We don't hard-depend on it being sourced — guard with declare -F.
  if declare -F ss_references_exist >/dev/null; then
    if ! ss_references_exist 2>/dev/null; then
      echo "doesn't match canonical schema (Spec corpus / Reference codebases / Memory directories) — /ss:specify and /ss:clarify won't consult it"
      return 1
    fi
    return 0
  fi

  # Fallback: look for at least one structured bullet
  if ! grep -qE '^[[:space:]]*-[[:space:]]+(path|name):' "$file"; then
    echo "doesn't match canonical schema — no '- path:' or '- name:' entries found"
    return 1
  fi
  return 0
}

# -----------------------------------------------------------------------------
# ss_augment_with_skeleton
# -----------------------------------------------------------------------------
# Non-destructive augment: rewrite <target_file> so it contains:
#   1. The <banner_text> as a leading blockquote (so any reader sees context)
#   2. The full content of <skeleton_file> (the canonical SpecSwarm-readable
#      structure)
#   3. A "Pre-existing Content" section wrapping the target's original content
#      in a <!-- ss:user-additions --> block — so it both survives and gets
#      preserved on future /ss:init re-runs
#
# Idempotent guard: if the target already contains the marker string
# "<!-- ss:augmented-on:" at the top, skip — augmentation already happened.
# Caller can detect this and inform the user.
ss_augment_with_skeleton() {
  local target_file="$1"
  local skeleton_file="$2"
  local banner_text="$3"

  [ -f "$target_file" ] || return 1
  [ -f "$skeleton_file" ] || return 1

  # Idempotent check
  if head -5 "$target_file" 2>/dev/null | grep -q '<!-- ss:augmented-on:'; then
    return 2  # already augmented
  fi

  local tmp
  tmp="$(mktemp)"
  local today
  today="$(date +%Y-%m-%d)"

  {
    printf '<!-- ss:augmented-on: %s -->\n' "$today"
    printf '> **NOTE**: This file was augmented by `/ss:init` on %s to add SpecSwarm-readable structure.\n' "$today"
    printf '> %s\n' "$banner_text"
    printf '> Your original content is preserved verbatim at the bottom under "Pre-existing Content".\n\n'
    cat "$skeleton_file"
    printf '\n\n---\n\n## Pre-existing Content\n\n'
    printf '_The content below was your file before %s. Edit freely — it lives inside an `ss:user-additions` block, so it survives future `/ss:init` re-runs._\n\n' "$today"
    printf '<!-- ss:user-additions -->\n'
    cat "$target_file"
    printf '\n<!-- ss:end -->\n'
  } > "$tmp"

  mv "$tmp" "$target_file"
  return 0
}
