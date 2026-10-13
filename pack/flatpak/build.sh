#!/usr/bin/env bash
# Build Frametop's Python runtime Flatpak (io.github.frametop.Frametop.yml) into a bundle,
# pack/flatpak/build/frametop.flatpak, with flatpak-builder: on the Frame host, on a PC with
# an aarch64 Flatpak setup, or in CI (an arm64 runner). The KDE SDK (about 1 GB, once) and
# the wheels uv.lock pins are downloaded; nothing compiles, so a build takes a few minutes.
# Downloads and build state stay in build/, so a rebuild fetches only what changed.
#
# Usage: pack/flatpak/build.sh [--install]
#   --install  also install the bundle for this user (pack/flatpak/install.sh does the same
#              from a bundle, and builds one when there's none)
# Prints the bundle's path last. flatpak-builder is the host's, or the org.flatpak.Builder
# Flatpak when the host has none (SteamOS); FLATPAK_BUILDER names another.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP=io.github.frametop.Frametop
manifest=$here/$APP.yml
out=$here/build
install=0
[ "${1:-}" = --install ] && install=1

command -v flatpak >/dev/null || { echo "flatpak not found" >&2; exit 1; }
builder=${FLATPAK_BUILDER:-}
if [ -z "$builder" ]; then
  if command -v flatpak-builder >/dev/null; then
    builder=flatpak-builder
  elif flatpak info org.flatpak.Builder >/dev/null 2>&1; then
    builder="flatpak run org.flatpak.Builder"
  else
    echo "no flatpak-builder: install it, or: flatpak install flathub org.flatpak.Builder" >&2
    exit 1
  fi
fi
[ -e /run/.containerenv ] && { echo "run this on the host, not in a distrobox" >&2; exit 1; }

mkdir -p "$out"
python3 "$here/modules.py" --out "$out/python-packages.json"
# The runtime and SDK come from Flathub, into the user installation (no root).
flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
runtime=$(sed -n 's/^runtime-version: *'"'"'\(.*\)'"'"'/\1/p' "$manifest")
# shellcheck disable=SC2086
$builder --user --force-clean --install-deps-from=flathub --disable-rofiles-fuse \
  --state-dir="$out/.flatpak-builder" --repo="$out/repo" "$out/app" "$manifest"
flatpak build-bundle "$out/repo" "$out/frametop.flatpak" "$APP" \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
# What went in, for install.sh to tell a bundle of these inputs from an older one.
sha256sum "$manifest" "$out/python-packages.json" | cut -d' ' -f1 | sha256sum | cut -c1-16 >"$out/frametop.flatpak.inputs"
echo "runtime org.kde.Platform//$runtime"
if [ "$install" = 1 ]; then
  flatpak install --user -y --reinstall "$out/frametop.flatpak" >/dev/null
  echo "installed $APP"
fi
echo "$out/frametop.flatpak"
