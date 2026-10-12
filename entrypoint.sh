#!/usr/bin/env bash
# Container entrypoint for the Paper and Velocity images.
#
# Usage: entrypoint <paper|velocity> [args...]

set -euo pipefail

server_type="${1:?usage: entrypoint <paper|velocity> [args...]}"
shift

: "${MEMORY_LIMIT:=2G}"
: "${SERVER_JAR:=/opt/server/server.jar}"
: "${SERVER_DIR:=/server}"
: "${PLUGIN_DIR:=/opt/plugins}"
: "${CONFIG_DIR:=$SERVER_DIR/config}"

cd "$SERVER_DIR"

# Create symlink to server binary
if [ ! -e server.jar ]; then
  ln -s "$SERVER_JAR" server.jar
fi

# Create symlinks to plugin binaries
if [ -d "$PLUGIN_DIR" ]; then
  mkdir -p plugins
  for jar in "$PLUGIN_DIR"/*.jar; do
    [ -e "$jar" ] || continue
    ln -sf "$jar" "plugins/$(basename "$jar")"
  done
fi

if [ "$server_type" = "paper" ]; then
  # Ensure user accepts Minecraft EULA
  if [ "${EULA:-}" = "true" ]; then
    printf 'eula=true\n' >eula.txt
  elif [ -f eula.txt ] && grep -q '^eula=true' eula.txt; then
    :
  else
    cat >&2 <<'EOF'
This server requires you to accept the Minecraft EULA before it will start.

By setting EULA=true you confirm that you have read and agree to the Minecraft
End User License Agreement: https://aka.ms/MinecraftEULA
EOF
    exit 1
  fi

  # Isolate Paper config files in a config directory
  mkdir -p "$CONFIG_DIR"
  set -- \
    --config "$CONFIG_DIR/server.properties" \
    --bukkit-settings "$CONFIG_DIR/bukkit.yml" \
    --spigot-settings "$CONFIG_DIR/spigot.yml" \
    --commands-settings "$CONFIG_DIR/commands.yml" \
    --paper-dir "$CONFIG_DIR" \
    --nogui \
    "$@"
else
  # Isolate Velocity config file in a config directory
  mkdir -p "$CONFIG_DIR"
  if [ -f velocity.toml ] && [ ! -e "$CONFIG_DIR/velocity.toml" ]; then
    mv velocity.toml "$CONFIG_DIR/velocity.toml"
  fi
  if [ ! -e "$CONFIG_DIR/velocity.toml" ] && [ -f /opt/server/velocity.toml ]; then
    cp /opt/server/velocity.toml "$CONFIG_DIR/velocity.toml"
  fi
  if [ ! -e velocity.toml ]; then
    ln -s "$CONFIG_DIR/velocity.toml" velocity.toml
  fi
fi

# Run server binary
exec java \
  -Xms"$MEMORY_LIMIT" -Xmx"$MEMORY_LIMIT" \
  ${JVM_FLAGS:-} \
  -jar server.jar "$@"
