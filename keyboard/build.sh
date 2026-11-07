#!/usr/bin/env bash
# Build Full Keyboard (TaiKeid's, vendored here: FRAMETOP.md) on the Frame host, with its own
# gcc, cmake and libraries (cairo, pango, SDL2, libhangul, pyzy; Anthy loads at run time):
# build/frametop/framekeyboard, which frametop-keyboard.service runs with --frametop. It finds
# its layouts, themes and Steam bridge beside itself, in build/frametop. Like Frametop's other
# OpenVR programs it builds against the header scripts/openvr.sh pins and loads SteamVR's own
# libopenvr_api first, and scripts/host-glibc.sh keeps it, its guard and its engines within the
# host's glibc. Its two programs link libstdc++ statically: a newer toolchain (the build image's
# gcc 16) gives their C++20 atomics a libstdc++ symbol past the floor; its engines, loaded with
# dlopen, keep the shared one, and the ctest's engine loading shows the two copies get along.
# Its tests: FULL_KEYBOARD_TESTS=1 keyboard/build.sh (ctest in build/frametop).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C keyboard "set -e
. ../scripts/openvr.sh
. ../scripts/host-glibc.sh
tests=${FULL_KEYBOARD_TESTS:-0}
host_build_stamp build/frametop
cmake -S . -B build/frametop -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DBUILD_TESTING=\$([ \$tests = 1 ] && echo ON || echo OFF) \
  -DCMAKE_C_FLAGS=\"\$host_cflags\" -DCMAKE_CXX_FLAGS=\"\$host_cflags\" -DCMAKE_EXE_LINKER_FLAGS=-static-libstdc++ \
  -DOPENVR_INCLUDE_DIR=\$PWD/build/include \\
  -DOPENVR_LIBRARY=\$openvr_lib/libopenvr_api.so -DOPENVR_RUNTIME_PATH=\$openvr_rpath >/dev/null
cmake --build build/frametop
host_glibc_check build/frametop/framekeyboard build/frametop/framekeyboard-native-guard build/frametop/engines/*.so
[ \$tests = 1 ] && (cd build/frametop && XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)} ctest --output-on-failure)
echo 'built build/frametop/framekeyboard'"
