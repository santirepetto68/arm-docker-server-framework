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

# Pre-warm SteamCMD: run once with just +quit so it can self-update and
# relaunch. Without this, the self-update triggered by the real command
# consumes our args on the first exec, then the relaunched binary drops
# into the interactive REPL ("-- type 'quit' to exit --") and hangs.
log "Pre-warming SteamCMD (self-update pass)"
./steamcmd.sh +quit || true

# Some games (e.g. Project Zomboid) split their install into per-platform depots.
# Under box64 emulation SteamCMD can misdetect the host platform and skip depots
# (for PZ this means the bundled jre64/ tree is missing). Allow games to force a
# specific platform via STEAMCMD_PLATFORM_TYPE in game.env or the instance env.
PLATFORM_ARGS=()
if [[ -n "${STEAMCMD_PLATFORM_TYPE:-}" ]]; then
  log "Forcing SteamCMD platform type: ${STEAMCMD_PLATFORM_TYPE}"
  PLATFORM_ARGS=(+@sSteamCmdForcePlatformType "${STEAMCMD_PLATFORM_TYPE}")
fi

# Build +login with only the tokens actually supplied. Passing empty "" args
# trips "Missing configuration" on recent SteamCMD builds when doing anonymous
# login.
LOGIN_ARGS=(+login "${STEAM_USER}")
if [[ "${STEAM_USER}" != "anonymous" ]]; then
  [[ -n "${STEAM_PASS}" ]] && LOGIN_ARGS+=("${STEAM_PASS}")
  [[ -n "${STEAM_AUTH}" ]] && LOGIN_ARGS+=("${STEAM_AUTH}")
fi

./steamcmd.sh \
  "${PLATFORM_ARGS[@]}" \
  +force_install_dir "${SERVER_DIR}" \
  "${LOGIN_ARGS[@]}" \
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
