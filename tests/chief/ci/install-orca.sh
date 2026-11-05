#!/usr/bin/env bash
# install-orca.sh - installs the pinned Orca into tests/.cache/orca (extracted
# AppImage; its CLI is tests/.cache/orca/squashfs-root/AppRun, which the suite
# exposes as `orca-ide`). Used by CI and locally to match CI's Orca.
set -euo pipefail

ORCA_VERSION=v1.4.200
ORCA_SHA256=c82d9ddf532431e0da51ec5d1899a0e315aabb8e77fce45ecce7fad4733fc96a

DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.cache/orca"
rm -rf "$DEST"; mkdir -p "$DEST"
cd "$DEST"
curl -fsSL -o orca-linux.AppImage "https://github.com/stablyai/orca/releases/download/$ORCA_VERSION/orca-linux.AppImage"
echo "$ORCA_SHA256  orca-linux.AppImage" | sha256sum -c --quiet
chmod +x orca-linux.AppImage
./orca-linux.AppImage --appimage-extract >/dev/null
rm orca-linux.AppImage
echo "orca $ORCA_VERSION installed in $DEST/squashfs-root"
