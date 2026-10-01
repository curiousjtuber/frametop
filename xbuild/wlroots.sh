#!/usr/bin/env bash
# Build wlroots 0.20.2 as a static library for ft-screens, into xbuild/build/wlroots-install.
# The host has no wlroots. ft-screens uses only its protocol side, so every backend,
# renderer and allocator is off; what's left needs only wayland, libdrm, xkbcommon and
# pixman (see sysroot.sh). werror is off because release builds leave assert-only
# variables unused.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/_env.sh"  # the pinned zig
work=$here/build
ver=0.20.2
sysroot=$work/alarm/sysroot
mkdir -p "$work"
cd "$work"
[ -d wlroots-$ver ] || curl -fsSL https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/$ver/wlroots-$ver.tar.gz | tar xz
sed "s|@SYSROOT@|$sysroot|g" "$here/aarch64-frame.ini.in" > aarch64-frame.ini
[ -d wlroots-build ] || meson setup --cross-file aarch64-frame.ini --wrap-mode=nofallback \
  -Ddefault_library=static -Dbuildtype=release -Dwerror=false -Dprefix=/usr --libdir=lib \
  -Dbackends= -Drenderers= -Dallocators= -Dxwayland=disabled -Dsession=disabled \
  -Dcolor-management=disabled -Dlibliftoff=disabled -Dxcb-errors=disabled -Dexamples=false \
  wlroots-build wlroots-$ver
ninja -C wlroots-build
DESTDIR=$work/wlroots-install meson install -C wlroots-build --quiet
