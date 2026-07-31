#!/usr/bin/env bash
set -euo pipefail

SRC=/src
OUT=/out
CACHE=/cache
WORK=/work
CHECKSUMS=/tools.sha256sums

# tilibs (TiLP project): AUR-only, must be built from source. Versions/URLs
# match exactly what's already installed and proven to work against this
# tilem-gtk3 tree via the AUR libticalcs/libticables/libtifiles/libticonv
# packages (confirmed against their cached PKGBUILD and the upstream
# SourceForge release listing). Order matters: each depends on the ones
# before it.
TILIBS_BASE_URL="https://downloads.sourceforge.net/project/tilp/tilp2-linux/tilp2-1.18"
TILIBS="libticonv-1.1.5 libtifiles2-1.1.7 libticables2-1.3.5 libticalcs2-1.1.9"

LINUXDEPLOY_TAG="1-alpha-20251107-1"
LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/${LINUXDEPLOY_TAG}/linuxdeploy-x86_64.AppImage"

APPIMAGETOOL_TAG="1.9.1"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/${APPIMAGETOOL_TAG}/appimagetool-x86_64.AppImage"

GTKPLUGIN_COMMIT="7a3fbc31a9e5075073ff8790f26effbac5f84453"
GTKPLUGIN_URL="https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/${GTKPLUGIN_COMMIT}/linuxdeploy-plugin-gtk.sh"

log() { echo "==> $*" >&2; }

fetch_cached() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    log "using cached $(basename "$dest")"
  else
    log "fetching $(basename "$dest")"
    # SourceForge's download redirector sometimes hands out a dead mirror;
    # --retry-connrefused makes curl retry (getting a fresh mirror pick each
    # time) instead of giving up on the first refused connection.
    curl -fL --retry 6 --retry-delay 3 --retry-connrefused -o "$dest.tmp" "$url"
    mv "$dest.tmp" "$dest"
  fi
}

verify_checksum() {
  local file="$1" name
  name="$(basename "$file")"
  ( cd "$(dirname "$file")" && grep -F " $name" "$CHECKSUMS" | sha256sum -c - )
}

mkdir -p "$WORK" "$CACHE/tarballs" "$CACHE/tools" "$OUT"

# 1. Build the tilibs stack, in dependency order.
for nameversion in $TILIBS; do
  tarball="${nameversion}.tar.bz2"
  cached="$CACHE/tarballs/$tarball"
  fetch_cached "$TILIBS_BASE_URL/$tarball" "$cached"
  rm -rf "${WORK:?}/$nameversion"
  tar xjf "$cached" -C "$WORK"
  log "building $nameversion"
  extra_configure_flags=""
  case "$nameversion" in
    libticonv-*)
      # libticonv's own bundled torture test unconditionally calls
      # ticonv_iconv_open/ticonv_iconv/ticonv_iconv_close, but iconv.c
      # (where those live) is only compiled in with --enable-iconv --
      # without it, the default build fails to link its own test suite.
      # No extra libs needed on Linux: iconv() comes from glibc.
      extra_configure_flags="--enable-iconv"
      ;;
    libticables2-*)
      # Defaults to the legacy libusb 0.1.x API, whose pkg-config module
      # ("libusb") isn't installed here. --enable-libusb10 switches it to
      # the modern libusb-1.0 API we do have (libusb-1.0-0-dev).
      extra_configure_flags="--enable-libusb10"
      ;;
  esac
  (
    cd "$WORK/$nameversion"
    autoreconf -fi
    ./configure --prefix=/usr $extra_configure_flags
    make -j"$(nproc)"
    make install
  )
  ldconfig
done

# 2. Build tilem2 from the read-only bind-mounted source tree.
log "copying source tree"
rm -rf "$WORK/tilem-gtk3"
rsync -a --exclude='.git' "$SRC"/ "$WORK/tilem-gtk3"/
cd "$WORK/tilem-gtk3"
./configure --prefix=/usr --with-sdl=no
make -j"$(nproc)"

# 3. Stage into an AppDir. Prefix stays /usr at configure AND install time
# (only DESTDIR changes) because SHARE_DIR is baked into the binary at
# compile time as $prefix/share/tilem2 -- overriding prefix= at install
# time only (as the AUR PKGBUILD does) would silently break that.
APPDIR="$WORK/AppDir"
rm -rf "$APPDIR"
make install DESTDIR="$APPDIR"

# 4. Fetch + checksum-verify the AppImage tooling.
fetch_cached "$LINUXDEPLOY_URL" "$CACHE/tools/linuxdeploy-x86_64.AppImage"
fetch_cached "$APPIMAGETOOL_URL" "$CACHE/tools/appimagetool-x86_64.AppImage"
fetch_cached "$GTKPLUGIN_URL" "$CACHE/tools/linuxdeploy-plugin-gtk.sh"
verify_checksum "$CACHE/tools/linuxdeploy-x86_64.AppImage"
verify_checksum "$CACHE/tools/appimagetool-x86_64.AppImage"
verify_checksum "$CACHE/tools/linuxdeploy-plugin-gtk.sh"
chmod +x "$CACHE/tools/linuxdeploy-x86_64.AppImage" \
         "$CACHE/tools/appimagetool-x86_64.AppImage" \
         "$CACHE/tools/linuxdeploy-plugin-gtk.sh"

# 5. Assemble the AppDir with linuxdeploy + the gtk plugin. No FUSE inside
# a container, so tell the AppImage tools to extract-and-run themselves.
export APPIMAGE_EXTRACT_AND_RUN=1
export PATH="$CACHE/tools:$PATH"

"$CACHE/tools/linuxdeploy-x86_64.AppImage" \
  --appdir "$APPDIR" \
  -e "$APPDIR/usr/bin/tilem2" \
  -d "$APPDIR/usr/share/applications/tilem2.desktop" \
  -i "$WORK/tilem-gtk3/data/icons/hicolor/48x48/apps/tilem.png" \
  --icon-filename tilem \
  --plugin gtk

# 5b. linuxdeploy-plugin-gtk forces GDK_BACKEND=x11 (its own comment: the
# bundled GTK3 "crash[es] with Wayland backend on Wayland"). But tilem2's
# window aspect-ratio hint (GDK_HINT_ASPECT, set in gui/emuwin.c) is only
# enforced client-side by GTK during interactive resize under Wayland --
# under X11/XWayland it depends on the window manager, which doesn't
# reliably honor it for this app, causing free-form resize distortion.
# Verified stable under Wayland for this build; let GDK auto-detect the
# backend (as a native, non-AppImage build would) instead of forcing X11.
sed -i '/^export GDK_BACKEND=x11/d' "$APPDIR/apprun-hooks/linuxdeploy-plugin-gtk.sh"

# 6. Package the AppDir into the final AppImage.
VERSION="${VERSION:-dev}"
OUT_FILE="$OUT/TilEm-${VERSION}-x86_64.AppImage"
rm -f "$OUT_FILE"
ARCH=x86_64 VERSION="$VERSION" \
  "$CACHE/tools/appimagetool-x86_64.AppImage" --no-appstream "$APPDIR" "$OUT_FILE"

log "built $OUT_FILE"
