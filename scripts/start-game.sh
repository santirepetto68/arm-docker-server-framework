#!/usr/bin/env bash
set -euo pipefail

source /project/scripts/common.sh

# Load game metadata
GAME_ENV="/project/game/game.env"
if [[ -f "${GAME_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${GAME_ENV}"
else
  log "No game.env found at ${GAME_ENV}"
  exit 1
fi

# Load game-specific startup/shutdown logic
GAME_SH="/project/game/game.sh"
if [[ -f "${GAME_SH}" ]]; then
  # shellcheck disable=SC1090
  source "${GAME_SH}"
else
  log "No game.sh found at ${GAME_SH}"
  exit 1
fi

SERVER_DIR=/mnt/server
RCON_WAIT_TIMEOUT="${RCON_WAIT_TIMEOUT:-300}"

require_file "${SERVER_DIR}/${GAME_BINARY}"

# Create required directories
mkdir -p "${SERVER_DIR}/${GAME_CONFIG_DIR}"
mkdir -p "${SERVER_DIR}/${GAME_LOG_DIR}"
if [[ -n "${GAME_SAVE_DIR:-}" ]]; then
  mkdir -p "${SERVER_DIR}/${GAME_SAVE_DIR}"
fi

# Sync config files from game module into runtime location
if is_true "${SYNC_CONFIG_ON_START:-1}"; then
  for config_file in ${GAME_CONFIG_FILES:-}; do
    if [[ -f "/project/game/config/${config_file}" ]]; then
      sync_config_file "/project/game/config/${config_file}" \
                       "${SERVER_DIR}/${GAME_CONFIG_DIR}/${config_file}"
    fi
  done
fi

# Log mod hint if applicable
if is_true "${GAME_SUPPORTS_MODS:-0}" && is_true "${MODS_ENABLED:-0}"; then
  log "Mod support enabled for ${GAME_NAME}."
fi

# Build startup command (defined in game.sh)
build_startup_command

# Set up shutdown trap (shutdown_server defined in game.sh)
trap shutdown_server TERM INT

# Launch server
cd "${SERVER_DIR}/${GAME_WORKING_DIR}"
log "Starting ${GAME_NAME} dedicated server"
# Resolve the binary path relative to GAME_WORKING_DIR. ARK uses a
# `GAME_BINARY` that's inside `GAME_WORKING_DIR`, so basename works. PZ
# uses `GAME_WORKING_DIR=.` + `GAME_BINARY=jre64/bin/java`, so we need
# the subpath preserved.
if [[ "${GAME_WORKING_DIR:-.}" != "." ]]; then
  BINARY_REL="./$(basename "${GAME_BINARY}")"
else
  BINARY_REL="./${GAME_BINARY}"
fi

# Only pass STARTUP_CMD as an argument if the game module populated it.
# ARK uses it for the map/options URL; PZ leaves it empty (all config via flags).
if [[ -n "${STARTUP_CMD:-}" ]]; then
  "${BINARY_REL}" "${STARTUP_CMD}" "${STARTUP_FLAGS[@]}" &
else
  "${BINARY_REL}" "${STARTUP_FLAGS[@]}" &
fi
SERVER_PID=$!
echo "${SERVER_PID}" > /tmp/game.pid

# RCON readiness loop (if game uses RCON health checks)
if [[ "${GAME_HEALTHCHECK_STRATEGY:-}" == "rcon" ]] && declare -f is_rcon_ready >/dev/null 2>&1; then
  elapsed=0
  while ! is_rcon_ready; do
    if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      log "${GAME_NAME} server process exited before RCON became available"
      wait "${SERVER_PID}"
      exit 1
    fi

    if (( elapsed >= RCON_WAIT_TIMEOUT )); then
      log "RCON did not become available after ${RCON_WAIT_TIMEOUT}s. Continuing without RCON readiness confirmation."
      break
    fi

    rcon_port_var="${GAME_RCON_PORT_VAR:-RCON_PORT}"
    log "Waiting for RCON on 127.0.0.1:${!rcon_port_var}..."
    sleep 5
    elapsed=$((elapsed + 5))
  done

  if is_rcon_ready; then
    log "${GAME_NAME} server is up and RCON is responding"
  else
    log "${GAME_NAME} server is still running, but RCON is not responding"
  fi
fi

wait "${SERVER_PID}"
