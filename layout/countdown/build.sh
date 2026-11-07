#!/usr/bin/env bash
# Build the short-lived reset countdown on the Frame host, or inside the build image
# (FRAME_IN_BOX=1), for the host (scripts/host-glibc.sh). Output stays in layout/countdown/build/.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C layout/countdown 'set -e
./deps.sh
. ../../scripts/openvr.sh
. ../../scripts/host-glibc.sh
g++ -std=c++17 -O2 -Wall -Wextra -Wno-missing-field-initializers $host_cflags $OPENVR_CFLAGS \
  -o build/ft-reset-timer ft-reset-timer.cpp $OPENVR_LIBS -pthread
strip --strip-unneeded build/ft-reset-timer
host_glibc_check build/ft-reset-timer
build/ft-reset-timer --check
echo "built build/ft-reset-timer"'
