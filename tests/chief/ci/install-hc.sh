#!/usr/bin/env bash
# install-hc.sh - installs the pinned herdr-core into tests/.cache/bin as
# `herdr-core` and `hc`, which the suite puts first on PATH. Used by CI and
# locally to match CI's hc.
set -euo pipefail

HC_VERSION=0.1.20
HC_SHA256_X86_64=ac6b86890c451a37584620aaa438b71bc0d0bd430a2e7c1d7e095f052c414e74

[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || { echo "install-hc: only linux x86_64 is pinned" >&2; exit 1; }
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.cache/bin"
mkdir -p "$DEST"
tmp=$(mktemp -d "$DEST/hc.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/hc.tar.gz" "https://releases.herdr.dev/core/$HC_VERSION/herdr-core-linux-x86_64.tar.gz"
echo "$HC_SHA256_X86_64  $tmp/hc.tar.gz" | sha256sum -c --quiet
tar -xzf "$tmp/hc.tar.gz" -C "$tmp" herdr-core
mv "$tmp/herdr-core" "$DEST/herdr-core"
ln -sf herdr-core "$DEST/hc"
"$DEST/hc" --version
