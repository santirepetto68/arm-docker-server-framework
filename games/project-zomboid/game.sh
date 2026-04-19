#!/usr/bin/env bash
# Project Zomboid — game-specific startup and shutdown logic.
# Sourced by scripts/start-game.sh. Must define:
#   build_startup_command()  — sets STARTUP_CMD (string) and STARTUP_FLAGS (array)
#   shutdown_server()        — graceful shutdown using SERVER_PID global
#
# Launch strategy: run the stock ProjectZomboid64 shell launcher under FEX-Emu
# (GAME_LAUNCHER="FEX" in game.env). Credit: QuintenQVD0/Q_eggs ARM64 PZ egg
# (quintenqvd/pterodactyl_images:dev_fex_latest).
#
# History: we previously invoked `jre64/bin/java` directly under box64 with a
# curated JVM flag set, because ProjectZomboid64.json's flags (ZGC, compressed
# oops) make box64's dynarec mistranslate JIT'd code. FEX handles those flags
# correctly, so under FEX we use the launcher as-is and let it read its JSON.

# Defaults for Project Zomboid variables
SERVER_PORT="${SERVER_PORT:-16261}"
STEAM_PORT="${STEAM_PORT:-16262}"
SERVER_NAME="${SERVER_NAME:-servertest}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-CHANGE_ME}"
MAX_PLAYERS="${MAX_PLAYERS:-${GAME_DEFAULT_MAX_PLAYERS:-10}}"
ADDITIONAL_ARGS="${ADDITIONAL_ARGS:-}"
MODS="${MODS:-}"
MOD_WORKSHOP_IDS="${MOD_WORKSHOP_IDS:-}"

build_startup_command() {
  # Match the Quinten Q_eggs FEX egg env verbatim. Credit:
  # github.com/QuintenQVD0/Q_eggs (egg-project-zomboid-a-r-m64.json).
  export HOME="/mnt/server"
  export PATH="/mnt/server/jre64/bin:${PATH}"
  export LD_LIBRARY_PATH="/mnt/server/linux64:/mnt/server/natives:/mnt/server:/mnt/server/lib:${LD_LIBRARY_PATH:-}"

  # NOTE: libjsig.so preload is intentionally omitted. The host-side jre64/
  # copy isn't resolvable from FEX's x86_64 ld-linux, and PZ runs fine
  # without it under FEX. The Quinten egg preloads it because the panel
  # injects the env line unconditionally, not because it's required.

  # FEX rootfs bootstrap.
  #
  # The quintenqvd/pterodactyl_images:dev_fex_latest image does NOT bundle a
  # rootfs — its entrypoint script downloads one on first run. We bypass
  # that entrypoint, so we replicate the bootstrap here.
  #
  # FEX resolves its rootfs by:
  #   1. Reading $FEX_APP_CONFIG_LOCATION/Config.json (or ~/.fex-emu/Config.json)
  #   2. That JSON's Config.RootFS value names a subdirectory under
  #      $FEX_APP_DATA_LOCATION/RootFS/<name>/ (our ROOTFS_NAME below)
  #
  # Rootfs lives under /mnt/server/.fex/ so it persists across container
  # recreates via the data bind mount. We deliberately do NOT use
  # FEXRootFSFetcher — it's an interactive tool that spawns zenity and fails
  # silently in headless containers. Instead, curl the tarball directly.
  export FEX_APP_DATA_LOCATION="/mnt/server/.fex/"
  export FEX_APP_CONFIG_LOCATION="/mnt/server/.fex/"
  export XDG_DATA_HOME="/mnt/server/.fex"
  mkdir -p "${FEX_APP_DATA_LOCATION}/RootFS" "${FEX_APP_CONFIG_LOCATION}"

  local rootfs_name="Ubuntu_22_04"
  local rootfs_dir="${FEX_APP_DATA_LOCATION}RootFS/${rootfs_name}"
  local fex_config="${FEX_APP_CONFIG_LOCATION}Config.json"

  if [[ ! -d "${rootfs_dir}" ]]; then
    log "FEX rootfs not found — resolving download URL"
    # The rootfs URLs are date-stamped and rotate over time. The FEX-Emu
    # project publishes a catalog at the URL below; we parse out the
    # Ubuntu 22.04 SquashFS entry to stay current.
    local catalog_url="https://raw.githubusercontent.com/FEX-Emu/RootFS/refs/heads/main/RootFS_links.json"
    local rootfs_url
    rootfs_url="$(curl -fsSL "${catalog_url}" | \
                  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["v1"]["Ubuntu 22.04 (SquashFS)"]["URL"])' 2>/dev/null)"
    if [[ -z "${rootfs_url}" ]]; then
      log "Failed to resolve FEX rootfs URL from ${catalog_url}"
      exit 1
    fi

    log "Downloading FEX rootfs from ${rootfs_url} (~2GB, several minutes)"
    local tmp_sqsh="/tmp/${rootfs_name}.sqsh"
    if ! curl -fSL --retry 3 -o "${tmp_sqsh}" "${rootfs_url}"; then
      log "Failed to download FEX rootfs"
      exit 1
    fi
    mkdir -p "${rootfs_dir}"
    log "Extracting rootfs squashfs to ${rootfs_dir}"
    if ! unsquashfs -f -d "${rootfs_dir}" "${tmp_sqsh}" >/dev/null; then
      log "unsquashfs failed — keeping ${tmp_sqsh} as direct-mount fallback"
      mv "${tmp_sqsh}" "${FEX_APP_DATA_LOCATION}RootFS/${rootfs_name}.sqsh"
      rootfs_dir="${FEX_APP_DATA_LOCATION}RootFS/${rootfs_name}.sqsh"
    else
      rm -f "${tmp_sqsh}"
    fi
    log "FEX rootfs ready at ${rootfs_dir}"
  fi

  # Write Config.json pointing FEX at the rootfs.
  if [[ ! -f "${fex_config}" ]]; then
    echo "{\"Config\":{\"RootFS\":\"${rootfs_name}\"}}" > "${fex_config}"
    log "Generated FEX Config.json at ${fex_config}"
  fi

  # Pre-create Workshop/mod staging dirs — PZ enumerates them on startup.
  mkdir -p /mnt/server/.cache/mods \
           /mnt/server/.cache/Workshop \
           /mnt/server/steamapps/workshop/content/108600

  # We run the stock launcher (GAME_BINARY=ProjectZomboid64) under FEX.
  # All JVM flags come from ProjectZomboid64.json in the install dir; tune
  # heap and GC by editing that file.
  STARTUP_CMD=""
  STARTUP_FLAGS=(
    "-port" "${SERVER_PORT}"
    "-udpport" "${STEAM_PORT}"
    "-cachedir=/mnt/server/.cache"
    "-servername" "${SERVER_NAME}"
    "-adminusername" "${ADMIN_USER}"
    "-adminpassword" "${ADMIN_PASSWORD}"
  )

  # Disable Steam (no VAC, no Workshop). Only set NO_STEAM=1 for LAN-only servers.
  if is_true "${NO_STEAM:-0}"; then
    STARTUP_FLAGS+=("-nosteam")
  fi

  if is_true "${MODS_ENABLED:-0}" && [[ -n "${MODS}" ]]; then
    STARTUP_FLAGS+=("-mods" "${MODS}")
  fi

  if is_true "${MODS_ENABLED:-0}" && [[ -n "${MOD_WORKSHOP_IDS}" ]]; then
    STARTUP_FLAGS+=("-workshopids" "${MOD_WORKSHOP_IDS}")
  fi

  if [[ -n "${ADDITIONAL_ARGS}" ]]; then
    IFS=' ' read -ra extra_args <<< "${ADDITIONAL_ARGS}"
    STARTUP_FLAGS+=("${extra_args[@]}")
  fi
}

shutdown_server() {
  log "Received stop signal. Attempting graceful ${GAME_NAME} shutdown."

  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    # PZ has no RCON. SIGTERM is the correct graceful stop — PZ handles it.
    log "Sending SIGTERM to PID ${SERVER_PID}..."
    kill -TERM "${SERVER_PID}" >/dev/null 2>&1 || true

    for _ in $(seq 1 "${GAME_SHUTDOWN_GRACE_SECONDS:-30}"); do
      if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
        log "${GAME_NAME} server stopped cleanly."
        break
      fi
      sleep 1
    done

    if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      log "Server did not stop in time. Forcing SIGKILL."
      kill -KILL "${SERVER_PID}" >/dev/null 2>&1 || true
    fi

    wait "${SERVER_PID}" || true
  fi
}
