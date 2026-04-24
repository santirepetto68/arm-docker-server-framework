#!/usr/bin/env bash
# Build the custom FEX-Emu PZ runtime image on the Oracle host.
# Run from the repo root: ./docker/pz-fex/build.sh
# Build takes ~20-40 min on a 4-core Neoverse-N1. Use a tmux session.
set -euo pipefail
cd "$(dirname "$0")/../.."
docker build \
    --platform linux/arm64 \
    -t pz-fex-arm64:a08a6ce \
    -t pz-fex-arm64:latest \
    -f docker/pz-fex/Dockerfile \
    docker/pz-fex
echo "Built pz-fex-arm64:latest (FEX commit a08a6ce5)"
