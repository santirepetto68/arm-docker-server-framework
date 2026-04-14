#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${PROJECT_ROOT}/backups"
SAVE_DIR="${PROJECT_ROOT}/data/server/ShooterGame/Saved"

mkdir -p "${BACKUP_DIR}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

if command -v docker >/dev/null 2>&1; then
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" exec -T ark \
    rcon -a 127.0.0.1:"${RCON_PORT:-27020}" -p "${ARK_ADMIN_PASSWORD:?ARK_ADMIN_PASSWORD missing in .env}" -c saveworld || true
  sleep 5
fi

if [[ ! -d "${SAVE_DIR}" ]]; then
  echo "Save directory not found: ${SAVE_DIR}" >&2
  exit 1
fi

tar -czf "${BACKUP_DIR}/ark-saved-${TIMESTAMP}.tar.gz" -C "${PROJECT_ROOT}/data/server" ShooterGame/Saved

echo "Backup created: ${BACKUP_DIR}/ark-saved-${TIMESTAMP}.tar.gz"
