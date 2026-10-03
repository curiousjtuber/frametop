#!/usr/bin/env bash
# Build ft-screens on the Frame host, with the gcc and libraries its SteamOS image ships
# (screens/build/ft-screens), and ft-handtest, which tries the hand cutouts (handcut.cpp) on
# a test panel of its own. The host has no wlroots, so the first build makes it, as a static
# library in build/wlroots/: 0.20.2, only the protocol side ft-screens uses (seat,
# xdg-shell, linux-dmabuf, shm), with every backend, renderer and allocator off.
# compositor.c is the wlroots side (C; wlroots headers aren't C++), vr.cpp the OpenVR side.
# vr.cpp needs OpenVR's IVRIPCResourceManagerClient (ImportDmabuf), which the header
# shipped with SteamVR on the Frame predates, so the build uses the public header from
# Valve's openvr repo (pinned; the Frame's runtime supports its interface versions).
# keyboard.cpp draws its key labels with stb_truetype (public domain, one header, pinned).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C screens 'set -e; mkdir -p build/include
openvr=v2.15.6
[ -f build/include/openvr-$openvr ] || { curl -fsSL "https://raw.githubusercontent.com/ValveSoftware/openvr/$openvr/headers/openvr.h" -o build/include/openvr.h && touch build/include/openvr-$openvr; }
stb=2c980bb59875b0d32144a71867fbdebb2f77cd20
[ -f build/include/stb-$stb ] || { curl -fsSL "https://raw.githubusercontent.com/nothings/stb/$stb/stb_truetype.h" -o build/include/stb_truetype.h && touch build/include/stb-$stb; }
wlr=build/wlroots/install/usr
if [ ! -f $wlr/lib/libwlroots-0.20.a ]; then
  (cd build/wlroots 2>/dev/null || { mkdir -p build/wlroots && cd build/wlroots; }
  [ -d src ] || { mkdir src && curl -fsSL https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/0.20.2/wlroots-0.20.2.tar.gz | tar xz -C src --strip-components=1; }
  [ -d build ] || meson setup --wrap-mode=nofallback -Ddefault_library=static -Dbuildtype=release \
    -Dwerror=false -Dprefix=/usr --libdir=lib -Dbackends= -Drenderers= -Dallocators= -Dxwayland=disabled \
    -Dsession=disabled -Dcolor-management=disabled -Dlibliftoff=disabled -Dxcb-errors=disabled \
    -Dexamples=false build src
  ninja -C build
  DESTDIR=$PWD/install meson install -C build --quiet)
fi
gcc -std=c11 -O2 -Wall -Wno-unused-parameter -c -o build/compositor.o compositor.c \
  -I$wlr/include/wlroots-0.20 $(pkg-config --cflags wayland-server xkbcommon libdrm pixman-1)
cxx="g++ -std=c++17 -O2 -Wall -Wno-missing-field-initializers -Ibuild/include $(pkg-config --cflags egl glesv2 gbm libdrm)"
$cxx -c -o build/vr.o vr.cpp
$cxx -c -o build/keyboard.o keyboard.cpp
$cxx -c -o build/handcut.o handcut.cpp
$cxx -c -o build/handtest.o handtest.cpp
vrlibs="$(pkg-config --libs egl glesv2 gbm) -L/opt/steamvr/bin/linuxarm64 -lopenvr_api -Wl,-rpath,/opt/steamvr/bin/linuxarm64"
g++ -o build/ft-screens build/compositor.o build/vr.o build/keyboard.o build/handcut.o \
  $wlr/lib/libwlroots-0.20.a $(pkg-config --libs wayland-server wayland-client xkbcommon libdrm pixman-1) -lm -lrt $vrlibs
g++ -o build/ft-handtest build/handtest.o build/handcut.o $vrlibs
echo "built build/ft-screens build/ft-handtest"'
