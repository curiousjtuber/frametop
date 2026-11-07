#!/usr/bin/env bash
# Build ft-powerd on the Frame host, with its own gcc (it runs there too). In the build image
# (pack/Containerfile) the same build runs for the host (scripts/host-glibc.sh).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C power 'set -e; mkdir -p build
. ../scripts/openvr.sh
. ../scripts/host-glibc.sh
g++ -std=c++17 -O2 -Wall -Wno-unused-parameter $host_cflags $OPENVR_CFLAGS \
  -o build/ft-powerd ft-powerd.cpp $OPENVR_LIBS
strip --strip-unneeded build/ft-powerd
host_glibc_check build/ft-powerd
echo "built build/ft-powerd"'
