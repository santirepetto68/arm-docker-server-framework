#!/usr/bin/env bash
set -euo pipefail

# ARK health check: process alive is sufficient, RCON is a bonus.
# Under emulation RCON can be delayed — don't mark unhealthy just because
# RCON hasn't started yet.

PID_FILE="/tmp/game.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  exit 1
fi

SERVER_PID="$(cat "${PID_FILE}")"

if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  exit 1
fi

# Process is alive — healthy enough.
# Optionally probe RCON for deeper readiness.
if command -v rcon >/dev/null 2>&1 && [[ -n "${RCON_PORT:-}" ]] && [[ -n "${ARK_ADMIN_PASSWORD:-}" ]]; then
  if timeout 5 rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" listplayers >/dev/null 2>&1; then
    exit 0
  fi
fi

exit 0
