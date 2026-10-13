#!/usr/bin/env bash
# Build vrprobe on the Frame host (pointer/probe/build/vrprobe).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C pointer/probe 'set -e; mkdir -p build
. ../../scripts/openvr.sh
g++ -std=c++17 -O2 -Wall $OPENVR_CFLAGS -I../common \
  -o build/vrprobe vrprobe.cpp $OPENVR_LIBS
echo "built build/vrprobe"'
