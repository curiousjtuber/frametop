#!/usr/bin/env bash
# Install what xbuild/build.sh and install-cross.sh need to build on this machine, with its
# package manager (apt, dnf or pacman), so the build needs no dev box. In a distrobox it
# installs into that container. zig itself comes from mise (xbuild/mise.toml): this
# installs mise into ~/.local/bin if it isn't there (https://mise.jdx.dev).
# Usage: xbuild/install-tools.sh [--yes]   (uses sudo unless run as root)
#   --yes   don't ask before installing
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/_host.sh"

yes=0
for arg in "$@"; do
  case $arg in
    --yes) yes=1 ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
[ "$where" != frame ] || {
  echo "The Frame host's system is read-only: run this in a distrobox there, or let" >&2
  echo "xbuild/build.sh build in the dev box." >&2
  exit 1
}

if command -v apt-get >/dev/null; then
  install=(apt-get install -y --no-install-recommends)
  pkgs=(curl ca-certificates libarchive-tools binutils meson ninja-build pkgconf gcc libc6-dev
    libwayland-bin libwayland-dev git rsync patch)
elif command -v dnf >/dev/null; then
  install=(dnf install -y)
  pkgs=(curl bsdtar binutils meson ninja-build pkgconf gcc wayland-devel git rsync patch)
elif command -v pacman >/dev/null; then
  install=(pacman -S --needed --noconfirm)
  pkgs=(curl libarchive binutils meson ninja pkgconf gcc wayland git rsync patch)
else
  echo "no apt, dnf or pacman here: install these yourself: curl bsdtar nm objdump meson ninja" >&2
  echo "pkgconf, a C compiler, wayland-scanner (with its .pc file), git, rsync, patch" >&2
  exit 1
fi
sudo=()
[ "$(id -u)" = 0 ] || sudo=(sudo)

echo "Installing with ${install[0]}${box:+ in the $box container}: ${pkgs[*]}"
mise=$(command -v mise || echo "$HOME/.local/bin/mise")
[ -x "$mise" ] || echo "and mise into ~/.local/bin, for zig"
if [ "$yes" = 0 ]; then
  [ -t 0 ] || { echo "Not asking without a terminal: --yes installs them." >&2; exit 1; }
  read -r -p "Go ahead? [Y/n] " answer || answer=n
  [[ ${answer:-y} =~ ^[Yy] ]] || exit 1
fi
if [ "${install[0]}" = apt-get ]; then
  "${sudo[@]}" apt-get update -qq
  sudo+=(env DEBIAN_FRONTEND=noninteractive)
fi
"${sudo[@]}" "${install[@]}" "${pkgs[@]}"
[ -x "$mise" ] || curl -fsSL https://mise.run | sh
echo "Done: xbuild/build.sh builds here now."
