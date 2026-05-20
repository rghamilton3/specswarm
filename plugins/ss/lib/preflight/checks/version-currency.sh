#!/bin/bash
# SpecSwarm Preflight Check: version-currency
#
# Verifies every pinned version mentioned in plan.md actually exists in its
# package registry. Catches hallucinated versions, typos, and yanked releases.
#
# Project-agnostic: auto-detects package manager from the project root,
# extracts version pins matching ecosystem conventions, queries the
# appropriate public registry (with a 24h cache).
#
# Skips silently if no package manager is detected.
#
# Input:  $1 = absolute path to plan.md
# Output: First line "PASS|WARN|FAIL <summary>", then indented details.

set -e

PLAN_PATH="${1:-}"
if [ -z "$PLAN_PATH" ] || [ ! -f "$PLAN_PATH" ]; then
  echo "FAIL version-currency: plan path missing or not found ($PLAN_PATH)"
  exit 2
fi

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${LIB_DIR}/package-manager-detector.sh"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PM=$(ss_detect_package_manager "$REPO_ROOT")
REGISTRY=$(ss_detect_registry "$PM")

if [ "$REGISTRY" = "none" ]; then
  echo "PASS version-currency: skipped (no package manager detected)"
  exit 0
fi

# Extract candidate package@version pairs from plan.md.
# Multiple patterns to cover JS, Python, Rust, Ruby:
#   foo@1.2.3              (JS/TS canonical)
#   foo@^1.2.3 / foo@~1    (npm semver — version stripped to bare)
#   "foo": "1.2.3"         (package.json)
#   foo==1.2.3             (pip)
#   foo~=1.2.3             (pip)
#   foo = "1.2.3"          (Cargo.toml / pyproject.toml)
#   gem 'foo', '1.2.3'     (Gemfile)
#
# Emits TSV: package<TAB>version (deduped).

extract_pins() {
  local file="$1"
  case "$REGISTRY" in
    npm)
      # Match @scoped/name@version OR name@version
      grep -oE '@?[a-zA-Z0-9_.-]+(\/[a-zA-Z0-9_.-]+)?@[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?' "$file" 2>/dev/null \
        | sed -E 's/^([@a-zA-Z0-9_./-]+)@([0-9].+)$/\1\t\2/' || true
      # Match "name": "1.2.3" (package.json style; strip ^ ~ >= etc.)
      grep -oE '"[a-zA-Z0-9_./@-]+"\s*:\s*"[\^~>=<]*[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9.-]*"' "$file" 2>/dev/null \
        | sed -E 's/"([^"]+)"\s*:\s*"[\^~>=<]*([0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9.-]*)"/\1\t\2/' || true
      ;;
    pypi)
      grep -oE '[a-zA-Z0-9_.-]+(==|~=)[0-9]+\.[0-9]+(\.[0-9]+)?' "$file" 2>/dev/null \
        | sed -E 's/^([a-zA-Z0-9_.-]+)(==|~=)(.+)$/\1\t\3/' || true
      ;;
    crates)
      grep -oE '[a-zA-Z0-9_-]+\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9.-]*"' "$file" 2>/dev/null \
        | sed -E 's/^([a-zA-Z0-9_-]+)\s*=\s*"([0-9].+)"$/\1\t\2/' || true
      ;;
    rubygems)
      grep -oE "gem\s+['\"][a-zA-Z0-9_-]+['\"]\s*,\s*['\"][~>=]*[0-9]+\.[0-9]+\.[0-9]+['\"]" "$file" 2>/dev/null \
        | sed -E "s/gem\s+['\"]([a-zA-Z0-9_-]+)['\"]\s*,\s*['\"][~>=]*([0-9].+)['\"]/\1\t\2/" || true
      ;;
    go-proxy)
      # Go modules: e.g. github.com/foo/bar v1.2.3
      grep -oE '[a-zA-Z0-9./_-]+\s+v[0-9]+\.[0-9]+\.[0-9]+' "$file" 2>/dev/null \
        | sed -E 's/^(.+)\s+(v[0-9].+)$/\1\t\2/' || true
      ;;
  esac
}

PINS=$(extract_pins "$PLAN_PATH" | awk -F'\t' 'NF==2 && $1!="" && $2!=""' | sort -u || true)

if [ -z "$PINS" ]; then
  echo "PASS version-currency: no version pins detected in plan.md"
  exit 0
fi

TOTAL=0
MISSING=()
UNKNOWN=()
VERIFIED=0

while IFS=$'\t' read -r pkg ver; do
  [ -z "$pkg" ] && continue
  TOTAL=$((TOTAL + 1))
  RESULT=$(ss_version_check "$REGISTRY" "$pkg" "$ver")
  case "$RESULT" in
    EXISTS) VERIFIED=$((VERIFIED + 1)) ;;
    MISSING) MISSING+=("${pkg}@${ver}") ;;
    UNKNOWN) UNKNOWN+=("${pkg}@${ver}") ;;
  esac
done <<< "$PINS"

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "FAIL version-currency: ${#MISSING[@]} pinned version(s) NOT FOUND in ${REGISTRY} registry"
  for entry in "${MISSING[@]}"; do
    echo "  🚫 ${entry} (registry: ${REGISTRY}) — does not exist or was yanked"
  done
  if [ "${#UNKNOWN[@]}" -gt 0 ]; then
    echo "  (also: ${#UNKNOWN[@]} unverifiable due to network/parse errors)"
  fi
  exit 2
fi

if [ "${#UNKNOWN[@]}" -gt 0 ]; then
  echo "WARN version-currency: ${VERIFIED}/${TOTAL} verified, ${#UNKNOWN[@]} unverifiable (network/registry issue)"
  for entry in "${UNKNOWN[@]}"; do
    echo "  ⚠️  ${entry}"
  done
  exit 1
fi

echo "PASS version-currency: ${VERIFIED} pinned version(s) verified in ${REGISTRY} registry"
exit 0
