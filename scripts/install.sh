#!/usr/bin/env bash
# DEPRECATED: Use install-game.sh with GAME_ID set in your environment.
# This shim will be removed in a future release.
echo "[DEPRECATED] install.sh is deprecated. Use install-game.sh instead." >&2
export GAME_ID="${GAME_ID:-ark-se}"
exec "$(dirname "$0")/install-game.sh" "$@"
