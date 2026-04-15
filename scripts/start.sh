#!/usr/bin/env bash
# DEPRECATED: Use start-game.sh with GAME_ID set in your environment.
# This shim will be removed in a future release.
echo "[DEPRECATED] start.sh is deprecated. Use start-game.sh instead." >&2
export GAME_ID="${GAME_ID:-ark-se}"
exec "$(dirname "$0")/start-game.sh" "$@"
