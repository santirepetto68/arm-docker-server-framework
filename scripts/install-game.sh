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

SERVER_DIR=/mnt/server
STEAMCMD_DIR="${SERVER_DIR}/steamcmd"
STEAM_THIRDPARTY_DIR="${SERVER_DIR}/Engine/Binaries/ThirdParty/SteamCMD/Linux"
APP_ID="${SRCDS_APPID:?SRCDS_APPID not defined in game.env}"
STEAM_USER="${STEAM_USER:-anonymous}"
STEAM_PASS="${STEAM_PASS:-}"
STEAM_AUTH="${STEAM_AUTH:-}"
EXTRA_FLAGS="${EXTRA_FLAGS:-}"
VALIDATE_FLAG=""

if is_true "${INSTALL_VALIDATE:-0}"; then
  VALIDATE_FLAG="validate"
fi

log "Installing/updating ${GAME_NAME:-game} (App ID: ${APP_ID})"

mkdir -p "${SERVER_DIR}" "${STEAMCMD_DIR}" "${STEAM_THIRDPARTY_DIR}" "${SERVER_DIR}/steamapps"
cd /tmp

if [[ ! -f "${STEAMCMD_DIR}/steamcmd.sh" ]]; then
  log "Downloading SteamCMD bootstrap"
  curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
  tar -xzvf steamcmd.tar.gz -C "${STEAMCMD_DIR}"
  tar -xzvf steamcmd.tar.gz -C "${STEAM_THIRDPARTY_DIR}"
fi

log "Running SteamCMD install/update for app ${APP_ID}"
cd "${STEAMCMD_DIR}"
export HOME="${SERVER_DIR}"

./steamcmd.sh \
  +force_install_dir "${SERVER_DIR}" \
  +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" \
  +app_update "${APP_ID}" ${EXTRA_FLAGS} ${VALIDATE_FLAG} \
  +quit

mkdir -p "${SERVER_DIR}/.steam/sdk32" "${SERVER_DIR}/.steam/sdk64"
if [[ -f "${STEAMCMD_DIR}/linux32/steamclient.so" ]]; then
  cp -f "${STEAMCMD_DIR}/linux32/steamclient.so" "${SERVER_DIR}/.steam/sdk32/steamclient.so"
fi
if [[ -f "${STEAMCMD_DIR}/linux64/steamclient.so" ]]; then
  cp -f "${STEAMCMD_DIR}/linux64/steamclient.so" "${SERVER_DIR}/.steam/sdk64/steamclient.so"
fi

mkdir -p "${SERVER_DIR}/Engine/Binaries/ThirdParty/SteamCMD/Linux"
ln -sfn ../../../../../Steam/steamapps "${SERVER_DIR}/Engine/Binaries/ThirdParty/SteamCMD/Linux/steamapps"

SERVER_BINARY="${SERVER_DIR}/${GAME_BINARY:?GAME_BINARY not defined in game.env}"
require_file "${SERVER_BINARY}"

SERVER_UID="${SERVER_UID:-0}"
SERVER_GID="${SERVER_GID:-0}"
if [[ "${SERVER_UID}" != "0" ]] || [[ "${SERVER_GID}" != "0" ]]; then
  log "Setting ownership to ${SERVER_UID}:${SERVER_GID} on ${SERVER_DIR}"
  chown -R "${SERVER_UID}:${SERVER_GID}" "${SERVER_DIR}"
fi

log "Install/update for ${GAME_NAME:-game} completed successfully"
