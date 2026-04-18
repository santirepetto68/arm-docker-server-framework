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
  export HOME="/mnt/server"

  # PZ silently crashes later if these are missing — watch service expects them.
  mkdir -p /mnt/server/.cache/mods /mnt/server/.cache/Workshop

  # box64 tuning for the JVM. These make the difference between "crashes in
  # the JIT" and "runs". Documented in box64's README under JVM workloads.
  export BOX64_JVM=1
  export BOX64_DYNAREC_BIGBLOCK=0
  export BOX64_DYNAREC_STRONGMEM=1

  # Force box64 to emulate PZ's bundled x86 SDL/libs rather than trying to
  # substitute ARM-native versions we don't have (libSDL3.so.0 in particular —
  # the substitution attempt fails dlopen and the JVM then SIGSEGVs in JNI).
  export BOX64_EMULATED_LIBS="libSDL3.so.0:libSDL3.so:libSDL2-2.0.so.0:libSDL2.so"
  export BOX64_NOGTK=1
  export BOX64_NOPULSE=1
  export BOX64_NOSANDBOX=1

  # JRE + native libs shipped with PZ. Note: deliberately do NOT LD_PRELOAD
  # libjsig.so — with our JVM flag set it isn't needed, and preloading it
  # under box64 occasionally trips the dynarec.
  export LD_LIBRARY_PATH="/mnt/server/linux64:/mnt/server/natives:/mnt/server/jre64/lib:/mnt/server/jre64/lib/server:/mnt/server${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

  # We invoke java directly (GAME_BINARY=jre64/bin/java), so STARTUP_CMD stays
  # empty and all JVM + PZ args go through STARTUP_FLAGS.
  STARTUP_CMD=""

  STARTUP_FLAGS=(
    # --- JVM flags tuned for box64 ---
    "-Djava.awt.headless=true"
    "-Xms${JVM_XMS}"
    "-Xmx${JVM_XMX}"
    "-XX:ActiveProcessorCount=4"
    "-Dzomboid.steam=1"
    "-Dzomboid.znetlog=1"
    "-Djava.library.path=linux64/:natives/"
    "-Djava.security.egd=file:/dev/urandom"
    # SerialGC is the simplest collector and the one that actually survives
    # box64's dynarec. G1GC and ZGC both crash mid-game under emulation.
    "-XX:+UseSerialGC"
    # Compressed pointer tricks don't translate cleanly — disable them.
    "-XX:-UseCompressedOops"
    # Tier 1 = C1 compiler only. C2's aggressive inlining + method handle
    # machinery is what box64 kept mistranslating.
    "-XX:TieredStopAtLevel=1"
    # Classpath must include every jar under java/ — PZ ships Guava, Steamworks4J,
    # TRove4j, etc. as separate jars. The `*` wildcard expands at JVM launch.
    "-cp" "java/:java/*"
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
