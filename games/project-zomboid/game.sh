#!/usr/bin/env bash
# Project Zomboid — game-specific startup and shutdown logic.
# Sourced by scripts/start-game.sh. Must define:
#   build_startup_command()  — sets STARTUP_CMD (string) and STARTUP_FLAGS (array)
#   shutdown_server()        — graceful shutdown using SERVER_PID global
#
# Launch strategy: call `java` directly under box64 instead of the
# ProjectZomboid64 shell launcher. The launcher applies JVM flags from
# ProjectZomboid64.json (ZGC, compressed oops, bigblock-friendly code paths)
# that make the JVM crash under box64's x86→ARM dynarec. The flag set below
# is what the community found to actually run PZ reliably on ARM64 —
# credit: github.com/Dyarven/zomboid-server-on-arm.

# Defaults for Project Zomboid variables
SERVER_PORT="${SERVER_PORT:-16261}"
STEAM_PORT="${STEAM_PORT:-16262}"
SERVER_NAME="${SERVER_NAME:-servertest}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-CHANGE_ME}"
MAX_PLAYERS="${MAX_PLAYERS:-${GAME_DEFAULT_MAX_PLAYERS:-10}}"
ADDITIONAL_ARGS="${ADDITIONAL_ARGS:-}"
MODS="${MODS:-}"
MOD_WORKSHOP_IDS="${MOD_WORKSHOP_IDS:-}"

# JVM heap — PZ recommends at least 4G. Tunable per instance.
JVM_XMS="${JVM_XMS:-4g}"
JVM_XMX="${JVM_XMX:-8g}"

build_startup_command() {
  # Match the working arm64 script's env as closely as possible. Credit:
  # github.com/Dyarven/zomboid-server-on-arm.
  #
  # Notable differences from the working setup that we deliberately keep:
  #  - cachedir stays at /mnt/server/.cache so config/saves live on the
  #    bind-mounted volume instead of a container-local $HOME.
  #  - We still export HOME so PZ's internal "where do I put Zomboid/"
  #    logic has something to anchor to.
  export HOME="/mnt/server"

  # Pre-create Workshop/mod staging dirs — PZ enumerates them on startup
  # and closedir() on a missing dir crashes under box64.
  mkdir -p /mnt/server/.cache/mods \
           /mnt/server/.cache/Workshop \
           /mnt/server/steamapps/workshop/content/108600

  # box64 env that matches the Dyarven systemd unit verbatim. Don't add
  # BOX64_DYNAREC_SAFEFLAGS / BOX64_ALLOWMISSINGLIBS / BOX64_EMULATED_LIBS
  # here — the working script doesn't use them and adding them has been
  # making things worse, not better.
  export BOX64_JVM=1
  export BOX64_DYNAREC_BIGBLOCK=0
  export BOX64_DYNAREC_STRONGMEM=1

  # LD_LIBRARY_PATH — mirror the working script exactly. The trailing `.`
  # (CWD) matters: PZ's native loader looks for some libs relative to CWD.
  export LD_LIBRARY_PATH="/mnt/server/linux64:/mnt/server/natives:/mnt/server/jre64/lib:."

  # We invoke java directly (GAME_BINARY=jre64/bin/java), so STARTUP_CMD stays
  # empty and all JVM + PZ args go through STARTUP_FLAGS.
  STARTUP_CMD=""

  STARTUP_FLAGS=(
    # --- JVM flags tuned for box64 (matches Dyarven's working config) ---
    "-Djava.awt.headless=true"
    "-Xms${JVM_XMS}"
    "-Xmx${JVM_XMX}"
    "-XX:ActiveProcessorCount=4"
    "-Dzomboid.steam=1"
    "-Dzomboid.znetlog=1"
    "-Djava.library.path=linux64/:natives/"
    "-Djava.security.egd=file:/dev/urandom"
    "-XX:+UseSerialGC"
    "-XX:-UseCompressedOops"
    # Also disable compressed class pointers. A SIGSEGV inside C1-compiled
    # String.getBytes pointed at UseCompressedClassPointers in the dynarec'd
    # code — box64 mistranslates the class-pointer compression check.
    "-XX:-UseCompressedClassPointers"
    "-XX:TieredStopAtLevel=1"
    # Classpath: include all jars in java/ (Guava, Steamworks4J, trove, etc.)
    # plus projectzomboid.jar. Dyarven's script uses just `java/:java/projectzomboid.jar`
    # but that relies on their java/ dir being flat-extracted; our SteamCMD install
    # keeps dependencies as separate jars, so we need the `java/*` glob.
    "-cp" "java/:java/*:java/projectzomboid.jar"
    "zombie.network.GameServer"
    # --- PZ server args below this line ---
    "-port" "${SERVER_PORT}"
    "-udpport" "${STEAM_PORT}"
    "-cachedir=/mnt/server/.cache"
    "-servername" "${SERVER_NAME}"
    "-adminusername" "${ADMIN_USER}"
    "-adminpassword" "${ADMIN_PASSWORD}"
  )

  # Disable Steam (no VAC, no Workshop). Only set NO_STEAM=1 for LAN-only servers.
  if is_true "${NO_STEAM:-0}"; then
    STARTUP_FLAGS+=("-nosteam")
  fi

  if is_true "${MODS_ENABLED:-0}" && [[ -n "${MODS}" ]]; then
    STARTUP_FLAGS+=("-mods" "${MODS}")
  fi

  if is_true "${MODS_ENABLED:-0}" && [[ -n "${MOD_WORKSHOP_IDS}" ]]; then
    STARTUP_FLAGS+=("-workshopids" "${MOD_WORKSHOP_IDS}")
  fi

  if [[ -n "${ADDITIONAL_ARGS}" ]]; then
    IFS=' ' read -ra extra_args <<< "${ADDITIONAL_ARGS}"
    STARTUP_FLAGS+=("${extra_args[@]}")
  fi
}

shutdown_server() {
  log "Received stop signal. Attempting graceful ${GAME_NAME} shutdown."

  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    # PZ has no RCON. SIGTERM is the correct graceful stop — PZ handles it.
    log "Sending SIGTERM to PID ${SERVER_PID}..."
    kill -TERM "${SERVER_PID}" >/dev/null 2>&1 || true

    for _ in $(seq 1 "${GAME_SHUTDOWN_GRACE_SECONDS:-30}"); do
      if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
        log "${GAME_NAME} server stopped cleanly."
        break
      fi
      sleep 1
    done

    if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      log "Server did not stop in time. Forcing SIGKILL."
      kill -KILL "${SERVER_PID}" >/dev/null 2>&1 || true
    fi

    wait "${SERVER_PID}" || true
  fi
}
