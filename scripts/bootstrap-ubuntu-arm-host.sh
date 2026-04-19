#!/usr/bin/env bash
set -euo pipefail

# Derived from QuintenQVD0/Q_eggs steamgames.sh.
# Purpose: install box86/box64 and register binfmt on an Ubuntu ARM64 host,
# which the original egg family expects for SteamCMD-based x86/x64 game servers.

LOG_FILE="$(pwd)/install_log.txt"
exec &> >(tee -a "$LOG_FILE")

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this script as root"
  exit 1
fi

if ! ping -c 1 google.com &>/dev/null; then
  echo "Error: No internet connectivity. Please connect to the internet and try again."
  exit 1
fi

ARCH="$(uname -m)"
if [[ "$ARCH" != "aarch64" ]]; then
  echo "Error: This script is intended for ARM64 architecture only."
  exit 1
fi

detect_box_cmake_flags() {
  local model=""
  if [[ -f /proc/device-tree/model ]]; then
    model="$(tr -d '\0' < /proc/device-tree/model)"
  fi
  case "$model" in
    *"Raspberry Pi 5"*) echo "-DRPI5ARM64=1" ;;
    *"Raspberry Pi 4"*) echo "-DRPI4ARM64=1" ;;
    *"Raspberry Pi 3"*) echo "-DRPI3ARM64=1" ;;
    *)                  echo "-DARM64=1" ;;
  esac
}

BOX_CMAKE_FLAGS="$(detect_box_cmake_flags)"
echo "Detected cmake flags: ${BOX_CMAKE_FLAGS}"

TEMP_DIR="$(pwd)/temp"
echo "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

NUM_JOBS="$(nproc || echo 2)"

echo "Checking and installing required dependencies"
dpkg --add-architecture armhf
apt update
apt install -y git curl cmake gcc-arm-linux-gnueabihf sudo libc6:armhf

echo "Cloning and building box86"
git clone https://github.com/ptitSeb/box86
cd box86
mkdir build && cd build
cmake .. ${BOX_CMAKE_FLAGS} -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j"$NUM_JOBS"
sudo make install
sudo systemctl restart systemd-binfmt
box86 --version || true

cd "$TEMP_DIR"
rm -rf box86

echo "Cloning and building box64"
# Pin to the v0.4.0 tag (Jan 2025) instead of master. Master HEAD was observed
# to miscompile JIT'd Java (Zulu 17) under BOX64_JVM=1 even with BIGBLOCK=0 /
# STRONGMEM=1 — every crash landed at the same translated block address
# (0x30060013) across unrelated methods. v0.4.0 is the most recent stable
# release with BOX64_JVM heuristics. Override with BOX64_GIT_REF if needed.
BOX64_GIT_REF="${BOX64_GIT_REF:-v0.4.0}"
git clone https://github.com/ptitSeb/box64
cd box64
git checkout "${BOX64_GIT_REF}"
mkdir build && cd build
cmake .. ${BOX_CMAKE_FLAGS} -DCMAKE_BUILD_TYPE=RelWithDebInfo
make -j"$NUM_JOBS"
sudo make install
sudo systemctl restart systemd-binfmt
box64 --version || true

cd "$TEMP_DIR"
rm -rf box64
cd ..
rm -rf "$TEMP_DIR"

echo "Installation completed successfully at $(date)"
