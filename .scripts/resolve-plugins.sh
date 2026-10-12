#!/usr/bin/env bash
# Resolves plugin manifests into a lockfile and downloads the plugin binaries.
#
# Usage: resolve-plugins.sh -b <paper|velocity> -V <minecraft-version> -o <out-dir> <manifest>...

set -euo pipefail
source "$(dirname "$0")/lib.sh"

require curl jq

base="" minecraft_version="" out_dir="" manifests=()
while getopts "b:V:o:" opt; do
  case $opt in
  b) base="$OPTARG" ;;
  V) minecraft_version="$OPTARG" ;;
  o) out_dir="$OPTARG" ;;
  *) die "usage: resolve-plugins.sh -b <paper|velocity> -V <minecraft-version> -o <out-dir> <manifest>..." ;;
  esac
done
shift $((OPTIND - 1))
manifests=("$@")

[ -n "$base" ] || die "missing -b base"
[ -n "$minecraft_version" ] || die "missing -V minecraft version"
[ -n "$out_dir" ] || die "missing -o output directory"
[ "${#manifests[@]}" -gt 0 ] || die "no manifests given"

for manifest in "${manifests[@]}"; do
  [ -f "$manifest" ] || die "manifest not found: $manifest"
done

mkdir -p "$out_dir"

# Merge manifests and keep the last entry for a duplicated plugin name
merged="$(jq -s 'map(if type == "array" then . else .plugins end) | add | group_by(.name) | map(.[-1])' "${manifests[@]}")"

# Prints "<version>\t<url>\t<algo>\t<hash>\t<newest-minecraft-version>" for the newest matching Modrinth release
modrinth() {
  local slug="$1" beta="$2" pin="$3" game="${4:-}" loaders games types json
  loaders="$(jq -cn --arg l "$base" '[$l]')"
  types='["release"]'
  [ "$beta" = "true" ] && types='["release","beta"]'

  local args=(-G "https://api.modrinth.com/v2/project/$slug/version"
    --data-urlencode "loaders=$loaders"
    --data-urlencode 'include_changelog=false')
  # Restrict to the target game version when one is given
  if [ -n "$game" ]; then
    games="$(jq -cn --arg v "$game" '[$v]')"
    args+=(--data-urlencode "game_versions=$games")
  fi

  json="$(api "${args[@]}")"

  # Pick the newest allowed/pinned release and report the newest supported game version
  jq -r --argjson types "$types" --arg pin "$pin" '
    [.[] | select(.version_type as $t | $types | index($t))]
    | (if $pin == "" then .[0] else map(select(.version_number == $pin))[0] end)
    | select(. != null)
    | (.files | map(select(.primary))[0] // .files[0]) as $f
    | "\(.version_number)\t\($f.url)\tsha512\t\($f.hashes.sha512)\t\(.game_versions | sort_by(split(".") | map(tonumber)) | last)"
  ' <<<"$json"
}

# Prints "<version>\t<url>\t<algo>\t<hash>\t" for the newest matching GitHub release
github() {
  local slug="$1" pin="$2" asset="$3" json
  if [ -n "$pin" ]; then
    json="$(api "https://api.github.com/repos/$slug/releases/tags/$pin")"
  else
    json="$(api "https://api.github.com/repos/$slug/releases/latest")"
  fi

  # Select the first matching asset
  jq -r --arg asset "$asset" '
    select(.tag_name != null)
    | .tag_name as $tag
    | [.assets[] | select(.name | test($asset))][0]
    | select(. != null)
    | "\($tag | sub("^v"; ""))\t\(.browser_download_url)\tsha256\t\(.digest // "" | sub("^sha256:"; ""))\t"
  ' <<<"$json"
}

lock="[]"
count="$(jq 'length' <<<"$merged")"
log "resolving $count plugin(s) for $base $minecraft_version"

for ((i = 0; i < count; i++)); do
  # Read one entry as tab-separated fields ("-" for an unset version)
  read -r name source slug beta pin asset strict < <(
    jq -r --argjson i "$i" '.[$i] | [.name, .source, (.slug // .name), (.beta // false), (.version // "-"), (.asset // "[.]jar$"), (.strict // false)] | @tsv' <<<"$merged"
  )
  [ "$pin" = "-" ] && pin=""

  case "$source" in
  modrinth)
    resolved="$(modrinth "$slug" "$beta" "$pin" "$minecraft_version")"
    # Allow Minecraft release fallback unless strict is set
    if [ -z "$resolved" ]; then
      if [ "$strict" = "true" ]; then
        die "$name: no release supports $base $minecraft_version"
      fi
      resolved="$(modrinth "$slug" "$beta" "$pin")"
      [ -n "$resolved" ] || die "$name: no release found"
      supported="$(cut -f5 <<<"$resolved")"
      warn "$name: no release for $minecraft_version, using latest (supports up to ${supported:-unknown})"
    fi
    ;;
  github) resolved="$(github "$slug" "$pin" "$asset")" ;;
  manual)
    url="$(jq -r --argjson i "$i" '.[$i].url // ""' <<<"$merged")"
    [ -n "$url" ] || die "$name: manual source requires a url"
    resolved="${pin:-manual}"$'\t'"$url"$'\tsha256\t\t'
    ;;
  *) die "$name: unknown source '$source'" ;;
  esac

  [ -n "$resolved" ] || die "$name: no matching release for $base $minecraft_version"

  IFS=$'\t' read -r version url algo hash _ <<<"$resolved"
  file="$name-$version.jar"

  log "  $name $version"
  download "$url" "$out_dir/$file" "$hash" "$algo" "${DOWNLOAD_CACHE:-}"

  # Record the resolved plugin in the lockfile
  lock="$(jq -c --arg n "$name" --arg s "$source" --arg v "$version" \
    --arg u "$url" --arg f "$file" --arg h "$hash" --arg a "$algo" \
    '. + [{name: $n, source: $s, version: $v, url: $u, file: $f, hash: (if $h == "" then null else "\($a):\($h)" end)}]' <<<"$lock")"
done

jq -S '.' <<<"$lock" >"$out_dir/plugins.lock.json"
log "wrote $out_dir/plugins.lock.json"
