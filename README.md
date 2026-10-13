# Minecraft container images

[![Build Workflow Status](https://img.shields.io/github/actions/workflow/status/teanup/minecraft-containers/build.yml?style=flat-square&logo=github&logoColor=white&label=Build)](https://github.com/teanup/minecraft-containers/actions/workflows/build.yml)

Ready-to-run Minecraft server and proxy images, built from upstream releases and published to GHCR. The server jar and plugins are baked in, so there's no build step and no jar rangling &ndash; just pull and run. Every image supports running as any non-root user.

## Images

Every image is rebuilt weekly, and its tag moves whenever a layer changes. Pin a Minecraft version with `ghcr.io/teanup/minecraft-paper:26.3` to stay on a known build.

| Image                                                                                         | What it runs                                                                                                           |
| --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| [`minecraft-paper`](https://github.com/teanup/minecraft-containers/pkgs/container/minecraft-paper)       | A [Paper](https://papermc.io/software/paper/) server, tagged with the latest supported Minecraft version (e.g. `26.3`) |
| [`minecraft-velocity`](https://github.com/teanup/minecraft-containers/pkgs/container/minecraft-velocity) | A [Velocity](https://velocitypowered.com/) proxy for distributing players across servers                               |

Plugins can be mounted into `/opt/plugins`, or baked into a layered image on top of a base image. Two examples ship in this repo:

| Image                                                                                               | What it adds                                                           |
| --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| [`minecraft-exploration`](https://github.com/teanup/minecraft-containers/pkgs/container/minecraft-exploration) | A survival Paper server with handy exploration plugins                 |
| [`minecraft-proxy`](https://github.com/teanup/minecraft-containers/pkgs/container/minecraft-proxy)             | A Velocity proxy with plugins for server management and authentication |

## Getting started

Run the latest Paper image:

```bash
docker run --rm -it -p 25565:25565 -e EULA=true ghcr.io/teanup/minecraft-paper
```

Or use Docker Compose for a persistent setup:

```yaml
services:
  proxy:
    image: ghcr.io/teanup/minecraft-velocity:latest
    restart: unless-stopped
    stdin_open: true           # keep the console attached
    tty: true
    ports:
      - 25565:25565
    networks:
      - minecraft
    environment:
      MEMORY_LIMIT: 512M       # JVM max heap size
    volumes:
      - proxy-data:/server

  survival:
    image: ghcr.io/teanup/minecraft-paper:latest
    restart: unless-stopped
    stdin_open: true
    tty: true
    networks:
      - minecraft
    environment:
      MEMORY_LIMIT: 8G
      EULA: true               # accept the Minecraft EULA
    volumes:
      - survival-data:/server  # config, worlds, logs, etc.

networks:
  minecraft:

volumes:
  proxy-data:
  survival-data:
```

## Inside the container

```
/server/             Data directory (set by SERVER_DIR)
  server.jar         Symlink to the baked-in server jar
  config/            Config directory (set by CONFIG_DIR)
  plugins/           Plugin data, and symlinks to the baked-in jars
  logs/ world/ etc.  Minecraft-generated data

/opt/server/
  server.jar         Baked-in Paper/Velocity jar (set by SERVER_JAR)
  velocity.toml      Baked-in default Velocity config

/opt/plugins/        Baked-in plugin jars (set by PLUGIN_DIR)

/usr/local/bin/
  entrypoint         Container entrypoint script
  healthcheck        Container health check script
```

### Health check

Every image ships a `healthcheck` that performs a full Minecraft server list ping, so the container reports its health without extra tooling. Run it by hand inside a running container:

```bash
docker exec minecraft healthcheck -v 127.0.0.1 25565; echo "exit=$?"
```

## Layered images

A layered image is a single JSON file at the repository root. The workflow discovers these files and builds images that include the listed plugins.

```jsonc
{
  // Layered image published under minecraft-<name>
  "name": "exploration",
  // Base image to layer (minecraft-<base>), can pin a version
  "base": "paper",
  // Optional Minecraft version for plugins, defaults to latest
  "minecraft": "26.3",
  "plugins": [
    // Latest release from Modrinth
    { "name": "LuckPerms", "source": "modrinth", "slug": "luckperms" },
    // Latest release from GitHub, picking the asset matching the regex
    { "name": "ViaVersion", "source": "github", "slug": "ViaVersion/ViaVersion", "asset": ".*.jar" },
    // Pin an exact version from Modrinth
    { "name": "BlueMap", "source": "modrinth", "slug": "bluemap", "version": "5.29-paper" },
    // Allow beta releases, and fail the build if none supports the target Minecraft version
    { "name": "VeinMiner", "source": "modrinth", "slug": "veinminer", "beta": true, "strict": true },
    // Download from a direct URL
    { "name": "Custom", "source": "manual", "url": "https://example.com/custom.jar", "version": "1.0" },
  ],
}
```

## Building locally

Build a base image, then a layered image on top of it:

```bash
# Resolve latest Paper build
eval "$(./.scripts/resolve-server.sh -b paper)"

# Download Paper and build base image
./.scripts/prepare-context.sh -b paper -u "$url" -s "$sha256"
docker build -f Dockerfile.paper -t localhost/minecraft-paper .build

# Download plugins and build layered image
./.scripts/prepare-context.sh -l exploration.json -V "$version"
docker build -f Dockerfile.layered -t localhost/minecraft-exploration --build-arg BASE_IMAGE=localhost/minecraft-paper .build
```

For Velocity, pass the Paper version as the Minecraft version, since plugin sources track Minecraft versions:

```bash
minecraft=$version
# Resolve latest Velocity build
eval "$(./.scripts/resolve-server.sh -b velocity)"

# Download Velocity and build base image
./.scripts/prepare-context.sh -b velocity -u "$url" -s "$sha256"
docker build -f Dockerfile.velocity -t localhost/minecraft-velocity .build

# Download plugins and build layered image
./.scripts/prepare-context.sh -l proxy.json -V "$minecraft"
docker build -f Dockerfile.layered -t localhost/minecraft-proxy --build-arg BASE_IMAGE=localhost/minecraft-velocity .build
```
