#!/usr/bin/env bash
set -euo pipefail

# Layered health check: process alive is sufficient, RCON is a bonus.
# This avoids marking the container unhealthy when RCON is slow under emulation.

PID_FILE="/tmp/game.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  exit 1
fi

SERVER_PID="$(cat "${PID_FILE}")"

if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  exit 1
fi

# Process is alive — that's healthy enough.
# Optionally probe RCON for deeper readiness (non-blocking).
if command -v rcon >/dev/null 2>&1 && [[ -n "${RCON_PORT:-}" ]] && [[ -n "${ARK_ADMIN_PASSWORD:-}" ]]; then
  if timeout 5 rcon -a 127.0.0.1:"${RCON_PORT}" -p "${ARK_ADMIN_PASSWORD}" listplayers >/dev/null 2>&1; then
    exit 0
  fi
fi

# Process alive is sufficient for healthy status
exit 0
