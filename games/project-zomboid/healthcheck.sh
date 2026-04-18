#!/usr/bin/env bash
set -euo pipefail

# Project Zomboid health check: PID-only.
# PZ has no RCON, so process-alive is the only check available.

PID_FILE="/tmp/game.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  exit 1
fi

SERVER_PID="$(cat "${PID_FILE}")"

if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  exit 1
fi

exit 0
