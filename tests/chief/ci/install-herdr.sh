#!/usr/bin/env bash
# install-herdr.sh - installs the pinned herdr into tests/.cache/bin, which the
# suite puts first on PATH. Used by CI and locally to match CI's herdr.
set -euo pipefail

HERDR_VERSION=v0.9.3
HERDR_SHA256_X86_64=18a8dc65f1c2fa485884344356dea1cfd911c6f06cf46fa78e193f4087f4dba7

[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || { echo "install-herdr: only linux x86_64 is pinned" >&2; exit 1; }
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.cache/bin"
mkdir -p "$DEST"
tmp=$(mktemp "$DEST/herdr.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "https://github.com/herdrdev/herdr/releases/download/$HERDR_VERSION/herdr-linux-x86_64"
echo "$HERDR_SHA256_X86_64  $tmp" | sha256sum -c --quiet
chmod +x "$tmp"
mv "$tmp" "$DEST/herdr"
"$DEST/herdr" --version
