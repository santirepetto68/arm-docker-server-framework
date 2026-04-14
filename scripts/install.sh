#!/usr/bin/env bash
set -euo pipefail

source /project/scripts/common.sh

SERVER_DIR=/mnt/server
STEAMCMD_DIR="${SERVER_DIR}/steamcmd"
STEAM_THIRDPARTY_DIR="${SERVER_DIR}/Engine/Binaries/ThirdParty/SteamCMD/Linux"
APP_ID="${SRCDS_APPID:-376030}"
STEAM_USER="${STEAM_USER:-anonymous}"
STEAM_PASS="${STEAM_PASS:-}"
STEAM_AUTH="${STEAM_AUTH:-}"
EXTRA_FLAGS="${EXTRA_FLAGS:-}"
VALIDATE_FLAG=""

if is_true "${INSTALL_VALIDATE:-0}"; then
  VALIDATE_FLAG="validate"
fi

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

SERVER_BINARY="${SERVER_DIR}/ShooterGame/Binaries/Linux/ShooterGameServer"
require_file "${SERVER_BINARY}"

log "Install/update completed successfully"
