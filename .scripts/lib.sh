#!/usr/bin/env bash
# Shared helpers for the build scripts.

set -euo pipefail

REPO="${GITHUB_REPOSITORY:-teanup/minecraft}"
USER_AGENT="${USER_AGENT:-$REPO (https://github.com/$REPO)}"

# Logs a message
log() { printf '%s\n' "$*" >&2; }

# Logs an error message and exits
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Emits a GitHub Actions warning annotation when running in CI
warn() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::warning::%s\n' "$*" >&2
  else
    printf 'warning: %s\n' "$*" >&2
  fi
}

# Fails if a command is missing
require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
  done
}

# Performs HTTP requests with a custom User-Agent
api() {
  curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 2 --retry-connrefused \
    -H "User-Agent: $USER_AGENT" "$@"
}

# Downloads a file, validates its hash and adds it to a cache
download() {
  local url="$1" dest="$2" hash="${3:-}" algo="${4:-sha256}" cache="${5:-}"
  mkdir -p "$(dirname "$dest")"

  local cached=""
  if [ -n "$cache" ] && [ -n "$hash" ]; then
    cached="$cache/$(basename "$dest")"
    if [ -f "$cached" ] && [ "$("${algo}sum" "$cached" | cut -d' ' -f1)" = "$hash" ]; then
      cp "$cached" "$dest"
      return 0
    fi
  fi

  api -o "$dest" "$url"

  if [ -n "$hash" ]; then
    local actual
    actual="$("${algo}sum" "$dest" | cut -d' ' -f1)"
    [ "$actual" = "$hash" ] || die "checksum mismatch for $url"
  fi

  if [ -n "$cached" ]; then
    cp "$dest" "$cached"
  fi
}

# Prints "<build-id>\t<download-url>\t<sha256>" for the newest stable Paper/Velocity build
papermc_build() {
  local project="$1" version="$2"
  api "https://fill.papermc.io/v3/projects/$project/versions/$version/builds" |
    jq -r '[.[] | select(.channel == "STABLE")][0]
           | if . == null then empty
             else "\(.id)\t\(.downloads["server:default"].url)\t\(.downloads["server:default"].checksums.sha256)"
             end'
}

# Prints the newest Paper/Velocity version id that has a stable build
papermc_latest_version() {
  local project="$1" version
  while read -r version; do
    if [ -n "$(papermc_build "$project" "$version")" ]; then
      printf '%s' "$version"
      return 0
    fi
  done < <(api "https://fill.papermc.io/v3/projects/$project/versions" |
    jq -r '[.versions[] | select(.version.support.status == "SUPPORTED")][].version.id')
  return 1
}
