#!/bin/bash
# Incremental 32-bit wineopenxr rebuild + auto-install to GE-Proton.
#
# First run: patches wine (~5-10 min), configures, full 32-bit tree build (long).
# Subsequent runs: only recompiles changed .c files in wineopenxr and relinks.
#
# Only 32-bit is targeted (per user request).
#
# Usage: ./build.sh [-c]
#   -c   Clean: wipe the build/ tree and rebuild everything from scratch.
#        (Needed if the repo was moved: meson subproject ninja caches bake in
#        the old absolute path and cannot be reconfigured in place.)

set -euo pipefail

CLEAN=0
while getopts ":c" opt; do
    case "$opt" in
        c) CLEAN=1 ;;
        *) echo "Usage: $0 [-c]" >&2; exit 2 ;;
    esac
done

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD=$ROOT/build
SDK=registry.gitlab.steamos.cloud/proton/sniper/sdk:latest

# The build tree bakes the SRCDIR absolute path (set by configure.sh) into
# build/Makefile AND into every meson subproject's build.ninja. If the repo has
# since been moved, those paths break ("Makefile.in: No such file or directory",
# meson "Neither directory contains a build file"). Reconfiguring the top
# Makefile is NOT enough - the meson caches must be regenerated - so a stale
# path forces a full clean rebuild.
if [ -f "$BUILD/Makefile" ]; then
    BAKED_SRCDIR=$(sed -n 's/^SRCDIR[[:space:]]*:=[[:space:]]*//p' "$BUILD/Makefile" | head -n1)
    if [ -n "$BAKED_SRCDIR" ] && [ "$(readlink -f "$BAKED_SRCDIR" 2>/dev/null)" != "$ROOT" ]; then
        echo "==> Build tree was configured for '$BAKED_SRCDIR' but repo is now '$ROOT'."
        echo "==> Forcing a clean rebuild (meson subproject caches can't be relocated)."
        CLEAN=1
    fi
fi

if [ "$CLEAN" = 1 ]; then
    echo "==> Clean: removing '$BUILD'"
    rm -rf "$BUILD"
fi

mkdir -p "$BUILD"

STAMP=$ROOT/.protonprep-done
if [ ! -f "$STAMP" ]; then
    echo "==> Applying protonprep patches (heavy, first-run only)..."
    "$ROOT/patches/protonprep-valve-staging.sh"
    touch "$STAMP"
fi

if [ ! -f "$BUILD/Makefile" ]; then
    echo "==> Configuring..."
    cd "$BUILD"
    "$ROOT/configure.sh" \
        --build-name=woxr-dbg \
        --proton-sdk-image="$SDK" \
        --container-engine=podman
fi

# Rebuild wineopenxr (i386). Source edits are auto-detected via rsync source
# tracking, so make only recompiles when wineopenxr/*.c actually changed.
#
# The x86_64 wine build is a prerequisite that the narrow wineopenxr-i386 target
# does NOT pull on its own: it only builds wine's x86_64 *tools* plus wine-i386.
# But wine-i386's resource compiler (wrc) needs obj-wine-x86_64/nls/locale.nls,
# which is generated only by the full x86_64 wine build. Without it a clean
# build dies with "wrc: unable to load locale.nls". Build it first (cheap no-op
# once built) so a from-clean build works, matching a full/redist build.
echo "==> Ensuring x86_64 wine is built (generates locale.nls for i386 wrc)..."
cd "$BUILD"
make -j"$(nproc)" wine-x86_64-build

echo "==> Building wineopenxr (i386)..."
make -j"$(nproc)" wineopenxr-i386

# Install the freshly-built 32-bit wineopenxr. The Unix-side .so is where the
# actual logic (incl. the layer-conversion thunk) lives, so it is the file that
# carries source patches; the PE-side .dll is the thin stub the game loads.
#
# Do NOT overwrite shipped winevulkan (v36 ABI mismatch with shipped win32u v47
# breaks DXVK for both xrizer and wineopenxr paths). Wineopenxr falls back to
# inline unwrap when __wine_get_native_Vk* are absent, so shipped winevulkan works.
#
# Deploy targets:
#   .so  -> GE-Proton host tree (i386-unix). Host-global: every prefix that
#           loads wineopenxr picks it up at runtime.
#   .dll -> GE-Proton host tree (i386-windows) AND the .wine-gtr2 prefix
#           (syswow64) so the prefix's PE stub stays in ABI-sync with the .so.
#   (64-bit intentionally not handled - 32-bit game only, per user.)
GEP=/home/vl/Games/CompatLayers/GE-Proton/files
PREFIX=/home/vl/Games/CompatLayers/prefixes/.wine-gtr2
SO_SRC=$BUILD/dst-wineopenxr-i386/lib/wine/i386-unix/wineopenxr.so
DLL_SRC=$BUILD/dst-wineopenxr-i386/lib/wine/i386-windows/wineopenxr.dll
declare -A INSTALL_MAP=(
    [$SO_SRC]=$GEP/lib/wine/i386-unix/wineopenxr.so
    [$DLL_SRC]=$GEP/lib/wine/i386-windows/wineopenxr.dll
    [$DLL_SRC.pfx]=$PREFIX/drive_c/windows/syswow64/wineopenxr.dll
)
for src in "${!INSTALL_MAP[@]}"; do
    real_src=${src%.pfx}   # .pfx suffix lets one built dll map to two dsts
    dst=${INSTALL_MAP[$src]}
    if [ ! -f "$real_src" ]; then
        echo "!! not built: $real_src"
        continue
    fi
    if [ ! -e "$dst" ]; then
        echo "!! target missing, skipping (won't create new files): $dst"
        continue
    fi
    chmod u+w "$dst" 2>/dev/null || true
    cp -v "$real_src" "$dst"
done
