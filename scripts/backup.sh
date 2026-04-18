#!/usr/bin/env bash
# DEPRECATED: Use backup-game.sh with a game ID argument.
# This shim will be removed in a future release.
echo "[DEPRECATED] backup.sh is deprecated. Use backup-game.sh instead." >&2
exec "$(dirname "$0")/backup-game.sh" "${1:-ark-se}"
