#!/bin/bash
# SpecSwarm Extraction Schema (v7.0.0)
# Defines and validates the pipe-delimited proposal record format produced by
# the three Step 4.0 extractor subagents (tech-stack, quality-standards,
# constitution) and consumed by the Step 4.1 aggregator.
#
# See .specswarm/features/001-subagent-foundation-extraction/data-model.md for
# the canonical format spec. This file is the executable, lib-side restatement.
#
# Conventions:
#   - Pure bash + awk/sed/grep, no jq
#   - DOES NOT enable `set -e` — validation functions return non-zero as signal
#   - Public functions are prefixed `ss_proposal_*`
#
# Record format (single-line):
#   destination|key|value|confidence|citation|rationale
#
# Constitution records carry two trailing fields:
#   constitution|key|value|confidence|citation|rationale|severity|rule_block
#
# Multi-line / pipe-containing values use a BLOCK marker. The marker `<<<BLOCK`
# appears as the field value, followed by a newline; the content spans
# subsequent lines verbatim; the marker `BLOCK` alone on its line closes the
# block; the next line starts with the next field delimiter `|`.
#
#   tech-stack|framework|<<<BLOCK
#   React Router (multi-line because rationale is long)
#   BLOCK
#   |high|docs/STRATEGY.md:42|...
#
# Allowed values:
#   destination  ∈ {tech-stack, quality-standards, constitution}
#   confidence   ∈ {high, medium, low}
#   severity     ∈ {warn, block}        (constitution only)
#
# Phase 1B exposes:
#   ss_proposal_validate_line <line>    — record-header syntactic check
#   ss_proposal_emit ...                — write a well-formed record line
#                                          (auto-BLOCK-wraps if needed)
#
# Phase 1C (proposal-aggregator.sh) adds:
#   ss_proposal_iter <file> <callback>  — multi-line BLOCK-aware reader

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

# True if a field needs BLOCK-wrapping (contains newline, literal |, or marker).
__ss_proposal_field_needs_block() {
  local v="$1"
  case "$v" in
    *$'\n'*|*'|'*|*'<<<BLOCK'*|*'BLOCK'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Emit a single field — BLOCK-wrapped if it needs to be, plain otherwise.
# The BLOCK closer ends with a newline so the caller's next `|` lands on a
# fresh line (per the format spec).
#
# Note: do NOT call this via command substitution `$(...)` — bash strips
# trailing newlines from command-substitution output, which would put the
# BLOCK closer on the same line as the next field separator. Call directly
# so the bytes go straight to stdout.
__ss_proposal_emit_field() {
  if __ss_proposal_field_needs_block "$1"; then
    printf '<<<BLOCK\n%s\nBLOCK\n' "$1"
  else
    printf '%s' "$1"
  fi
}

# -----------------------------------------------------------------------------
# ss_proposal_validate_line
# -----------------------------------------------------------------------------
# Returns 0 if the given line looks like a valid record HEADER — i.e., starts
# with one of the known destination tokens followed by a `|`, and contains at
# least 5 pipes (6 fields minimum: destination|key|value|conf|cit|rationale).
#
# Lines that start a BLOCK-form record are valid even though the value field
# itself is just `<<<BLOCK`.
#
# Comment lines (`# ...`) and group markers (`conflict-group: ...`) are NOT
# valid records — caller should pre-filter.
#
# Usage:
#   if ss_proposal_validate_line "$line"; then
#     ...
#   else
#     echo "malformed: $line"
#   fi
ss_proposal_validate_line() {
  local line="$1"

  # Reject empties + comments + group markers + BLOCK markers themselves
  [ -z "$line" ] && return 1
  case "$line" in
    '#'*|'conflict-group:'*|'<<<BLOCK'|'BLOCK') return 1 ;;
  esac

  # Must start with a known destination
  case "$line" in
    'tech-stack|'*|'quality-standards|'*|'constitution|'*) ;;
    *) return 1 ;;
  esac

  # Count `|` separators — need at least 5 to make 6 fields
  local pipe_count
  pipe_count="$(printf '%s' "$line" | tr -cd '|' | wc -c | tr -d ' ')"
  if [ "${pipe_count:-0}" -lt 5 ]; then
    return 1
  fi

  # Constitution records: need 7 separators (8 fields) — but tolerate 5 (the
  # severity + rule_block tail can be omitted in early-draft proposals).
  # No further check here; aggregator will normalize.
  return 0
}

# -----------------------------------------------------------------------------
# ss_proposal_emit
# -----------------------------------------------------------------------------
# Emit a well-formed record to stdout, BLOCK-wrapping any field that needs it.
#
# Usage:
#   ss_proposal_emit <destination> <key> <value> <conf> <cit> <rationale> \
#                    [<severity> <rule_block>]
#
# The two trailing args are only meaningful for destination=constitution.
# For other destinations they're ignored if passed.
#
# This function is mainly for SHELL callers (tests, the aggregator, and the
# augmenter). Subagents emit records as plain text per their prompt; they don't
# call into this function.
ss_proposal_emit() {
  local dest="$1" key="$2" value="$3" conf="$4" cit="$5" rationale="$6"
  local severity="${7:-}" rule_block="${8:-}"

  case "$dest" in
    tech-stack|quality-standards|constitution) ;;
    *) echo "ss_proposal_emit: unknown destination '$dest'" >&2 ;;
  esac

  # Direct printf chain (no command substitution) so multi-line BLOCK closers
  # stay alone on their line and the next `|` lands on a fresh line.
  printf '%s|%s|' "$dest" "$key"
  __ss_proposal_emit_field "$value"
  printf '|%s|%s|' "$conf" "$cit"
  __ss_proposal_emit_field "$rationale"

  if [ "$dest" = "constitution" ]; then
    printf '|%s|' "${severity:-warn}"
    __ss_proposal_emit_field "$rule_block"
  fi
  printf '\n'
}

# -----------------------------------------------------------------------------
# ss_proposal_destinations
# -----------------------------------------------------------------------------
# Echo the recognized destination tokens, one per line. Useful for iteration
# in the aggregator and the acceptance UI.
ss_proposal_destinations() {
  printf '%s\n' 'tech-stack' 'quality-standards' 'constitution'
}

# -----------------------------------------------------------------------------
# ss_proposal_confidence_rank
# -----------------------------------------------------------------------------
# Echo a numeric rank for a confidence token (high=3, medium=2, low=1, else=0).
# Used by the aggregator's sort.
ss_proposal_confidence_rank() {
  case "$1" in
    high)   echo 3 ;;
    medium) echo 2 ;;
    low)    echo 1 ;;
    *)      echo 0 ;;
  esac
}

# -----------------------------------------------------------------------------
# ss_proposal_canonical_keys
# -----------------------------------------------------------------------------
# Echo the canonical key set for a given destination, one per line.
# Used by ss_proposals_coverage_gaps (Phase 1C) to flag missing-from-proposals
# canonical sections so the user knows when the corpus didn't cover something.
#
# These are NOT a hard schema (extractors may emit additional keys, e.g.
# `prohibited.N`, `audit_required.N`). They represent the canonical scalar slots
# in the generated foundation files.
ss_proposal_canonical_keys() {
  case "$1" in
    tech-stack)
      cat <<'EOF'
framework
framework_version
language
language_version
language_strict_flags
build_tool
build_tool_version
state_mgmt
styling
unit_test
integration_test
e2e_test
EOF
      ;;
    quality-standards)
      cat <<'EOF'
coverage_threshold
browser_support_floor
a11y_wcag_level
a11y_axe_required
a11y_contrast
a11y_focus_visible
a11y_touch_targets
a11y_reduced_motion
error_handling_pattern
EOF
      ;;
    constitution)
      # Constitution has no canonical scalar slots — principles are open-ended.
      # Coverage gap detection for constitution checks for "at least one
      # principle proposed" rather than a key set.
      ;;
  esac
}
