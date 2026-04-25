# ── Stage 1: build FEX from source ────────────────────────────────────────────
FROM ubuntu:22.04 AS fex-builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake ninja-build pkg-config \
    clang lld llvm \
    libsdl2-dev libepoxy-dev libssl-dev \
    python3 python3-setuptools nasm python3-clang \
    g++-x86-64-linux-gnu \
    libstdc++-10-dev-i386-cross \
    libstdc++-10-dev-amd64-cross \
    libstdc++-10-dev-arm64-cross \
    squashfs-tools squashfuse \
    curl wget ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Full clone required — a08a6ce5 is not a tag so --depth 1 won't reach it.
# --filter=blob:none defers large blobs until needed, reducing initial transfer.
WORKDIR /build
# Clone, checkout the pinned commit, then re-init submodules at that commit
# (--filter=blob:none on the initial clone leaves submodules with no content
# until we explicitly re-init them at the checked-out ref).
RUN git clone --recurse-submodules https://github.com/FEX-Emu/FEX.git && \
    cd FEX && \
    git checkout a08a6ce5de51f5e625357ecaed46c463aa1e3c99 && \
    git submodule update --init --recursive

# Build + install. The strip is non-fatal (some FEX builds don't produce all
# expected binaries); the rest must succeed or the layer fails.
RUN cd /build/FEX && \
    mkdir Build && cd Build && \
    CC=clang CXX=clang++ cmake \
        -DCMAKE_INSTALL_PREFIX=/usr/local/fex \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LINKER=lld \
        -DENABLE_LTO=True \
        -DBUILD_TESTS=False \
        -DENABLE_ASSERTIONS=False \
        -G Ninja .. && \
    ninja -j$(nproc) && \
    ninja install && \
    (strip /usr/local/fex/bin/* 2>/dev/null || true)

# ── Stage 2: runtime ───────────────────────────────────────────────────────────
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 libgcc-s1 \
    libsdl2-2.0-0 libepoxy0 libssl3 libzstd1 \
    squashfs-tools squashfuse \
    curl ca-certificates \
    python3 \
    procps \
    binfmt-support \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Copy FEX binaries from builder stage.
COPY --from=fex-builder /usr/local/fex /usr/local/fex
ENV PATH="/usr/local/fex/bin:$PATH"

# Download Ubuntu 22.04 rootfs from the official FEX catalog at build time so
# the image is self-contained and requires no internet access at runtime.
# The catalog URL is stable; the sqsh URL is date-stamped but resolved here.
RUN mkdir -p /opt/fex-rootfs && \
    CATALOG_URL="https://raw.githubusercontent.com/FEX-Emu/RootFS/refs/heads/main/RootFS_links.json" && \
    ROOTFS_URL="$(curl -fsSL "${CATALOG_URL}" | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(d['v1']['Ubuntu 22.04 (SquashFS)']['URL'])")" && \
    curl -fSL --retry 3 -o /tmp/Ubuntu_22_04.sqsh "${ROOTFS_URL}" && \
    unsquashfs -f -d /opt/fex-rootfs/Ubuntu_22_04 /tmp/Ubuntu_22_04.sqsh && \
    rm /tmp/Ubuntu_22_04.sqsh && \
    chown -R root:root /opt/fex-rootfs && \
    chmod -R 755 /opt/fex-rootfs

# Write template Config.json so every user created from this image gets the
# correct rootfs path automatically (via /etc/skel).
RUN mkdir -p /etc/skel/.fex-emu && \
    echo '{"Config":{"RootFS":"/opt/fex-rootfs/Ubuntu_22_04"}}' \
        > /etc/skel/.fex-emu/Config.json

# steam user at UID 1001 matches the install container's chown expectations
# (install-game.sh chowns /mnt/server to SERVER_UID=1001 at end of install).
RUN useradd -m -u 1001 -s /bin/bash steam && \
    echo "steam ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/steam

USER steam
WORKDIR /home/steam
