#!/bin/bash
# SpecSwarm References Loader (v6.1.0)
# Parses .specswarm/references.md and exposes accessor functions.
# Sourced by hooks and commands that need to consult external references.
#
# Schema: see plugins/ss/templates/references.md.template
#
# Public functions (after sourcing this file):
#   ss_references_path                  — echoes the path to references.md (or empty)
#   ss_references_exist                 — exit 0 if references.md present + non-empty, else exit 1
#   ss_references_spec_corpus_paths     — echoes one path per line; resolves relative to repo root
#   ss_references_codebases             — echoes one TSV record per codebase: name<TAB>path<TAB>verify-file<TAB>rationale
#   ss_references_memory_dirs           — echoes one path per line; tilde-expanded
#
# Design notes:
#   - Pure Bash + grep/sed/awk; no Python dependency (matches quality-check.sh style)
#   - Silent + exit-0 when references.md is missing — never blocks workflows that don't use references
#   - Path resolution is the caller's job (we echo as written + tilde-expand only); avoids surprising behavior

set -e

# Resolve repo root once (shared by all functions)
__SS_REF_REPO_ROOT() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Echo absolute path to references.md, or empty string if not present
ss_references_path() {
  local repo_root
  repo_root="$(__SS_REF_REPO_ROOT)"
  local path="${repo_root}/.specswarm/references.md"
  if [ -f "$path" ]; then
    echo "$path"
  fi
}

# Exit 0 if references.md exists and has at least one section with content
ss_references_exist() {
  local path
  path="$(ss_references_path)"
  [ -z "$path" ] && return 1

  # File must contain at least one bullet line under a known section
  if grep -qE '^[[:space:]]*-[[:space:]]+(path|name):' "$path" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Internal: extract the body of a top-level section by name (between "## $name" and next "##" or EOF).
# Strips comment-only lines (`<!-- … -->` blocks are dropped wholesale).
__ss_ref_extract_section() {
  local path="$1"
  local section_name="$2"
  [ -f "$path" ] || return 0

  awk -v target="## $section_name" '
    BEGIN { in_section = 0; in_comment = 0 }
    /^<!--/ { in_comment = 1 }
    /-->/   { in_comment = 0; next }
    in_comment { next }
    /^## / {
      if ($0 == target) { in_section = 1; next }
      else if (in_section) { in_section = 0 }
    }
    in_section { print }
  ' "$path"
}

# Echo each spec-corpus path on its own line.
# Format in references.md:
#   - path: <relative-or-absolute-path>
ss_references_spec_corpus_paths() {
  local path
  path="$(ss_references_path)"
  [ -z "$path" ] && return 0

  __ss_ref_extract_section "$path" "Spec corpus" \
    | grep -E '^[[:space:]]*-[[:space:]]+path:' \
    | sed -E 's/^[[:space:]]*-[[:space:]]+path:[[:space:]]*//' \
    | sed 's/[[:space:]]*$//'
}

# Echo each reference codebase as TSV: name<TAB>path<TAB>verify-file<TAB>rationale
# Schema in references.md (each codebase is a multi-line bullet):
#   - name: foo
#     path: ../foo
#     verify-file: src/main.py
#     rationale: ...
ss_references_codebases() {
  local path
  path="$(ss_references_path)"
  [ -z "$path" ] && return 0

  local section_body
  section_body="$(__ss_ref_extract_section "$path" "Reference codebases")"
  [ -z "$section_body" ] && return 0

  # Awk state machine: collect fields per "- name:" delimiter, emit TSV when complete
  echo "$section_body" | awk '
    function emit() {
      if (name != "") {
        printf "%s\t%s\t%s\t%s\n", name, path, verify_file, rationale
      }
      name = ""; path = ""; verify_file = ""; rationale = ""
    }
    /^[[:space:]]*-[[:space:]]+name:/ {
      emit()
      sub(/^[[:space:]]*-[[:space:]]+name:[[:space:]]*/, "")
      name = $0
      next
    }
    /^[[:space:]]+path:/ {
      sub(/^[[:space:]]+path:[[:space:]]*/, "")
      path = $0
      next
    }
    /^[[:space:]]+verify-file:/ {
      sub(/^[[:space:]]+verify-file:[[:space:]]*/, "")
      verify_file = $0
      next
    }
    /^[[:space:]]+rationale:/ {
      sub(/^[[:space:]]+rationale:[[:space:]]*/, "")
      rationale = $0
      next
    }
    END { emit() }
  '
}

# Echo each memory directory on its own line, tilde-expanded.
ss_references_memory_dirs() {
  local path
  path="$(ss_references_path)"
  [ -z "$path" ] && return 0

  __ss_ref_extract_section "$path" "Memory directories" \
    | grep -E '^[[:space:]]*-[[:space:]]+path:' \
    | sed -E 's/^[[:space:]]*-[[:space:]]+path:[[:space:]]*//' \
    | sed 's/[[:space:]]*$//' \
    | sed "s|^~|$HOME|"
}

# Resolve a reference codebase path to an absolute path.
# Treats relative paths as relative to the repo root (NOT the v3 build dir or anywhere else).
# Echoes the resolved absolute path.
ss_references_resolve_path() {
  local path="$1"
  local repo_root
  repo_root="$(__SS_REF_REPO_ROOT)"

  # Tilde expand
  path="${path/#\~/$HOME}"

  # Already absolute?
  case "$path" in
    /*) echo "$path"; return 0 ;;
  esac

  # Relative — resolve against repo root
  echo "${repo_root}/${path}"
}

# ─────────────────────────────────────────────────────────────────────────────
# v6.2.0: Memory file scanning
# ─────────────────────────────────────────────────────────────────────────────

# Scan all declared memory directories for memory files matching SpecSwarm's
# expected naming conventions. Echoes one absolute file path per line.
#
# Conventions matched (Claude Code memory system):
#   feedback_*.md   — opinionated rules / preferences
#   project_*.md    — project-state context
#   reference_*.md  — cross-references to external systems
#   user_*.md       — user-profile entries (role, expertise, etc.)
#
# Silent + empty output when references.md is missing OR has no memory dirs.
# Symlinks are followed; non-existent dirs are skipped silently.
ss_memory_scan_files() {
  local dir
  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    [ -d "$dir" ] || continue
    # Only one level deep — memory dirs are flat by convention
    find "$dir" -maxdepth 1 -type f \
      \( -name "feedback_*.md" \
      -o -name "project_*.md" \
      -o -name "reference_*.md" \
      -o -name "user_*.md" \) \
      2>/dev/null
  done < <(ss_references_memory_dirs) | sort -u
}

# Classify a memory filename by prefix. Echoes one of:
#   feedback   — rules / preferences ("never X", "always Y", policy)
#   project    — project-state context (decisions made, current phase, etc.)
#   reference  — cross-references ("the auth code lives in X")
#   user       — user-profile information
#   other      — anything else (returns this for files that don't match)
#
# Used by the principle-extraction step to decide whether a memory file is
# a likely PRINCIPLE source (feedback_*) or merely CONTEXT (project_*).
ss_memory_classify_kind() {
  local filename
  filename="$(basename "$1" 2>/dev/null)"
  case "$filename" in
    feedback_*)  echo "feedback" ;;
    project_*)   echo "project" ;;
    reference_*) echo "reference" ;;
    user_*)      echo "user" ;;
    *)           echo "other" ;;
  esac
}

# Count memory files by classification. Echoes TSV: kind<TAB>count
# Useful for /ss:init UX ("Found N feedback files, M project files, K reference files…").
ss_memory_count_by_kind() {
  local file
  declare -A counts=( [feedback]=0 [project]=0 [reference]=0 [user]=0 [other]=0 )
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    kind=$(ss_memory_classify_kind "$file")
    counts[$kind]=$((${counts[$kind]:-0} + 1))
  done < <(ss_memory_scan_files)

  for kind in feedback project reference user other; do
    printf "%s\t%d\n" "$kind" "${counts[$kind]:-0}"
  done
}
