#!/usr/bin/env bash
# Resolves the newest Paper/Velocity build for a project version.
#
# Usage: resolve-server.sh -b <paper|velocity> [-V version]

set -euo pipefail
source "$(dirname "$0")/lib.sh"

require curl jq

base="" version=""
while getopts "b:V:" opt; do
  case $opt in
  b) base="$OPTARG" ;;
  V) version="$OPTARG" ;;
  *) die "usage: resolve-server.sh -b <paper|velocity> [-V version]" ;;
  esac
done

[ -n "$base" ] || die "missing -b base"

# Fall back to the newest version with a stable build
[ -n "$version" ] || version="$(papermc_latest_version "$base")"
[ -n "$version" ] || die "could not resolve latest version for $base"

IFS=$'\t' read -r build url sha < <(papermc_build "$base" "$version")
[ -n "${build:-}" ] || die "no stable build found for $base $version"

# Compute valid semver version for image tags
cat <<EOF
version=$version
semver=$(echo ${version,,} | sed 's/^\([0-9]*\.[0-9]*\)\(-\|$\)/\1.0\2/')-$build
url=$url
sha256=$sha
EOF
