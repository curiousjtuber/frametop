#!/usr/bin/env bash
# Build Frametop's native programs on the Frame host itself, with the gcc and libraries its
# SteamOS image ships (0.3.0 and the 0.4.3 beta have them), so they run on the host instead
# of in the dev container, linked against exactly the libraries they run with. The flags
# are each component's build.sh's, which builds them in the dev box. ft-screens' wlroots,
# which the host lacks, is built once as a static library in host/build/.
# Usage: host/build.sh   (on the Frame host; install-host.sh runs it)
# Writes each program into build-host/, next to the dev box build's build/:
# screens/build-host/ft-screens, pointer/helper/build-host/ft-pointer, pointer/driver/
# build-host/driver_ft_pointer.so, pointer/probe/build-host/vrprobe, gaze/build-host/ft-gaze
# and ft-gazepanel, power/build-host/ft-powerd, gaze/tracker/build-host/ft-eyegrab.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
. "$root/scripts/_env.sh"
[ "$FRAME_LOCAL" = 1 ] || { echo "host/build.sh builds on the Frame host only (not in a container, or from a PC)" >&2; exit 1; }

# SteamVR's own OpenVR headers, as pointer/ and power/ build with; screens/ and gaze/ pin v2.15.6.
ovr_h=/opt/steamvr/tools/hellovr_vulkan_linux/src/openvr/headers
missing=()
for t in gcc g++ meson ninja pkgconf wayland-scanner curl; do command -v $t >/dev/null || missing+=("$t"); done
for p in wayland-server wayland-client wayland-protocols xkbcommon libdrm pixman-1 egl glesv2 gbm; do
  pkgconf --exists $p 2>/dev/null || missing+=("$p")
done
[ -f "$ovr_h/openvr_driver.h" ] || missing+=("$ovr_h")
if [ ${#missing[@]} -gt 0 ]; then
  echo "This SteamOS image lacks what the host build needs: ${missing[*]}" >&2
  echo "Use ./install.sh instead, which builds in the dev box (README.md)." >&2
  exit 1
fi

work=$here/build
mkdir -p "$work/include"
openvr=v2.15.6
[ -f "$work/include/openvr-$openvr" ] || { curl -fsSL "https://raw.githubusercontent.com/ValveSoftware/openvr/$openvr/headers/openvr.h" \
  -o "$work/include/openvr.h" && touch "$work/include/openvr-$openvr"; }
stb=2c980bb59875b0d32144a71867fbdebb2f77cd20
[ -f "$work/include/stb-$stb" ] || { curl -fsSL "https://raw.githubusercontent.com/nothings/stb/$stb/stb_truetype.h" \
  -o "$work/include/stb_truetype.h" && touch "$work/include/stb-$stb"; }

# wlroots 0.20.2, only the protocol side ft-screens uses (seat, xdg-shell, linux-dmabuf,
# shm): every backend, renderer and allocator is off.
ver=0.20.2
wlr=$work/wlroots-install/usr
if [ ! -f "$wlr/lib/libwlroots-0.20.a" ]; then
  (cd "$work"
  [ -d wlroots-$ver ] || curl -fsSL https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/$ver/wlroots-$ver.tar.gz | tar xz
  [ -d wlroots-build ] || meson setup --wrap-mode=nofallback \
    -Ddefault_library=static -Dbuildtype=release -Dwerror=false -Dprefix=/usr --libdir=lib \
    -Dbackends= -Drenderers= -Dallocators= -Dxwayland=disabled -Dsession=disabled \
    -Dcolor-management=disabled -Dlibliftoff=disabled -Dxcb-errors=disabled -Dexamples=false \
    wlroots-build wlroots-$ver
  ninja -C wlroots-build
  DESTDIR=$work/wlroots-install meson install -C wlroots-build --quiet)
fi

cd "$root"
mkdir -p {screens,pointer/helper,pointer/driver,pointer/probe,gaze,gaze/tracker,power}/build-host
cxx=(g++ -std=c++17 -O2 -Wall)
vr=(-L/opt/steamvr/bin/linuxarm64 -lopenvr_api -Wl,-rpath,/opt/steamvr/bin/linuxarm64)

"${cxx[@]}" -fPIC -shared -fvisibility=hidden -fno-math-errno -Wno-unused-parameter \
  -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL -I"$ovr_h" \
  -o pointer/driver/build-host/driver_ft_pointer.so pointer/driver/driver_ft_pointer.cpp -lpthread
"${cxx[@]}" -Wno-unused-parameter -I"$ovr_h" -Ipointer/common \
  -o pointer/helper/build-host/ft-pointer pointer/helper/ft-pointer.cpp "${vr[@]}" -lpthread
"${cxx[@]}" -I"$ovr_h" -Ipointer/common -o pointer/probe/build-host/vrprobe pointer/probe/vrprobe.cpp "${vr[@]}"
"${cxx[@]}" -Wno-unused-parameter -I"$ovr_h" -o power/build-host/ft-powerd power/ft-powerd.cpp "${vr[@]}"
"${cxx[@]}" -Wno-unused-parameter -Wno-missing-field-initializers -I"$work/include" -Ipointer/common \
  -o gaze/build-host/ft-gaze gaze/ft-gaze.cpp "${vr[@]}" -lpthread
"${cxx[@]}" -Wno-unused-parameter -Wno-missing-field-initializers -I"$work/include" $(pkgconf --cflags gbm libdrm) \
  -o gaze/build-host/ft-gazepanel gaze/panel/ft-gazepanel.cpp "${vr[@]}" $(pkgconf --libs gbm libdrm) -lpthread
gcc -std=gnu11 -O2 -Wall -Wextra -pthread -o gaze/tracker/build-host/ft-eyegrab gaze/tracker/ft-eyegrab.c

obj=$work/screens
mkdir -p "$obj"
gcc -std=c11 -O2 -Wall -Wno-unused-parameter -I"$wlr/include/wlroots-0.20" \
  $(pkgconf --cflags wayland-server xkbcommon libdrm pixman-1) -c -o "$obj/compositor.o" screens/compositor.c
for f in vr keyboard handcut; do
  "${cxx[@]}" -Wno-missing-field-initializers -I"$work/include" $(pkgconf --cflags egl glesv2 gbm libdrm) \
    -c -o "$obj/$f.o" screens/$f.cpp
done
g++ -o screens/build-host/ft-screens "$obj"/{compositor,vr,keyboard,handcut}.o "$wlr/lib/libwlroots-0.20.a" \
  $(pkgconf --libs wayland-server wayland-client xkbcommon libdrm pixman-1 egl glesv2 gbm) -lm -lrt "${vr[@]}"
echo "built screens, pointer helper, driver and probe, gaze, gaze panel, power and frame grabber into */build-host/"
