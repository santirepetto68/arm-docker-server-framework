# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A Docker Compose stack for running ARK: Survival Evolved (x86_64) on an Ubuntu ARM64 host via box86/box64 emulation. The project is intentionally structured for future generalization into a multi-Steam-game framework, but only ARK is supported today.

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
./scripts/backup.sh
```
Sends `saveworld` via RCON, waits, then tars `ShooterGame/Saved` into `./backups/`.

## Architecture

### Service split
`docker-compose.yml` defines two services:
- **`ark-install`** (`restart: no`) — runs `scripts/install.sh` inside the `installer_steamcmd` image to download/update server files via SteamCMD. Exits when done.
- **`ark`** — runs `scripts/start.sh` inside the `emulation` image. Mounts the same `./data/server` volume as the installer.

Both containers mount:
- `./data/server` → `/mnt/server` (server binary + save data)
- `./scripts` → `/project/scripts` (read-only)
- `./config` → `/project/config` (read-only)

### Config sync model
`config/GameUserSettings.ini` and `config/Game.ini` are the source of truth. On every start, `start.sh` copies them into `ShooterGame/Saved/Config/LinuxServer/`. Edit the files under `config/` — not the runtime copies.

### Startup and shutdown (`scripts/start.sh`)
1. Syncs config files (unless `SYNC_CONFIG_ON_START=0`).
2. Builds the startup URI and flag array from env vars.
3. Launches `ShooterGameServer` as a background process.
4. Polls RCON in a loop (up to `RCON_WAIT_TIMEOUT` seconds, default 300) to confirm readiness — but continues even if RCON never responds.
5. On `TERM`/`INT`: attempts graceful `saveworld` + `DoExit` via RCON if available, falls back to `SIGTERM`, then force-kills after a timeout.

### Shared helpers (`scripts/common.sh`)
All scripts source this file. It provides: `log()`, `is_true()`, `require_file()`, `sync_config_file()`.

### Environment variables
Copy `.env.example` to `.env`. Key variables:
- `INSTALL_IMAGE` / `RUNTIME_IMAGE` — container images (from `quintenqvd/pterodactyl_images`)
- `SRCDS_APPID` — Steam app ID (`376030` for ARK)
- `SERVER_MAP`, `SESSION_NAME`, `MAX_PLAYERS`, `SERVER_PORT`, `QUERY_PORT`, `RCON_PORT`, `RAW_SOCKET_PORT`
- `ARK_PASSWORD`, `ARK_ADMIN_PASSWORD`
- `CROSSPLAY=1` + `PUBLIC_IP_FOR_EPIC=<ip>` for Epic Games crossplay
- `MODS_ENABLED=1` — enables `-AutoManagedMods` and mod logging
- `INSTALL_VALIDATE=1` — passes `validate` to SteamCMD
- `RCON_WAIT_TIMEOUT` — seconds to wait for RCON before continuing (default 300)
- `ADDITIONAL_ARGS` — appended verbatim to the server flags array

## Design rules (from AGENT.md)

- Use `set -euo pipefail` in all scripts.
- **Never require RCON for lifecycle management.** RCON can be late or absent under emulation; always have a signal-based fallback.
- Health/readiness reflects reality: bound UDP sockets ≠ fully ready; browser listing ≠ joinable.
- Every change touching `/mnt/server` must consider UID/GID consistency between install and runtime containers.
- Prefer additive refactors. Extract shared helpers first, then introduce per-game metadata, then restructure compose.
- Do not over-generalize before a second game is added.

## Planned evolution

The project is intended to grow into a multi-game framework with a `games/<slug>/` structure per game. Until a second game is added, do not prematurely abstract the ARK-specific logic.
