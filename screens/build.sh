#!/usr/bin/env bash
# Build ft-screens on the Frame host, with the gcc and libraries its SteamOS image ships
# (screens/build/ft-screens), and ft-handtest, which tries the hand cutouts (handcut.cpp) on
# a test panel of its own. In the build image (pack/Containerfile, FRAME_IN_BOX=1) the same
# build runs there, against the host's glibc version (scripts/host-glibc.sh).
# The host has no wlroots, so the first build makes it, as a static library in build/wlroots/:
# 0.20.2 (pinned, checked by sha256), only the protocol side ft-screens uses (seat, xdg-shell,
# linux-dmabuf, shm), with every backend, renderer and allocator off.
# compositor.c is the wlroots side (C; wlroots headers aren't C++), vr.cpp the OpenVR side,
# remote.c the remote screens (their streams are ft-stream's, stream/build.sh).
# vr.cpp needs OpenVR's IVRIPCResourceManagerClient (ImportDmabuf), which the header
# shipped with SteamVR on the Frame predates, so the build uses the public header from
# Valve's openvr repo (pinned in scripts/openvr.sh).
# keyboard.cpp draws its key labels with stb_truetype (public domain, one header, pinned).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C screens 'set -e; mkdir -p build/include
. ../scripts/openvr.sh
. ../scripts/host-glibc.sh
stb=2c980bb59875b0d32144a71867fbdebb2f77cd20
[ -f build/include/stb-$stb ] || { curl -fsSL "https://raw.githubusercontent.com/nothings/stb/$stb/stb_truetype.h" -o build/include/stb_truetype.h && touch build/include/stb-$stb; }
wlr_ver=0.20.2 wlr_sha=972c7ac44b17828f4702bfae7cd8347346a3fb5b2c1076cfa2c3fcedac5ec343
wlr=$PWD/build/wlroots
host_build_stamp build/wlroots build/*.o
if [ ! -f "$wlr/install/lib/libwlroots-0.20.a" ]; then
  rm -rf "$wlr"; mkdir -p "$wlr/src"
  curl -fsSL "https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/$wlr_ver/wlroots-$wlr_ver.tar.gz" -o "$wlr/src.tar.gz"
  echo "$wlr_sha  $wlr/src.tar.gz" | sha256sum -c --status || { echo "wlroots $wlr_ver does not match its pinned sha256" >&2; exit 1; }
  tar xzf "$wlr/src.tar.gz" -C "$wlr/src" --strip-components=1
  meson setup --wrap-mode=nofallback -Ddefault_library=static -Dbuildtype=release -Dwerror=false \
    -Dprefix="$wlr/install" --libdir=lib -Dbackends= -Drenderers= -Dallocators= -Dxwayland=disabled \
    -Dsession=disabled -Dcolor-management=disabled -Dlibliftoff=disabled -Dxcb-errors=disabled \
    -Dexamples=false "$wlr/build" "$wlr/src" >/dev/null
  ninja -C "$wlr/build" >/dev/null
  meson install -C "$wlr/build" --quiet
fi
export PKG_CONFIG_PATH=$wlr/install/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
cc="gcc -std=c11 -O2 -Wall -Wno-unused-parameter $(pkg-config --cflags wlroots-0.20 wayland-server xkbcommon libdrm pixman-1)"
$cc -c -o build/compositor.o compositor.c
$cc -c -o build/remote.o remote.c
cxx="g++ -std=c++17 -O2 -Wall -Wno-missing-field-initializers -Ibuild/include $(pkg-config --cflags egl glesv2 gbm libdrm)"
$cxx -c -o build/vr.o vr.cpp
$cxx -c -o build/keyboard.o keyboard.cpp
$cxx -c -o build/handcut.o handcut.cpp
$cxx -c -o build/handtest.o handtest.cpp
vrlibs="$(pkg-config --libs egl glesv2 gbm) $OPENVR_LIBS"
g++ -o build/ft-screens build/compositor.o build/remote.o build/vr.o build/keyboard.o build/handcut.o \
  $(pkg-config --static --libs wlroots-0.20 wayland-server xkbcommon pixman-1) -lm -lrt $vrlibs
g++ -o build/ft-handtest build/handtest.o build/handcut.o $vrlibs
host_glibc_check build/ft-screens build/ft-handtest
echo "built build/ft-screens build/ft-handtest"'
