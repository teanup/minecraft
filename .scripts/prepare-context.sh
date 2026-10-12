#!/usr/bin/env bash
# Assembles the Docker build context in .build.
#
# Usage: prepare-context.sh -b <paper|velocity> -u <jar-url> -s <sha256>
#        prepare-context.sh -l <definition.json> -V <minecraft-version>

set -euo pipefail
source "$(dirname "$0")/lib.sh"

require curl jq

project="" jar_url="" sha256="" definition="" minecraft_version=""
while getopts "b:u:s:l:V:" opt; do
  case $opt in
  b) project="$OPTARG" ;;
  u) jar_url="$OPTARG" ;;
  s) sha256="$OPTARG" ;;
  l) definition="$OPTARG" ;;
  V) minecraft_version="$OPTARG" ;;
  *) die "usage: prepare-context.sh -b <paper|velocity> -u <jar-url> -s <sha256> | -l <definition.json> -V <minecraft-version>" ;;
  esac
done

root="$(dirname "$0")/.."
context="$root/.build"
cache="${DOWNLOAD_CACHE:-$root/.cache}"

rm -rf "$context"
mkdir -p "$context" "$cache"

if [ -n "$definition" ]; then
  [ -f "$definition" ] || die "no image definition at $definition"
  [ -n "$minecraft_version" ] || die "missing -V minecraft version"

  # Download and cache plugins
  mkdir -p "$context/plugins"
  jq -c '.plugins' "$definition" >"$context/plugins.json"
  DOWNLOAD_CACHE="$cache" "$(dirname "$0")/resolve-plugins.sh" \
    -b "$(jq -r '.base | split(":")[0]' "$definition")" -V "$minecraft_version" \
    -o "$context/plugins" "$context/plugins.json"
else
  [ -n "$project" ] || die "missing -b server type"
  [ -n "$jar_url" ] || die "missing -u jar url"
  [ -n "$sha256" ] || die "missing -s sha256"

  # Prepare shared scripts
  cp "$root/entrypoint.sh" "$context/entrypoint.sh"
  cp "$(dirname "$0")/healthcheck.sh" "$context/healthcheck.sh"

  # Download and cache server binary
  log "fetching $project server jar"
  download "$jar_url" "$context/server.jar" "$sha256" sha256 "$cache"
fi

log "prepared $context"
