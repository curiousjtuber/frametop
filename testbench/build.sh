#!/usr/bin/env bash
# Build the testbench's native parts on the Frame host: the input proxy and loader SteamVR
# preloads, and frame-observe. All three run on the SteamOS host, so like the ft_pointer
# driver they may only need glibc symbols the host has (scripts/host-glibc.sh).
# Usage: testbench/build.sh
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
"$root/scripts/sync.sh" >/dev/null
exec "$root/scripts/frame.sh" --host -C testbench 'set -e
. ../scripts/host-glibc.sh
export CXXFLAGS="${CXXFLAGS:-} $host_cflags"
bash scripts/build-input.sh
sh scripts/build-observe.sh
for f in build/libframe_input.so build/libframe_loader.so build/frame-observe; do
  max=$(objdump -T "$f" | grep -oE "GLIBC_[0-9.]+" | sort -uV | tail -1)
  [ -n "$max" ] || { echo "$f: objdump found no glibc symbols" >&2; exit 1; }
  echo "$f: newest glibc symbol $max"
done
host_glibc_check build/libframe_input.so build/libframe_loader.so build/frame-observe'
