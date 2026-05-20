#!/bin/bash
# SpecSwarm Verify: Completion Detector
#
# Given a tasks.md path, computes which T### tasks just transitioned from
# unchecked → checked compared to the last committed version (HEAD).
#
# Public API:
#   ss_detect_newly_checked <tasks_md_path>
#     Echoes one T### per line for every checkbox that flipped from [ ] to [x]
#     since HEAD. Empty if none / no git / tasks.md not tracked.
#
# Design:
#   - Uses `git diff HEAD -- <path>` (single file scope; fast)
#   - A newly-checked task is a "+- [x] T###" line whose matching
#     "-- [ ] T###" also appears in the diff (i.e., the line was MODIFIED,
#     not added fresh). We treat both as completion signals — adding a
#     pre-checked task in a fresh commit is unusual but still worth verifying.
#   - Silent + empty output on any error (not in a git repo, file not tracked,
#     diff parse fails, etc.).

set -e

ss_detect_newly_checked() {
  local tasks_md="$1"
  [ -z "$tasks_md" ] && return 0
  [ -f "$tasks_md" ] || return 0

  local repo_root
  repo_root=$(git -C "$(dirname "$tasks_md")" rev-parse --show-toplevel 2>/dev/null || echo "")
  [ -z "$repo_root" ] && return 0

  # Build a relative path for git
  local rel="${tasks_md#${repo_root}/}"

  # If file is not yet tracked, treat every currently-checked task as new
  if ! git -C "$repo_root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    grep -oE '^[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+T[0-9]+' "$tasks_md" 2>/dev/null \
      | grep -oE 'T[0-9]+' \
      | sort -u
    return 0
  fi

  # Extract +-prefixed checked lines from the diff
  git -C "$repo_root" diff --no-color HEAD -- "$rel" 2>/dev/null \
    | grep -E '^\+[[:space:]]*-[[:space:]]+\[[xX]\][[:space:]]+T[0-9]+' \
    | grep -oE 'T[0-9]+' \
    | sort -u
}
