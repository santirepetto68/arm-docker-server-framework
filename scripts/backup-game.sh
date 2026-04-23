#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

# Resolve game ID from argument, env, or default
GAME_ID="${1:-${GAME_ID:-ark-se}}"

GAME_ENV="${PROJECT_ROOT}/games/${GAME_ID}/game.env"
if [[ ! -f "${GAME_ENV}" ]]; then
  echo "Game module not found: ${GAME_ENV}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${GAME_ENV}"

# Load shared infra vars
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

# Load game-specific instance vars (overrides .env where keys overlap)
INSTANCE_ENV="${PROJECT_ROOT}/instances/${GAME_ID}.env"
if [[ -f "${INSTANCE_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${INSTANCE_ENV}"
fi

BACKUP_DIR="${PROJECT_ROOT}/backups/${GAME_ID}"
DATA_DIR="${PROJECT_ROOT}/data/${GAME_ID}"
SAVE_DIR="${DATA_DIR}/${GAME_SAVE_DIR}"

mkdir -p "${BACKUP_DIR}"

# Pre-backup save via RCON if the game supports it
if [[ "${GAME_SHUTDOWN_STRATEGY:-}" == "rcon-then-signal" ]]; then
  rcon_port_var="${GAME_RCON_PORT_VAR:-RCON_PORT}"
  rcon_pass_var="${GAME_RCON_PASSWORD_VAR:-RCON_PASSWORD}"
  rcon_port="${!rcon_port_var:-27020}"
  rcon_pass="${!rcon_pass_var:-}"

  if [[ -n "${rcon_pass}" ]] && command -v docker >/dev/null 2>&1; then
    COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
    INSTANCE_ENV_FILE="${PROJECT_ROOT}/instances/${GAME_ID}.env"
    EXTRA_ENV_ARG=()
    if [[ -f "${INSTANCE_ENV_FILE}" ]]; then
      EXTRA_ENV_ARG=(--env-file "${INSTANCE_ENV_FILE}")
    fi
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "${EXTRA_ENV_ARG[@]}" \
      exec -T "${GAME_ID}" \
      timeout 5 rcon -a 127.0.0.1:"${rcon_port}" -p "${rcon_pass}" saveworld || true
    sleep 5
  fi
fi

if [[ ! -d "${SAVE_DIR}" ]]; then
  echo "Save directory not found: ${SAVE_DIR}" >&2
  exit 1
fi

tar -czf "${BACKUP_DIR}/${GAME_ID}-${TIMESTAMP}.tar.gz" -C "${DATA_DIR}" "${GAME_SAVE_DIR}"

echo "Backup created: ${BACKUP_DIR}/${GAME_ID}-${TIMESTAMP}.tar.gz"

# Retention: remove old backups if BACKUP_KEEP_LAST is set
BACKUP_KEEP_LAST="${BACKUP_KEEP_LAST:-0}"
if [[ "${BACKUP_KEEP_LAST}" -gt 0 ]]; then
  mapfile -t all_backups < <(ls -1t "${BACKUP_DIR}"/${GAME_ID}-*.tar.gz 2>/dev/null)
  if [[ ${#all_backups[@]} -gt ${BACKUP_KEEP_LAST} ]]; then
    for old in "${all_backups[@]:${BACKUP_KEEP_LAST}}"; do
      rm -f "$old"
      echo "Removed old backup: $old"
    done
  fi
fi
