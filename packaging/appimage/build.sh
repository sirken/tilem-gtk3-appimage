#!/usr/bin/env bash
# Build a portable TilEm AppImage inside a pinned Ubuntu 20.04 container, so
# the result runs on far more (older-glibc) systems than a native build here
# would (glibc is backward- but not forward-compatible).
#
# Requires Podman (rootless: no sudo needed for this script itself, only for
# the one-time `pacman -S podman` install). See README.md for the full
# install / build / uninstall lifecycle.
set -euo pipefail

PKGDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$PKGDIR" rev-parse --show-toplevel)"

mkdir -p "$PKGDIR/out" "$PKGDIR/.cache/tarballs" "$PKGDIR/.cache/tools"

VERSION="2.1-git$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
  VERSION="${VERSION}-dirty"
fi

podman build -t tilem2-appimage-builder "$PKGDIR"

podman run --rm \
  -e VERSION="$VERSION" \
  -v "$REPO_ROOT":/src:ro \
  -v "$PKGDIR/out":/out \
  -v "$PKGDIR/.cache":/cache \
  tilem2-appimage-builder

echo "Done: $PKGDIR/out/TilEm-${VERSION}-x86_64.AppImage"
