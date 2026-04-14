#!/usr/bin/env bash
set -euo pipefail

source /project/scripts/common.sh

SERVER_DIR=/mnt/server
SERVER_BINARY="${SERVER_DIR}/ShooterGame/Binaries/Linux/ShooterGameServer"
CONFIG_TARGET_DIR="${SERVER_DIR}/ShooterGame/Saved/Config/LinuxServer"
CONFIG_SOURCE_DIR=/project/config

SERVER_MAP="${SERVER_MAP:-TheIsland}"
SESSION_NAME="${SESSION_NAME:-ARK SE ARM Dedicated}"
SERVER_PORT="${SERVER_PORT:-7777}"
QUERY_PORT="${QUERY_PORT:-27015}"
RCON_PORT="${RCON_PORT:-27020}"
MAX_PLAYERS="${MAX_PLAYERS:-20}"
ARK_PASSWORD="${ARK_PASSWORD:-}"
ARK_ADMIN_PASSWORD="${ARK_ADMIN_PASSWORD:-ChangeMeNow123}"
ADDITIONAL_ARGS="${ADDITIONAL_ARGS:-}"
MULTIHOME="${MULTIHOME:-}"
PUBLIC_IP_FOR_EPIC="${PUBLIC_IP_FOR_EPIC:-}"
ALT_SAVE_DIRECTORY_NAME="${ALT_SAVE_DIRECTORY_NAME:-}"
CLUSTER_ID="${CLUSTER_ID:-}"
CLUSTER_DIR_OVERRIDE="${CLUSTER_DIR_OVERRIDE:-}"
RCON_WAIT_TIMEOUT="${RCON_WAIT_TIMEOUT:-300}"

require_file "${SERVER_BINARY}"

mkdir -p "${SERVER_DIR}/ShooterGame/Saved/Config/LinuxServer"
mkdir -p "${SERVER_DIR}/ShooterGame/Saved/Logs"
mkdir -p "${SERVER_DIR}/ShooterGame/Saved/SavedArks"

if is_true "${SYNC_CONFIG_ON_START:-1}"; then
  if [[ -f "${CONFIG_SOURCE_DIR}/GameUserSettings.ini" ]]; then
    sync_config_file "${CONFIG_SOURCE_DIR}/GameUserSettings.ini" "${CONFIG_TARGET_DIR}/GameUserSettings.ini"
  fi
  if [[ -f "${CONFIG_SOURCE_DIR}/Game.ini" ]]; then
    sync_config_file "${CONFIG_SOURCE_DIR}/Game.ini" "${CONFIG_TARGET_DIR}/Game.ini"
  fi
fi

if is_true "${MODS_ENABLED:-0}"; then
  log "Mod support enabled. Ensure ActiveMods is set in GameUserSettings.ini and [ModInstaller] ModIDS lines exist in Game.ini."
fi

startup_uri="${SERVER_MAP}?listen?SessionName=\"${SESSION_NAME}\"?ServerAdminPassword=${ARK_ADMIN_PASSWORD}?Port=${SERVER_PORT}?QueryPort=${QUERY_PORT}?RCONPort=${RCON_PORT}?RCONEnabled=True?MaxPlayers=${MAX_PLAYERS}"

if [[ -n "${ARK_PASSWORD}" ]]; then
  startup_uri+="?ServerPassword=${ARK_PASSWORD}"
fi

if [[ -n "${ALT_SAVE_DIRECTORY_NAME}" ]]; then
  startup_uri+="?AltSaveDirectoryName=${ALT_SAVE_DIRECTORY_NAME}"
fi

flags=("-server")

if ! is_true "${BATTLE_EYE:-0}"; then
  flags+=("-NoBattlEye")
fi

if is_true "${MODS_ENABLED:-0}"; then
  flags+=("-AutoManagedMods")
fi

if is_true "${CROSSPLAY:-0}"; then
  flags+=("-crossplay")
  if [[ -n "${PUBLIC_IP_FOR_EPIC}" ]]; then
    flags+=("-PublicIPForEpic=${PUBLIC_IP_FOR_EPIC}")
  fi
fi

if [[ -n "${MULTIHOME}" ]]; then
  flags+=("-MultiHome=${MULTIHOME}")
fi

if [[ -n "${CLUSTER_ID}" ]]; then
  flags+=("-ClusterId=${CLUSTER_ID}")
fi

if [[ -n "${CLUSTER_DIR_OVERRIDE}" ]]; then
  flags+=("-ClusterDirOverride=${CLUSTER_DIR_OVERRIDE}")
fi

flags+=("-log")

if [[ -n "${ADDITIONAL_ARGS}" ]]; then
  # shellcheck disable=SC2206
  extra_args=( ${ADDITIONAL_ARGS} )
  flags+=("${extra_args[@]}")
fi

is_rcon_ready() {
  if ! command -v rcon >/dev/null 2>&1; then
    return 1
  fi
  rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" -c listplayers >/dev/null 2>&1
}

shutdown_server() {
  log "Received stop signal. Attempting graceful ARK shutdown."

  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    if is_rcon_ready; then
      log "RCON is available. Saving world and requesting clean shutdown."
      rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" -c saveworld || true
      sleep 3
      rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" -c DoExit || true
      sleep 10
    else
      log "RCON is not available. Falling back to SIGTERM."
      kill -TERM "${SERVER_PID}" >/dev/null 2>&1 || true
    fi

    for _ in $(seq 1 15); do
      if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      log "ShooterGameServer did not stop in time. Forcing SIGKILL."
      kill -KILL "${SERVER_PID}" >/dev/null 2>&1 || true
    fi

    wait "${SERVER_PID}" || true
  fi
}

trap shutdown_server TERM INT

cd "${SERVER_DIR}/ShooterGame/Binaries/Linux"
log "Starting ARK dedicated server on map ${SERVER_MAP}"
./ShooterGameServer "${startup_uri}" "${flags[@]}" &
SERVER_PID=$!

elapsed=0
while ! is_rcon_ready; do
  if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    log "ARK server process exited before RCON became available"
    wait "${SERVER_PID}"
    exit 1
  fi

  if (( elapsed >= RCON_WAIT_TIMEOUT )); then
    log "RCON did not become available after ${RCON_WAIT_TIMEOUT}s. Continuing without RCON readiness confirmation."
    break
  fi

  log "Waiting for RCON on 127.0.0.1:${RCON_PORT}..."
  sleep 5
  elapsed=$((elapsed + 5))
done

if is_rcon_ready; then
  log "ARK server is up and RCON is responding"
else
  log "ARK server is still running, but RCON is not responding"
fi

wait "${SERVER_PID}"