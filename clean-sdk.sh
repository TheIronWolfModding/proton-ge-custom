#!/bin/bash
# Remove the Proton SDK container image (~6.7 GB).
#
# The image is only needed at BUILD time (build.sh shells into it via
# `podman run --rm`). Removing it does NOT affect the installed wineopenxr.so
# or the running game. The next ./build.sh will auto re-pull it (6.7 GB
# download), so only run this if you are done building for a while.
#
# Also offers to prune dangling/unused images to reclaim more.

set -euo pipefail

SDK=registry.gitlab.steamos.cloud/proton/sniper/sdk:latest

if ! command -v podman >/dev/null 2>&1; then
    echo "!! podman not found."
    exit 1
fi

if podman image exists "$SDK" 2>/dev/null; then
    echo "==> Removing SDK image $SDK ..."
    podman rmi "$SDK"
else
    echo "==> SDK image $SDK not present."
fi

echo
echo "==> Remaining images:"
podman images

echo
read -r -p "Also prune ALL dangling/unused images? [y/N] " ans
case "$ans" in
    [yY]|[yY][eE][sS])
        podman image prune -af
        echo "==> Pruned."
        ;;
    *)
        echo "==> Skipped prune."
        ;;
esac

echo "==> Storage summary:"
podman system df
