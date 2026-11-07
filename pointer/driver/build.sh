#!/usr/bin/env bash
# Build the ft_pointer SteamVR driver on the Frame host, with its own gcc. vrserver loads it,
# so it may only need glibc symbols the host has: scripts/host-glibc.sh pins the ones a newer
# glibc renamed and checks the result (this driver is where that check began). libstdc++ and
# libgcc are linked in and hidden, so vrserver's own copies don't matter.
# -fno-math-errno keeps sqrtf inline.
# Usage: pointer/driver/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C pointer/driver 'set -e
mkdir -p build
. ../../scripts/openvr.sh
. ../../scripts/host-glibc.sh
g++ -std=c++17 -O2 -ffunction-sections -fdata-sections -fPIC -shared -fvisibility=hidden -fno-math-errno -Wall -Wno-unused-parameter \
  -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL,--gc-sections \
  $host_cflags $OPENVR_CFLAGS \
  -o build/driver_ft_pointer.so driver_ft_pointer.cpp -lpthread
strip --strip-unneeded build/driver_ft_pointer.so
host_glibc_check build/driver_ft_pointer.so
echo "built build/driver_ft_pointer.so"'
