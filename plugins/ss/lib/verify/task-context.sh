#!/bin/bash
# SpecSwarm Verify: Task Context Extractor
#
# Pulls structured context for a given task ID out of a SpecSwarm tasks.md.
# Project-agnostic — works with any tasks.md that follows the SpecSwarm
# convention of `- [ ] T### <description>` or `- [x] T### <description>`.
#
# Public API:
#   ss_task_block <tasks_md_path> <task_id>
#     Echoes the full task block: the line starting with `- [.] T### `
#     plus any indented child bullets that follow until the next top-level
#     task or blank gap. Empty output if not found.
#
#   ss_task_description <tasks_md_path> <task_id>
#     Echoes ONLY the description portion of the task header line
#     (i.e., everything after `T### `). One line.
#
#   ss_task_refs <tasks_md_path> <task_id>
#     Echoes one §X.Y reference per line, extracted from the task block.
#     Deduped. Empty if none.
#
#   ss_task_status <tasks_md_path> <task_id>
#     Echoes one of: open | done | not-found
#     based on the checkbox state.

set -e

# Helper: emit a portable awk that extracts the block for a task ID.
__ss_task_block_awk() {
  local task_id="$1"
  awk -v tid="$task_id" '
    BEGIN { in_block = 0 }
    # Match a top-level task line: "- [ ] T###" or "- [x] T###" with the exact ID
    /^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]+T[0-9]+/ {
      # Extract just the T### token
      match($0, /T[0-9]+/)
      found_id = substr($0, RSTART, RLENGTH)
      if (found_id == tid) {
        in_block = 1
        print
        next
      } else if (in_block) {
        # Reached the next top-level task — stop
        in_block = 0
        exit
      }
    }
    # Inside the block: print indented continuation lines (sub-bullets, notes)
    in_block {
      # A blank line is OK (some tasks have whitespace inside their block);
      # stop only on the next top-level task or unindented non-bullet line.
      if ($0 ~ /^[^[:space:]]/) { in_block = 0; exit }
      print
    }
  '
}

ss_task_block() {
  local tasks_md="$1"
  local task_id="$2"
  [ -f "$tasks_md" ] || return 0
  [ -z "$task_id" ] && return 0
  __ss_task_block_awk "$task_id" < "$tasks_md"
}

ss_task_description() {
  local tasks_md="$1"
  local task_id="$2"
  [ -f "$tasks_md" ] || return 0
  [ -z "$task_id" ] && return 0

  # First line of the block is the header; strip the leading "- [.] T### "
  ss_task_block "$tasks_md" "$task_id" \
    | head -n1 \
    | sed -E 's/^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]+T[0-9]+[[:space:]]*//'
}

ss_task_refs() {
  local tasks_md="$1"
  local task_id="$2"
  [ -f "$tasks_md" ] || return 0
  [ -z "$task_id" ] && return 0

  ss_task_block "$tasks_md" "$task_id" \
    | grep -oE '§[0-9]+(\.[0-9]+)*' 2>/dev/null \
    | sort -u
}

ss_task_status() {
  local tasks_md="$1"
  local task_id="$2"
  [ -f "$tasks_md" ] || { echo "not-found"; return 0; }
  [ -z "$task_id" ] && { echo "not-found"; return 0; }

  local header
  header=$(ss_task_block "$tasks_md" "$task_id" | head -n1)
  if [ -z "$header" ]; then
    echo "not-found"
  elif echo "$header" | grep -qE '^\s*-\s+\[[xX]\]'; then
    echo "done"
  else
    echo "open"
  fi
}
