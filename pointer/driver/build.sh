#!/usr/bin/env bash
# Build the ft_pointer SteamVR driver on the Frame host, with its own gcc.
# -fno-math-errno keeps sqrtf inline. The driver uses libm's double functions: built in the
# dev container, the float ones (sqrtf, atan2f, asinf, remainderf) were versioned
# GLIBC_2.43, newer than the host's.
# Usage: pointer/driver/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C pointer/driver 'set -e
mkdir -p build
g++ -std=c++17 -O2 -fPIC -shared -fvisibility=hidden -fno-math-errno -Wall -Wno-unused-parameter \
  -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL \
  -I/opt/steamvr/tools/hellovr_vulkan_linux/src/openvr/headers \
  -o build/driver_ft_pointer.so driver_ft_pointer.cpp -lpthread
echo "built build/driver_ft_pointer.so"'
