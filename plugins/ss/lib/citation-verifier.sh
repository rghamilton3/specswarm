#!/bin/bash
# SpecSwarm Citation Verifier (v7.0.0)
# Sanity-checks a proposal's citation by resolving the path and optionally
# the line / section anchor. Permissive by design — false-positive verification
# is worse than false-negative (a slightly wrong line number that still points
# to the right neighborhood is better than dropping a real citation).
#
# Citation formats (see research.md R4):
#   <repo-relative-path>
#   <repo-relative-path>:<line>
#   <repo-relative-path>:<line-start>-<line-end>
#   <repo-relative-path>:§<section-slug>
#   <repo-relative-path>:<line>:§<section-slug>
#
# Public:
#   ss_citation_verify <citation>
#     exit 0 → citation resolves (file exists; anchor matches if present)
#     exit 1 → citation does NOT resolve (file missing, or anchor mismatch)
#     exit 2 → citation malformed (no path)
#
#   ss_citation_verify_batch <agg_file> <out_file>
#     For each proposal in <agg_file>, verify its citation (field 5).
#     Writes <out_file> containing one TSV record per proposal:
#       <line-no-in-agg>\t<status>\t<citation>
#     where <status> ∈ {verified, missing, mismatched, malformed}.
#     Returns 0; the caller decides how to surface results.
#
# Convention: pure bash + grep; no jq; no `set -e`.

__SS_CITE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Internal: resolve <citation> into path, line, section components.
# Sets globals __cite_path, __cite_line_start, __cite_line_end, __cite_section.
# Returns 0 on parseable form, 2 on empty / malformed.
__ss_cite_parse() {
  local cit="$1"
  __cite_path=""
  __cite_line_start=""
  __cite_line_end=""
  __cite_section=""

  [ -z "$cit" ] && return 2

  # Split off section anchor first (everything after :§)
  if [[ "$cit" == *":§"* ]]; then
    __cite_section="${cit##*:§}"
    cit="${cit%:§*}"
  fi

  # Split path:line / path:line-range / path
  if [[ "$cit" == *:* ]]; then
    __cite_path="${cit%:*}"
    local tail="${cit##*:}"
    if [[ "$tail" =~ ^[0-9]+-[0-9]+$ ]]; then
      __cite_line_start="${tail%-*}"
      __cite_line_end="${tail#*-}"
    elif [[ "$tail" =~ ^[0-9]+$ ]]; then
      __cite_line_start="$tail"
      __cite_line_end="$tail"
    else
      # `:` present but tail not a line spec — treat whole thing as path
      __cite_path="$cit"
    fi
  else
    __cite_path="$cit"
  fi

  [ -z "$__cite_path" ] && return 2
  return 0
}

# -----------------------------------------------------------------------------
# ss_citation_verify
# -----------------------------------------------------------------------------
ss_citation_verify() {
  local cit="$1"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  if ! __ss_cite_parse "$cit"; then
    return 2
  fi

  # Resolve path: absolute? otherwise relative to repo root. Memory-dir paths
  # under ~ are also tilde-expanded.
  local abs="$__cite_path"
  abs="${abs/#\~/$HOME}"
  case "$abs" in
    /*) ;;
    *) abs="$repo_root/$abs" ;;
  esac

  [ -f "$abs" ] || return 1

  # Line anchor: file has at least <line_end> lines
  if [ -n "$__cite_line_end" ]; then
    local total
    total=$(wc -l < "$abs" 2>/dev/null | tr -d ' ')
    if [ "${total:-0}" -lt "$__cite_line_end" ]; then
      return 1
    fi
  fi

  # Section anchor: file contains a markdown heading whose slug-form matches.
  # Slug-form = lowercase, alnum + dashes only.
  if [ -n "$__cite_section" ]; then
    local target_slug
    target_slug=$(echo "$__cite_section" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')

    # Extract headings; build slugs; check for match.
    if ! awk -v target="$target_slug" '
      /^#+ / {
        h = $0
        sub(/^#+ +/, "", h)
        h = tolower(h)
        gsub(/[^a-z0-9]+/, "-", h)
        sub(/^-+/, "", h); sub(/-+$/, "", h)
        if (h == target || index(h, target) > 0) found = 1
      }
      END { exit (found ? 0 : 1) }
    ' "$abs"; then
      return 1
    fi
  fi

  return 0
}

# -----------------------------------------------------------------------------
# ss_citation_verify_batch
# -----------------------------------------------------------------------------
ss_citation_verify_batch() {
  local agg_file="$1"
  local out_file="$2"
  [ -f "$agg_file" ] || return 0
  [ -z "$out_file" ] && return 1

  : > "$out_file"

  local line_no=0
  local line cit status
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    [ -z "$line" ] && continue
    case "$line" in
      '#'*|'conflict-group:'*) continue ;;
    esac
    # Citation is field 5 in a 6-field record (1-indexed). Use cut on `|`.
    cit=$(printf '%s' "$line" | cut -d'|' -f5)
    [ -z "$cit" ] && continue

    if ss_citation_verify "$cit"; then
      status="verified"
    else
      local rc=$?
      if [ "$rc" = 2 ]; then
        status="malformed"
      else
        # Distinguish missing-file from anchor-mismatch by re-parsing
        __ss_cite_parse "$cit"
        local abs="$__cite_path"
        abs="${abs/#\~/$HOME}"
        case "$abs" in
          /*) ;;
          *) abs="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/$abs" ;;
        esac
        if [ ! -f "$abs" ]; then
          status="missing"
        else
          status="mismatched"
        fi
      fi
    fi

    printf '%d\t%s\t%s\n' "$line_no" "$status" "$cit" >> "$out_file"
  done < "$agg_file"

  return 0
}
