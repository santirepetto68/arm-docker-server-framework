# ARK: Survival Evolved on Ubuntu ARM with Docker Compose

This project packages the Pterodactyl ARM egg workflow into a cleaner Docker Compose layout focused on maintainability:

- separated install and runtime services
- source-controlled config files
- manual update path instead of opaque panel behavior
- mod-ready config structure
- simple backup helper

## What this project is and is not

This is a **Compose-first wrapper around the ARM emulation approach** used by the egg you shared.

It is **not** a native ARM server build. ARK: Survival Evolved remains an x86/x86_64 Steam server workload, so this setup relies on emulation.

## Project layout

- `docker-compose.yml` - install + runtime services
- `.env.example` - main environment variables
- `config/GameUserSettings.ini` - server settings and `ActiveMods`
- `config/Game.ini` - mod installer section and advanced game config
- `scripts/install.sh` - SteamCMD install/update job
- `scripts/start.sh` - runtime launcher with graceful RCON shutdown
- `scripts/backup.sh` - saveworld + tar backup helper
- `scripts/bootstrap-ubuntu-arm-host.sh` - one-time host bootstrap for Ubuntu ARM

## Host requirements

- Ubuntu ARM64 host
- Docker Engine + Docker Compose plugin
- Open outbound internet access
- Enough storage for ARK server files, updates, save data, and mods

## Important host bootstrap step

Because this stack is based on the same ARM/emulation approach as the egg repo, do the host bootstrap once before the first install:

```bash
cd scripts
sudo ./bootstrap-ubuntu-arm-host.sh
```

That script installs box86/box64 and refreshes binfmt on the host.

## First-time setup

1. Copy the environment template:

```bash
cp .env.example .env
```

2. Edit `.env` and at minimum set:

- `SESSION_NAME`
- `ARK_ADMIN_PASSWORD`
- `ARK_PASSWORD` if you want a private server
- `SERVER_MAP`
- `MAX_PLAYERS`

3. Optional: edit `config/GameUserSettings.ini` and `config/Game.ini`.

4. Install the server files:

```bash
docker compose run --rm ark-install
```

5. Start the server:

```bash
docker compose up -d ark
```

6. Follow logs:

```bash
docker compose logs -f ark
```

## Normal operations

### Stop the server

```bash
docker compose stop ark
```

The runtime script attempts `saveworld` and `DoExit` through RCON before the container stops.

### Start the server again

```bash
docker compose up -d ark
```

### Update the server

```bash
docker compose stop ark
docker compose run --rm ark-install
docker compose up -d ark
```

If you want a more expensive but safer update pass, set `INSTALL_VALIDATE=1` in `.env` before running the installer job.

## Mods

This project is ready for future Workshop mod use.

### Enable mod support

Set in `.env`:

```dotenv
MODS_ENABLED=1
```

### Add active mod IDs

Edit `config/GameUserSettings.ini` under `[ServerSettings]`:

```ini
ActiveMods=731604991,1404697612
```

Use a single comma-separated line with no spaces.

### Add installer entries

Edit `config/Game.ini`:

```ini
[ModInstaller]
ModIDS=731604991
ModIDS=1404697612
```

Add one `ModIDS=` line per mod.

### Apply changes

Restart the server:

```bash
docker compose restart ark
```

Large mods can take a while to download on startup. Do not assume the server is broken if the first modded boot is slow.

## Config management model

`config/GameUserSettings.ini` and `config/Game.ini` are treated as the source of truth.

On every start, `scripts/start.sh` copies them into:

- `ShooterGame/Saved/Config/LinuxServer/GameUserSettings.ini`
- `ShooterGame/Saved/Config/LinuxServer/Game.ini`

This keeps your runtime config maintainable and reviewable.

## Data locations

The project uses bind mounts so the data stays readable on the host.

- server files: `./data/server`
- backups: `./backups`
- runtime config source: `./config`

## Backup helper

Create a save backup from the host:

```bash
./scripts/backup.sh
```

This asks the server to `saveworld` over RCON, waits a few seconds, then archives `ShooterGame/Saved` into `./backups`.

## Ports

Default exposed ports:

- `7777/udp` - game port
- `7778/udp` - raw socket / peer port
- `27015/udp` - query port
- `27020/tcp` - RCON

Change them in `.env` if needed.

## Optional settings in `.env`

- `BATTLE_EYE=1` to enable BattleEye
- `CROSSPLAY=1` plus `PUBLIC_IP_FOR_EPIC=` if you want Epic crossplay parameters
- `MULTIHOME=` to bind a specific address
- `ALT_SAVE_DIRECTORY_NAME=` for per-map save naming
- `CLUSTER_ID=` and `CLUSTER_DIR_OVERRIDE=` for multi-map cluster setups
- `ADDITIONAL_ARGS=` for extra ARK launch flags

## Troubleshooting

### The installer fails on ARM

Re-run the host bootstrap script and confirm:

```bash
box86 --version
box64 --version
```

Also confirm Docker is running on the same ARM64 host where the bootstrap was executed.

### The server starts but is not reachable

Check:

- cloud firewall rules
- host firewall rules
- router/NAT forwarding if self-hosted
- the exposed UDP ports in `docker-compose.yml`
- `SESSION_NAME`, `SERVER_PORT`, `QUERY_PORT`, and `RAW_SOCKET_PORT`

### Mods do not load

Check all of the following:

- `MODS_ENABLED=1`
- `ActiveMods=` contains the exact IDs in `GameUserSettings.ini`
- `Game.ini` includes matching `ModIDS=` entries under `[ModInstaller]`
- the first boot after adding mods finished completely
- clients have enough time to download/update the same mods

## Notes

This project intentionally keeps install/update as an explicit maintenance action. That makes troubleshooting, rollback, and future mod administration much easier than hiding updates inside container startup.
