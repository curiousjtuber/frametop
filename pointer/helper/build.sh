#!/usr/bin/env bash
# Build the ft-pointer helper on the Frame host, with its own gcc (it runs there too). In the
# build image (pack/Containerfile) the same build runs for the host: scripts/host-glibc.sh
# keeps it within the host's glibc and libstdc++ and checks the result.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C pointer/helper 'set -e; mkdir -p build
. ../../scripts/openvr.sh
. ../../scripts/host-glibc.sh
g++ -std=c++17 -O2 -Wall -Wno-unused-parameter $host_cflags $OPENVR_CFLAGS -I../common \
  -o build/ft-pointer ft-pointer.cpp $OPENVR_LIBS -lpthread
strip --strip-unneeded build/ft-pointer
host_glibc_check build/ft-pointer
echo "built build/ft-pointer"'
