#!/usr/bin/env bash
# Unpack the Arch Linux ARM packages ft-screens builds against into xbuild/build/alarm/sysroot.
# SteamOS is Arch-based, and on SteamOS 0.3.0 these are the same versions the host has.
# Only headers and link-time libraries come from here: libc comes from zig, and at run time
# the host's own libraries are used. Checksums come from the repo databases.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
alarm=$here/build/alarm
mirror=http://mirror.archlinuxarm.org/aarch64
pkgs=(extra:wayland extra:libxkbcommon extra:libdrm extra:pixman core:libffi extra:wayland-protocols
  extra:libglvnd extra:mesa)  # EGL and GLESv2 from libglvnd, gbm from mesa: ft-screens draws with them
mkdir -p "$alarm/pkgs" "$alarm/sysroot"
cd "$alarm"
for r in core extra; do curl -fsSL -o $r.db $mirror/$r/$r.db; done
for spec in "${pkgs[@]}"; do
  r=${spec%%:*} name=${spec#*:}
  dir=$(bsdtar -tf $r.db | grep -E "^$name-[0-9][^/]*/$" | head -1)
  desc=$(bsdtar -xOf $r.db "${dir}desc")
  fn=$(awk '/^%FILENAME%/{getline; print}' <<<"$desc")
  sha=$(awk '/^%SHA256SUM%/{getline; print}' <<<"$desc")
  [ -f "pkgs/$fn" ] || curl -fsSL -o "pkgs/$fn" "$mirror/$r/$fn"
  echo "$sha  pkgs/$fn" | sha256sum -c --quiet
  bsdtar -xf "pkgs/$fn" -C sysroot --exclude .PKGINFO --exclude .BUILDINFO --exclude .MTREE --exclude .INSTALL
  echo "sysroot: ${dir%/}"
done
