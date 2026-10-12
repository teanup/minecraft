#!/usr/bin/env bash
# Minecraft server list ping as a container health check.
#
# Usage: healthcheck.sh [-t timeout] [-p protocol] [-v] [host] [port]

set -euo pipefail

timeout=1
protocol=777
verbose=""

while getopts "t:p:v" opt; do
  case $opt in
  t) timeout="$OPTARG" ;;
  p) protocol="$OPTARG" ;;
  v) verbose=1 ;;
  *) echo "usage: healthcheck.sh [-t timeout] [-p protocol] [-v] [host] [port]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

host="${1:-127.0.0.1}"
port="${2:-25565}"

varint() {
  local value="$1" out=""
  while :; do
    local byte=$((value & 0x7f))
    value=$((value >> 7))
    [ "$value" -ne 0 ] && byte=$((byte | 0x80))
    out+="$(printf '%02x' "$byte")"
    [ "$value" -eq 0 ] && break
  done
  printf '%s' "$out"
}

mc_string() {
  local value="$1"
  printf '%s%s' "$(varint "${#value}")" "$(printf '%s' "$value" | od -An -tx1 | tr -d ' \n')"
}

packet() {
  local payload="$1"
  printf '%s%s' "$(varint $((${#payload} / 2)))" "$payload"
}

handshake() {
  local payload
  payload="$(varint 0)$(varint "$protocol")$(mc_string "$host")$(printf '%02x%02x' $((port >> 8)) $((port & 0xff)))$(varint 1)"
  packet "$payload"
}

read_varint() {
  local hex="$1" pos="$2" value=0 shift=0 byte
  while :; do
    byte=$((16#${hex:$pos:2}))
    value=$((value | ((byte & 0x7f) << shift)))
    pos=$((pos + 2))
    shift=$((shift + 7))
    [ $((byte & 0x80)) -eq 0 ] && break
    [ "$shift" -ge 35 ] && return 1
  done
  printf '%s %s' "$value" "$pos"
}

request="$(handshake "$host" "$port")$(packet "$(varint 0)")"

# Keep stdin open until timeout to let response in
response="$(
  { printf '%s' "$request" | xxd -r -p; sleep "$timeout"; } |
  nc -w "$timeout" "$host" "$port" 2>/dev/null |
  od -An -tx1 | tr -d ' \n'
)" || exit 1

if [ -n "$verbose" ]; then
  printf 'request:  %s\n' "$request" >&2
  printf 'response: %s\n' "${response:-<empty>}" >&2
fi

[ -n "$response" ] || exit 1

# Parse response JSON
read -r _ pos <<<"$(read_varint "$response" 0)" || exit 1
read -r packet_id pos <<<"$(read_varint "$response" "$pos")" || exit 1
[ "$packet_id" -eq 0 ] || exit 1
read -r json_len pos <<<"$(read_varint "$response" "$pos")" || exit 1

json="$(printf '%s' "${response:$pos:$((json_len * 2))}" | xxd -r -p)"

if [ -n "$verbose" ]; then
  printf 'status:   %s\n' "$json" >&2
fi

# Validate response content
printf '%s' "$json" | jq -e '.version.name and .players.online' >/dev/null
