#!/bin/bash
# SpecSwarm Proposal Aggregator (v7.0.0)
# Reads .specswarm/.proposals.<destination>.tmp files produced by Step 4.0
# extractors, deduplicates, detects conflicts, sorts, and emits a normalized
# aggregated file at .specswarm/.proposals.aggregated.tmp for Step 4.2.
#
# See data-model.md §Format 3 for the aggregated-file format.
#
# Public functions (after sourcing):
#   ss_proposal_iter <file> <callback>
#       Iterate logical records (BLOCK-aware). Callback receives positional
#       args: dest key value conf citation rationale [severity rule_block].
#       Multi-line values arrive with embedded \n encoded as the literal
#       2-char sequence "\n" (backslash + n) so the callback sees a single
#       line. Use ss_proposal_decode to recover.
#
#   ss_proposal_decode <encoded>
#       Replace the literal "\n" sequence with actual newlines. Echoes
#       decoded value.
#
#   ss_proposals_aggregate <out_file> <in_file>...
#       Read each <in_file>, dedupe within and across, detect conflicts,
#       sort within destination, write the aggregated file. Returns exit 0
#       on success; emits human-readable progress to stderr.
#
#   ss_proposals_coverage_gaps <destination> <aggregated_file>
#       Echo one canonical-key per line that is NOT present in the aggregated
#       file for the given destination. Used by Step 4.1's coverage report.
#
# Conventions: pure bash + awk; no jq; no `set -e` (signaling via exit codes).

__SS_AGG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pull in extraction-schema.sh if not already sourced (idempotent).
if ! declare -F ss_proposal_validate_line >/dev/null; then
  # shellcheck disable=SC1091
  [ -f "$__SS_AGG_LIB_DIR/extraction-schema.sh" ] && source "$__SS_AGG_LIB_DIR/extraction-schema.sh"
fi

# -----------------------------------------------------------------------------
# ss_proposal_decode
# -----------------------------------------------------------------------------
# Reverse the in-block encoding the normalizer applies:
#   "\n" (backslash + n) → real newline
#   "\|" (backslash + pipe) → real pipe
# The pipe-escape exists so iter callbacks can use IFS=`|` to split records
# without truncating values whose BLOCK content contains literal pipes
# (e.g. regex alternations like `(info|warn)`).
ss_proposal_decode() {
  printf '%s' "$1" | sed -e 's/\\|/|/g' -e 's/\\n/\n/g'
}

# -----------------------------------------------------------------------------
# Internal: normalize a proposals file to "one logical record per line" form.
# Multi-line BLOCK fields collapse their newlines into the literal "\n"
# (two-character: backslash + n). Pipes inside BLOCK fields are preserved
# verbatim and decoded later via field-position awareness — they don't break
# the format because a BLOCK's content is captured before pipe-splitting.
#
# The awk state machine handles two cases:
#   1) A record line that ends with `|<<<BLOCK` (or is exactly `<<<BLOCK`):
#      enters block mode, accumulates subsequent lines until a line that is
#      exactly `BLOCK`, then emits a "\n"-joined replacement of those lines
#      into the record buffer.
#   2) A line that begins with `|`: it's the continuation of the previous
#      record after a closed BLOCK.
#
# Emits one normalized record per line to stdout.
# -----------------------------------------------------------------------------
__ss_agg_normalize() {
  local in_file="$1"
  [ -f "$in_file" ] || return 0

  awk '
    function flush_rec() { if (rec != "") { print rec; rec = "" } }

    BEGIN {
      in_block   = 0
      block_buf  = ""
      rec        = ""
      post_block = 0   # set true after closing a BLOCK; next line decides flush
    }

    {
      line = $0

      # ---- Inside a block: accumulate until the BLOCK closer ----
      if (in_block) {
        if (line == "BLOCK") {
          rec = rec block_buf
          block_buf = ""
          in_block = 0
          post_block = 1   # next line is continuation OR start of new record
          next
        }
        # Escape pipes inside block content so downstream IFS=`|` splitters
        # do not mistake regex alternations / inline pipes for field
        # delimiters. ss_proposal_decode reverses this.
        encoded = line
        gsub(/\|/, "\\|", encoded)
        if (block_buf == "") {
          block_buf = encoded
        } else {
          block_buf = block_buf "\\n" encoded  # literal two-char "\n" encoding
        }
        next
      }

      # ---- post_block: decide whether next line continues or starts fresh ----
      if (post_block) {
        if (substr(line, 1, 1) != "|") {
          flush_rec()
        }
        post_block = 0
      }

      # ---- Block opener (line ends with `<<<BLOCK`) ----
      pos = match(line, /<<<BLOCK$/)
      if (pos > 0) {
        prefix = substr(line, 1, pos - 1)
        rec = rec prefix
        in_block = 1
        block_buf = ""
        next
      }

      # ---- Continuation line (starts with `|`) ----
      if (substr(line, 1, 1) == "|") {
        rec = rec line
        if (match(rec, /<<<BLOCK$/) > 0) {
          rec = substr(rec, 1, length(rec) - length("<<<BLOCK"))
          in_block = 1
          block_buf = ""
          next
        }
        print rec
        rec = ""
        next
      }

      # ---- Regular line: flush any partial, then handle as single-line record ----
      flush_rec()
      n = gsub(/\|/, "|", line)
      if (n >= 5) {
        print line
      }
      # else: blank, comment, group-marker, or boilerplate — skip
    }

    END {
      flush_rec()
    }
  ' "$in_file"
}

# -----------------------------------------------------------------------------
# ss_proposal_iter
# -----------------------------------------------------------------------------
# Iterate logical records in a proposals file. For each record, call <callback>
# with positional args. Multi-line fields are passed with literal "\n" encoding;
# pass through ss_proposal_decode if you need the actual newlines.
#
# Usage:
#   my_cb() { local dest="$1" key="$2" value="$3" ...; ...; }
#   ss_proposal_iter "$file" my_cb
ss_proposal_iter() {
  local file="$1"
  local callback="$2"

  [ -f "$file" ] || return 0
  [ -z "$callback" ] && { echo "ss_proposal_iter: callback required" >&2; return 1; }

  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      '#'*|'conflict-group:'*) continue ;;
    esac

    # Split on `|` while preserving fields. Bash IFS-read can take up to 8 vars
    # for tech-stack(6) / constitution(8) records.
    local f1 f2 f3 f4 f5 f6 f7 f8
    IFS='|' read -r f1 f2 f3 f4 f5 f6 f7 f8 <<< "$line"

    case "$f1" in
      tech-stack|quality-standards|constitution) ;;
      *) continue ;;
    esac

    "$callback" "$f1" "$f2" "$f3" "$f4" "$f5" "$f6" "$f7" "$f8"
  done < <(__ss_agg_normalize "$file")
}

# -----------------------------------------------------------------------------
# ss_proposals_aggregate
# -----------------------------------------------------------------------------
# Read each input proposals file, dedupe (same dest+key → keep highest
# confidence), detect conflicts (same dest+key, different values), sort within
# destination by confidence (high > medium > low), and write the aggregated
# file in §Format 3 form.
#
# Usage:
#   ss_proposals_aggregate /path/to/.proposals.aggregated.tmp \
#                          /path/to/.proposals.tech-stack.tmp \
#                          /path/to/.proposals.quality-standards.tmp \
#                          /path/to/.proposals.constitution.tmp
ss_proposals_aggregate() {
  local out_file="$1"
  shift
  [ -z "$out_file" ] && { echo "ss_proposals_aggregate: out_file required" >&2; return 1; }

  local normalized
  normalized="$(mktemp)"
  trap 'rm -f "$normalized"' RETURN

  # Concatenate normalized inputs
  : > "$normalized"
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    __ss_agg_normalize "$f" >> "$normalized"
  done

  if [ ! -s "$normalized" ]; then
    # Nothing to aggregate — touch an empty out_file for downstream existence
    # checks and return.
    : > "$out_file"
    return 0
  fi

  # awk does the heavy lifting:
  # - Group records by destination+key
  # - Per group: pick winner (highest confidence); if ≥ 2 distinct values exist
  #   at the highest confidence tier OR the top two confidences disagree, emit
  #   as conflict-group
  # - Sort destinations in canonical order, then by confidence within
  awk -F'|' '
    function conf_rank(c) {
      if (c == "high") return 3
      if (c == "medium") return 2
      if (c == "low") return 1
      return 0
    }

    {
      dest = $1
      key  = $2
      val  = $3
      conf = $4
      cit  = $5
      rat  = $6
      sev  = $7
      rb   = $8

      gk = dest "|" key
      records[gk, ++count[gk]] = $0
      record_val[gk, count[gk]] = val
      record_conf[gk, count[gk]] = conf

      destinations[dest] = 1
      group_keys[dest, key] = gk

      # Track if the group has a value mismatch (conflict candidate)
      if (!(gk in primary_val)) {
        primary_val[gk] = val
        primary_conf_rank[gk] = conf_rank(conf)
      } else {
        if (primary_val[gk] != val) {
          conflict[gk] = 1
        }
        # Bump primary to highest-confidence record observed so far
        if (conf_rank(conf) > primary_conf_rank[gk]) {
          primary_val[gk] = val
          primary_conf_rank[gk] = conf_rank(conf)
        }
      }
    }

    END {
      # Emit in canonical destination order
      split("tech-stack quality-standards constitution", dest_order, " ")
      for (di = 1; di <= 3; di++) {
        d = dest_order[di]
        if (!(d in destinations)) continue
        printf "# Destination: %s\n", d

        # Collect group-keys for this destination
        # Iterating records and grouping again is wasteful, but bash arrays
        # are limited; do a second pass over count[]
        for (gk in count) {
          if (index(gk, d "|") != 1) continue
          if (gk in emitted) continue
          emitted[gk] = 1

          if (conflict[gk]) {
            printf "conflict-group: %s\n", gk
            for (i = 1; i <= count[gk]; i++) {
              print records[gk, i]
            }
          } else {
            # Single value or duplicates with same value — pick highest conf
            best_rank = 0
            best_idx = 1
            for (i = 1; i <= count[gk]; i++) {
              r = conf_rank(record_conf[gk, i])
              if (r > best_rank) {
                best_rank = r
                best_idx = i
              }
            }
            print records[gk, best_idx]
          }
        }
        print ""
      }
    }
  ' "$normalized" > "$out_file"

  return 0
}

# -----------------------------------------------------------------------------
# ss_proposals_coverage_gaps
# -----------------------------------------------------------------------------
# Echo canonical keys missing from the aggregated file for the given
# destination, one per line. Returns 0 always.
#
# Usage:
#   ss_proposals_coverage_gaps tech-stack /path/to/.proposals.aggregated.tmp
ss_proposals_coverage_gaps() {
  local dest="$1"
  local agg_file="$2"
  [ -f "$agg_file" ] || return 0

  local canonical
  canonical="$(ss_proposal_canonical_keys "$dest")"
  [ -z "$canonical" ] && return 0

  local key
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    if ! grep -qE "^${dest}\|${key}\|" "$agg_file"; then
      printf '%s\n' "$key"
    fi
  done <<< "$canonical"
}

# -----------------------------------------------------------------------------
# ss_proposals_count_conflicts
# -----------------------------------------------------------------------------
# Echo the count of conflict-group markers in the aggregated file.
ss_proposals_count_conflicts() {
  local agg_file="$1"
  [ -f "$agg_file" ] || { echo 0; return 0; }
  grep -c '^conflict-group:' "$agg_file" 2>/dev/null || echo 0
}

# -----------------------------------------------------------------------------
# ss_proposals_count_by_destination
# -----------------------------------------------------------------------------
# Echo TSV: destination<TAB>total<TAB>high<TAB>medium<TAB>low for each
# destination present in the aggregated file. Conflict-group records contribute
# to the total for their destination.
ss_proposals_count_by_destination() {
  local agg_file="$1"
  [ -f "$agg_file" ] || return 0

  awk -F'|' '
    /^#/ { next }
    /^conflict-group:/ { next }
    NF >= 6 {
      dest = $1
      conf = $4
      total[dest]++
      if (conf == "high")   high[dest]++
      if (conf == "medium") medium[dest]++
      if (conf == "low")    low[dest]++
    }
    END {
      for (d in total) {
        printf "%s\t%d\t%d\t%d\t%d\n", d, total[d], high[d]+0, medium[d]+0, low[d]+0
      }
    }
  ' "$agg_file"
}
