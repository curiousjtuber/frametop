#!/usr/bin/env bash
# Build ft-screens on the Frame host, with the gcc and libraries its SteamOS image ships
# (screens/build/ft-screens), and ft-handtest, which tries the hand cutouts (handcut.cpp) on
# a test panel of its own, ft-handview, which draws the hands when Room View is off
# (handview.cpp), and ft-spotpanel, frunner's search panel (frunner/ft-spotpanel.cpp;
# ft-frunner runs it). In the build image (pack/Containerfile, FRAME_IN_BOX=1) the same build
# runs for the host (scripts/host-glibc.sh keeps it within the host's glibc and checks it).
# The host has no wlroots, so the first build makes it, as a static library in build/wlroots/:
# 0.20.2 (pinned, checked by sha256), only the protocol side ft-screens uses (seat, xdg-shell,
# linux-dmabuf, shm), with every backend, renderer and allocator off; linked in, ft-screens
# loads 14 host libraries instead of 51.
# compositor.c is the wlroots side (C; wlroots headers aren't C++), vr.cpp the OpenVR side,
# remote.c the remote screens (their streams are ft-stream's, stream/build.sh).
# vr.cpp needs OpenVR's IVRIPCResourceManagerClient (ImportDmabuf), which the header
# shipped with SteamVR on the Frame predates, so the build uses the public header from
# Valve's openvr repo (pinned in scripts/openvr.sh).
# label.cpp draws the panels' labels with stb_truetype (public domain, one header, pinned and
# checked in scripts/stb.sh);
# ft-handview --snapshot writes PNGs with stb_image_write (the same).
# ft-handview's hand models are compiled in once: tools/hand-asset.py makes build/handasset.cpp from
# screens/assets/hands each build (handasset.h, which declares it, is in the tree);
# its robot hand is built in code (handrobot.cpp).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C screens 'set -e; mkdir -p build/include
. ../scripts/openvr.sh
. ../scripts/host-glibc.sh
. ../scripts/stb.sh
stb_fetch build/include stb_truetype.h stb_image_write.h
wlr_ver=0.20.2 wlr_sha=972c7ac44b17828f4702bfae7cd8347346a3fb5b2c1076cfa2c3fcedac5ec343
wlr=$PWD/build/wlroots
host_build_stamp build/wlroots build/*.o
if [ ! -f "$wlr/install/lib/libwlroots-0.20.a" ]; then
  rm -rf "$wlr"; mkdir -p "$wlr/src"
  curl -fsSL "https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/$wlr_ver/wlroots-$wlr_ver.tar.gz" -o "$wlr/src.tar.gz"
  echo "$wlr_sha  $wlr/src.tar.gz" | sha256sum -c --status || { echo "wlroots $wlr_ver does not match its pinned sha256" >&2; exit 1; }
  tar xzf "$wlr/src.tar.gz" -C "$wlr/src" --strip-components=1
  # Its output goes to a log, shown when it fails (a dependency the host lacks shows there).
  { CFLAGS="$host_cflags" meson setup --wrap-mode=nofallback -Ddefault_library=static -Dbuildtype=release -Dwerror=false \
      -Dprefix="$wlr/install" --libdir=lib -Dbackends= -Drenderers= -Dallocators= -Dxwayland=disabled \
      -Dsession=disabled -Dcolor-management=disabled -Dlibliftoff=disabled -Dxcb-errors=disabled \
      -Dexamples=false "$wlr/build" "$wlr/src" && ninja -C "$wlr/build"; } > "$wlr/build.log" 2>&1 ||
    { tail -40 "$wlr/build.log" >&2; echo "wlroots did not build (the log: $wlr/build.log)" >&2; exit 1; }
  meson install -C "$wlr/build" --quiet
fi
export PKG_CONFIG_PATH=$wlr/install/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
cc="gcc -std=c11 -O2 -Wall -Wno-unused-parameter $host_cflags $(pkg-config --cflags wlroots-0.20 wayland-server xkbcommon libdrm pixman-1)"
$cc -c -o build/compositor.o compositor.c
$cc -c -o build/remote.o remote.c
cxx="g++ -std=c++17 -O2 -Wall -Wno-missing-field-initializers $host_cflags -Ibuild/include $(pkg-config --cflags egl glesv2 gbm libdrm)"
$cxx -c -o build/vr.o vr.cpp
$cxx -c -o build/label.o label.cpp
$cxx -c -o build/overlaytex.o overlaytex.cpp
$cxx -c -o build/handcut.o handcut.cpp
$cxx -c -o build/handrender.o handrender.cpp
$cxx -c -o build/rendernode.o rendernode.cpp
$cxx -c -o build/handinput.o handinput.cpp
$cxx -c -o build/palmmenu.o palmmenu.cpp
$cxx -c -o build/grabthat.o grabthat.cpp
$cxx -c -o build/steampanels.o steampanels.cpp
$cxx -c -o build/handtest.o handtest.cpp
$cxx -c -o build/handmesh.o handmesh.cpp
$cxx -c -o build/handskin.o handskin.cpp
python3 -I tools/hand-asset.py --cpp build/handasset.cpp >/dev/null
$cxx -I. -c -o build/handasset.o build/handasset.cpp
$cxx -c -o build/handrobot.o handrobot.cpp
$cxx -c -o build/handview.o handview.cpp
vrlibs="$(pkg-config --libs egl glesv2 gbm) $OPENVR_LIBS"
g++ -o build/ft-screens build/compositor.o build/remote.o build/vr.o build/label.o build/overlaytex.o build/handcut.o build/handrender.o build/rendernode.o build/handinput.o build/palmmenu.o build/grabthat.o build/steampanels.o \
  $(pkg-config --static --libs wlroots-0.20 wayland-server xkbcommon pixman-1) -lm -lrt $vrlibs
g++ -o build/ft-handtest build/handtest.o build/handcut.o build/handrender.o build/rendernode.o $vrlibs
g++ -o build/ft-handview build/handview.o build/handmesh.o build/handskin.o build/handasset.o build/handrobot.o build/handcut.o build/handrender.o build/rendernode.o $vrlibs
$cxx -o build/ft-spotpanel ../frunner/ft-spotpanel.cpp $(pkg-config --libs gbm libdrm) $OPENVR_LIBS -lpthread
strip --strip-unneeded build/ft-screens build/ft-handtest build/ft-handview build/ft-spotpanel
host_glibc_check build/ft-screens build/ft-handtest build/ft-handview build/ft-spotpanel
echo "built build/ft-screens build/ft-handtest build/ft-handview build/ft-spotpanel"'
