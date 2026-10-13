#!/usr/bin/env bash
# Offline test of ft-gaze's eye-server.mmap layout detection (gaze/test/mmap-layout-test.cpp):
# builds it against gaze/ft-gaze.cpp on the Frame host and runs it there. Nothing reaches
# SteamVR or the eye tracker, so it's safe next to them. gaze/build.sh fetches the OpenVR
# header it needs, so run that once first.
#
#   gaze/test/mmap-layout-test.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C gaze 'set -e
[ -f build/include/openvr.h ] || { echo "no build/include/openvr.h: run gaze/build.sh first" >&2; exit 1; }
. ../scripts/openvr.sh
g++ -std=c++17 -O2 -Wall -Wno-unused-parameter -Wno-missing-field-initializers -Ibuild/include -I../pointer/common \
  -o build/mmap-layout-test test/mmap-layout-test.cpp $OPENVR_LIBS -lpthread
build/mmap-layout-test'
