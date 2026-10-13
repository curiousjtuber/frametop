#!/usr/bin/env bash
# Build the ft_pointer SteamVR driver on the Frame host, with its own gcc, and check it only
# needs glibc symbols the host has (scripts/host-glibc.sh; the build image's glibc is the
# host's version, and this is where that was first needed: vrserver loads the driver).
# -fno-math-errno keeps sqrtf inline. The driver uses libm's double functions: in a newer
# glibc the float ones (sqrtf, atan2f, asinf, remainderf) carry a newer symbol version.
# Usage: pointer/driver/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C pointer/driver 'set -e
mkdir -p build
. ../../scripts/openvr.sh
. ../../scripts/host-glibc.sh
g++ -std=c++17 -O2 -fPIC -shared -fvisibility=hidden -fno-math-errno -Wall -Wno-unused-parameter \
  -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL \
  $OPENVR_CFLAGS \
  -o build/driver_ft_pointer.so driver_ft_pointer.cpp -lpthread
host_glibc_check build/driver_ft_pointer.so
echo "built build/driver_ft_pointer.so"'
