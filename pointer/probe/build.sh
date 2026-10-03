#!/usr/bin/env bash
# Build vrprobe on the Frame host, with its own gcc (pointer/probe/build/vrprobe).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C pointer/probe 'set -e; mkdir -p build
g++ -std=c++17 -O2 -Wall -I/opt/steamvr/tools/hellovr_vulkan_linux/src/openvr/headers -I../common \
  -o build/vrprobe vrprobe.cpp -L/opt/steamvr/bin/linuxarm64 -lopenvr_api -Wl,-rpath,/opt/steamvr/bin/linuxarm64
echo "built build/vrprobe"'
