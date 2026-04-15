# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A Docker Compose framework for running Steam dedicated game servers (x86_64) on Ubuntu ARM64 hosts via box86/box64 emulation. Currently validated with ARK: Survival Evolved. Designed as a multi-game framework with a per-game module contract.

## Key commands

### First-time host setup (run once on the ARM64 host)
```bash
sudo ./scripts/bootstrap-ubuntu-arm-host.sh
```

### Install or update the server
```bash
docker compose run --rm ark-install
```
Set `INSTALL_VALIDATE=1` in `.env` for a full file validation pass (slower but thorough).

### Start / stop / logs
```bash
docker compose up -d ark
docker compose stop ark
docker compose logs -f ark
```

### Update flow
```bash
docker compose stop ark
docker compose run --rm ark-install
docker compose up -d ark
```

### Backup
```bash
./scripts/backup-game.sh ark-se
```
Sends `saveworld` via RCON, waits, then tars `ShooterGame/Saved` into `./backups/ark-se/`. Supports retention via `BACKUP_KEEP_LAST` env var.

## Architecture

### Per-game module contract

Each game lives in `games/<slug>/` and must provide:

- **`game.env`** — Bash-sourceable metadata: `GAME_ID`, `GAME_NAME`, `SRCDS_APPID`, `GAME_BINARY`, `GAME_WORKING_DIR`, `GAME_CONFIG_DIR`, `GAME_SAVE_DIR`, `GAME_LOG_DIR`, `GAME_CONFIG_FILES`, `GAME_SHUTDOWN_STRATEGY`, `GAME_HEALTHCHECK_STRATEGY`, `GAME_SUPPORTS_MODS`
- **`game.sh`** — Must define `build_startup_command()` (sets `STARTUP_CMD` and `STARTUP_FLAGS`), `shutdown_server()` (uses `SERVER_PID` global), and optionally `is_rcon_ready()`
- **`healthcheck.sh`** — Game-specific health check script used by Docker
- **`config/`** — Config files synced into the runtime container on start

### Generic scripts (`scripts/`)

- **`install-game.sh`** — Generic SteamCMD installer. Sources `game.env` for app ID and binary path. Handles ownership fix via `SERVER_UID`/`SERVER_GID`.
- **`start-game.sh`** — Generic runtime wrapper. Sources `game.env` + `game.sh`, syncs config, calls `build_startup_command()`, launches the server, runs RCON readiness loop if applicable, traps signals to call `shutdown_server()`.
- **`backup-game.sh`** — Generic backup. Takes game ID as arg, sources `game.env` for save directory, supports RCON pre-save and retention.
- **`healthcheck.sh`** — Fallback health check (PID-based with optional RCON).
- **`common.sh`** — Shared helpers: `log()`, `is_true()`, `require_file()`, `sync_config_file()`.

### Docker Compose services
- **`ark-install`** (`restart: no`) — runs `install-game.sh`. Exits when done.
- **`ark`** — runs `start-game.sh`. Both mount `./games/ark-se` at `/project/game:ro`.

Both containers mount:
- `./data/server` → `/mnt/server` (server binary + save data)
- `./scripts` → `/project/scripts` (read-only)
- `./games/ark-se` → `/project/game` (read-only, game module)
- `./config` → `/project/config` (read-only, deprecated)

### Deprecated shims

`scripts/install.sh`, `scripts/start.sh`, `scripts/backup.sh` are deprecated wrappers that exec the new generic scripts with `GAME_ID=ark-se`. They print a warning and will be removed in a future release.

### Config sync model
`games/ark-se/config/GameUserSettings.ini` and `Game.ini` are the source of truth. On every start, `start-game.sh` copies them into `ShooterGame/Saved/Config/LinuxServer/`. The old `config/` directory is deprecated.

### Health check model
Health checks use a layered approach: process alive (PID file at `/tmp/game.pid`) is sufficient for "healthy". RCON is checked as a bonus but its absence does not make the container unhealthy.

### Environment variables
Copy `.env.example` to `.env`. Key variables:
- `INSTALL_IMAGE` / `RUNTIME_IMAGE` — container images
- `SRCDS_APPID` — Steam app ID (`376030` for ARK, overridden by `game.env`)
- `SERVER_MAP`, `SESSION_NAME`, `MAX_PLAYERS`, `SERVER_PORT`, `QUERY_PORT`, `RCON_PORT`, `RAW_SOCKET_PORT`
- `ARK_PASSWORD`, `ARK_ADMIN_PASSWORD`
- `CROSSPLAY`, `PUBLIC_IP_FOR_EPIC`, `BATTLE_EYE`
- `MODS_ENABLED`, `SYNC_CONFIG_ON_START`, `RCON_WAIT_TIMEOUT`
- `ADDITIONAL_ARGS` — appended to the server flags array
- `MULTIHOME`, `ALT_SAVE_DIRECTORY_NAME`, `CLUSTER_ID`, `CLUSTER_DIR_OVERRIDE`
- `BACKUP_KEEP_LAST` — backup retention count (0 = keep all)
- `SERVER_UID` / `SERVER_GID` — file ownership repair after install

## Design rules (from AGENT.md)

- Use `set -euo pipefail` in all scripts.
- **Never require RCON for lifecycle management.** RCON can be late or absent under emulation; always have a signal-based fallback.
- Health/readiness reflects reality: bound UDP sockets ≠ fully ready; browser listing ≠ joinable.
- Every change touching `/mnt/server` must consider UID/GID consistency between install and runtime containers.
- Prefer additive refactors. Extract shared helpers first, then introduce per-game metadata, then restructure compose.
- Keep per-game differences visible. Don't hide everything behind one unreadable mega-script.
- Shared logic should only be extracted when at least two games clearly benefit.

## Planned evolution (Phases 3–4, not yet implemented)

- Phase 3: Restructure `docker-compose.yml` to use `${GAME_ID}` for all paths, split `.env` into shared + `instances/*.env`, migrate data to `data/games/<slug>/`
- Phase 4: Add `game-ctl.sh` CLI wrapper, per-game README, rewrite root README as framework docs
