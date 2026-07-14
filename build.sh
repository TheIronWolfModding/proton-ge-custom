#!/bin/bash
# Incremental 32-bit wineopenxr rebuild + auto-install to GE-Proton.
#
# First run: patches wine (~5-10 min), configures, full 32-bit tree build (long).
# Subsequent runs: only recompiles changed .c files in wineopenxr and relinks.
#
# Only 32-bit is targeted (per user request).

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD=$ROOT/build
SDK=registry.gitlab.steamos.cloud/proton/sniper/sdk:latest
DEST_SO=/home/vl/Games/CompatLayers/GE-Proton/files/lib/wine/i386-unix/wineopenxr.so

mkdir -p "$BUILD"

STAMP=$ROOT/.protonprep-done
if [ ! -f "$STAMP" ]; then
    echo "==> Applying protonprep patches (heavy, first-run only)..."
    "$ROOT/patches/protonprep-valve-staging.sh"
    touch "$STAMP"
fi

if [ ! -f "$BUILD/Makefile" ]; then
    echo "==> Configuring (first run only)..."
    cd "$BUILD"
    "$ROOT/configure.sh" \
        --build-name=woxr-dbg \
        --proton-sdk-image="$SDK" \
        --container-engine=podman
fi

# Force rebuild of both winevulkan (i386) and wineopenxr (i386): drop build stamps
rm -f "$BUILD/.wineopenxr-i386-build" \
      "$BUILD/.wineopenxr-i386-post-build" \
      "$BUILD/.wineopenxr-i386-dist"

echo "==> Building wineopenxr (i386)..."
cd "$BUILD"
make -j"$(nproc)" wineopenxr-i386

# Install 32-bit wineopenxr .so ONLY. Do NOT overwrite shipped winevulkan
# (v36 ABI mismatch with shipped win32u v47 breaks DXVK for both xrizer and
# wineopenxr paths). Wineopenxr now falls back to inline unwrap when
# __wine_get_native_Vk* are absent, so shipped winevulkan works.
GEP=/home/vl/Games/CompatLayers/GE-Proton/files
declare -A INSTALL_MAP=(
    [$BUILD/dst-wineopenxr-i386/lib/wine/i386-unix/wineopenxr.so]=$GEP/lib/wine/i386-unix/wineopenxr.so
)
for src in "${!INSTALL_MAP[@]}"; do
    dst=${INSTALL_MAP[$src]}
    if [ ! -f "$src" ]; then
        echo "!! not built: $src"
        continue
    fi
    chmod u+w "$dst" 2>/dev/null || true
    cp -v "$src" "$dst"
done
