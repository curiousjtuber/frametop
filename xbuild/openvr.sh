#!/usr/bin/env bash
# Fetch the pinned OpenVR headers and aarch64 libopenvr_api.so into xbuild/build/openvr,
# and build the link stub. Valve's library has no SONAME, so linking it directly records
# its absolute path as NEEDED; the stub has the same exports and SONAME libopenvr_api.so.
# At run time the rpath finds SteamVR's own copy on the Frame, so the stub never runs.
# v2.15.6 is the header ft-screens and ft-gaze already use (ImportDmabuf, eye tracking).
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/_env.sh"  # the pinned zig
ver=v2.15.6
raw=https://raw.githubusercontent.com/ValveSoftware/openvr/$ver
ovr=$here/build/openvr
mkdir -p "$ovr/include" "$ovr/lib" "$ovr/stub"
curl -fsSL -o "$ovr/include/openvr.h" $raw/headers/openvr.h
curl -fsSL -o "$ovr/include/openvr_driver.h" $raw/headers/openvr_driver.h
curl -fsSL -o "$ovr/lib/libopenvr_api.so" $raw/bin/linuxarm64/libopenvr_api.so
nm -D --defined-only "$ovr/lib/libopenvr_api.so" | awk '$2=="T"{print "void " $3 "(void) {}"}' > "$ovr/stub.c"
zig cc -target aarch64-linux-gnu.2.39 -shared -fPIC -Wl,-soname,libopenvr_api.so \
  -o "$ovr/stub/libopenvr_api.so" "$ovr/stub.c"
echo "openvr $ver: $(wc -l < "$ovr/stub.c") exports stubbed"
