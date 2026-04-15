#!/usr/bin/env bash
# ARK: Survival Evolved — game-specific startup and shutdown logic.
# Sourced by scripts/start-game.sh. Must define:
#   build_startup_command()  — sets STARTUP_CMD (string) and STARTUP_FLAGS (array)
#   shutdown_server()        — graceful shutdown using SERVER_PID global
#   is_rcon_ready()          — returns 0 if RCON responds

# Defaults for ARK-specific variables
SERVER_MAP="${SERVER_MAP:-${GAME_DEFAULT_MAP:-TheIsland}}"
SESSION_NAME="${SESSION_NAME:-ARK SE ARM Dedicated}"
SERVER_PORT="${SERVER_PORT:-7777}"
QUERY_PORT="${QUERY_PORT:-27015}"
RCON_PORT="${RCON_PORT:-27020}"
MAX_PLAYERS="${MAX_PLAYERS:-${GAME_DEFAULT_MAX_PLAYERS:-20}}"
ARK_PASSWORD="${ARK_PASSWORD:-}"
ARK_ADMIN_PASSWORD="${ARK_ADMIN_PASSWORD:-CHANGE_ME}"
ADDITIONAL_ARGS="${ADDITIONAL_ARGS:-}"
MULTIHOME="${MULTIHOME:-}"
PUBLIC_IP_FOR_EPIC="${PUBLIC_IP_FOR_EPIC:-}"
ALT_SAVE_DIRECTORY_NAME="${ALT_SAVE_DIRECTORY_NAME:-}"
CLUSTER_ID="${CLUSTER_ID:-}"
CLUSTER_DIR_OVERRIDE="${CLUSTER_DIR_OVERRIDE:-}"

build_startup_command() {
  STARTUP_CMD="${SERVER_MAP}?listen?SessionName=\"${SESSION_NAME}\"?ServerAdminPassword=${ARK_ADMIN_PASSWORD}?Port=${SERVER_PORT}?QueryPort=${QUERY_PORT}?RCONPort=${RCON_PORT}?RCONEnabled=True?MaxPlayers=${MAX_PLAYERS}"

  if [[ -n "${ARK_PASSWORD}" ]]; then
    STARTUP_CMD+="?ServerPassword=${ARK_PASSWORD}"
  fi

  if [[ -n "${ALT_SAVE_DIRECTORY_NAME}" ]]; then
    STARTUP_CMD+="?AltSaveDirectoryName=${ALT_SAVE_DIRECTORY_NAME}"
  fi

  STARTUP_FLAGS=("-server")

  if ! is_true "${BATTLE_EYE:-0}"; then
    STARTUP_FLAGS+=("-NoBattlEye")
  fi

  if is_true "${MODS_ENABLED:-0}"; then
    STARTUP_FLAGS+=("-AutoManagedMods")
  fi

  if is_true "${CROSSPLAY:-0}"; then
    STARTUP_FLAGS+=("-crossplay")
    if [[ -n "${PUBLIC_IP_FOR_EPIC}" ]]; then
      STARTUP_FLAGS+=("-PublicIPForEpic=${PUBLIC_IP_FOR_EPIC}")
    fi
  fi

  if [[ -n "${MULTIHOME}" ]]; then
    STARTUP_FLAGS+=("-MultiHome=${MULTIHOME}")
  fi

  if [[ -n "${CLUSTER_ID}" ]]; then
    STARTUP_FLAGS+=("-ClusterId=${CLUSTER_ID}")
  fi

  if [[ -n "${CLUSTER_DIR_OVERRIDE}" ]]; then
    STARTUP_FLAGS+=("-ClusterDirOverride=${CLUSTER_DIR_OVERRIDE}")
  fi

  STARTUP_FLAGS+=("-log")

  if [[ -n "${ADDITIONAL_ARGS}" ]]; then
    IFS=' ' read -ra extra_args <<< "${ADDITIONAL_ARGS}"
    STARTUP_FLAGS+=("${extra_args[@]}")
  fi
}

is_rcon_ready() {
  if ! command -v rcon >/dev/null 2>&1; then
    return 1
  fi
  timeout 5 rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" listplayers >/dev/null 2>&1
}

shutdown_server() {
  log "Received stop signal. Attempting graceful ${GAME_NAME} shutdown."

  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    rcon_ok=0
    if command -v rcon >/dev/null 2>&1 && [[ -n "${RCON_PORT:-}" ]] && [[ -n "${ARK_ADMIN_PASSWORD:-}" ]]; then
      log "Attempting RCON saveworld on 127.0.0.1:${RCON_PORT}..."
      if timeout 5 rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" saveworld 2>&1; then
        rcon_ok=1
        log "World saved via RCON. Requesting clean exit."
        sleep 3
        timeout 5 rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" DoExit 2>&1 || true
        sleep 10
      else
        log "RCON saveworld failed. Falling back to SIGTERM."
      fi
    else
      log "RCON not available (missing binary or credentials). Falling back to SIGTERM."
    fi

    if [[ "${rcon_ok}" -eq 0 ]]; then
      kill -TERM "${SERVER_PID}" >/dev/null 2>&1 || true
    fi

    for _ in $(seq 1 "${GAME_SHUTDOWN_GRACE_SECONDS:-15}"); do
      if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
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
