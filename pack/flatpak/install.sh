#!/usr/bin/env bash
# Install Frametop's Python runtime, the Flatpak that runs the settings apps, the Hand Recorder
# and ft-eyes (pack/flatpak/io.github.frametop.Frametop.yml, pack/host-and-flatpak.md), for
# this user. Runs on the Frame host; install.sh calls it.
#
# Usage: pack/flatpak/install.sh [BUNDLE | --uninstall | --status]
#   BUNDLE  a frametop.flatpak to install (a release's); without one, the bundle
#           pack/flatpak/build.sh made for these inputs is installed, and built first
#           when there's none
# The KDE runtime it needs (org.kde.Platform, about 1 GB) comes from Flathub when it isn't
# installed yet; everything else is in the bundle. --status prints what's installed.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP=io.github.frametop.Frametop
manifest=$here/$APP.yml
out=$here/build

installed() { flatpak info --user "$APP" >/dev/null 2>&1; }
# The inputs of the bundle in build/ (build.sh writes it), and of the manifest now.
inputs_now() {
  python3 "$here/modules.py" --out "$out/python-packages.json" >/dev/null
  sha256sum "$manifest" "$out/python-packages.json" | cut -d' ' -f1 | sha256sum | cut -c1-16
}
# The inputs the installed app was built from, kept next to the user's Flatpak data.
stamp=$HOME/.local/share/frametop/python-runtime.inputs

case ${1:-} in
  --status)
    if installed; then
      echo "installed: $APP $(flatpak info --user "$APP" 2>/dev/null | sed -n 's/^ *Commit: *//p' | cut -c1-12)"
    else
      echo "not installed: $APP"
    fi
    exit 0 ;;
  --uninstall)
    if installed; then
      flatpak uninstall --user -y --noninteractive "$APP" >/dev/null && echo "removed $APP"
    else
      echo "$APP wasn't installed"
    fi
    rm -f "$stamp"
    exit 0 ;;
  -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
esac

command -v flatpak >/dev/null || { echo "flatpak not found" >&2; exit 1; }
[ -e /run/.containerenv ] && { echo "run this on the host, not in a distrobox" >&2; exit 1; }
export XDG_RUNTIME_DIR=/run/user/$(id -u)  # flatpak's, even from a terminal in a VR desktop

runtime=$(sed -n 's/^runtime-version: *'"'"'\(.*\)'"'"'/\1/p' "$manifest")
flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if ! flatpak info --user "org.kde.Platform//$runtime" >/dev/null 2>&1 && ! flatpak info "org.kde.Platform//$runtime" >/dev/null 2>&1; then
  echo "downloading KDE's runtime org.kde.Platform//$runtime from Flathub (about 1 GB, once; the"
  echo "bundle holds everything else)"
  flatpak install --user -y --noninteractive flathub "org.kde.Platform//$runtime"
fi

bundle=${1:-}
if [ -n "$bundle" ]; then
  [ -f "$bundle" ] || { echo "no bundle at $bundle" >&2; exit 1; }
  flatpak install --user -y --noninteractive --reinstall "$bundle" >/dev/null
  rm -f "$stamp"
  echo "installed $APP from $bundle"
  exit 0
fi

now=$(inputs_now)
if installed && [ "$(cat "$stamp" 2>/dev/null)" = "$now" ]; then
  echo "already installed: $APP (built from these inputs)"
  exit 0
fi
if [ ! -f "$out/frametop.flatpak" ] || [ "$(cat "$out/frametop.flatpak.inputs" 2>/dev/null)" != "$now" ]; then
  echo "building $APP (flatpak-builder; the KDE SDK is a 1 GB download the first time)"
  "$here/build.sh" >/dev/null
fi
flatpak install --user -y --noninteractive --reinstall "$out/frametop.flatpak" >/dev/null
mkdir -p "$(dirname "$stamp")"
echo "$now" >"$stamp"
echo "installed $APP"
