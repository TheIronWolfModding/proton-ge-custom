#!/bin/bash
# Reclaim build disk space.
#
# Removes the entire build/ tree and the ccache. This is a FULL clean: the next
# ./build.sh will re-run configure and do a full first-run build (long, ~6-7 GB,
# ~20-40 min), then resume fast incremental wineopenxr rebuilds.
#
# Deliberately does NOT do a partial clean of build/ — wineopenxr depends on the
# whole wine dep graph (ffmpeg, kaldi, vosk, openfst, libpcap, ...), so deleting
# individual package dirs leaves make in a half-broken state that still triggers
# a full cascade rebuild. All-or-nothing is the only clean state.
#
# Keeps:
#   - root .protonprep-done stamp -> wine is NOT re-patched on next build
#   - your patched sources (wineopenxr/*.c) -> untouched, they live in the repo
#   - the installed wineopenxr.so in GE-Proton -> untouched, VR keeps working
#
# Does NOT touch the podman SDK image; use clean-sdk.sh for that.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD=$ROOT/build
CCACHE=${CCACHE_DIR:-$HOME/.ccache}

before=$(df -h "$ROOT" | awk 'NR==2 {print $4}')

if [ -d "$BUILD" ]; then
    echo "==> Removing $BUILD ..."
    du -sh "$BUILD" 2>/dev/null || true
    rm -rf "$BUILD"
else
    echo "==> $BUILD already gone."
fi

if [ -d "$CCACHE" ]; then
    echo "==> Removing ccache $CCACHE ..."
    du -sh "$CCACHE" 2>/dev/null || true
    rm -rf "$CCACHE"
fi

after=$(df -h "$ROOT" | awk 'NR==2 {print $4}')
echo "==> Done. Free space: $before -> $after"
echo "    Next ./build.sh will do a full first-run build (no wine re-patch)."
