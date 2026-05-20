#!/bin/bash
# SpecSwarm Preflight: Package Manager Detector
# Auto-detects the project's package manager from lockfiles + manifest files.
# Project-agnostic: supports JS/TS, Python, Rust, Go, Ruby ecosystems.
#
# Public functions:
#   ss_detect_package_manager [project_root]
#     Echoes one of: pnpm, npm, yarn, bun, pip, poetry, uv, cargo, go, gem, none
#
#   ss_detect_registry [package_manager]
#     Echoes the registry kind for use in version-currency check.
#     One of: npm, pypi, crates, go-proxy, rubygems, none

set -e

ss_detect_package_manager() {
  local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

  # Order matters: lockfiles are more authoritative than manifests
  [ -f "$root/pnpm-lock.yaml" ] && { echo "pnpm"; return 0; }
  [ -f "$root/bun.lockb" ] && { echo "bun"; return 0; }
  [ -f "$root/bun.lock" ] && { echo "bun"; return 0; }
  [ -f "$root/yarn.lock" ] && { echo "yarn"; return 0; }
  [ -f "$root/package-lock.json" ] && { echo "npm"; return 0; }
  [ -f "$root/poetry.lock" ] && { echo "poetry"; return 0; }
  [ -f "$root/uv.lock" ] && { echo "uv"; return 0; }
  [ -f "$root/Pipfile.lock" ] && { echo "pip"; return 0; }
  [ -f "$root/Cargo.lock" ] && { echo "cargo"; return 0; }
  [ -f "$root/Gemfile.lock" ] && { echo "gem"; return 0; }
  [ -f "$root/go.sum" ] && { echo "go"; return 0; }

  # Manifest-only fallbacks
  [ -f "$root/package.json" ] && { echo "npm"; return 0; }
  [ -f "$root/pyproject.toml" ] && { echo "poetry"; return 0; }
  [ -f "$root/requirements.txt" ] && { echo "pip"; return 0; }
  [ -f "$root/Cargo.toml" ] && { echo "cargo"; return 0; }
  [ -f "$root/go.mod" ] && { echo "go"; return 0; }
  [ -f "$root/Gemfile" ] && { echo "gem"; return 0; }

  echo "none"
}

ss_detect_registry() {
  local pm="$1"
  case "$pm" in
    pnpm|npm|yarn|bun) echo "npm" ;;
    pip|poetry|uv) echo "pypi" ;;
    cargo) echo "crates" ;;
    go) echo "go-proxy" ;;
    gem) echo "rubygems" ;;
    *) echo "none" ;;
  esac
}

# Query a registry for a specific package@version.
# Echoes "EXISTS" if published, "MISSING" if not, "UNKNOWN" on network/parse error.
# Uses a 24h cache at ~/.cache/specswarm/version-check/<registry>/<pkg>@<ver>.
ss_version_check() {
  local registry="$1"
  local pkg="$2"
  local ver="$3"

  [ -z "$registry" ] && { echo "UNKNOWN"; return 0; }
  [ -z "$pkg" ] && { echo "UNKNOWN"; return 0; }
  [ -z "$ver" ] && { echo "UNKNOWN"; return 0; }

  local cache_dir="${HOME}/.cache/specswarm/version-check/${registry}"
  mkdir -p "$cache_dir" 2>/dev/null || true

  # Sanitize filename: replace / with __ (scoped npm packages)
  local safe_pkg
  safe_pkg=$(echo "$pkg" | tr '/' '_')
  local cache_file="${cache_dir}/${safe_pkg}@${ver}"

  # 24h cache
  if [ -f "$cache_file" ]; then
    local age_seconds
    age_seconds=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))
    if [ "$age_seconds" -lt 86400 ]; then
      cat "$cache_file"
      return 0
    fi
  fi

  local result="UNKNOWN"
  local url=""
  case "$registry" in
    npm) url="https://registry.npmjs.org/${pkg}/${ver}" ;;
    pypi) url="https://pypi.org/pypi/${pkg}/${ver}/json" ;;
    crates) url="https://crates.io/api/v1/crates/${pkg}/${ver}" ;;
    rubygems) url="https://rubygems.org/api/v2/rubygems/${pkg}/versions/${ver}.json" ;;
    go-proxy) url="https://proxy.golang.org/${pkg}/@v/${ver}.info" ;;
  esac

  if [ -n "$url" ]; then
    # Do NOT use -f: it suppresses 4xx response codes via early exit.
    # We need the actual HTTP status to distinguish MISSING (404) from UNKNOWN (network).
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 "$url" 2>/dev/null || echo "000")
    case "$code" in
      200) result="EXISTS" ;;
      404|410) result="MISSING" ;;
      *) result="UNKNOWN" ;;
    esac
  fi

  echo "$result" > "$cache_file" 2>/dev/null || true
  echo "$result"
}
