# TilEm AppImage packaging

Builds a self-contained `TilEm-<version>-x86_64.AppImage` that bundles GTK3
and the whole tilibs stack (`libticalcs2`, `libticables2`, `libtifiles2`,
`libticonv`) — none of which exist outside the AUR — so it runs on any
x86_64 Linux without those packages installed.

Everything is built inside a pinned `ubuntu:20.04` container (old glibc =
wider portability, since glibc is backward- but not forward-compatible: a
binary built against glibc 2.31 runs fine on newer systems, but not the
reverse) using Podman.

## One-time setup: install Podman

```
sudo pacman -S podman
```

This is the **only** step in this whole workflow that needs root. Podman is
rootless and daemonless: it runs containers as your own user via user
namespaces, with no persistent background service, so nothing else here
ever needs `sudo`.

## Build

```
./packaging/appimage/build.sh
```

This builds the `ubuntu:20.04`-based builder image (see `Dockerfile`),
builds tilibs from source, builds `tilem2` with `--with-sdl=no`, and
assembles the AppImage via `linuxdeploy` + `linuxdeploy-plugin-gtk` +
`appimagetool` (see `build-in-container.sh` for the exact steps). Output
lands in `out/TilEm-<version>-x86_64.AppImage`.

Two caches make repeat builds fast and avoid re-downloading things:
- `.cache/` (bind-mounted into the container) holds the downloaded tilibs
  source tarballs and the pinned linuxdeploy/appimagetool binaries.
- The builder image itself is cached by Podman (`podman images`) and only
  gets rebuilt if `Dockerfile`/`build-in-container.sh` change.

## Rebuilding later

Just run `./build.sh` again — no need to reinstall Podman or redo anything
manually. Podman reuses the cached image layers and `.cache/` holds the
downloaded sources/tools, so a repeat build only redoes the actual
compilation.

## Full cleanup (including uninstalling Podman)

```
rm -rf packaging/appimage/out packaging/appimage/.cache   # build output + downloaded caches
podman system reset -f                                     # wipe Podman's image/container storage (no sudo needed)
sudo pacman -Rns podman                                     # uninstall the package + any deps nothing else needs
```

`podman system reset -f` and the cache/output removal can be run any time
without sudo. Only the final `pacman -Rns` step needs root, and it's a clean
Arch-standard removal — it won't touch dependencies still used by other
installed packages, and rootless Podman never touches host networking
(no `docker0`-style bridge) or systemd services, so there's nothing else
lingering on the system afterward.

## Known limitations

- Built binaries require glibc >= 2.31 (Ubuntu 20.04's). This covers
  essentially all Debian/Ubuntu/Fedora/Arch systems from the last several
  years, but not truly ancient distros. Swap the `ARG BASE_IMAGE` in the
  `Dockerfile` to something older if wider reach is ever needed.
- No SDL / audio support (built with `--with-sdl=no`).
- The AppImage does not register itself as a MIME/desktop-menu handler for
  TI file types — that requires either running `xdg-mime`/`xdg-desktop-menu`
  manually, or a helper like AppImageLauncher on the end user's system.
- A ROM image is required at runtime and is never bundled (not
  redistributable).
