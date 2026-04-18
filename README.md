# Steam Dedicated Game Servers on Ubuntu ARM64

A Docker Compose framework for running Steam dedicated game servers (x86_64) on Ubuntu ARM64 hosts via box86/box64 emulation.

Currently validated with:
- **ARK: Survival Evolved**
- **Project Zomboid**

Designed as a multi-game framework: adding a new game means creating a `games/<slug>/` module folder with a small contract of metadata + shell hooks.

## What this project is and is not

This is a **Compose-first wrapper around an ARM/emulation approach**. None of the supported games ship native ARM64 binaries — they run as x86_64 Steam workloads under box86/box64.

This is **not** a panel, a database, or a Kubernetes-ready platform. It is a small, readable shell + Compose framework meant to stay debuggable.

## Project layout

```
.
├── docker-compose.yml          # Base + per-game services (ARK, PZ, ...)
├── .env.example                # Shared infrastructure variables
├── instances/                  # Per-game user config (NOT committed)
│   ├── ark-se.env.example
│   └── project-zomboid.env.example
├── games/                      # Per-game module directories (committed)
│   ├── ark-se/
│   │   ├── game.env            # Framework metadata
│   │   ├── game.sh             # Startup / shutdown logic
│   │   ├── healthcheck.sh
│   │   └── config/             # Config files synced on start
│   └── project-zomboid/
│       └── ...
├── scripts/
│   ├── bootstrap-ubuntu-arm-host.sh  # One-time host setup
│   ├── install-game.sh         # Generic SteamCMD installer
│   ├── start-game.sh           # Generic runtime launcher
│   ├── backup-game.sh          # Generic save-archive helper
│   ├── healthcheck.sh          # Generic fallback health check
│   ├── game-ctl.sh             # CLI wrapper (install/start/stop/backup/...)
│   ├── common.sh               # Shared shell helpers
│   ├── install.sh              # [DEPRECATED] shim → install-game.sh
│   ├── start.sh                # [DEPRECATED] shim → start-game.sh
│   └── backup.sh               # [DEPRECATED] shim → backup-game.sh
├── data/                       # Bind-mounted server files (NOT committed)
│   ├── ark-se/
│   └── project-zomboid/
└── backups/                    # Backup archives
```

## Host requirements

- Ubuntu ARM64 host (tested on Raspberry Pi 5 and other aarch64 boards)
- Docker Engine + Docker Compose plugin
- Open outbound internet access
- Enough storage for each game's server files, updates, saves, and mods

## First-time host bootstrap

Run once per host, before the first install:

```bash
cd scripts
sudo ./bootstrap-ubuntu-arm-host.sh
```

Installs box86/box64 (auto-detecting RPi3/4/5 for the correct cmake flags) and refreshes binfmt on the host.

## Environment file layout

Three layers, loaded in order (later overrides earlier):

| File | What goes here | Committed? |
|---|---|---|
| `.env` | Shared infra: images, `GAME_ID`, backup retention, UID/GID | No |
| `instances/<game-id>.env` | Game-specific user values: ports, passwords, mods | No |
| `games/<game-id>/game.env` | Framework metadata: binary path, app ID, shutdown strategy | Yes |

### Setup

```bash
cp .env.example .env
# Then for each game you want to run:
cp instances/ark-se.env.example         instances/ark-se.env
cp instances/project-zomboid.env.example instances/project-zomboid.env
# Edit instances/<game-id>.env with your passwords, ports, server name, etc.
```

At minimum edit **`ARK_ADMIN_PASSWORD`** (ARK) or **`ADMIN_PASSWORD`** (PZ) before starting the server.

## Quick start: the `game-ctl` CLI

All lifecycle operations are wrapped in one script. Pass a game ID (or omit to use `GAME_ID` from `.env`):

```bash
./scripts/game-ctl.sh list                             # show available game modules
./scripts/game-ctl.sh install ark-se                   # install or update
./scripts/game-ctl.sh start ark-se                     # start the server
./scripts/game-ctl.sh logs ark-se                      # follow logs
./scripts/game-ctl.sh status ark-se                    # container status + health
./scripts/game-ctl.sh backup ark-se                    # create a save backup
./scripts/game-ctl.sh stop ark-se                      # graceful stop
./scripts/game-ctl.sh restart ark-se
./scripts/game-ctl.sh update ark-se                    # stop + reinstall + start
```

Replace `ark-se` with `project-zomboid` for PZ operations.

## Running ARK: Survival Evolved

1. `cp instances/ark-se.env.example instances/ark-se.env`
2. Edit `instances/ark-se.env` — at minimum set `SESSION_NAME`, `ARK_ADMIN_PASSWORD`, `SERVER_MAP`, `MAX_PLAYERS`.
3. Optional: edit `games/ark-se/config/GameUserSettings.ini` and `games/ark-se/config/Game.ini`.
4. Install + start:
   ```bash
   ./scripts/game-ctl.sh install ark-se
   ./scripts/game-ctl.sh start ark-se
   ./scripts/game-ctl.sh logs ark-se
   ```

Or with raw Compose:
```bash
docker compose run --rm ark-install
docker compose up -d ark-se
docker compose logs -f ark-se
```

### ARK ports (default)

- `7777/udp` — game
- `7778/udp` — raw socket / peer
- `27015/udp` — query
- `27020/tcp` — RCON

### ARK shutdown behaviour

The runtime script uses RCON (`saveworld` then `DoExit`) with a SIGTERM fallback if RCON is unavailable. All RCON calls are `timeout 5`-wrapped so a hung socket can't block shutdown.

### ARK mods

Set in `instances/ark-se.env`:
```dotenv
MODS_ENABLED=1
```

Add mod IDs in `games/ark-se/config/GameUserSettings.ini`:
```ini
[ServerSettings]
ActiveMods=731604991,1404697612
```

And in `games/ark-se/config/Game.ini`:
```ini
[ModInstaller]
ModIDS=731604991
ModIDS=1404697612
```

Restart the server. First boot after adding mods can be slow.

## Running Project Zomboid

1. `cp instances/project-zomboid.env.example instances/project-zomboid.env`
2. Edit `instances/project-zomboid.env` — at minimum set `ADMIN_PASSWORD` and `SERVER_NAME`. The server name must be alphanumeric+underscores only.
3. Optional: edit `games/project-zomboid/config/servertest.ini` (world config) and `games/project-zomboid/config/servertest_SandboxVars.lua` (sandbox rules).
   - **Important:** if you change `SERVER_NAME` in the instance env, rename those two files to match (e.g. `myserver.ini`, `myserver_SandboxVars.lua`) and update `GAME_CONFIG_FILES` in `games/project-zomboid/game.env`.
4. Install + start:
   ```bash
   ./scripts/game-ctl.sh install project-zomboid
   ./scripts/game-ctl.sh start project-zomboid
   ./scripts/game-ctl.sh logs project-zomboid
   ```

Or with raw Compose:
```bash
docker compose run --rm project-zomboid-install
docker compose up -d project-zomboid
docker compose logs -f project-zomboid
```

### PZ ports (default)

- `16261/udp,tcp` — game port
- `16262/udp` — Steam UDP port

### PZ shutdown behaviour

PZ has no RCON. Shutdown is SIGTERM with a 30-second grace period, falling back to SIGKILL if the process doesn't exit in time. The JVM signal handler (`libjsig.so`) is preloaded automatically so SIGTERM lands cleanly.

### PZ mods

Set in `instances/project-zomboid.env`:
```dotenv
MODS_ENABLED=1
MODS=ExampleMod,AnotherMod
MOD_WORKSHOP_IDS=2392987739,2619072426
```

`MODS` is the in-game mod folder name (from the Workshop page), `MOD_WORKSHOP_IDS` is the numeric Workshop ID. Restart the server after changes.

### PZ health check

PID-only. The container is marked healthy as soon as the `ProjectZomboid64` process is alive and the PID file at `/tmp/game.pid` exists. PZ takes a few minutes to finish its first-boot world generation — the `start_period: 8m` in the healthcheck accounts for that.

## Data layout

Bind-mounted per game, readable directly on the host:

- `./data/ark-se/` — ARK server files, saves, config overrides
- `./data/project-zomboid/` — PZ server files, `.cache/Zomboid/` (saves + config)
- `./backups/<game-id>/` — backup archives from `game-ctl.sh backup` or `backup-game.sh`

## Per-game module contract

Each game lives in `games/<slug>/` and must provide:

| File | Purpose |
|---|---|
| `game.env` | Bash-sourceable metadata: `GAME_ID`, `SRCDS_APPID`, `GAME_BINARY`, paths, shutdown strategy, health check strategy, mod support flag |
| `game.sh` | Defines `build_startup_command()` (sets `STARTUP_CMD` + `STARTUP_FLAGS`), `shutdown_server()`, optionally `is_rcon_ready()` |
| `healthcheck.sh` | Docker health check script |
| `config/` | Config files synced into the runtime on start (when `SYNC_CONFIG_ON_START=1`) |

Generic scripts in `scripts/` handle the shared install/launch/backup/healthcheck flow; per-game files implement the differences.

## Backup

```bash
./scripts/game-ctl.sh backup ark-se
./scripts/game-ctl.sh backup project-zomboid
```

Or directly:
```bash
./scripts/backup-game.sh ark-se
./scripts/backup-game.sh project-zomboid
```

For ARK, the script issues `saveworld` over RCON before archiving. For PZ there is no RCON, so the archive may catch a mid-save state — stop the server first if you need a perfectly consistent snapshot.

## Troubleshooting

### Installer fails on ARM

Re-run the host bootstrap and confirm box86/box64 are present:
```bash
box86 --version
box64 --version
```
Confirm Docker is running on the same ARM64 host where bootstrap was executed.

### The server starts but isn't reachable

- Cloud firewall rules
- Host firewall (`ufw status`)
- Router/NAT port forwarding if self-hosted
- Ports in `instances/<game-id>.env` and the published ports in `docker-compose.yml` agree
- For PZ: both `PZ_SERVER_PORT` and `PZ_STEAM_PORT` must be reachable

### ARK: RCON issues

All RCON calls in this project use the positional syntax:
```
rcon -a host:port -p password command
```
Do NOT use `-c` — that flag does not exist and makes rcon enter interactive mode, hanging any script that calls it. All calls are `timeout 5`-wrapped for defense in depth.

### ARK: server crashes mid-session (Signal 11 / SIGSEGV)

Under box64 emulation, ARK can crash during world saves if `DefaultGameUserSettings.ini` in the server dir has been hand-edited. Keep your overrides in `games/ark-se/config/GameUserSettings.ini` (which this project syncs on start) and leave the base `Default*.ini` files alone.

### PZ: container unhealthy immediately

PZ's first boot generates the world from scratch — several minutes on ARM. The health check allows 8 minutes of `start_period` before the retry counter starts. Watch `docker compose logs -f project-zomboid` and wait for the `SERVER STARTED` line.

### Mods do not load

**ARK:**
- `MODS_ENABLED=1` in `instances/ark-se.env`
- `ActiveMods=` in `GameUserSettings.ini` matches the IDs in `Game.ini`'s `[ModInstaller]` block
- First boot finished completely before testing
- Clients have the same mods installed

**PZ:**
- `MODS_ENABLED=1` in `instances/project-zomboid.env`
- `MODS=` (folder names) and `MOD_WORKSHOP_IDS=` (numeric IDs) both set
- `NO_STEAM=0` (Workshop requires Steam)

## Design rules

See `AGENT.md` for the full rationale. Key ones:

- Use `set -euo pipefail` in all scripts.
- **Never require RCON for lifecycle management.** Always have a signal-based fallback.
- Health/readiness reflects reality: process alive is sufficient, RCON is a bonus.
- Every change touching `/mnt/server` must consider UID/GID consistency between install and runtime.
- Keep per-game differences visible. Don't hide everything behind one unreadable mega-script.
- Shared logic extracted only when at least two games clearly benefit.

## Credit

The install flow and base container images draw from [QuintenQVD0/Q_eggs](https://github.com/QuintenQVD0/Q_eggs) — a collection of Pterodactyl Panel eggs for Steam dedicated servers. This project uses those eggs as reference implementations when adding new games.
