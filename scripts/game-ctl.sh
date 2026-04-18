#!/usr/bin/env bash
# game-ctl.sh — CLI wrapper for managing game server instances.
# Usage: ./scripts/game-ctl.sh <command> [game-id]
#
# Commands:
#   install   Run the installer/updater for the game
#   start     Start the game server in the background
#   stop      Gracefully stop the game server
#   restart   Stop then start the game server
#   status    Show container status and health
#   logs      Follow the game server logs (Ctrl+C to exit)
#   backup    Create a backup of the game save data
#   update    Stop, reinstall/update, then start the game server
#   list      List all available game modules (games/ directory)
#
# Examples:
#   ./scripts/game-ctl.sh start ark-se
#   ./scripts/game-ctl.sh backup project-zomboid
#   ./scripts/game-ctl.sh list

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  sed -n '/^# Usage:/,/^[^#]/{ s/^# \?//; /^[^#]/d; p }' "$0"
  exit 1
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_game_module() {
  local game_id="$1"
  local module_dir="${PROJECT_ROOT}/games/${game_id}"
  if [[ ! -d "${module_dir}" ]]; then
    die "No game module found at games/${game_id}/. Run './scripts/game-ctl.sh list' to see available games."
  fi
  if [[ ! -f "${module_dir}/game.env" ]]; then
    die "Game module games/${game_id}/ is missing game.env."
  fi
}

resolve_game_id() {
  local arg="${1:-}"
  if [[ -n "${arg}" ]]; then
    echo "${arg}"
    return
  fi
  # Fall back to GAME_ID in .env, then default to ark-se
  if [[ -f "${ENV_FILE}" ]]; then
    local env_game
    env_game="$(grep -E '^GAME_ID=' "${ENV_FILE}" | tail -1 | cut -d= -f2 | tr -d '[:space:]')"
    if [[ -n "${env_game}" ]]; then
      echo "${env_game}"
      return
    fi
  fi
  echo "ark-se"
}

compose_cmd() {
  local game_id="$1"
  shift
  GAME_ID="${game_id}" docker compose \
    -f "${COMPOSE_FILE}" \
    --env-file "${ENV_FILE}" \
    "$@"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_list() {
  echo "Available game modules:"
  for dir in "${PROJECT_ROOT}/games"/*/; do
    local slug
    slug="$(basename "${dir}")"
    if [[ -f "${dir}/game.env" ]]; then
      local name
      name="$(grep -E '^GAME_NAME=' "${dir}/game.env" | cut -d= -f2 | tr -d '"' || echo "${slug}")"
      printf '  %-24s %s\n' "${slug}" "${name}"
    fi
  done
}

cmd_install() {
  local game_id="$1"
  require_game_module "${game_id}"
  log "Installing/updating ${game_id}..."
  compose_cmd "${game_id}" run --rm "${game_id}-install"
}

cmd_start() {
  local game_id="$1"
  require_game_module "${game_id}"
  log "Starting ${game_id} server..."
  compose_cmd "${game_id}" up -d "${game_id}"
  log "Server started. Use './scripts/game-ctl.sh logs ${game_id}' to follow output."
}

cmd_stop() {
  local game_id="$1"
  require_game_module "${game_id}"
  log "Stopping ${game_id} server..."
  compose_cmd "${game_id}" stop "${game_id}"
}

cmd_restart() {
  local game_id="$1"
  cmd_stop "${game_id}"
  cmd_start "${game_id}"
}

cmd_status() {
  local game_id="$1"
  require_game_module "${game_id}"
  compose_cmd "${game_id}" ps "${game_id}"
}

cmd_logs() {
  local game_id="$1"
  require_game_module "${game_id}"
  compose_cmd "${game_id}" logs -f "${game_id}"
}

cmd_backup() {
  local game_id="$1"
  require_game_module "${game_id}"
  log "Creating backup for ${game_id}..."
  bash "${SCRIPT_DIR}/backup-game.sh" "${game_id}"
}

cmd_update() {
  local game_id="$1"
  require_game_module "${game_id}"
  log "Updating ${game_id}: stopping server, running installer, then restarting..."
  compose_cmd "${game_id}" stop "${game_id}" || true
  compose_cmd "${game_id}" run --rm "${game_id}-install"
  compose_cmd "${game_id}" up -d "${game_id}"
  log "Update complete."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

COMMAND="${1:-}"
shift || true

case "${COMMAND}" in
  list)
    cmd_list
    ;;
  install|start|stop|restart|status|logs|backup|update)
    GAME_ID="$(resolve_game_id "${1:-}")"
    "cmd_${COMMAND}" "${GAME_ID}"
    ;;
  ""|help|--help|-h)
    usage
    ;;
  *)
    die "Unknown command: '${COMMAND}'. Run without arguments for usage."
    ;;
esac
